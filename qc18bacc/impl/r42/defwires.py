#!/usr/bin/env python3
"""R42: routed signal-wire segments of a DEF that touch an instance's box (+2 um), as obsclash39.py input
('<layer> x1 y1 x2 y2 <net>', um relative to the instance origin; width = LEF default per layer, vias ignored).
   python3 -I defwires.py <def> <inst> <out.txt> [orient check: R0 only]"""
import sys, re
deff, inst, outf = sys.argv[1:4]
W = {'M1': 0.09, 'M2': 0.1, 'M3': 0.1, 'M4': 0.1, 'M5': 0.1, 'M6': 0.1, 'M7': 0.1, 'M8': 0.4, 'M9': 0.4}
f = open(deff); u = 1000; ox = oy = None; sx = sy = None
for ln in f:
    if ln.startswith('UNITS DISTANCE MICRONS'): u = int(ln.split()[3])
    if ln.startswith('COMPONENTS'): break
for ln in f:
    t = ln.split()
    if len(t) > 2 and t[0] == '-' and t[1] == inst:
        m = re.search(r'PLACED\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*(\S+)', ln) or re.search(r'FIXED\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*(\S+)', ln)
        if not m:
            ln2 = next(f); m = re.search(r'(?:PLACED|FIXED)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*(\S+)', ln2)
        ox, oy, ori = int(m.group(1)) / u, int(m.group(2)) / u, m.group(3)
    if ln.startswith('END COMPONENTS'): break
bw, bh = float(sys.argv[4]), float(sys.argv[5])
print('DEFWIRES', inst, 'origin', ox, oy, ori, 'size', bw, bh)
X1, Y1, X2, Y2 = ox - 2, oy - 2, ox + bw + 2, oy + bh + 2
for ln in f:
    if ln.startswith('NETS'): break
o = open(outf, 'w'); n = 0; net = None; layer = None
pt = re.compile(r'\(\s*(\S+)\s+(\S+)(?:\s+\S+)?\s*\)')
for ln in f:
    if ln.startswith('END NETS'): break
    s = ln.strip()
    if s.startswith('- '): net = s.split()[1]; continue
    m = re.match(r'(?:\+\s*ROUTED|NEW)\s+(M\d)\s+(.*)', s)
    if not m: continue
    layer, rest = m.group(1), m.group(2)
    pts = pt.findall(rest); px = py = None; segs = []
    for a, b in pts:
        x = px if a == '*' else int(a) / u; y = py if b == '*' else int(b) / u
        if px is not None: segs.append((px, py, x, y))
        px, py = x, y
    hw = W[layer] / 2
    for (a, b, c, d) in segs:
        x1, x2 = min(a, c) - hw, max(a, c) + hw; y1, y2 = min(b, d) - hw, max(b, d) + hw
        if x2 < X1 or x1 > X2 or y2 < Y1 or y1 > Y2: continue
        o.write('%s %.3f %.3f %.3f %.3f %s\n' % (layer, x1 - ox, y1 - oy, x2 - ox, y2 - oy, net)); n += 1
print('DEFWIRES', inst, n, 'segments')
