#!/usr/bin/env python3
"""R5b (results/r5b.md): top-level view of an exact-shape abstract LEF (write_abstract_lef -bloat_factor 0, 9.2 M OBS
rects for qb_col_blk).  Per OBS layer in BLOCK_LAYERS: keep the exact rects that reach into the edge ring of width D um
(where the signal pins are, so top-level pin access sees the real geometry) and replace everything else by one interior
rect (the box shrunk by D).  Layers not listed (M7: the PG pins are M7 straps, a full M7 OBS would cover them) keep every
exact rect.  Pins, macro header and vias unchanged.
usage: lef_ring.py <in.lef> <out.lef> [D=1.5] [BLOCK_LAYERS=M1,M2,M3,M4,M5,M6]"""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
D = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
blk = set((sys.argv[4] if len(sys.argv) > 4 else 'M1,M2,M3,M4,M5,M6').split(','))
W = H = None
kept, total = {}, {}
with open(src) as f, open(dst, 'w') as o:
    obs = False; layer = None; pending = []
    for line in f:
        s = line.split()
        if not obs:
            if s[:1] == ['SIZE']: W, H = float(s[1]), float(s[3])
            o.write(line)
            if s == ['OBS']: obs = True
            continue
        if s[:1] == ['LAYER']:
            layer = s[1]; o.write(line)
            if layer in blk:
                o.write('     RECT  %.3f %.3f %.3f %.3f ;\n' % (D, D, W - D, H - D))
            continue
        if s[:1] == ['RECT']:
            total[layer] = total.get(layer, 0) + 1
            x0, y0, x1, y1 = map(float, s[1:5])
            if layer in blk and x0 >= D and y0 >= D and x1 <= W - D and y1 <= H - D:
                continue
            kept[layer] = kept.get(layer, 0) + 1
            o.write(line); continue
        if s == ['END']: obs = False
        o.write(line)
print('LEF_RING size %s x %s D %.2f' % (W, H, D))
for l in sorted(total): print('  %s exact %d kept %d' % (l, total[l], kept.get(l, 0)))
