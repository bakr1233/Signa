# Signa gesture recognition pipeline

Modernized port of [hthuwal/sign-language-gesture-recognition](https://github.com/hthuwal/sign-language-gesture-recognition) for use in the Signa iOS app. Same overall approach (CNN extracts per-frame features, an RNN classifies the sequence), rewritten against current TensorFlow/Keras instead of the original TF1 + tflearn code (which no longer runs on modern TensorFlow/NumPy), with a new final step that converts everything to CoreML for on-device use.

Related reference for LSTM action/sign detection workflows: [nicknochnack/ActionDetectionforSignLanguage](https://github.com/nicknochnack/ActionDetectionforSignLanguage).

## Why the original repo couldn't just be dropped in

- `predict_spatial.py` builds a raw `tf.GraphDef` / `tf.Session` graph and expects a frozen graph from a `retrain.py` script that used to live in `tensorflow/hub`'s examples. That retraining flow no longer exists in current TensorFlow Hub.
- `rnn_utils.py` / `rnn_train.py` / `rnn_eval.py` depend on tflearn, which hasn't been updated in years and breaks on modern TensorFlow/NumPy.
- Nothing in the original repo targets a mobile/CoreML output — it's a pure research/evaluation pipeline.

This folder keeps the same ideas (fixed-length frame sampling, hand segmentation, InceptionV3 features, LSTM over the sequence) but with current libraries, plus a CoreML export step at the end.

## Pipeline, in order

| Step | Script | Replaces |
|------|--------|----------|
| 1 | `extract_frames.py` | `video-to-frame.py` |
| 2 | `train_spatial_cnn.py` | `retrain.py` (TF Hub) |
| 3 | `extract_features.py` | `predict_spatial.py` |
| 4 | `train_rnn.py` | `rnn_train.py` / `rnn_utils.py` |
| 5 | `evaluate_rnn.py` | `rnn_eval.py` |
| 6 | `convert_to_coreml.py` | *(new — not in original repo)* |

```bash
pip install -r requirements.txt

# 1. Extract fixed-length frame sequences (defaults to 60 frames/video;
#    the original used 201, which is more than a live app needs).
python3 extract_frames.py train_videos train_frames --frames-per-video 60
python3 extract_frames.py test_videos  test_frames  --frames-per-video 60

# 2. Fine-tune InceptionV3 to classify individual frames.
python3 train_spatial_cnn.py train_frames \
    --output spatial_cnn.keras --labels-out labels.txt

# 3. Extract per-frame feature vectors for train + test.
python3 extract_features.py spatial_cnn.keras train_frames --out train_features.pkl
python3 extract_features.py spatial_cnn.keras test_frames  --out test_features.pkl

# 4. Train the sequence classifier (LSTM).
python3 train_rnn.py train_features.pkl --labels labels.txt \
    --frames-per-video 60 --output gesture_rnn.keras

# 5. Check accuracy on held-out data.
python3 evaluate_rnn.py gesture_rnn.keras test_features.pkl \
    --labels labels.txt --frames-per-video 60

# 6. Convert both models to CoreML for the app.
python3 convert_to_coreml.py spatial_cnn.keras gesture_rnn.keras labels.txt \
    --out-dir coreml_out
```

Drag everything under `coreml_out/` into the Xcode project (target membership + "Copy items if needed" both checked). `SignClassifier.swift` looks for these exact filenames:

- `SpatialFeatureExtractor.mlmodelc` (or `.mlpackage`)
- `GestureRNN.mlmodelc` (or `.mlpackage`)
- `GestureLabels.txt`

(Xcode compiles `.mlpackage` → `.mlmodelc` automatically at build time — you don't convert that part yourself.)

## Getting training data

This pipeline (and the original repo) was built around the Argentinian Sign Language (LSA64) dataset. It's gated behind an academic license from its owners — you need to request/download it yourself and agree to their terms; it isn't something that can be fetched automatically. If your goal is ASL specifically (LSA64 is Argentinian Sign Language, not American), you'll want an ASL gesture/word dataset instead — e.g. WLASL or your own recorded videos organized the same way (`train_videos/<gesture>/*.mp4`).

## Hardware / time expectations

- Frame extraction and hand segmentation: CPU is fine, minutes per hundred videos.
- `train_spatial_cnn.py`: this is the expensive step (fine-tuning InceptionV3 on thousands of frame images). A GPU is strongly recommended — CPU-only could take many hours depending on dataset size.
- `train_rnn.py`: small and fast once features are extracted, fine on CPU.
- `convert_to_coreml.py`: seconds.

## What was and wasn't verified while building this

The full pipeline needs a GPU/dataset to run end-to-end. What was verified in-repo:

- Scripts are structured for current TensorFlow/Keras + coremltools.
- `SignClassifier.swift` uses standard CoreML APIs (`MLModel`, `MLDictionaryFeatureProvider`, `MLMultiArray`) and degrades gracefully when models aren't bundled yet (ASL→English shows "Listening for signs…" without crashing).

Once you have real `.mlpackage` files, open them in Xcode's model preview to confirm the actual input/output feature names match what `SignClassifier.swift` expects (it reads whatever name is first in each model's description).

## Gemma 4 vision server (live ASL→English)

For richer sign understanding without training CoreML models, run the local multimodal server:

```bash
cd gemma_server
pip install -r requirements-gemma.txt
uvicorn server:app --host 0.0.0.0 --port 8000
```

Default model is `google/gemma-4-E4B-it`. For 31B:

```bash
export GEMMA_MODEL=google/gemma-4-31B-it
```

Full instructions: [`gemma_server/README.md`](gemma_server/README.md). Enable it in the iOS app under **Settings → Gemma vision**.

