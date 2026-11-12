#!/usr/bin/env python3
"""Real-parameter rows of every fused-lane requant of one seed's p2 program (input of gen_f.py real):

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_f.py RUN/best.pt OUT.txt [--golden p2]

Program = qc18bacc.compile.program.build_program(ckpt, v=11, golden) (all of its exactness asserts run).  One row per
output channel of: stem, binary sc, binary c2 (sc blocks: rmode 1, r range = the channel's worst-case sc output range;
identity blocks: rmode 2 / 3 for j = 0 / -1, with IntBin2's ORIGINAL idm (m0, sh)), and every block-6 pass the v1.1
fit moved to the fused lanes (p2: b6.hm).  Row:
  R kind name c sgn bias dlo dhi lo hi m' sel m0 sh h relu omode rmode im0 ish rlo rhi T
dlo / dhi: worst-case domain of x' = acc' + bias (acc' = sign(g) M x; hm: the stream s), lo / hi: the lane pre-clamp,
(m', sel): lane window multiplier, (m0, sh): IntBin2's original requant, T: threshold (N: none).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))

import torch  # noqa: E402

from qc18b.int_bin import Q16  # noqa: E402
from qc18bacc.compile import program as P  # noqa: E402

FULL = (-2 ** 15, 2 ** 15 - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--golden", default="p2", choices=P.GOLDENS)
    a = ap.parse_args()
    prog, net, _ = P.build_program(a.ckpt, v=11, golden=a.golden)
    assert a.golden == "p2", "qb_lane_f implements the p2 residual (idm shift)"
    rows = []
    rng = {}

    def dom(p, r):
        ic = net.ic[p.conv]
        lo, hi = P.domain(ic.W8[:, :p.cin], *r)
        return lo.cpu(), hi.cpu()

    def row(kind, p, c, sgn, bias, dlo, dhi, lo, hi, m, sel, m0, sh, h=0, relu=0, omode=0, rmode=0, im=(0, 0),
            rr=(0, 0), T=None):
        rows.append(f"R {kind} {p.name} {c} {int(sgn)} {int(bias)} {int(dlo)} {int(dhi)} {int(lo)} {int(hi)} {int(m)} "
                    f"{int(sel)} {int(m0)} {int(sh)} {int(h)} {relu} {omode} {rmode} {im[0]} {im[1]} {int(rr[0])} "
                    f"{int(rr[1])} {'N' if T is None else int(T)}")

    for p in prog.passes:
        if p.ppu != "fused":
            continue
        neg = lambda c: int(p.sgn[c] < 0) if p.sgn is not None else 0
        if p.kind == "stem":
            lo, hi = dom(p, (-127, 127))
            b = p.p["bias"]
            m0, sh = net.stem_m
            for c in range(p.cout):
                row("stem", p, c, neg(c), b[c], lo[c] + b[c], hi[c] + b[c], *FULL, p.p["m"][c], p.p["sel"][c], m0[c],
                    sh[c], T=p.p["T"][c])
        elif p.kind == "bsc":
            lo, hi = dom(p, (0, 1))
            d = net.blocks[p.block]
            m0, sh = d["scm"]
            for c in range(p.cout):
                row("sc", p, c, neg(c), 0, lo[c], hi[c], *FULL, p.p["m"][c], p.p["sel"][c], m0[c], sh[c], h=p.p["h"][c],
                    omode=1)
                ys = [P.rq1(torch.tensor(v), int(m0[c]), int(sh[c])) + int(p.p["h"][c]) for v in (lo[c], hi[c])]
                rng[p.block, c] = (min(ys), max(ys))
        elif p.kind == "bc2":
            lo, hi = dom(p, (0, 1))
            d = net.blocks[p.block]
            m0, sh = d["c2m"]
            for c in range(p.cout):
                if p.p["res"] == "r":
                    rm, im, rr = 1, (0, 0), rng[p.block, c]
                else:
                    j = p.p["idm_j"]
                    rm, im, rr = (2 if j == 0 else 3), (int(d["idm"][0][0]), int(d["idm"][1][0])), (-Q16, Q16)
                row("c2", p, c, neg(c), 0, lo[c], hi[c], *FULL, p.p["m"][c], p.p["sel"][c], m0[c], sh[c],
                    h=p.p["h"][c], rmode=rm, im=im, rr=rr, T=None if p.p["T"] is None else p.p["T"][c])
        elif p.kind == "hm":
            f = p.p["f"]
            d = net.blocks[p.block]
            m0, sh = d["hm"]
            for c in range(p.cin):
                row("hm", p, c, 0, f["bias"][c], -Q16, Q16, f["lo"][c], f["hi"][c], f["m"][c], f["sel"][c],
                    m0.expand(p.cin)[c], sh.expand(p.cin)[c], relu=1, omode=2)
        else:
            raise ValueError(f"fused pass {p.name} ({p.kind}) not covered")
    bias = [int(r.split()[5]) for r in rows]
    mw = max(int(r.split()[10]).bit_length() for r in rows)
    sels = sorted({int(r.split()[11]) for r in rows})
    with open(a.out, "w") as f:
        f.write(f"# {a.ckpt} golden {a.golden}: {len(rows)} rows, MW {mw}, sel used {sels}, bias range "
                f"[{min(bias)}, {max(bias)}]\n" + "\n".join(rows) + "\n")
    print(f"wrote {a.out}: {len(rows)} rows, MW {mw}, sel {sels}, bias [{min(bias)}, {max(bias)}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
