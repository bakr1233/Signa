"""
train_spatial_cnn.py

Replaces the original repo's retrain.py + TensorFlow-Hub frozen-graph
step. That step relied on TF1 `tf.GraphDef` / `tf.Session` and a
`retrain.py` script fetched from `tensorflow/hub`'s example directory,
which no longer works against modern TensorFlow.

Same idea (fine-tune an ImageNet CNN to classify individual gesture
frames), but done with plain tf.keras transfer learning on top of
InceptionV3, saved as a standard SavedModel/.keras file so it can be
reused in extract_features.py and converted to CoreML later.

Usage:
    python3 train_spatial_cnn.py train_frames --val-split 0.2 --epochs 5 \
        --output spatial_cnn.keras --labels-out labels.txt
"""
import argparse
from pathlib import Path

import tensorflow as tf
from tensorflow.keras import layers, models


def build_model(num_classes: int, image_size: int = 299) -> tuple[tf.keras.Model, tf.keras.Model]:
    base = tf.keras.applications.InceptionV3(
        include_top=False, weights="imagenet", input_shape=(image_size, image_size, 3), pooling="avg"
    )
    base.trainable = False  # Stage 1: train only the new head.

    inputs = layers.Input(shape=(image_size, image_size, 3))
    x = tf.keras.applications.inception_v3.preprocess_input(inputs)
    x = base(x, training=False)
    outputs = layers.Dense(num_classes, activation="softmax", name="gesture_head")(x)
    model = models.Model(inputs, outputs, name="spatial_cnn")
    return model, base


def main(frames_dir: str, output: str, labels_out: str, image_size: int,
         batch_size: int, epochs: int, val_split: float, fine_tune_epochs: int):
    frames_dir = Path(frames_dir)

    train_ds = tf.keras.utils.image_dataset_from_directory(
        frames_dir, validation_split=val_split, subset="training", seed=42,
        image_size=(image_size, image_size), batch_size=batch_size, color_mode="grayscale",
    )
    val_ds = tf.keras.utils.image_dataset_from_directory(
        frames_dir, validation_split=val_split, subset="validation", seed=42,
        image_size=(image_size, image_size), batch_size=batch_size, color_mode="grayscale",
    )

    class_names = train_ds.class_names
    print(f"Classes ({len(class_names)}): {class_names}")

    # InceptionV3 expects 3 channels; frames were saved grayscale by
    # extract_frames.py, so tile the single channel into RGB.
    to_rgb = lambda x, y: (tf.image.grayscale_to_rgb(x), y)
    train_ds = train_ds.map(to_rgb).prefetch(tf.data.AUTOTUNE)
    val_ds = val_ds.map(to_rgb).prefetch(tf.data.AUTOTUNE)

    model, base = build_model(len(class_names), image_size)
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    model.summary()

    print(f"\n== Stage 1: training classification head ({epochs} epochs) ==")
    model.fit(train_ds, validation_data=val_ds, epochs=epochs)

    if fine_tune_epochs > 0:
        print(f"\n== Stage 2: fine-tuning top of InceptionV3 ({fine_tune_epochs} epochs) ==")
        base.trainable = True
        for layer in base.layers[:-30]:
            layer.trainable = False
        model.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
                      loss="sparse_categorical_crossentropy", metrics=["accuracy"])
        model.fit(train_ds, validation_data=val_ds, epochs=fine_tune_epochs)

    model.save(output)
    Path(labels_out).write_text("\n".join(class_names))
    print(f"\nSaved model to {output}")
    print(f"Saved labels to {labels_out}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fine-tune InceptionV3 to classify individual gesture frames.")
    parser.add_argument("frames_dir", help="Folder of per-class frame subfolders (output of extract_frames.py).")
    parser.add_argument("--output", default="spatial_cnn.keras")
    parser.add_argument("--labels-out", default="labels.txt")
    parser.add_argument("--image-size", type=int, default=299)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--epochs", type=int, default=5, help="Head-only training epochs.")
    parser.add_argument("--fine-tune-epochs", type=int, default=3, help="Epochs fine-tuning top InceptionV3 layers. 0 to skip.")
    parser.add_argument("--val-split", type=float, default=0.2)
    args = parser.parse_args()
    main(args.frames_dir, args.output, args.labels_out, args.image_size,
         args.batch_size, args.epochs, args.val_split, args.fine_tune_epochs)
