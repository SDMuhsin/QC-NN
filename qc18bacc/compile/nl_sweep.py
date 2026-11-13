"""Fused-lane count sweep under supply config C (compile/supply.py), results/nl_sweep.md (cycle part).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.nl_sweep CKPT [CKPT ...] [--n 100] [--cache DIR] [--json OUT]

Config C = two qb_act contexts sharing the 512-b map port, block-6 int8 slices from S at 2048 b / cycle (supply.py
CONFIGS "C"), NW 32 wide lanes, v1.1 list scheduler with its hazard check (check=True).  Only NL changes: the scheduler
models a fused drain / hm job as ceil(1024 / NL) cycles (cycles.drain / list_schedule dd).  Nothing in supply.py
depends on NL.

Also reported per NL (for the S macro sizing, impl/mem/s_nl.py):
* S occupancy per pass (entries written to S: cout x Hout x Wout, block-6 r = 2 entries per output) and the r bounds
  of the program (prog.checks): binary r / idm rs <= 32767 under p2 -> 16-b entries.
* NL 128 S read conflicts: with S = 16 x 128 b (2048 b / cycle total) the block-6 int8 word read (2048 b) and the
  b6.c2 wide-lane r reads (32 lanes x lo + hi = 1024 b / cycle, every cycle of a b6.c2 drain [ds, de)) cannot share a
  cycle; counted = S int8 grants of the config-C schedule that fall inside a b6.c2 drain interval (each such grant
  slips >= 1 cycle if r has priority; upper bound on the image delta if every slip propagated: +count).
"""
import argparse
import json
import os

import numpy as np

from . import cycles as Cy
from . import supply as Sp

NLS = (128, 192, 256)
NWD = 32


def s_occupancy(prog):
    """entries written to S by each pass (block-6 r: lo + hi = 2 entries per output)."""
    out = {}
    for p in prog.passes:
        if "S" in p.dst:
            out[p.name] = p.cout * p.Hout * p.Wout * (2 if p.kind == "wsc" else 1)
    return out


def conflicts(prog, sup, tim):
    """per image: S int8 grants inside a b6.c2 wide drain interval (r lo / hi read cycles)."""
    T, _ = Cy.BASE[(id(prog), "tiles")]
    pi = [p.name for p in prog.passes].index("b6.c2")
    ts = [t for t, d in enumerate(T) if d["pi"] == pi]
    out = []
    for img in sorted(sup.final):
        iv = [(tim["ds"][img, t], tim["de"][img, t]) for t in ts]
        g = [st for e in sup.final[img].log for (port, st) in e["loads"] if port == "S"]
        out.append(sum(any(a <= x < b for a, b in iv) for x in g))
    return np.array(out)


def sweep(ck, n, cache):
    prog, net, val, st, correct, mk = Sp.load(ck, n, cache)
    res = dict(run=prog.run, passes=[p.name for p in prog.passes], nl={})
    for NL in NLS:
        sup = Sp.Supply(prog, mk, width=512, b6="S", ctx=2)
        rows, per, tim = Cy.list_schedule(prog, st, NL, NWD, ctx=2, sup=sup, check=True)
        fr, fper = Cy.list_schedule(prog, st, NL, NWD, ctx=2)[:2]          # C0: two contexts, free supply
        cf = conflicts(prog, sup, tim)
        res["nl"][NL] = dict(mean=float(per.mean()), min=int(per.min()), max=int(per.max()),
                             c0=float(fper.mean()), pp=[float(r["cyc"]) for r in rows],
                             stall=[float(np.mean([sup.final[i].ps[k]["extra"] for i in sup.final]))
                                    for k in range(len(prog.passes))],
                             conf_mean=float(cf.mean()), conf_max=int(cf.max()),
                             drain=[int(Cy.drain(p, NL, NWD, Cy.FL_ALL)) if p.k else
                                    int(Cy.cdiv(1024, NL if Cy.unit(p, Cy.FL_ALL) == "fused" else NWD))
                                    for p in prog.passes])
        print(f"{prog.run} NL {NL}: C {per.mean():.1f} ({per.min()} / {per.max()}), C0 {fper.mean():.1f}, "
              f"NL128-style S conflicts {cf.mean():.1f} / img (max {cf.max()}), hazard check PASS", flush=True)
    res["s_occ"] = s_occupancy(prog)
    res["checks"] = [c for c in prog.checks if c.startswith("r bounds")]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", default=None)
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    out = [sweep(ck, a.n, a.cache) for ck in a.ckpts]
    if a.json:
        with open(a.json, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
