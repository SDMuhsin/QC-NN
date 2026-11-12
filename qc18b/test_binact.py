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
