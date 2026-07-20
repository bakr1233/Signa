"""
extract_features.py

Replaces predict_spatial.py. The original used a raw TF1 frozen graph
(`tf.GraphDef`, `tf.Session`, `import/<op_name>` lookups) to pull a
2048-d pooled feature vector per frame. Here we just load the
tf.keras model trained by train_spatial_cnn.py and read its pooling
layer output directly -- no graph surgery needed.

Produces the same downstream artifact as the original: a pickle file
of [feature_vector, class_label] pairs, consumed by train_rnn.py.

Usage:
    python3 extract_features.py spatial_cnn.keras train_frames --out train_features.pkl
    python3 extract_features.py spatial_cnn.keras test_frames  --out test_features.pkl
"""
import argparse
import pickle
from pathlib import Path

import numpy as np
import tensorflow as tf
from tqdm import tqdm


def build_feature_extractor(model_path: str) -> tf.keras.Model:
    full_model = tf.keras.models.load_model(model_path)
    # The penultimate layer of build_model() in train_spatial_cnn.py is
    # the InceptionV3 global-average-pool output, i.e. the layer feeding
    # the "gesture_head" Dense. Grab it by name so this stays correct
    # even if Keras renames intermediate layers.
    pooled_output = full_model.get_layer("inception_v3").output
    return tf.keras.Model(inputs=full_model.input, outputs=pooled_output, name="feature_extractor")


def load_and_preprocess(path: Path, image_size: int) -> np.ndarray:
    img = tf.io.read_file(str(path))
    img = tf.io.decode_jpeg(img, channels=1)
    img = tf.image.resize(img, [image_size, image_size])
    img = tf.image.grayscale_to_rgb(img)
    img = tf.keras.applications.inception_v3.preprocess_input(img)
    return img


def main(model_path: str, frames_folder: str, out_file: str, image_size: int, batch_size: int):
    frames_root = Path(frames_folder)
    extractor = build_feature_extractor(model_path)

    class_dirs = sorted(p for p in frames_root.iterdir() if p.is_dir())
    predictions = []

    for class_dir in class_dirs:
        label = class_dir.name
        frame_paths = sorted(class_dir.glob("*.jpeg"))
        print(f"Extracting features for class '{label}' ({len(frame_paths)} frames)")

        for i in tqdm(range(0, len(frame_paths), batch_size), ascii=True):
            batch_paths = frame_paths[i:i + batch_size]
            batch = tf.stack([load_and_preprocess(p, image_size) for p in batch_paths])
            features = extractor(batch, training=False).numpy()
            for feat in features:
                predictions.append([feat.tolist(), label])

    with open(out_file, "wb") as f:
        pickle.dump(predictions, f)
    print(f"\nWrote {len(predictions)} feature vectors to {out_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract per-frame CNN feature vectors for RNN training.")
    parser.add_argument("model", help="Path to spatial_cnn.keras from train_spatial_cnn.py")
    parser.add_argument("frames_folder", help="Folder of per-class frame subfolders (output of extract_frames.py)")
    parser.add_argument("--image-size", type=int, default=299)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--out", default="features.pkl")
    args = parser.parse_args()
    main(args.model, args.frames_folder, args.out, args.image_size, args.batch_size)
