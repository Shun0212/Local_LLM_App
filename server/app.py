from __future__ import annotations

import json
import os
from typing import Dict, Iterable
from flask import Flask, request, jsonify, Response
import requests
import socket
import base64
from io import BytesIO
import webbrowser
import threading
import subprocess


app = Flask(__name__)


OLLAMA_BASE = os.environ.get("OLLAMA_BASE", "http://localhost:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "gpt-oss:20b")


def _local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    finally:
        s.close()
    return ip


@app.route("/healthz", methods=["GET"]) 
def healthz():
    return {"status": "ok", "model": MODEL}


@app.route("/chat", methods=["GET", "POST"]) 
def chat():
    if request.method == "GET":
        return (
            "<html><body><h3>Chat endpoint</h3>"
            "<p>This endpoint accepts JSON via <code>POST /chat</code>.</p>"
            "<pre>{\n  \"message\": \"Hello\",\n  \"provider\": \"ollama|gemini\"\n}</pre>"
            "<p>Example: <code>curl -X POST -H 'Content-Type: application/json' "
            "-d '{\"message\":\"Hello\"}' http://HOST:PORT/chat</code></p>"
            "</body></html>",
            200,
            {"Content-Type": "text/html; charset=utf-8"},
        )

    data: Dict = request.get_json(force=True) or {}
    message = (data.get("message") or "").strip()
    messages = data.get("messages") or []
    provider = (data.get("provider") or "ollama").strip().lower()
    if not message and not messages:
        return jsonify({"error": "message is required"}), 400
    # Basic input sanitization and limits (avoid excessive payloads)
    if message and len(message) > 8000:
        message = message[:8000]
    if isinstance(messages, list) and len(messages) > 0:
        # Keep only the last 20 turns at most
        messages = messages[-20:]

    # Default: Ollama
    try:
        if messages:
            # Use chat API with history + current user message
            chat_messages = list(messages)
            if message:
                chat_messages.append({"role": "user", "content": message})
            payload = {"model": MODEL, "messages": chat_messages, "stream": False}
            r = requests.post(f"{OLLAMA_BASE}/api/chat", json=payload, timeout=120)
            r.raise_for_status()
            j = r.json()
            # Response shape: {"message": {"role":"assistant","content":"..."}, ...}
            reply = (j.get("message") or {}).get("content", "")
            return jsonify({"reply": reply})
        else:
            # Single-turn: use generate API
            payload = {"model": MODEL, "prompt": message, "stream": False}
            r = requests.post(f"{OLLAMA_BASE}/api/generate", json=payload, timeout=120)
            r.raise_for_status()
            j = r.json()
            reply = j.get("response", "")
            return jsonify({"reply": reply})
    except requests.RequestException as e:
        return jsonify({"error": str(e)}), 502


# --- Streaming endpoint (NDJSON) ---
@app.route("/chat_stream", methods=["POST"]) 
def chat_stream() -> Response:
    data: Dict = request.get_json(force=True) or {}
    message = (data.get("message") or "").strip()
    messages = data.get("messages") or []
    provider = (data.get("provider") or "ollama").strip().lower()
    if not message and not messages:
        return jsonify({"error": "message is required"}), 400

    def _ndjson(obj: Dict) -> str:
        return json.dumps(obj, ensure_ascii=False) + "\n"

    def ollama_stream() -> Iterable[str]:
        try:
            if messages:
                # Chat API with history + current user message
                chat_messages = list(messages)
                if message:
                    chat_messages.append({"role": "user", "content": message})
                payload = {"model": MODEL, "messages": chat_messages, "stream": True}
                url = f"{OLLAMA_BASE}/api/chat"
            else:
                payload = {"model": MODEL, "prompt": message, "stream": True}
                url = f"{OLLAMA_BASE}/api/generate"
            with requests.post(
                url,
                json=payload,
                stream=True,
                timeout=(10, 600),  # connect, read
            ) as r:
                r.raise_for_status()
                for raw in r.iter_lines(decode_unicode=True):
                    if not raw:
                        continue
                    try:
                        j = json.loads(raw)
                    except Exception:
                        continue
                    # /api/generate: {"response":"...", "done": false}
                    if "response" in j and j.get("response"):
                        yield _ndjson({"response": j["response"]})
                    # /api/chat: {"message": {"role":"assistant","content":"..."}, "done": false}
                    elif "message" in j and isinstance(j.get("message"), dict):
                        content = (j["message"].get("content") or "")
                        if content:
                            yield _ndjson({"response": content})
                    if j.get("done"):
                        break
        except Exception as e:
            yield _ndjson({"error": f"ollama stream failed: {e}"})

    def gemini_cli_stream() -> Iterable[str]:
        cmd = os.environ.get("GEMINI_CMD", "gemini")
        model = os.environ.get("GEMINI_MODEL", "gemini-1.5-flash")
        args = [cmd, "stream", "-m", model, "-p", message]
        try:
            proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        except Exception as e:
            yield _ndjson({"error": f"failed to start gemini cli: {e}"})
            return
        # Stream stdout line by line
        try:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.rstrip("\n")
                if not line:
                    continue
                yield _ndjson({"response": line})
        finally:
            try:
                proc.terminate()
            except Exception:
                pass

    generator = ollama_stream if provider == "ollama" else gemini_cli_stream
    return Response(generator(), mimetype="application/x-ndjson; charset=utf-8")


def _qr_png_data_uri(u: str) -> str:
    try:
        import qrcode
        from PIL import Image  # noqa: F401  # imported for qrcode PNG backend
    except Exception:
        return ""
    img = qrcode.make(u)
    buf = BytesIO()
    img.save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{data}"


@app.route("/", methods=["GET"]) 
def root() -> Response:
    url = request.args.get("u")
    if not url:
        ip = _local_ip()
        url = f"http://{ip}:{os.environ.get('PORT', '8000')}/chat"
    data_uri = _qr_png_data_uri(url)
    img_html = (
        f"<img src='{data_uri}' alt='qr' style='width:280px;height:280px;'/>" if data_uri
        else f"<p>Please install <code>pip install qrcode Pillow</code> to generate the QR image.</p>"
    )
    html = (
        "<!doctype html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'/>"
        "<title>Local LLM Server</title>"
        "<style>body{font-family:-apple-system,system-ui,Segoe UI,Roboto,sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#fafafa;color:#222}"
        ".card{background:#fff;border:1px solid #eee;border-radius:12px;padding:24px;box-shadow:0 6px 20px rgba(0,0,0,.06);text-align:center}"
        "a{word-break:break-all}</style></head><body><div class='card'>"
        f"<h2>Local LLM Server</h2><p><a href='{url}'>{url}</a></p>"
        f"{img_html}"
        "<p style='margin-top:12px'>Scan the QR with your camera, or share the URL to your phone.</p>"
        "</div></body></html>"
    )
    return Response(html, content_type="text/html; charset=utf-8")


@app.route("/qr", methods=["GET"]) 
def qr() -> Response:
    try:
        import qrcode
        from io import BytesIO
        from PIL import Image
    except Exception:
        return Response("Pillow/qrcode not installed: pip install qrcode Pillow", status=500)

    u = request.args.get("u") or f"http://{_local_ip()}:{os.environ.get('PORT','8000')}/chat"
    img = qrcode.make(u)
    buf = BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return Response(buf.read(), content_type="image/png")


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    # Open browser automatically to the QR page after startup.
    def _open_browser():
        try:
            ip = _local_ip()
            # Open on localhost; embed LAN-reachable IP in the QR URL content.
            url = f"http://127.0.0.1:{port}/?u=http://{ip}:{port}/chat"
            webbrowser.open(url)
        except Exception:
            pass

    threading.Timer(0.8, _open_browser).start()
    app.run(host=host, port=port)
