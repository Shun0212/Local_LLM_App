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
- POST `/generate_image` **[NEW]**
  - Request: `{ "prompt": "description of image", "width": 512, "height": 512, "steps": 20 }`
    - `width`, `height`, `steps` are optional parameters.
  - Response: `{ "image": "data:image/png;base64,...", "prompt": "...", "width": 512, "height": 512 }`
- GET `/healthz` -> health check

4) Image Generation

The server supports image generation from text prompts. By default, it uses placeholder images when AI models are not available. To use real AI image generation:

```bash
# Install additional dependencies
pip install torch transformers diffusers

# Optional: Set image model (default: runwayml/stable-diffusion-v1-5)
export IMAGE_MODEL=runwayml/stable-diffusion-v1-5
```

Note: AI image generation requires significant computational resources and may be slow on CPU.
