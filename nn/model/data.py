"""CIFAR-10 loader (python pickle version, see nn/fetch.sh).

Images are returned as uint8 NHWC (raw pixels 0..255), exactly what the MLPerf Tiny
ResNet-8 was trained on (no mean/std normalisation, see mlcommons/tiny train.py).
"""
import os
import pickle

import numpy as np

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
CIFAR_DIR = os.path.join(DATA_DIR, "cifar-10-batches-py")
H5_PATH = os.path.join(DATA_DIR, "pretrainedResnet.h5")


def _load(name):
    with open(os.path.join(CIFAR_DIR, name), "rb") as f:
        d = pickle.load(f, encoding="bytes")
    x = d[b"data"].reshape(-1, 3, 32, 32).transpose(0, 2, 3, 1)  # NHWC uint8
    return np.ascontiguousarray(x), np.array(d[b"labels"], dtype=np.int64)


def test_set():
    return _load("test_batch")


def train_set():
    xs, ys = zip(*[_load(f"data_batch_{i}") for i in range(1, 6)])
    return np.concatenate(xs), np.concatenate(ys)
