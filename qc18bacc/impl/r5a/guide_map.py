#!/usr/bin/env python3
"""Routing-demand map from an OpenROAD route.guide (results/r5a.md): guide area per layer in B x B um bins, as a fraction
of the bin area (a proxy of GR usage), top bins per layer, and the net classes of the guides in the hottest M2 bins.
   guide_map.py <route.guide> [bin_um] [dbu_per_um]"""
import sys, collections as C, re
f = sys.argv[1]; B = float(sys.argv[2]) if len(sys.argv) > 2 else 50.0; U = float(sys.argv[3]) if len(sys.argv) > 3 else 2000.0
area = C.defaultdict(float); cls = C.defaultdict(C.Counter)
def ncls(n):
    m = re.search(r'g_r_(\d+)__g_c_0__', n)
    if m: return 'pe'
    if re.search(r'g_(fq|wq)_|u_pb[fw]', n): return 'lane'
    if re.match(r'(act|act_o|s_rd|f_y|pf|pw|b2|cd|t2)\[', n): return 'port:' + n.split('[')[0]
    if n.startswith('clk'): return 'clk'
    if re.match(r'net\d+$', n): return 'buf'
    return 'other'
net = None; inb = False
for line in open(f):
    t = line.split()
    if not t: continue
    if t[0] == '(': inb = True; continue
    if t[0] == ')': inb = False; continue
    if not inb: net = t[0]; continue
    x0, y0, x1, y1 = (float(v) / U for v in t[:4]); lay = t[4]
    # distribute the guide box over bins
    bx0, bx1, by0, by1 = int(x0 // B), int((x1 - 1e-6) // B), int(y0 // B), int((y1 - 1e-6) // B)
    for bx in range(bx0, bx1 + 1):
        for by in range(by0, by1 + 1):
            ox = min(x1, (bx + 1) * B) - max(x0, bx * B); oy = min(y1, (by + 1) * B) - max(y0, by * B)
            if ox > 0 and oy > 0:
                area[(lay, bx, by)] += ox * oy
                if lay == 'M2': cls[(bx, by)][ncls(net)] += ox * oy
lays = sorted(set(k[0] for k in area))
for lay in lays:
    v = sorted(((a / (B * B), bx, by) for (l, bx, by), a in area.items() if l == lay), reverse=True)
    mean = sum(x[0] for x in v) / max(len(v), 1)
    print('%s mean %.2f top: %s' % (lay, mean, ', '.join('(%d,%d)um %.2f' % (bx * B, by * B, a) for a, bx, by in v[:6])))
v = sorted(((a / (B * B), bx, by) for (l, bx, by), a in area.items() if l == 'M2'), reverse=True)[:5]
for a, bx, by in v:
    c = cls[(bx, by)]; tot = sum(c.values())
    print('M2 bin (%d,%d): %s' % (bx * B, by * B, ', '.join('%s %.0f%%' % (k, 100 * x / tot) for k, x in c.most_common(5))))
