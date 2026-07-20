# Signa Gemma vision server

Local multimodal inference for ASL→English. The iOS app POSTs camera JPEGs to
`POST /analyze` while recording.

**Gemma 4 31B does not run on the iPhone.** This server runs on a Mac/GPU host;
Signa calls it over your LAN.

## Models

| Env | Model | Notes |
|-----|--------|--------|
| default | `google/gemma-4-E4B-it` | Smaller multimodal Gemma 4 — preferred for laptops |
| `GEMMA_MODEL=google/gemma-4-31B-it` | 31B instruct | Needs substantial GPU VRAM |

## Setup

```bash
cd ml/gemma_server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-gemma.txt

# If the model is gated on Hugging Face:
huggingface-cli login
# or: export HF_TOKEN=hf_...

# Optional: skip eager load for faster process start (first request will be slow)
# export GEMMA_EAGER_LOAD=0

uvicorn server:app --host 0.0.0.0 --port 8000
```

Check health:

```bash
curl http://127.0.0.1:8000/health
```

Test analyze:

```bash
curl -X POST http://127.0.0.1:8000/analyze -F "file=@frame.jpg"
# -> {"label":"Hello","model":"google/gemma-4-E4B-it"}
```

## Connect the iPhone app

1. Find your Mac’s LAN IP (`System Settings → Network`, or `ipconfig getifaddr en0`).
2. In Signa → Settings → **Gemma vision**:
   - Enable **Use Gemma vision**
   - Server URL: `http://YOUR_MAC_IP:8000`
3. ASL→English → record. Captions use Gemma when the server is reachable; otherwise Vision hand-pose fallback.

Phone and Mac must be on the same Wi‑Fi. Simulator can use `http://127.0.0.1:8000`.
