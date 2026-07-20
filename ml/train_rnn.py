"""
train_rnn.py

Replaces the original repo's rnn_train.py + rnn_utils.get_network_wide().
Same architecture in spirit (a single wide LSTM over the per-frame CNN
features, feeding a softmax head) but implemented in tf.keras instead
of tflearn, which has been unmaintained and incompatible with modern
TensorFlow/NumPy for years.

Usage:
    python3 train_rnn.py train_features.pkl --labels labels.txt \
        --frames-per-video 60 --epochs 20 --output gesture_rnn.keras
"""
import argparse

import tensorflow as tf
from tensorflow.keras import layers, models

from rnn_data import load_labels, get_sequences, train_val_split


def build_model(frames_per_video: int, feature_dim: int, num_classes: int) -> tf.keras.Model:
    inputs = layers.Input(shape=(frames_per_video, feature_dim))
    x = layers.LSTM(256, dropout=0.2)(inputs)
    outputs = layers.Dense(num_classes, activation="softmax")(x)
    return models.Model(inputs, outputs, name="gesture_rnn")


def main(feature_pickle, labels_file, frames_per_video, epochs, batch_size, val_split, output):
    labels = load_labels(labels_file)
    X, y = get_sequences(feature_pickle, frames_per_video, labels)
    X_train, X_val, y_train, y_val = train_val_split(X, y, val_split)

    model = build_model(frames_per_video, X.shape[-1], len(labels))
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    model.summary()

    model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        batch_size=batch_size,
        epochs=epochs,
    )

    model.save(output)
    print(f"\nSaved RNN model to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train an LSTM over per-frame CNN features.")
    parser.add_argument("feature_pickle", help="Output of extract_features.py")
    parser.add_argument("--labels", default="labels.txt", help="Class list from train_spatial_cnn.py")
    parser.add_argument("--frames-per-video", type=int, default=60)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--val-split", type=float, default=0.2)
    parser.add_argument("--output", default="gesture_rnn.keras")
    args = parser.parse_args()
    main(args.feature_pickle, args.labels, args.frames_per_video,
         args.epochs, args.batch_size, args.val_split, args.output)
