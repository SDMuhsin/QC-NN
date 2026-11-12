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
arch="bireal" (needs preact=1; same modules / state_dict keys, wiring only; A = BinAct, or ReLU when act=False):
  block: h = A1(s);  y1 = c1(h) + (sc(h) if sc else s);  return c2(A2(y1)) + y1  (pre-ReLU).

Grad-flow logging (training forwards with grad enabled, every `log_every`-th call): that forward runs eager with
tensor hooks; per BinAct p1 = mean(b), const = frac. channels with mean(b) < 0.01 or > 0.99, pass = frac. |u| < w,
g_out = ||dL/db||, g_in = ||dL/dx|| (this BinAct's path only), t_mean / t_std, eff = mean over channels of the
effective db/du scale (a_c, or K x mean window derivative); per QCConv2d ||grad theta||; kind="bn": max |beta|, max gamma
over all BatchNorm2d.
stem_therm K > 0 (therm_stem): the stem reads a fixed thermometer code of the image instead: per colour channel c and
level i < K, plane = 1[pixel_c > (i+0.5)*256/K - 0.5] (raw uint8 units; threshold moved to floor(.)+0.5, strictly
between integers, same code), applied to the normalised input via (v/255 - mean_c)/std_c; 3K planes {0,1}, order (c, i);
model.stem = ThermConvBN(3K, 64, 3, 1) (same state_dict keys stem.conv / stem.bn).
Records are appended to `log_path` (jsonl) on the next forward call.  Other forwards: compiled (training) or eager.
Progressive binarisation (set_prog(model, steps) with steps = round(H * total steps) > 0): training forward number t
(0-based, counted in BinQCResNet18.forward) uses p = min(1, t / steps) in every BinAct; while p < 1 each BinAct output is
y = where(m, b, soft), m = (U[0,1) < p) resampled every forward, b = hard + STE as above, soft = a_c relu(x) with
a_c = mean(hard)_c / mean(relu(x))_c over (N, H, W) of this batch (detached, fp32; 1 if the denominator is 0), autograd
derivative of soft exact.  p = 1 / eval / no-grad (BN recal, val): y = b (mix off).
MultiBitAct(C, nbits) (--abits-blocks / --abits; subclass of BinAct, replaces b1 and b2 in the listed blocks): L = 2^N - 1,
  forward q = clamp(floor(u / s_c) + 1, 0, L) for u = x - t_c > 0, else 0 (levels 0..L, exact integers; u / s_c in fp32,
  output in x.dtype); N = 1: q = 1[u > 0] == BinAct.  t_c learnable (init 0); s_c learnable, set once from the first
  forward that sees it (eager): s_c = max(2 std_c / L, 1e-3), std over (N, H, W), biased;
  the forward uses max(s_c, 1e-3).
  Backward: dq/du = K 1[-w <= u <= (L - 1) s_c + w] (the hull of BinAct's clip window |u - j s_c| <= w around each of the
  L thresholds j s_c; L = 1 -> identical to BinAct clip), dL/dt_c = -sum g dq/du as BinAct;
  dq/ds_c = -(u / s_c^2) g_s 1[0 < u < L s_c] (LSQ-style, slope of the linear u / s_c in the active range, LSQ grad scale
  g_s = 1 / sqrt(N H W L) per channel, K not applied).  ste must be "clip"; no progressive mix.
"""
import json

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc18.model import BasicBlock, ConvBN, QCResNet18
from qc18.qcconv import QCConv2d


class BinAct(nn.Module):
    def __init__(self, C, ste="clip", w=1.0, k=1.0, t_train=1):
        super().__init__()
        assert ste in ("clip", "approx", "bussgang", "stein")
        self.t = nn.Parameter(torch.zeros(C), requires_grad=bool(t_train))
        self.ste, self.w, self.k = ste, float(w), float(k)
        self.rec = None                     # set to a dict by the logging forward
        self.mix = False                    # progressive: mix hard / soft with P(hard) = self.p (training, grad only)
        self.register_buffer("p", torch.ones(()), persistent=False)

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
        if self.mix and self.training and torch.is_grad_enabled():
            hd = hard.detach().float()
            r = F.relu(x)
            with torch.no_grad():
                den = r.detach().float().mean((0, 2, 3))
                a = torch.where(den > 0, hd.mean((0, 2, 3)) / den.clamp_min(1e-30), torch.ones_like(den))
            soft = (a.view(1, -1, 1, 1) * r.float()).to(x.dtype)
            m = torch.rand(x.shape, device=x.device) < self.p
            b = torch.where(m, b, soft)
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


class MultiBitAct(BinAct):
    def __init__(self, C, nbits, ste="clip", w=1.0, k=1.0, t_train=1):
        assert ste == "clip" and nbits >= 1, (ste, nbits)
        super().__init__(C, ste, w, k, t_train)
        self.nbits, self.L = int(nbits), 2 ** int(nbits) - 1
        self.s = nn.Parameter(torch.ones(C))
        self.register_buffer("inited", torch.zeros((), dtype=torch.bool))
        self._ready = False                 # python mirror of `inited` (no tensor branch under torch.compile)

    def _load_from_state_dict(self, sd, prefix, *args, **kw):
        super()._load_from_state_dict(sd, prefix, *args, **kw)
        self._ready = bool(self.inited)

    def forward(self, x):
        assert not self.mix, "--prog not supported with MultiBitAct"
        if not self._ready:
            with torch.no_grad():
                sd0 = x.detach().float().std((0, 2, 3), unbiased=False)
                self.s.copy_((2 * sd0 / self.L).clamp_min(1e-3))
                self.inited.fill_(True)
            self._ready = True
        rec = self.rec
        if rec is not None:
            x = x.view_as(x)
            x.register_hook(lambda g: rec.__setitem__("g_in", g.float().norm()))
        u = x - self.t.view(1, -1, 1, 1)
        s_d = self.s.detach().clamp_min(1e-3).view(1, -1, 1, 1)        # guard: s_c used >= 1e-3
        uf = u.detach().float()
        hard = torch.where(u.detach() > 0, (torch.floor(uf / s_d) + 1).clamp(0, self.L), torch.zeros_like(uf)).to(x.dtype)
        sx = self.k * torch.clamp(u, torch.full_like(s_d, -self.w).to(x.dtype), ((self.L - 1) * s_d + self.w).to(x.dtype))                   # L = 1: BinAct clip surrogate
        n = x.numel() // x.shape[1]
        gs = 1.0 / (n * self.L) ** 0.5
        sg = self.s * gs
        s_sc = (sg - sg.detach()).view(1, -1, 1, 1) + s_d               # value s, grad scaled by g_s
        r = ((uf > 0) & (uf < self.L * s_d)).float()
        ss = uf / s_sc * r
        b = hard + (sx - sx.detach()).to(x.dtype) + (ss - ss.detach()).to(x.dtype)
        if rec is not None:
            with torch.no_grad():
                bd = b.detach().float()
                m = bd.mean((0, 2, 3)) / self.L
                rec.update(p1=bd.mean() / self.L, const=((m < 0.01) | (m > 0.99)).float().mean(),
                           pass_=((uf >= -self.w) & (uf <= (self.L - 1) * s_d + self.w)).float().mean(),
                           t_mean=self.t.mean(), t_std=self.t.std(), s_mean=self.s.mean(),
                           eff=self.k * ((uf >= -self.w) & (uf <= (self.L - 1) * s_d + self.w)).float().mean(),
                           exact01=((bd == torch.round(bd)) & (bd >= 0) & (bd <= self.L)).all())
            b.register_hook(lambda g: rec.__setitem__("g_out", g.float().norm()))
        return b

    def extra_repr(self):
        return super().extra_repr() + f", nbits={self.nbits}"


class Therm(nn.Module):
    """normalised NCHW image (3 channels) -> 3K planes in {0,1}, order (c, i)."""

    def __init__(self, K, mean, std):
        super().__init__()
        v = torch.floor((torch.arange(K, dtype=torch.float64) + 0.5) * 256 / K - 0.5) + 0.5     # raw thresholds
        thr = (v.view(1, K) / 255 - torch.tensor(mean, dtype=torch.float64).view(3, 1)) / torch.tensor(std, dtype=torch.float64).view(3, 1)
        self.register_buffer("thr", thr.float().view(1, 3 * K, 1, 1), persistent=False)
        self.K = K

    def forward(self, x):
        return (x.float().repeat_interleave(self.K, 1) > self.thr).to(x.dtype).contiguous(memory_format=torch.channels_last)


class ThermConvBN(ConvBN):
    def __init__(self, K, mean, std, cout, k, stride, **qc):
        super().__init__(3 * K, cout, k, stride, **qc)
        self.therm = Therm(K, mean, std)

    def forward(self, x):
        return self.bn(self.conv(self.therm(x)))


def therm_stem(model, K, mean, std, **qc):
    """replace model.stem by ThermConvBN (QC conv on 3K 1-bit planes); qc = the QCResNet18 qc kwargs."""
    model.stem = ThermConvBN(K, mean, std, 64, 3, 1, **qc).to(model.stem.bn.weight.device)
    return model


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


class BiRealBlock(BasicBlock):
    def forward(self, s):
        h = self.b1(s)
        y1 = self.c1(h) + (self.sc(h) if self.sc is not None else s)
        return self.c2(self.b2(y1)) + y1


class BinQCResNet18(QCResNet18):
    """Forward = qc18 forward; training forwards dispatch to a compiled copy, every log_every-th one eager+logged."""

    @torch._dynamo.disable
    def forward(self, x):
        self._flush()
        if not (self.training and torch.is_grad_enabled()):
            return self._net(x)                        # eval / BN recalibration: eager, as qc18.train
        if self._prog_steps:
            p = min(1.0, self._calls / self._prog_steps)
            for _, m in self.binacts():
                m.mix = p < 1
                m.p.fill_(p)
            self._prog_p.append(p)
        self._calls += 1
        if any(isinstance(m, MultiBitAct) and not m._ready for _, m in self.binacts()):
            return self._net(x)                        # MultiBitAct step-size init: eager
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


def set_prog(model, steps):
    """progressive binarisation over the first `steps` training forwards (0: off); model._prog_p = p of each forward."""
    model._prog_steps, model._prog_p = int(steps), []
    return model


def binarize(model, ste="clip", w=1.0, bin_stem=0, log_path="", log_every=50, spe=1, compile=True, act=True, k=1.0,
             t_train=1, preact=0, arch="qc18", fp_blocks=(), abits_blocks=(), abits=1):
    """act=False: no BinAct (FP-activation reference), only the logging forward (grad theta records).
    fp_blocks: block indices whose b1 / b2 are ReLU instead of BinAct (FP-activation block, same pre-activation).
    abits_blocks: block indices whose b1 / b2 are MultiBitAct(abits) instead of BinAct."""
    if model.mode == "dense":
        return model
    assert not bin_stem, "--bin-stem 1 not implemented"
    assert arch in ("qc18", "bireal") and (arch == "qc18" or preact), "--arch bireal requires --preact 1"
    assert all(0 <= i < len(model.blocks) for i in fp_blocks), fp_blocks
    assert all(0 <= i < len(model.blocks) for i in abits_blocks) and not set(abits_blocks) & set(fp_blocks), abits_blocks
    for i, blk in enumerate(model.blocks if act or preact else ()):
        dev = blk.c1.bn.weight.device
        blk.__class__ = BiRealBlock if arch == "bireal" else PreBlock if preact else BinBlock
        ba = act and i not in fp_blocks
        A = (lambda C: MultiBitAct(C, abits, ste, w, k, t_train)) if i in abits_blocks else (lambda C: BinAct(C, ste, w, k, t_train))
        blk.b1 = A(blk.c1.conv.cin).to(dev) if ba else nn.ReLU()
        blk.b2 = A(blk.c2.conv.cin).to(dev) if ba else nn.ReLU()
    model.__class__ = BinQCResNet18
    model._preact = bool(preact)
    model._hooks, model._calls, model._pending, model._log_path, model._log_every, model._spe = [], 0, None, log_path, log_every, spe
    set_prog(model, 0)
    fwd = lambda x: model._net(x)
    model._cfwd = torch.compile(fwd) if compile else fwd
    return model
