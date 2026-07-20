"""
evaluate_rnn.py

Replaces rnn_eval.py. Loads a trained gesture_rnn.keras and reports
accuracy + a gold/pred dump, same as the original repo's result.txt.

Usage:
    python3 evaluate_rnn.py gesture_rnn.keras test_features.pkl --labels labels.txt --frames-per-video 60
"""
import argparse

import numpy as np
import tensorflow as tf

from rnn_data import load_labels, get_sequences


def main(model_path, feature_pickle, labels_file, frames_per_video, out_file):
    labels = load_labels(labels_file)
    rev_labels = {v: k for k, v in labels.items()}

    X, y = get_sequences(feature_pickle, frames_per_video, labels)
    model = tf.keras.models.load_model(model_path)

    probs = model.predict(X)
    preds = np.argmax(probs, axis=1)

    acc = 100.0 * np.sum(preds == y) / len(y)
    print(f"Accuracy: {acc:.2f}%")

    with open(out_file, "w") as f:
        f.write("gold,pred\n")
        for g, p in zip(y, preds):
            f.write(f"{rev_labels[g]},{rev_labels[p]}\n")
    print(f"Wrote per-example gold/pred to {out_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluate a trained gesture RNN on held-out features.")
    parser.add_argument("model", help="Path to gesture_rnn.keras from train_rnn.py")
    parser.add_argument("feature_pickle", help="Output of extract_features.py on the test set")
    parser.add_argument("--labels", default="labels.txt")
    parser.add_argument("--frames-per-video", type=int, default=60)
    parser.add_argument("--out", default="results.csv")
    args = parser.parse_args()
    main(args.model, args.feature_pickle, args.labels, args.frames_per_video, args.out)
