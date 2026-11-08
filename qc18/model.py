"""CIFAR ResNet-18 (kuangliu/pytorch-cifar layout) with QCConv2d convs.

3x3 stem 64ch stride 1 (no maxpool), BasicBlocks [2, 2, 2, 2] with 64/128/256/512 channels, 1x1 conv + BN
shortcut on the downsampling blocks, global average pool, dense FC.  Every conv (stem, block convs, shortcuts)
is a bias-free QCConv2d followed by BatchNorm (the allowed per-output-channel scale + bias), grouped in ConvBN.
Input: normalised float NCHW (see qc18.data.prep).
"""
import torch.nn as nn
import torch.nn.functional as F

from .qcconv import QCConv2d


class ConvBN(nn.Module):
    def __init__(self, cin, cout, k, stride, **qc):
        super().__init__()
        self.conv = QCConv2d(cin, cout, k, stride, k // 2, **qc)
        self.bn = nn.BatchNorm2d(cout)

    def forward(self, x):
        return self.bn(self.conv(x))


class BasicBlock(nn.Module):
    def __init__(self, cin, cout, stride, **qc):
        super().__init__()
        self.c1 = ConvBN(cin, cout, 3, stride, **qc)
        self.c2 = ConvBN(cout, cout, 3, 1, **qc)
        self.sc = ConvBN(cin, cout, 1, stride, **qc) if stride != 1 or cin != cout else None

    def forward(self, x):
        out = self.c2(F.relu(self.c1(x)))
        return F.relu(out + (self.sc(x) if self.sc is not None else x))


class QCResNet18(nn.Module):
    def __init__(self, mode="dense", b=8, estimator="ste", tau=1.0, num_classes=10, relax="none", qinit_scale="unit",
                 homotopy="none"):
        super().__init__()
        qc = dict(mode=mode, b=b, estimator=estimator, tau=tau)
        if mode != "dense":
            qc["relax"], qc["qinit_scale"], qc["homotopy"] = relax, qinit_scale, homotopy
        self.mode = mode
        self.stem = ConvBN(3, 64, 3, 1, **qc)
        blocks, cin = [], 64
        for cout, stride in ((64, 1), (128, 2), (256, 2), (512, 2)):
            for s in (stride, 1):
                blocks.append(BasicBlock(cin, cout, s, **qc))
                cin = cout
        self.blocks = nn.Sequential(*blocks)
        self.fc = nn.Linear(512, num_classes)

    def forward(self, x):
        x = self.blocks(F.relu(self.stem(x)))
        return self.fc(x.mean(dim=(2, 3)))

    def convbns(self):
        """[(name, ConvBN)] for every conv in the network (stem, block convs, shortcuts)."""
        return [(n, m) for n, m in self.named_modules() if isinstance(m, ConvBN)]

    def qconvs(self):
        return [m.conv for _, m in self.convbns()] if self.mode != "dense" else []

    def set_tau(self, tau):
        for c in self.qconvs():
            c.tau.fill_(tau)

    def set_homotopy(self, on, tau=None, lam=None):
        """Homotopy forward on/off (off = hard + STE); gibbs temperature tau / ramp weight lam."""
        for c in self.qconvs():
            c.h_on = on
            if tau is not None:
                c.tau.fill_(tau)
            if lam is not None:
                c.hlam.fill_(lam)

    def refresh(self):
        for c in self.qconvs():
            c.refresh()
