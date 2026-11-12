"""CPU check of BinAct bussgang / stein / K / t_train:  python3 -m qc18b.test_binact"""
import torch

from qc18b.binact import BinAct

torch.manual_seed(0)
for ste in ("bussgang", "stein"):
    m = BinAct(5, ste)
    with torch.no_grad():
        m.t.copy_(torch.randn(5) * 0.5)
    x = (torch.randn(4, 5, 3, 3) * torch.rand(1, 5, 1, 1) * 2 + torch.randn(1, 5, 1, 1)).requires_grad_()
    g = torch.randn(4, 5, 3, 3)
    b = m(x)
    b.backward(g)
    xd, bd, t = x.detach().double(), (x.detach() > m.t.detach().view(1, -1, 1, 1)).double(), m.t.detach().double()
    mu, var = xd.mean((0, 2, 3)), xd.var((0, 2, 3), unbiased=False)
    if ste == "bussgang":
        a = (((bd - bd.mean((0, 2, 3), keepdim=True)) * (xd - mu.view(1, -1, 1, 1))).mean((0, 2, 3)) / var).clamp_min(0)
    else:
        sig = var.sqrt().clamp_min(1e-3)
        a = torch.exp(-0.5 * ((t - mu) / sig) ** 2) / (2 * torch.pi) ** 0.5 / sig
    ex = (a.view(1, -1, 1, 1) * g.double()).float()
    et = (-a * g.double().sum((0, 2, 3))).float()
    assert torch.equal(b.detach(), bd.float()) and ((b == 0) | (b == 1)).all(), ste
    assert torch.allclose(x.grad, ex, atol=1e-6, rtol=1e-5), (ste, (x.grad - ex).abs().max())
    assert torch.allclose(m.t.grad, et, atol=1e-5, rtol=1e-5), (ste, (m.t.grad - et).abs().max())
    print(f"{ste}: b exact 0/1, max|dx err| {(x.grad - ex).abs().max():.2e}, max|dt err| {(m.t.grad - et).abs().max():.2e}, a {a.numpy().round(3)}")
m = BinAct(3, "clip", 1.0, 0.43, 0)
x = torch.randn(2, 3, 4, 4).requires_grad_()
m(x).backward(torch.ones(2, 3, 4, 4))
assert m.t.grad is None and not m.t.requires_grad
assert torch.allclose(x.grad, 0.43 * (x.detach().abs() < 1).float())
print("clip K=0.43 t_train=0: ok")
import copy

from qc18.model import QCResNet18
from qc18b.binact import binarize

ref = QCResNet18("signed", 8, num_classes=100).eval()
for mod in ref.modules():                                 # non-trivial BN stats / affine
    if isinstance(mod, torch.nn.BatchNorm2d):
        with torch.no_grad():
            mod.running_mean.normal_(0, 0.3); mod.running_var.uniform_(0.5, 2); mod.weight.uniform_(0.5, 1.5); mod.bias.normal_(0, 0.3)
pre = binarize(copy.deepcopy(ref), compile=False, act=False, preact=1).eval()
x = torch.randn(4, 3, 32, 32)
with torch.no_grad():
    d = (pre(x) - ref(x)).abs().max().item()
print(f"preact, act off vs qc18 (same weights, eval): max |logit diff| {d}")
assert d == 0
from qc18b.binact import BiRealBlock

for act in (0, 1):                                        # bireal: forward, b exact 0/1, state_dict interchangeable with qc18
    br = binarize(copy.deepcopy(ref), compile=False, act=bool(act), preact=1, arch="bireal").train()
    assert all(isinstance(b, BiRealBlock) for b in br.blocks)
    q = binarize(copy.deepcopy(ref), compile=False, act=bool(act), preact=1)
    assert br.state_dict().keys() == q.state_dict().keys()
    br.load_state_dict(q.state_dict()); q.load_state_dict(br.state_dict())
    bs = []
    hk = [m.register_forward_hook(lambda m, i, o: bs.append(o)) for _, m in br.binacts()]
    y = br(x)
    y.sum().backward()
    assert torch.isfinite(y).all() and y.shape == (4, 100)
    assert len(bs) == 16 * act and all(((b == 0) | (b == 1)).all() for b in bs)
    print(f"bireal binact={act}: forward ok, {len(bs)} BinAct outputs exact 0/1, state_dict loads both ways")

from qc18b import data
from qc18b.binact import Therm, therm_stem

xi = torch.randint(0, 256, (4, 32, 32, 3), dtype=torch.uint8)
xi[0, :8] = torch.arange(256, dtype=torch.uint8).view(8, 32, 1)          # every pixel value, all channels
xn = data.prep(xi)
for K in (1, 3, 16, 32, 255, 256):
    pl = Therm(K, data.MEAN, data.STD)(xn)
    assert pl.shape == (4, 3 * K, 32, 32) and ((pl == 0) | (pl == 1)).all()
    p = xi.permute(0, 3, 1, 2).long()                                    # level on uint8: #{i : p > (i+.5)256/K - .5}
    lev = ((K * (2 * p + 1) + 255) // 512).clamp(0, K)                    # = #{i < K : 512 i + 256 < K (2p + 1)}
    brute = sum((K * (2 * p + 1) > 256 * (2 * i + 1)).long() for i in range(K))
    assert torch.equal(lev, brute)
    assert torch.equal(pl.view(4, 3, K, 32, 32).sum(2).long(), lev), K
    assert torch.equal(pl.view(4, 3, K, 32, 32), torch.sort(pl.view(4, 3, K, 32, 32), 2, descending=True)[0])
print("stem therm K in 1,3,16,32,255,256: planes exact 0/1, sum over i == uint8 level (exact), monotone in i")
tm = therm_stem(copy.deepcopy(ref), 16, data.MEAN, data.STD, mode="signed", b=8)
tm = binarize(tm, compile=False, preact=1, arch="bireal").to(memory_format=torch.channels_last).train()
assert tm.stem.conv.cin == 48 and torch.isfinite(tm(xn)).all()
print("therm_stem K=16 + bireal binact: forward ok, stem cin 48")

fb = binarize(copy.deepcopy(ref), compile=False, preact=1, fp_blocks=tuple(range(8))).eval()      # --fp-blocks 0..7 == --binact 0
assert not fb.binacts()
with torch.no_grad():
    d = (fb(x) - pre(x)).abs().max().item()
print(f"preact fp_blocks 0..7 vs binact 0 (same weights, eval): max |logit diff| {d}")
assert d == 0
fh = binarize(copy.deepcopy(ref), compile=False, preact=1, fp_blocks=(2, 3))
assert [n for n, _ in fh.binacts()] == [f"blocks.{i}.b{j}" for i in (0, 1, 4, 5, 6, 7) for j in (1, 2)]
print("fp_blocks 2,3: BinActs only in blocks 0,1,4..7")

for dt in (torch.float32, torch.bfloat16):                # --prog: p = 1 == binary forward, p = 0 == a_c relu(x)
    m = BinAct(5, "clip", 1.0, 0.6).train()
    with torch.no_grad():
        m.t.copy_(torch.randn(5) * 0.3)
    x0 = (torch.randn(4, 5, 3, 3) + torch.randn(1, 5, 1, 1)).to(dt)
    x0[:, 4] = -x0[:, 4].abs() - 0.1                      # channel 4: relu(x) == 0 -> a_c = 1
    g = torch.randn(4, 5, 3, 3).to(dt)
    outs = []
    for mix, p in ((False, 1.0), (True, 1.0), (True, 0.0)):
        m.mix = mix
        m.p.fill_(p)
        m.t.grad = None
        x = x0.clone().requires_grad_()
        y = m(x)
        y.backward(g)
        outs.append((y.detach(), x.grad, m.t.grad.clone()))
    (b0, gx0, gt0), (b1, gx1, gt1), (s, gxs, gts) = outs
    assert torch.equal(b0, b1) and torch.equal(gx0, gx1) and torch.equal(gt0, gt1) and ((b1 == 0) | (b1 == 1)).all()
    xd, t = x0.double(), m.t.detach().double().view(1, -1, 1, 1)
    hd, r = (xd > t).double(), xd.clamp_min(0)
    den = r.mean((0, 2, 3))
    a = torch.where(den > 0, hd.mean((0, 2, 3)) / den, torch.ones_like(den)).view(1, -1, 1, 1)
    assert a[0, 4] == 1
    tol = dict(atol=1e-6, rtol=1e-5) if dt == torch.float32 else dict(atol=2e-2, rtol=1e-2)
    assert torch.allclose(s.double(), a * r, **tol), (s.double() - a * r).abs().max()
    assert torch.allclose(gxs.double(), a * (xd > 0).double() * g.double(), **tol)
    assert torch.equal(gts, torch.zeros_like(gts))        # soft does not depend on t
    m.mix, m.p = True, torch.full((), 0.3)
    y = m(x0)
    k = (y == b0).float().mean().item()
    m.eval()
    assert torch.equal(m(x0), b0)                          # eval: binary regardless of mix / p
    print(f"prog {dt}: p=1 output/grads == binary (exact, values 0/1), p=0 == a_c relu(x) (dx exact), "
          f"p=0.3 frac==hard {k:.2f}, eval binary")

pm = binarize(copy.deepcopy(ref), compile=False, preact=1).train()
from qc18b.binact import set_prog
set_prog(pm, 4)
xi3 = torch.randn(4, 3, 32, 32)
for _ in range(6):
    pm(xi3).sum().backward()
assert pm._prog_p == [0, 0.25, 0.5, 0.75, 1.0, 1.0] and not any(b.mix for _, b in pm.binacts())
print("set_prog 4: p per training forward", pm._prog_p)

from qc18b.binact import MultiBitAct

for dt in (torch.float32, torch.bfloat16):                # --abits: N = 1 == BinAct (forward, dx, dt exact); N = 2 levels
    x0 = (torch.randn(8, 6, 5, 5) * 1.5 + torch.randn(1, 6, 1, 1)).to(dt)
    x0[0, 0, 0, :3] = torch.tensor([0.0, 1.0, -1.0])     # u == 0 and window edges |u| == w
    g = torch.randn(8, 6, 5, 5).to(dt)
    t0 = torch.randn(6) * 0.3
    t0[0] = 0
    res = []
    for m in (BinAct(6, "clip", 1.0, 0.6), MultiBitAct(6, 1, "clip", 1.0, 0.6)):
        with torch.no_grad():
            m.t.copy_(t0)
        x = x0.clone().requires_grad_()
        y = m(x)
        y.backward(g)
        res.append((y.detach(), x.grad, m.t.grad))
    (yb, gxb, gtb), (ym, gxm, gtm) = res
    assert torch.equal(yb, ym) and torch.equal(gxb, gxm) and torch.equal(gtb, gtm), dt
    print(f"abits N=1 {dt}: forward, dL/dx, dL/dt identical (torch.equal) to BinAct clip K=0.6")
    m = MultiBitAct(6, 2, "clip", 1.0, 0.6)
    with torch.no_grad():
        m.t.copy_(t0)
    x = x0.clone().requires_grad_()
    y = m(x)
    y.backward(g)
    sd = (2 * x0.float().std((0, 2, 3), unbiased=False) / 3).clamp_min(1e-3)
    assert torch.allclose(m.s.detach(), sd) and bool(m.inited)
    u = x0.double() - t0.double().view(1, -1, 1, 1)
    sv = m.s.detach().double().view(1, -1, 1, 1)
    q = torch.where(u > 0, (torch.floor(u / sv) + 1).clamp(0, 3), torch.zeros_like(u))
    assert torch.equal(y.detach().double(), q) and set(y.unique().tolist()) == {0.0, 1.0, 2.0, 3.0}
    win = ((u >= -1) & (u <= 2 * sv + 1)).double()
    tol = dict(atol=1e-6, rtol=1e-5) if dt == torch.float32 else dict(atol=2e-2, rtol=1e-2)
    assert torch.allclose(x.grad.double(), 0.6 * win * g.double(), **tol)
    assert torch.allclose(m.t.grad.double(), -(0.6 * win * g.double()).sum((0, 2, 3)), **tol)
    es = (-(u / sv ** 2) * ((u > 0) & (u < 3 * sv)).double() * g.double()).sum((0, 2, 3)) / (200 * 3) ** 0.5
    assert torch.allclose(m.s.grad.double(), es, atol=1e-4, rtol=1e-3), (m.s.grad.double() - es).abs().max()
    print(f"abits N=2 {dt}: outputs {sorted(y.unique().tolist())} == reference q (exact), s init 2std/3, dx / dt / ds (LSQ) ok")
mb = binarize(copy.deepcopy(ref), compile=False, preact=1, abits_blocks=(6, 7), abits=2).train()
names = [(n, type(m).__name__) for n, m in mb.binacts()]
assert [n for n, c in names if c == "MultiBitAct"] == [f"blocks.{i}.b{j}" for i in (6, 7) for j in (1, 2)] and len(names) == 16
mb(torch.randn(4, 3, 32, 32)).sum().backward()
assert all(m._ready for _, m in mb.binacts() if isinstance(m, MultiBitAct))
mb2 = binarize(copy.deepcopy(ref), compile=False, preact=1, abits_blocks=(6, 7), abits=2)
mb2.load_state_dict(mb.state_dict())
assert all(m._ready for _, m in mb2.binacts() if isinstance(m, MultiBitAct))
print("abits_blocks 6,7 N=2: 4 MultiBitAct in blocks 6,7 + 12 BinAct, forward/backward ok, state_dict round trip keeps s / inited")
