#!/usr/bin/env python3
"""R17 [E] side estimate (not implemented): S1 crossings measured on act-unit rows (S1 value -> act units, before
row-homing) for (i) the current pixel -> act-row map, (ii) the same + best slot-independent lb permutation, (iii) an
interleaved act-row map for multi-row tiles (cfg 5 / 6 / 7 / 8 / 9: r = 8 oyr + ox -> 2 ox + oyr; cfg 10: r = 4 oy + ox ->
4 ox + oy) + permutation.  Bound per layout = slot-independent optimum, as lbp_feas.py.
    python3 -I qc18bacc/impl/r17/lbp_rowmap.py"""
import os, sys
from collections import defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "..", "hw", "tb"))
import lbp_feas as F            # noqa: E402
import gen_act2_s2m as M       # noqa: E402

def relabel(c, r, mode):
    if mode == 0 or c in (0, 1, 2, 3, 4):
        return r
    if c == 10:
        oy, ox = divmod(r, 4); return 4 * ox + oy
    oyr, ox = divmod(r, 8); return 2 * ox + oyr

def readers(mode):
    s1, s2 = M.ref()
    R = {L: defaultdict(lambda: defaultdict(set)) for L in F.LAYOUTS}
    for u in range(16 * 9):
        for p, cs in s2[u].items():
            for c in cs:
                for G, ls in s1[p].items():
                    for l in ls:
                        if l in M.RL[c]:
                            R[F.lay(c, l)][G % 64][G // 64].add(relabel(c, u // 9, mode))
    return R

for mode in (0, 1):
    R = readers(mode)
    rd = defaultdict(set)
    for L in F.LAYOUTS:
        for j, bys in R[L].items():
            for s, rs in bys.items(): rd[(s, j)] |= rs
    cur = sum(32 * F.span(v) for v in rd.values())
    lb = {L: sum(32 * min(sum(F.span(rs | {y}) for rs in bys.values()) for y in range(16)) for bys in R[L].values())
          for L in F.LAYOUTS}
    tot_lb_layouts = max(lb.values())
    print(f"row map {'interleaved' if mode else 'current    '}: S1 crossings (act-unit rows, fixed lb order) {cur:6d}; "
          f"any-permutation bound {tot_lb_layouts:6d} (worst layout {max(lb, key=lb.get)}); per layout "
          + ", ".join(f"{L} {v}" for L, v in lb.items()))
