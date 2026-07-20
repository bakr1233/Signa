# Signa

ASL ↔ English sign-language translator (iOS).

- **App:** `Version_0_1/` — SwiftUI client (camera ASL→English, English→ASL avatar, dictionary, feedback).
- **ML pipeline:** `ml/` — train CNN+LSTM gesture models and export CoreML bundles.
- **Gemma vision:** `ml/gemma_server/` — local Gemma 4 multimodal API for richer ASL→English when a GPU host is available.

## Quick start (Gemma vision)

```bash
cd ml/gemma_server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-gemma.txt
huggingface-cli login   # if the model is gated
uvicorn server:app --host 0.0.0.0 --port 8000
```

In the app: **Settings → Gemma vision** → enable → set URL to `http://YOUR_MAC_LAN_IP:8000` (simulator can use `http://127.0.0.1:8000`).

See [`ml/gemma_server/README.md`](ml/gemma_server/README.md). Training/CoreML steps: [`ml/README.md`](ml/README.md).
