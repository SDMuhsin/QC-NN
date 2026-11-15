#!/usr/bin/env python3
"""R5e step 1: does a 128-b FC weight port (16 int8 MAC / cycle) fit the head overlap on every image?  [Mod]

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/impl/r5e/head_slack.py RUN0/best.pt RUN1/best.pt --cache DIR --n 300 \
        [--pq0 OFF] [--lat256 1638]

Static-order model (compile/static_seq.static_order, = hw/tb/export_top2.py) per image of val[:n]:
  M = model cycles; interval = M + 1 (r3c.md).  T7 = drain start (ds) of the first tile of the last pass (b7.c2) in the
  image's own time (go = 0); the head's pq is first written by image i+1 at go(i+1) + T7(i+1) + OFF (OFF measured by the
  chip bench, tb QB_CHIP_OVERLAP; pass --pq0).
Head of image i, from go(i+1) (= its end + 1): R3c measured last logit at go(i+1) + 1638 with 1 613 FC rows (256 b).
  At 128 b: rows = 25 bias rows (4 x int32) + 100 x 32 weight rows = 3 225 -> latency 1638 + (3225 - 1613) = 3250.
Constraints: (a) the brief's: head (from go(i+1)) <= interval(i+1);  (b) the RTL's: FC i done before image i+1's
  first pq write (qb_head err), FC done = last logit + 1.
Imports compile/ (nothing copied); never touches test.
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))

from qc18bacc.compile import cycles as Cy  # noqa: E402
from qc18bacc.compile import supply as SU  # noqa: E402
from qc18bacc.compile import static_seq as SS  # noqa: E402


def rows(ncls, nk, bits):
    per = bits // 32                                        # classes per bias row
    return -(-ncls // per) + ncls * (nk // (bits // 8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--pq0", type=int, default=None, help="bench offset: first pq write - (go + T7)")
    ap.add_argument("--lat256", type=int, default=1638)
    a = ap.parse_args()
    for ck in a.ckpts:
        prog, net, val, st, correct, mk = SU.load(ck, a.n, a.cache)
        order, per, per2, tim, sup, nord = SS.static_order(prog, st, mk)
        T = Cy.BASE[(id(prog), "tiles")][0]
        last = len(prog.passes) - 1
        t7 = [t for t, d in enumerate(T) if d["pi"] == last]
        T7 = tim["ds"][:, t7].min(1)
        ncls, nk = prog.head["fW8"].shape
        r256, r128 = rows(ncls, nk, 256), rows(ncls, nk, 128)
        h128 = a.lat256 + r128 - r256
        iv = per2 + 1
        print(f"{prog.run}: val[:{a.n}] {nord} commit order(s); interval M+1 min {iv.min()} mean {iv.mean():.1f} max "
              f"{iv.max()} (argmin val {iv.argmin()}); FC rows 256 b {r256} / 128 b {r128}; head from go(i+1) "
              f"256 b {a.lat256} / 128 b {h128}", flush=True)
        print(f"{prog.run}: (a) head 128 b vs interval: min slack {iv.min() - h128} (fits {(iv >= h128).sum()}/{a.n})",
              flush=True)
        print(f"{prog.run}: T7 (b7.c2 first drain start, model) min {T7.min()} mean {T7.mean():.1f} max {T7.max()} "
              f"(argmin val {T7.argmin()}); M - T7 min {(per2 - T7).min()} max {(per2 - T7).max()}", flush=True)
        if a.pq0 is not None:
            fcd = h128                          # FC done = last logit cycle (bench: FC done = go(i+1) + 3250)
            s = T7 + a.pq0 - fcd
            print(f"{prog.run}: (b) RTL overlap 128 b: FC done go+{fcd}, first pq write go+T7+{a.pq0}: slack min {s.min()} "
                  f"mean {s.mean():.1f} max {s.max()} (fits {(s > 0).sum()}/{a.n}); 256 b slack min "
                  f"{(T7 + a.pq0 - a.lat256).min()}", flush=True)
            np.savetxt(os.path.join(a.cache, f"{prog.run}_r5e_slack.txt"), np.stack([iv, T7, s], 1), fmt="%d")
    return 0


if __name__ == "__main__":
    sys.exit(main())
