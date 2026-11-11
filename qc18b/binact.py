"""Binary activations for the qc18 QC ResNet-18 (composition over qc18.model, no copy of it).

BinAct(C): forward b = 1[x > t_c] in {0,1} (exact, dtype of x), t_c learnable per channel (init 0).
Backward (straight-through, u = x - t_c, w = ste_w):
  clip:   db/du = 1[|u| < w]
  approx: db/du = 2 (1 - |u|/w) 1[|u| < w]   (Bi-Real ApproxSign shape, area 2w = area of clip)
  dL/dx = g db/du,  dL/dt_c = -sum over (n, h, w) of g db/du.
Implemented as b = hard(u) + (s(u) - s(u).detach()) with s' = db/du (s - s.detach() is exactly 0, so b is exact).

binarize(model): QC-mode QCResNet18 -> every non-stem QCConv2d reads a BinAct output:
  block: h = B1(x) (shared by c1 and sc);  out = c2(B2(c1(h))) + (sc(h) if sc else x);  return relu(out).
The stem reads the FP normalised image (bin_stem=0 only).  Dense models are returned unchanged.

Grad-flow logging (training forwards with grad enabled, every `log_every`-th call): that forward runs eager with
tensor hooks; per BinAct p1 = mean(b), const = frac. channels with mean(b) < 0.01 or > 0.99, pass = frac. |u| < w,
g_out = ||dL/db||, g_in = ||dL/dx|| (this BinAct's path only), t_mean / t_std; per QCConv2d ||grad theta||.
Records are appended to `log_path` (jsonl) on the next forward call.  Other forwards: compiled (training) or eager.
"""
import json

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc18.model import BasicBlock, QCResNet18
from qc18.qcconv import QCConv2d


class BinAct(nn.Module):
    def __init__(self, C, ste="clip", w=1.0):
        super().__init__()
        assert ste in ("clip", "approx")
        self.t = nn.Parameter(torch.zeros(C))
        self.ste, self.w = ste, float(w)
        self.rec = None                     # set to a dict by the logging forward

    def forward(self, x):
        rec = self.rec
        if rec is not None:
            x = x.view_as(x)                # private node: its grad is this BinAct's dL/dx only
            x.register_hook(lambda g: rec.__setitem__("g_in", g.float().norm()))
        u = x - self.t.view(1, -1, 1, 1)
        c = u.clamp(-self.w, self.w)
        s = c if self.ste == "clip" else 2 * c - c * c.abs() / self.w
        b = (u > 0).to(x.dtype) + (s - s.detach()).to(x.dtype)
        if rec is not None:
            with torch.no_grad():
                bd = b.detach().float()
                m = bd.mean((0, 2, 3))
                rec.update(p1=bd.mean(), const=((m < 0.01) | (m > 0.99)).float().mean(),
                           pass_=(u.detach().abs() < self.w).float().mean(), t_mean=self.t.mean(), t_std=self.t.std(),
                           exact01=((bd == 0) | (bd == 1)).all())
            b.register_hook(lambda g: rec.__setitem__("g_out", g.float().norm()))
        return b

    def extra_repr(self):
        return f"{self.t.numel()}, ste={self.ste}, w={self.w}"


class BinBlock(BasicBlock):
    def forward(self, x):
        h = self.b1(x)
        out = self.c2(self.b2(self.c1(h)))
        return F.relu(out + (self.sc(h) if self.sc is not None else x))


class BinQCResNet18(QCResNet18):
    """Forward = qc18 forward; training forwards dispatch to a compiled copy, every log_every-th one eager+logged."""

    @torch._dynamo.disable
    def forward(self, x):
        self._flush()
        if not (self.training and torch.is_grad_enabled()):
            return QCResNet18.forward(self, x)         # eval / BN recalibration: eager, as qc18.train
        self._calls += 1
        if self._log_path and self._log_every and self._calls % self._log_every == 0:
            return self._logged_forward(x)
        return self._cfwd(x)

    def _logged_forward(self, x):
        step = self._calls
        recs = {n: {} for n, _ in self.binacts()}
        for n, m in self.binacts():
            m.rec = recs[n]
        crec = {}
        self._hooks = [c.theta.register_hook(lambda g, n=n: crec.__setitem__(n, g.float().norm()))
                       for n, c in self.named_modules() if isinstance(c, QCConv2d) and c.theta.requires_grad]
        try:
            out = QCResNet18.forward(self, x)
        finally:
            for _, m in self.binacts():
                m.rec = None
        self._pending = (step, recs, crec)
        return out

    def _flush(self):
        if self._pending is None:
            return
        step, recs, crec = self._pending
        self._pending = None
        ep = (step - 1) // self._spe
        f = lambda v: float(v) if torch.is_tensor(v) else v
        with open(self._log_path, "a") as fh:
            for n, r in recs.items():
                d = {k.rstrip("_"): f(v) for k, v in r.items()}
                d["exact01"] = bool(d.get("exact01", True))
                fh.write(json.dumps(dict(step=step, epoch=ep, layer=n, kind="binact", **d)) + "\n")
            for n, g in crec.items():           # theta hooks fire only once the step's backward has run
                fh.write(json.dumps(dict(step=step, epoch=ep, layer=n, kind="conv", g_theta=f(g))) + "\n")
        for h in self._hooks:
            h.remove()
        self._hooks = []

    def binacts(self):
        return [(n, m) for n, m in self.named_modules() if isinstance(m, BinAct)]


def binarize(model, ste="clip", w=1.0, bin_stem=0, log_path="", log_every=50, spe=1, compile=True, act=True):
    """act=False: no BinAct (FP-activation reference), only the logging forward (grad theta records)."""
    if model.mode == "dense":
        return model
    assert not bin_stem, "--bin-stem 1 not implemented"
    for blk in (model.blocks if act else ()):
        dev = blk.c1.bn.weight.device
        blk.__class__ = BinBlock
        blk.b1 = BinAct(blk.c1.conv.cin, ste, w).to(dev)
        blk.b2 = BinAct(blk.c2.conv.cin, ste, w).to(dev)
    model.__class__ = BinQCResNet18
    model._hooks, model._calls, model._pending, model._log_path, model._log_every, model._spe = [], 0, None, log_path, log_every, spe
    fwd = lambda x: QCResNet18.forward(model, x)
    model._cfwd = torch.compile(fwd) if compile else fwd
    return model
