"""Binary activations for the qc18 QC ResNet-18 (composition over qc18.model, no copy of it).

BinAct(C): forward b = 1[x > t_c] in {0,1} (exact, dtype of x), t_c learnable per channel (init 0).
Backward (straight-through, u = x - t_c, w = ste_w, K = ste_scale):
  clip:   db/du = K 1[|u| < w]
  approx: db/du = K 2 (1 - |u|/w) 1[|u| < w]   (Bi-Real ApproxSign shape, area 2w = area of clip)
  bussgang: db/du = a_c (every element), a_c = max(0, Cov(b, x) / Var(x)) per channel over (N, H, W) of this batch
  stein:    db/du = a_c = phi((t_c - mu_c) / sigma_c) / sigma_c, mu_c / sigma_c batch mean / std of x (sigma >= 1e-3)
  (a_c detached, fp32; K is not applied to bussgang / stein; Var(x) floored at 1e-6)
  dL/dx = g db/du,  dL/dt_c = -sum over (n, h, w) of g db/du.  t_train=0: t_c frozen at 0.
Implemented as b = hard(u) + (s(u) - s(u).detach()) with s' = db/du (s - s.detach() is exactly 0, so b is exact).

binarize(model): QC-mode QCResNet18 -> every non-stem QCConv2d reads a BinAct output:
  block: h = B1(x) (shared by c1 and sc);  out = c2(B2(c1(h))) + (sc(h) if sc else x);  return relu(out).
The stem reads the FP normalised image (bin_stem=0 only).  Dense models are returned unchanged.
preact=1: B1 reads the PRE-ReLU block input s (the stem passes its BN output s0, no relu):
  block: h = B1(s);  out = c2(B2(c1(h))) + (sc(h) if sc else relu(s));  return out (pre-ReLU);
  network: relu(last block out) -> pool -> fc.  act=False: B1 = B2 = ReLU (same function as qc18).

Grad-flow logging (training forwards with grad enabled, every `log_every`-th call): that forward runs eager with
tensor hooks; per BinAct p1 = mean(b), const = frac. channels with mean(b) < 0.01 or > 0.99, pass = frac. |u| < w,
g_out = ||dL/db||, g_in = ||dL/dx|| (this BinAct's path only), t_mean / t_std, eff = mean over channels of the
effective db/du scale (a_c, or K x mean window derivative); per QCConv2d ||grad theta||; kind="bn": max |beta|, max gamma
over all BatchNorm2d.
Records are appended to `log_path` (jsonl) on the next forward call.  Other forwards: compiled (training) or eager.
"""
import json

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc18.model import BasicBlock, QCResNet18
from qc18.qcconv import QCConv2d


class BinAct(nn.Module):
    def __init__(self, C, ste="clip", w=1.0, k=1.0, t_train=1):
        super().__init__()
        assert ste in ("clip", "approx", "bussgang", "stein")
        self.t = nn.Parameter(torch.zeros(C), requires_grad=bool(t_train))
        self.ste, self.w, self.k = ste, float(w), float(k)
        self.rec = None                     # set to a dict by the logging forward

    def forward(self, x):
        rec = self.rec
        if rec is not None:
            x = x.view_as(x)                # private node: its grad is this BinAct's dL/dx only
            x.register_hook(lambda g: rec.__setitem__("g_in", g.float().norm()))
        u = x - self.t.view(1, -1, 1, 1)
        hard = (u > 0).to(x.dtype)
        if self.ste in ("clip", "approx"):
            c = u.clamp(-self.w, self.w)
            s = self.k * (c if self.ste == "clip" else 2 * c - c * c.abs() / self.w)
        else:
            a = self.gain(x.detach().float(), hard.detach().float())
            s = a.view(1, -1, 1, 1) * u.float()
        b = hard + (s - s.detach()).to(x.dtype)
        if rec is not None:
            with torch.no_grad():
                bd = b.detach().float()
                m = bd.mean((0, 2, 3))
                rec.update(p1=bd.mean(), const=((m < 0.01) | (m > 0.99)).float().mean(),
                           pass_=(u.detach().abs() < self.w).float().mean(), t_mean=self.t.mean(), t_std=self.t.std(),
                           eff=self.eff(u) if self.ste in ("clip", "approx") else a.mean(),
                           exact01=((bd == 0) | (bd == 1)).all())
            b.register_hook(lambda g: rec.__setitem__("g_out", g.float().norm()))
        return b

    def gain(self, xf, bf):
        """per-channel a_c (fp32, no grad) for bussgang / stein."""
        with torch.no_grad():
            mu = xf.mean((0, 2, 3))
            var = xf.var((0, 2, 3), unbiased=False)
            if self.ste == "bussgang":
                cov = ((bf - bf.mean((0, 2, 3)).view(1, -1, 1, 1)) * (xf - mu.view(1, -1, 1, 1))).mean((0, 2, 3))
                return (cov / var.clamp_min(1e-6)).clamp_min(0)
            sig = var.sqrt().clamp_min(1e-3)
            z = (self.t.detach().float() - mu) / sig
            return torch.exp(-0.5 * z * z) / (2 * torch.pi) ** 0.5 / sig

    def eff(self, u):
        """K x mean window derivative (clip / approx)."""
        ua = u.detach().float().abs()
        d = (ua < self.w).float() if self.ste == "clip" else 2 * (1 - ua / self.w).clamp_min(0)
        return self.k * d.mean()

    def extra_repr(self):
        return f"{self.t.numel()}, ste={self.ste}, w={self.w}, k={self.k}, t_train={self.t.requires_grad}"


class BinBlock(BasicBlock):
    def forward(self, x):
        h = self.b1(x)
        out = self.c2(self.b2(self.c1(h)))
        return F.relu(out + (self.sc(h) if self.sc is not None else x))


class PreBlock(BasicBlock):
    def forward(self, s):
        h = self.b1(s)
        out = self.c2(self.b2(self.c1(h)))
        return out + (self.sc(h) if self.sc is not None else F.relu(s))


class BinQCResNet18(QCResNet18):
    """Forward = qc18 forward; training forwards dispatch to a compiled copy, every log_every-th one eager+logged."""

    @torch._dynamo.disable
    def forward(self, x):
        self._flush()
        if not (self.training and torch.is_grad_enabled()):
            return self._net(x)                        # eval / BN recalibration: eager, as qc18.train
        self._calls += 1
        if self._log_path and self._log_every and self._calls % self._log_every == 0:
            return self._logged_forward(x)
        return self._cfwd(x)

    def _net(self, x):
        if not self._preact:
            return QCResNet18.forward(self, x)
        x = F.relu(self.blocks(self.stem(x)))
        return self.fc(x.mean(dim=(2, 3)))

    def _logged_forward(self, x):
        step = self._calls
        recs = {n: {} for n, _ in self.binacts()}
        for n, m in self.binacts():
            m.rec = recs[n]
        crec = {}
        self._hooks = [c.theta.register_hook(lambda g, n=n: crec.__setitem__(n, g.float().norm()))
                       for n, c in self.named_modules() if isinstance(c, QCConv2d) and c.theta.requires_grad]
        try:
            out = self._net(x)
        finally:
            for _, m in self.binacts():
                m.rec = None
        with torch.no_grad():
            bns = [m for m in self.modules() if isinstance(m, nn.BatchNorm2d) and m.affine]
            recs["bn"] = dict(max_abs_beta=max(m.bias.abs().max() for m in bns), max_gamma=max(m.weight.max() for m in bns))
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
                if n != "bn":
                    d["exact01"] = bool(d.get("exact01", True))
                fh.write(json.dumps(dict(step=step, epoch=ep, layer=n, kind="bn" if n == "bn" else "binact", **d)) + "\n")
            for n, g in crec.items():           # theta hooks fire only once the step's backward has run
                fh.write(json.dumps(dict(step=step, epoch=ep, layer=n, kind="conv", g_theta=f(g))) + "\n")
        for h in self._hooks:
            h.remove()
        self._hooks = []

    def binacts(self):
        return [(n, m) for n, m in self.named_modules() if isinstance(m, BinAct)]


def binarize(model, ste="clip", w=1.0, bin_stem=0, log_path="", log_every=50, spe=1, compile=True, act=True, k=1.0,
             t_train=1, preact=0):
    """act=False: no BinAct (FP-activation reference), only the logging forward (grad theta records)."""
    if model.mode == "dense":
        return model
    assert not bin_stem, "--bin-stem 1 not implemented"
    for blk in (model.blocks if act or preact else ()):
        dev = blk.c1.bn.weight.device
        blk.__class__ = PreBlock if preact else BinBlock
        blk.b1 = BinAct(blk.c1.conv.cin, ste, w, k, t_train).to(dev) if act else nn.ReLU()
        blk.b2 = BinAct(blk.c2.conv.cin, ste, w, k, t_train).to(dev) if act else nn.ReLU()
    model.__class__ = BinQCResNet18
    model._preact = bool(preact)
    model._hooks, model._calls, model._pending, model._log_path, model._log_every, model._spe = [], 0, None, log_path, log_every, spe
    fwd = lambda x: model._net(x)
    model._cfwd = torch.compile(fwd) if compile else fwd
    return model
