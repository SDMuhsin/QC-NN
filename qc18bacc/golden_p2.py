"""Power-of-two residual-stream ladder variant of qc18b.int_bin.IntBin (measurement only, val split):
    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.golden_p2 RUN/best.pt [RUN2/best.pt ...]

IntBin2: identical to IntBin except the int16 stream scales.  S_0 = max|s_0|/32767 (same calibration, train[:2000] via
int_bin.float_trace); for k >= 1, S_k = S_0 2^-e_k with e_k = max{e integer : S_0 2^-e >= max|s_k|/32767}.  The ladder is
injected as modified calibration maxima v_k = v_0 2^-e_k (exact in fp64), so IntBin.__init__ recomputes every dependent
quantity (stem_m, c2m/c2h, scm/sch, T1, hm, fp-block scales, pool_m, idm) unchanged in code.  Every S_{k-1}/S_k is then an
exact power of two; each identity multiplier idm is checked to equal the plain shift (x << j, or round-half-up >> -j) on
x in [0, 32767].
Reports per seed: IntBin vs IntBin2 val accuracy, difference, argmax disagreements, saturations, e_k ladder and
S_k(ladder)/S_k(calibrated), paired bootstrap (1000) 95 % CI of the accuracy difference.  Never touches the test set.
"""
import math
import sys

import torch

from qc18.int8 import requant
from qc18b import data
from qc18b.int_bin import IntBin, float_trace
from qc18b.verify_bin import Folded, build


def ladder(rec, L):
    """rec: calibration maxima.  Returns (rec2 with stream maxima on the 2^-e ladder of s0, e list)."""
    v0 = rec["s0"]
    rec2, es = dict(rec), [0]
    for k in range(1, L + 1):
        vk = rec[f"s{k}"]
        e = math.floor(math.log2(v0 / vk)) + 2
        while not math.ldexp(v0, -e) >= vk:                    # largest e with v0 2^-e >= vk
            e -= 1
        assert math.ldexp(v0, -(e + 1)) < vk
        rec2[f"s{k}"] = math.ldexp(v0, -e)
        es.append(e)
    return rec2, es


class IntBin2(IntBin):
    def __init__(self, model, fn, rec, signed):
        L = len(fn.blocks)
        rec2, self.e = ladder(rec, L)
        super().__init__(model, fn, rec2, signed)
        self.S_cal = {f"s{k}": rec[f"s{k}"] / 32767 for k in range(L + 1)}
        assert self.S["s0"] == self.S_cal["s0"]
        for k in range(1, L + 1):                               # exact power-of-two ratios, ladder >= calibrated
            j = self.e[k] - self.e[k - 1]                       # S_{k-1}/S_k = 2^j
            assert self.S[f"s{k-1}"] / self.S[f"s{k}"] == math.ldexp(1.0, j)
            assert self.S[f"s{k}"] == math.ldexp(self.S["s0"], -self.e[k]) >= self.S_cal[f"s{k}"]
        x = torch.arange(0, 32768, dtype=torch.int64).view(1, 1, -1)
        self.idm_checked = []
        for i, d in enumerate(self.blocks):
            if "idm" not in d:
                continue
            j = self.e[i + 1] - self.e[i]
            m0, sh = d["idm"]
            assert int(m0[0]) == 2 ** 30 and int(sh[0]) == 30 - j, (i, j, m0, sh)
            ref = x << j if j >= 0 else (x + (1 << (-j - 1))) >> (-j)
            assert torch.equal(requant(x, m0, sh), ref), f"block {i}: requant != shift {j}"
            self.idm_checked.append((i, j))


def run(net, xv):
    net.sat = 0
    return torch.cat([net(xv[i:i + 500]).argmax(1) for i in range(0, len(xv), 500)]), net.sat


@torch.no_grad()
def main(ckpts):
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda"
    (xt, _), (xv, yv) = data.split(dev)
    n = len(yv)
    for ck_path in ckpts:
        model, ck, o, logp, fpb = build(ck_path, dev)
        signed = ck["args"]["mode"] == "signed"
        fn = Folded(model, fpb, signed, ck["args"]["b"])
        rec = {}
        for i in range(0, 2000, 500):
            float_trace(fn, xt[i:min(i + 500, 2000)], rec)
        a, b = IntBin(model, fn, rec, signed), IntBin2(model, fn, rec, signed)
        pa, sa = run(a, xv)
        pb, sb = run(b, xv)
        ca, cb = (pa == yv), (pb == yv)
        na, nb, dis = int(ca.sum()), int(cb.sum()), int((pa != pb).sum())
        g = torch.Generator(device="cpu").manual_seed(0)
        idx = torch.randint(0, n, (1000, n), generator=g).to(dev)
        dd = (cb.double()[idx].mean(1) - ca.double()[idx].mean(1)) * 100
        lo, hi = torch.quantile(dd, torch.tensor([0.025, 0.975], dtype=torch.float64, device=dev)).tolist()
        L = len(fn.blocks)
        print(f"{ck_path}")
        print(f"  IntBin  {100*na/n:.2f} % ({na}/{n}) sat {sa}")
        print(f"  golden_p2 {100*nb/n:.2f} % ({nb}/{n}) sat {sb}")
        print(f"  diff {100*(nb-na)/n:+.2f} pt, CI95 [{lo:+.2f}, {hi:+.2f}], argmax disagree {dis}")
        print(f"  e_k {b.e}")
        print("  ratio " + " ".join(f"{b.S[f's{k}']/b.S_cal[f's{k}']:.4f}" for k in range(L + 1)))
        print(f"  idm shifts checked (block, j): {b.idm_checked}")
        print(f"  S_cal " + " ".join(f"{b.S_cal[f's{k}']:.3g}" for k in range(L + 1)))


if __name__ == "__main__":
    main(sys.argv[1:])
