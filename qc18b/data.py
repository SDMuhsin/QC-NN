"""CIFAR-100 (python pickle, fine labels, 100 classes) on the GPU, mirroring qc18.data: the fixed 45k/5k
train/val split (np.random.default_rng(0) permutation of the 50k train images, as qc.train.split), random crop
(pad 4) + h-flip augmentation (qc.train.augment, re-exported), per-channel mean/std normalisation -> float NCHW
channels_last.  Data dir: $QC18B_DATA (default /workspace/PulseGrad/data/cifar-100-python; files train, test).
MEAN / STD: per-channel statistics of the 45k train split (pixels / 255, population std), computed once:
    mean (0.5078, 0.4873, 0.4415), std (0.2675, 0.2566, 0.2765)."""
import os
import pickle

import numpy as np
import torch

from qc.train import augment  # noqa: F401  (re-exported)

DATA = os.environ.get("QC18B_DATA", "/workspace/PulseGrad/data/cifar-100-python")
MEAN = (0.5078, 0.4873, 0.4415)
STD = (0.2675, 0.2566, 0.2765)
NUM_CLASSES = 100


def _load(name):
    with open(os.path.join(DATA, name), "rb") as f:
        d = pickle.load(f, encoding="bytes")
    x = d[b"data"].reshape(-1, 3, 32, 32).transpose(0, 2, 3, 1)  # NHWC uint8
    return np.ascontiguousarray(x), np.array(d[b"fine_labels"], dtype=np.int64)


def split(dev):
    x, y = _load("train")
    p = np.random.default_rng(0).permutation(len(x))
    t = lambda a: torch.as_tensor(a, device=dev)
    return (t(x[p[:45000]]), t(y[p[:45000]])), (t(x[p[45000:]]), t(y[p[45000:]]))


def test(dev):
    return tuple(torch.as_tensor(t, device=dev) for t in _load("test"))


def prep(x, dtype=torch.float32):
    """uint8 NHWC -> normalised float NCHW (channels_last)."""
    m = torch.tensor(MEAN, device=x.device, dtype=dtype)
    s = torch.tensor(STD, device=x.device, dtype=dtype)
    x = (x.to(dtype) / 255 - m) / s
    return x.permute(0, 3, 1, 2).contiguous(memory_format=torch.channels_last)
