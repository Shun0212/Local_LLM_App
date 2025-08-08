Local LLM Flask server (English only)

1) Install dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2) Run

```bash
source .venv/bin/activate
export OLLAMA_BASE=http://localhost:11434
export OLLAMA_MODEL=gpt-oss:20b
export HOST=0.0.0.0
export PORT=8000
python3 app.py
```

3) Endpoints

- POST `/chat`
  - Request: `{ "message": "...", "messages": [{"role":"user|assistant|system","content":"..."}], "provider": "ollama|gemini" }`
    - `messages` optional. When provided, server uses prior conversation for context (Ollama `/api/chat`).
  - Response: `{ "reply": "..." }`
- POST `/chat_stream`
  - Same as `/chat`, responds with NDJSON lines like `{"response":"..."}`.
- GET `/healthz` -> health check
