"""
convert_to_coreml.py

New step that didn't exist in the original research repo at all (it
only ever targeted a Python/TensorFlow evaluation script). This is
the piece that actually makes the model usable from the iOS app:
converts both tf.keras models to CoreML and drops them where Xcode
expects to find them.

Produces:
    SpatialFeatureExtractor.mlpackage  -- image -> 2048-d feature vector
    GestureRNN.mlpackage               -- (frames_per_video, 2048) -> class probabilities
    GestureLabels.txt                  -- copy of labels.txt for the app bundle

Usage:
    python3 convert_to_coreml.py spatial_cnn.keras gesture_rnn.keras labels.txt \
        --out-dir coreml_out
"""
import argparse
import shutil
from pathlib import Path

import coremltools as ct
import tensorflow as tf


def convert_spatial_cnn(model_path: str, image_size: int, out_dir: Path):
    full_model = tf.keras.models.load_model(model_path)
    feature_layer = full_model.get_layer("inception_v3")
    feature_model = tf.keras.Model(inputs=full_model.input, outputs=feature_layer.output)

    mlmodel = ct.convert(
        feature_model,
        source="tensorflow",
        inputs=[ct.ImageType(name="frame", shape=(1, image_size, image_size, 3),
                             scale=1 / 127.5, bias=[-1, -1, -1])],
        convert_to="mlprogram",
    )
    mlmodel.short_description = "Per-frame CNN feature extractor for ASL gesture recognition."
    out_path = out_dir / "SpatialFeatureExtractor.mlpackage"
    mlmodel.save(str(out_path))
    print(f"Saved {out_path}")


def convert_rnn(model_path: str, out_dir: Path):
    model = tf.keras.models.load_model(model_path)
    mlmodel = ct.convert(
        model,
        source="tensorflow",
        convert_to="mlprogram",
    )
    mlmodel.short_description = "Sequence classifier over per-frame features; outputs gesture probabilities."
    out_path = out_dir / "GestureRNN.mlpackage"
    mlmodel.save(str(out_path))
    print(f"Saved {out_path}")


def main(spatial_model, rnn_model, labels_file, image_size, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    convert_spatial_cnn(spatial_model, image_size, out_dir)
    convert_rnn(rnn_model, out_dir)

    shutil.copy(labels_file, out_dir / "GestureLabels.txt")
    print(f"\nCopy everything in {out_dir}/ into the Xcode project (drag into the "
          f"target so 'Copy items if needed' + the app target checkbox are both on).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert trained CNN + RNN gesture models to CoreML.")
    parser.add_argument("spatial_model", help="spatial_cnn.keras from train_spatial_cnn.py")
    parser.add_argument("rnn_model", help="gesture_rnn.keras from train_rnn.py")
    parser.add_argument("labels_file", help="labels.txt from train_spatial_cnn.py")
    parser.add_argument("--image-size", type=int, default=299)
    parser.add_argument("--out-dir", default="coreml_out")
    args = parser.parse_args()
    main(args.spatial_model, args.rnn_model, args.labels_file, args.image_size, args.out_dir)
