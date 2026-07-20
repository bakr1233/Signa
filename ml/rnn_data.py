"""
rnn_data.py

Replaces rnn_utils.py's get_data(). Same job: reshape the flat list of
[feature_vector, label] pairs from extract_features.py into fixed-length
sequences (one sequence per source video) for the RNN, and one-hot
encode the labels. No tflearn/sklearn dependency required.
"""
from collections import deque
from pathlib import Path
import pickle

import numpy as np


def load_labels(labels_file: str) -> dict:
    names = Path(labels_file).read_text().splitlines()
    return {name.strip().lower(): i for i, name in enumerate(names) if name.strip()}


def get_sequences(feature_pickle: str, frames_per_video: int, labels: dict):
    """Group consecutive frame features into `frames_per_video`-length
    sequences and attach the (numeric) label for that video."""
    X, y = [], []
    window = deque()

    with open(feature_pickle, "rb") as f:
        frames = pickle.load(f)

    for feat, label in frames:
        window.append(feat)
        if len(window) == frames_per_video:
            X.append(np.array(window, dtype=np.float32))
            y.append(labels[label.lower()])
            window.clear()

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.int64)
    print(f"Loaded {X.shape[0]} sequences of shape {X.shape[1:]}")
    return X, y


def train_val_split(X, y, val_split=0.2, seed=42):
    rng = np.random.default_rng(seed)
    idx = rng.permutation(len(X))
    cut = int(len(X) * (1 - val_split))
    train_idx, val_idx = idx[:cut], idx[cut:]
    return X[train_idx], X[val_idx], y[train_idx], y[val_idx]
