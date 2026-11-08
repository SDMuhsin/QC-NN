"""Shared helpers for the qc18 measurement tools."""
import torch

from ..model import QCResNet18


def load(path, dev="cuda"):
    """qc18 checkpoint -> (ckpt dict, fp32 model in eval mode, channels_last)."""
    ck = torch.load(path, map_location=dev)
    a = ck["args"]
    model = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"]).to(dev).to(memory_format=torch.channels_last)
    model.load_state_dict(ck["state"])
    return ck, model.eval()


def layer_names():
    """Conv names in model.qconvs() order (snapshot list order)."""
    return [n for n, _ in QCResNet18("signed", 8).convbns()]
