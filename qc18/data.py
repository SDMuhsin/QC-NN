"""CIFAR-10 on the GPU: the fixed 45k/5k train/val split of qc.train (seed 0), random crop (pad 4) + h-flip
augmentation (qc.train.augment, uint8 NHWC), and per-channel mean/std normalisation (preprocessing, not part
of the model) -> float NCHW channels_last."""
import torch

from nn.model.data import test_set
from qc.train import augment, split  # noqa: F401  (re-exported)

MEAN = (0.4914, 0.4822, 0.4465)
STD = (0.2470, 0.2435, 0.2616)


def prep(x, dtype=torch.float32):
    """uint8 NHWC -> normalised float NCHW (channels_last)."""
    m = torch.tensor(MEAN, device=x.device, dtype=dtype)
    s = torch.tensor(STD, device=x.device, dtype=dtype)
    x = (x.to(dtype) / 255 - m) / s
    return x.permute(0, 3, 1, 2).contiguous(memory_format=torch.channels_last)


def test(dev):
    return tuple(torch.as_tensor(t, device=dev) for t in test_set())
