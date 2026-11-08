"""Shared helpers for the qc18 measurement tools."""
import torch

from ..data import prep
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


@torch.no_grad()
def recal_v(model, x, bs=500):
    """BN running statistics = exact average over x for the network of the stored v: BN in train mode, every
    QCConv2d in eval mode (train.recal_bn runs the convs in train mode = hard(theta), which ignores moves written
    into v).  Leaves the model in eval mode."""
    model.train()
    for c in model.qconvs():
        c.eval()
    bns = [m for m in model.modules() if isinstance(m, torch.nn.BatchNorm2d)]
    for m in bns:
        m.reset_running_stats()
        m.momentum = None
    for i in range(0, len(x), bs):
        model(prep(x[i:i + bs]))
    for m in bns:
        m.momentum = 0.1
    model.eval()
