"""
Signa Gemma vision server

Local FastAPI endpoint that runs a Gemma 4 multimodal model and answers
ASL→English prompts from JPEG frames sent by the iOS app.

Default model: google/gemma-4-E4B-it (fits more machines).
Override with GEMMA_MODEL=google/gemma-4-31B-it when you have enough VRAM.

Usage:
    export HF_TOKEN=hf_...   # if the model is gated on Hugging Face
    pip install -r requirements-gemma.txt
    uvicorn server:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import io
import os
import re
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image

ASL_PROMPT = (
    "You are an ASL (American Sign Language) interpreter looking at one camera frame. "
    "Identify the sign being produced. "
    "Reply with ONLY a short English word or phrase for the meaning "
    "(examples: Hello, Thank you, Yes, No, How are you). "
    "If the hands are unclear or no sign is visible, reply exactly: UNKNOWN"
)

MODEL_ID = os.environ.get("GEMMA_MODEL", "google/gemma-4-E4B-it")

_pipe = None


def _load_pipeline():
    global _pipe
    if _pipe is not None:
        return _pipe

    # Prefer token from env for gated Gemma weights.
    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    kwargs: dict[str, Any] = {"model": MODEL_ID}
    if token:
        kwargs["token"] = token

    from transformers import pipeline

    print(f"Loading Gemma vision pipeline: {MODEL_ID}")
    _pipe = pipeline("image-text-to-text", **kwargs)
    print("Gemma pipeline ready.")
    return _pipe


def _extract_text(result: Any) -> str:
    """Normalize transformers pipeline output into a plain string."""
    if result is None:
        return ""
    if isinstance(result, str):
        return result.strip()
    if isinstance(result, list) and result:
        first = result[0]
        if isinstance(first, dict):
            for key in ("generated_text", "text", "output_text"):
                if key in first and isinstance(first[key], str):
                    return first[key].strip()
            # Some multimodal pipelines nest chat messages.
            if "generated_text" in first and isinstance(first["generated_text"], list):
                msgs = first["generated_text"]
                if msgs and isinstance(msgs[-1], dict) and "content" in msgs[-1]:
                    content = msgs[-1]["content"]
                    if isinstance(content, str):
                        return content.strip()
                    if isinstance(content, list):
                        parts = [
                            c.get("text", "")
                            for c in content
                            if isinstance(c, dict) and c.get("type") == "text"
                        ]
                        return " ".join(parts).strip()
        if isinstance(first, str):
            return first.strip()
    if isinstance(result, dict):
        for key in ("generated_text", "text"):
            if key in result and isinstance(result[key], str):
                return result[key].strip()
    return str(result).strip()


def _clean_label(raw: str) -> str:
    text = raw.strip().strip('"').strip("'")
    # If the model echoed the prompt/messages, keep the last non-empty line.
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if lines:
        text = lines[-1]
    text = re.sub(r"^(answer|translation|sign)\s*:\s*", "", text, flags=re.I)
    text = text.strip()
    if not text:
        return "UNKNOWN"
    # Cap verbosity for the live caption UI.
    if len(text) > 80:
        text = text[:80].rsplit(" ", 1)[0] or text[:80]
    return text


def analyze_image(image: Image.Image) -> str:
    pipe = _load_pipeline()
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": image},
                {"type": "text", "text": ASL_PROMPT},
            ],
        }
    ]
    # Prefer the chat-style API used by Gemma-4 multimodal docs; fall back to
    # simpler image+text if the installed transformers version differs.
    try:
        result = pipe(text=messages, max_new_tokens=32)
    except TypeError:
        try:
            result = pipe(messages, max_new_tokens=32)
        except TypeError:
            result = pipe(image, text=ASL_PROMPT, max_new_tokens=32)

    return _clean_label(_extract_text(result))


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Eager-load so the first phone request isn't a multi-minute cold start.
    if os.environ.get("GEMMA_EAGER_LOAD", "1") != "0":
        try:
            _load_pipeline()
        except Exception as exc:  # noqa: BLE001 — surface at /health
            print(f"WARNING: failed to preload Gemma: {exc}")
    yield


app = FastAPI(title="Signa Gemma Vision", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {
        "ok": True,
        "model": MODEL_ID,
        "loaded": _pipe is not None,
    }


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    if not file.content_type or not file.content_type.startswith("image/"):
        # iOS may send application/octet-stream; still try to decode.
        pass
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image upload")
    try:
        image = Image.open(io.BytesIO(data)).convert("RGB")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Invalid image: {exc}") from exc

    try:
        label = analyze_image(image)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"Inference failed: {exc}") from exc

    return {"label": label, "model": MODEL_ID}
