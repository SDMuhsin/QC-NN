#!/usr/bin/env python3
"""R7c: act pin geometry of the column block abstract (r5b_blk qb_col_blk[_ring].lef) -> text table
'bit layer x0 y0 x1 y1' (um, block coordinates), plus a per-row y summary on stderr.
usage: col_pins.py <col.lef> <out.txt>"""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
pins, cur, layer = {}, None, None
for line in open(src):
    s = line.split()
    if s[:1] == ['PIN']:
        m = re.match(r'act\[(\d+)\]$', s[1]); cur = int(m.group(1)) if m else None; continue
    if cur is None: continue
    if s[:1] == ['LAYER']: layer = s[1]
    elif s[:1] == ['RECT'] and cur not in pins: pins[cur] = (layer, *map(float, s[1:5]))
    elif s[:1] == ['END']: pass
with open(dst, 'w') as o:
    for b in sorted(pins): o.write('%d %s %.3f %.3f %.3f %.3f\n' % (b, *pins[b]))
rows = {}
for b, (l, x0, y0, x1, y1) in pins.items(): rows.setdefault(b // 288, []).append((y0 + y1) / 2)
sys.stderr.write('act pins %d, layers %s\n' % (len(pins), sorted({p[0] for p in pins.values()})))
for r in sorted(rows):
    v = rows[r]; sys.stderr.write('row %2d n %d y %.1f .. %.1f\n' % (r, len(v), min(v), max(v)))
