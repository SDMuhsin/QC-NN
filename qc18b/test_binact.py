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
