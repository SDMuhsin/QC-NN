"""Unit tests:  python3 -m qc18.test_qcconv
(a) hard(theta) == brute-force argmax of the score over V;  (b) Gibbs backward == autograd Jacobian of the
smoothed mean E_p[v](theta);  (c) model forward weights (train and eval) are QC per qc.structure.decompose;  (d) per-row renormalisation
(sphere_, --qopt sphere) leaves hard(theta) unchanged."""
import torch

from qc.structure import decompose, from_matrix

from .model import QCResNet18
from .qcconv import GibbsProject, hard, row_alpha, sphere_, vset

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


if __name__ == "__main__":
    for t in (test_sizes, test_hard_bruteforce, test_gibbs_jacobian, test_model_weights_qc, test_sphere_invariant):
        t()
        print("PASS", t.__name__, flush=True)
    print("ALL PASS")
