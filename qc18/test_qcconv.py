"""Unit tests:  python3 -m qc18.test_qcconv
(a) hard(theta) == brute-force argmax of the score over V;  (b) Gibbs backward == autograd Jacobian of the
smoothed mean E_p[v](theta);  (c) model forward weights (train and eval) are QC per qc.structure.decompose;  (d) per-row renormalisation
(sphere_, --qopt sphere) leaves hard(theta) unchanged;  (e) homotopy: gibbs forward = E_p[v] with gradient = the Gibbs
VJP, ramp endpoints (lam 0: top2/alpha, 1: hard), eval = stored hard v, and once the homotopy has ended
(set_homotopy(False)) the training forward equals the hard projection with STE gradient;  (f) freeze_v
(--freeze-v-epoch): v and theta unchanged by further training steps (SGD + AdamW with wd), BN / FC still train."""
import torch

from qc.structure import decompose, from_matrix

from .model import QCResNet18
from .qcconv import GibbsProject, gibbs_mean, gibbs_vjp, hard, row_alpha, sphere_, vset

BS = (2, 4, 8)
MODES = ("signed", "unsigned")


def score(theta, alpha, V):
    """[R, Cb, K] score of every v in V."""
    return theta @ V.T - 0.5 * alpha * (V != 0).sum(1).to(theta.dtype)


def test_sizes():
    from math import comb
    for b in BS + (16,):
        assert len(vset(b, True)) == 1 + 2 * b + 4 * comb(b, 2)
        assert len(vset(b, False)) == 1 + b + comb(b, 2)
        assert len(set(map(tuple, vset(b, True).tolist()))) == len(vset(b, True))


def test_hard_bruteforce():
    g = torch.Generator().manual_seed(0)
    for b in BS:
        for mode in MODES:
            V = vset(b, mode == "signed", torch.float64)
            for scale in (1.0, 0.1):
                theta = torch.randn(16, 64, b, generator=g, dtype=torch.float64) * scale
                theta[:4] += 0.5 * scale                     # rows with mostly positive / mixed blocks
                alpha = row_alpha(theta)
                v = hard(theta, alpha, mode == "signed")
                ref = V[score(theta, alpha, V).argmax(-1)]
                assert torch.equal(v, ref), (b, mode, (v != ref).any(-1).sum())
                # also the fp32 path (as used in training) on the same blocks
                v32 = hard(theta.float(), row_alpha(theta.float()), mode == "signed").double()
                assert (v32 != ref).any(-1).float().mean() < 1e-3


def test_gibbs_jacobian():
    g = torch.Generator().manual_seed(1)
    for b in BS:
        for mode in MODES:
            for tau in (0.3, 1.0, 3.0):
                V = vset(b, mode == "signed", torch.float64)
                theta = torch.randn(3, 5, b, generator=g, dtype=torch.float64)
                alpha = row_alpha(theta)
                T = torch.tensor(tau, dtype=torch.float64)

                def mean(th):          # explicit softmax over V, alpha held constant (detached)
                    p = torch.softmax(score(th, alpha, V) / (tau * alpha), -1)
                    return p @ V

                gout = torch.randn(3, 5, b, generator=g, dtype=torch.float64)
                th = theta.clone().requires_grad_()
                mean(th).backward(gout)
                ref = th.grad
                th2 = theta.clone().requires_grad_()
                out = GibbsProject.apply(th2, alpha, T, V, mode == "signed")
                assert torch.equal(out, hard(theta, alpha, mode == "signed"))
                out.backward(gout)
                # backward computes in fp32
                assert torch.allclose(th2.grad, ref, rtol=1e-4, atol=1e-5 * ref.abs().max()), \
                    (b, mode, tau, (th2.grad - ref).abs().max())
                # full Jacobian check on one block row against autograd.functional.jacobian
                J = torch.autograd.functional.jacobian(mean, theta)            # [3,5,b,3,5,b]
                assert torch.allclose(torch.einsum("abc,abcdef->def", gout, J), ref)


def test_model_weights_qc():
    torch.manual_seed(0)
    for b in BS:
        for mode in MODES:
            for est in ("ste", "gibbs"):
                model = QCResNet18(mode, b, est)
                for train in (True, False):
                    model.train(train)
                    for name, cb in model.convbns():
                        c = cb.conv
                        W = c.get_weight().detach()
                        M = c.matrix()
                        C = decompose(M, b, signed=mode == "signed")
                        assert torch.equal(from_matrix(M, c.cin, c.k, b), W), name
                        assert (C != 0).sum(-1).max() <= 2
                        if mode == "unsigned":
                            assert C.min() >= 0


def test_sphere_invariant():
    """--qopt sphere: per-row renormalisation to unit RMS leaves the hard weights unchanged."""
    g = torch.Generator().manual_seed(1)
    for b in BS:
        for mode in MODES:
            for dt in (torch.float64, torch.float32):
                theta = torch.randn(16, 64, b, generator=g, dtype=dt) * torch.rand(16, 1, 1, generator=g, dtype=dt) * 5
                theta[:4] += 0.5
                v = hard(theta, row_alpha(theta), mode == "signed")
                th = sphere_(theta.clone())
                rms = th.flatten(1).pow(2).mean(1).sqrt()
                assert torch.allclose(rms, torch.ones_like(rms), atol=1e-5)
                vs = hard(th, row_alpha(th), mode == "signed")
                assert (vs != v).any(-1).float().mean() < (1e-3 if dt == torch.float32 else 1e-9), (b, mode, dt)


def test_homotopy():
    torch.manual_seed(0)
    g = torch.Generator().manual_seed(2)
    for b in BS:
        for mode in MODES:
            signed = mode == "signed"
            V = vset(b, signed, torch.float64)
            theta = torch.randn(4, 6, b, generator=g, dtype=torch.float64)
            alpha = row_alpha(theta)
            gout = torch.randn(4, 6, b, generator=g, dtype=torch.float64)
            th = theta.clone().requires_grad_()
            m = gibbs_mean(th, alpha, torch.tensor(0.5, dtype=torch.float64), V)
            p = torch.softmax(score(theta, alpha, V) / (0.5 * alpha), -1)
            assert torch.allclose(m, p @ V)
            m.backward(gout)
            assert torch.allclose(th.grad, gibbs_vjp(theta, alpha, torch.tensor(0.5, dtype=torch.float64), V, gout))
            # small tau: the Gibbs mean approaches the hard projection
            m0 = gibbs_mean(theta, alpha, torch.tensor(1e-4, dtype=torch.float64), V)
            assert (m0 - hard(theta, alpha, signed)).abs().max() < 1e-6
        for hom in ("gibbs", "ramp"):
            model = QCResNet18("signed", b, "ste", homotopy=hom).train()
            for c in model.qconvs():
                with torch.no_grad():
                    c.theta.add_(0.3 * torch.randn_like(c.theta))     # theta != v-consistent init
            model.set_homotopy(True, tau=0.5, lam=0.0)
            for c in model.qconvs():
                hv = hard(c.theta, row_alpha(c.theta), True)
                w = c.coef()
                assert not torch.equal(w.detach(), hv)
                if hom == "ramp":
                    t = c.theta.detach()
                    idx = t.abs().sort(dim=-1, descending=True, stable=True).indices[..., :2]
                    r = t * torch.zeros_like(t).scatter(-1, idx, 1.0) / row_alpha(t)
                    assert torch.allclose(w, r)
                    c.hlam.fill_(1.0)
                    assert torch.allclose(c.coef(), hv)
                c.refresh()
                c.eval()
                assert torch.equal(c.coef(), c.v)                      # eval: stored hard v during homotopy
                c.train()
            model.set_homotopy(False)                                  # homotopy ended
            for c in model.qconvs():
                th = c.theta
                w = c.coef()
                assert torch.equal(w.detach(), hard(th, row_alpha(th), True))
                gw = torch.randn_like(w)
                th.grad = None
                w.backward(gw)
                assert torch.equal(th.grad, gw)                        # STE
                C = decompose(c.matrix(), b, signed=True)
                assert torch.equal(from_matrix(c.matrix(), c.cin, c.k, b), c.get_weight().detach())
                assert (C != 0).sum(-1).max() <= 2


def test_freeze():
    torch.manual_seed(0)
    model = QCResNet18("signed", 8, "ste").train()
    theta = [p for n, p in model.named_parameters() if n.endswith("theta")]
    other = [p for p in model.parameters() if all(p is not q for q in theta)]
    opts = [torch.optim.SGD(other, lr=0.1, momentum=0.9), torch.optim.AdamW(theta, lr=1e-1, weight_decay=0.1)]
    x, y = torch.randn(8, 3, 32, 32), torch.randint(0, 10, (8,))

    def steps(n):
        for _ in range(n):
            for o in opts:
                o.zero_grad(set_to_none=True)
            torch.nn.functional.cross_entropy(model(x), y).backward()
            for o in opts:
                o.step()
        model.refresh()

    steps(3)
    v0 = [c.v.clone() for c in model.qconvs()]
    model.freeze_v()
    v1, th1 = [c.v.clone() for c in model.qconvs()], [t.clone() for t in theta]
    bns = [p for n, p in model.named_parameters() if ".bn." in n]
    fc1, bn1 = model.fc.weight.clone(), [p.clone() for p in bns]
    assert all(torch.equal(a, b) for a, b in zip(v0, v1))
    steps(3)
    assert all(torch.equal(c.v, w) for c, w in zip(model.qconvs(), v1))
    assert all(torch.equal(t, w) for t, w in zip(theta, th1))
    assert all(torch.equal(c.coef(), c.v) for c in model.qconvs())          # train-mode forward = stored v
    assert not torch.equal(model.fc.weight, fc1) and any(not torch.equal(p, q) for p, q in zip(bns, bn1))


if __name__ == "__main__":
    for t in (test_sizes, test_hard_bruteforce, test_gibbs_jacobian, test_model_weights_qc, test_sphere_invariant,
              test_homotopy, test_freeze):
        t()
        print("PASS", t.__name__, flush=True)
    print("ALL PASS")
