#!/usr/bin/env python3
"""R22: summary of impl/r22/sq22.tcl (S-macro net spans) per S column (macro x -> column (cx - X0) // 390) and pin
direction: nets, share whose load bbox crosses the die middle x = W / 2 (+ any column boundary k, listed), mean load-bbox
H span, mean offset of the load-bbox centre from the macro (in columns, signed: + = east), and the histogram of that offset.
    python3 -I sq22.py <sq22.txt> [X0 860] [W 3990]"""
import sys
import collections as C

fn = sys.argv[1]
X0 = float(sys.argv[2]) if len(sys.argv) > 2 else 860.0
W = float(sys.argv[3]) if len(sys.argv) > 3 else 3990.0
mid = W / 2
S = C.defaultdict(list)
for ln in open(fn):
    f = ln.split()
    if f[0] != 'S' or int(f[10]) == 0: continue
    cx, d, x0, x1 = float(f[2]), f[4], float(f[6]), float(f[7])
    c = int((cx - X0) // 390)
    S[(d, c)].append((min(x0, cx), max(x1, cx), ((x0 + x1) / 2 - cx) / 390.0))
print('# sq22 %s: per S column / direction: nets, crossing x %.0f %%, mean span um, mean offset (cols), offset histogram' % (fn, mid))
for d in ('O', 'I'):
    for c in range(8):
        v = S.get((d, c), [])
        if not v: continue
        cr = sum(1 for a, b, o in v if a < mid < b) / len(v)
        h = C.Counter(int(round(o)) for a, b, o in v)
        print('SQ %s col%d n %5d cross-mid %5.1f %% span %6.0f off %+5.2f | %s' % (
            d, c, len(v), 100 * cr, sum(b - a for a, b, o in v) / len(v), sum(o for a, b, o in v) / len(v),
            ' '.join('%+d:%d' % kv for kv in sorted(h.items()))))
