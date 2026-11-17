#!/usr/bin/env python3
"""R15: where in y the hub's GRT traffic runs, per layer (results/r15.md).
    python3 -I lay15.py <mplace.tcl> <route.guide> <gr_congestion.rpt> <grt.log> [xa 860] [xb 3200]
Over x in [xa, xb] (columns 0-5 by default) the die is cut into y bands from ::QB15_BANDS of mplace.tcl (S rows, logic
bands; the gaps are 'south' (params / B rows) and 'ch' (40-um channels)).  Per band and routing layer:
  use %  = guide demand (H layers: guide length along x; V: along y) / nominal tracks (band height or width / GRT pitch
           = max(track pitch, line-2-via pitch) from the GRT log) x span; no derating, no OBS: M2 / M3 over macros are
           obstructed (macro OBS M1-M3), M4-M9 over the S / B / params macros are free apart from PDN straps
  cut    = H guide crossings of the vertical lines x = 1055 + 390 k (k 0..5, column centres) per band / band H tracks
  ovf    = gr_congestion.rpt overflow records (2-D, all layers) with centre in the band: H / V tracks, gcells
"""
import re
import sys
from collections import defaultdict

import numpy as np

fm, fg, frpt, flog = sys.argv[1:5]
xa = float(sys.argv[5]) if len(sys.argv) > 5 else 860.0
xb = float(sys.argv[6]) if len(sys.argv) > 6 else 3200.0
t = open(fm).read()
H = float(re.search(r'DIE_AREA\) \{0 0 [\d.]+ ([\d.]+)\}', t).group(1))
m = re.search(r'::QB15_BANDS \{([^}]*)\}', t)
if m:
    v = m.group(1).split(); nb = [(v[i], float(v[i + 1]), float(v[i + 2])) for i in range(0, len(v), 3)]
else:   # mplace10 floorplan: S rows from the macro list, band above
    ys = sorted({float(a) for a in re.findall(r'g_s_\d+__u_m\S* [\d.]+ ([\d.]+)', t)})
    nb = [('S%d' % k, y, y + 204.09) for k, y in enumerate(ys)] + [('band_top', ys[-1] + 204.09, H)]
nb.sort(key=lambda b: b[1])
bands, y = [], 0.0
for n, a, b in nb:
    if a - y > 1.0: bands.append(('south' if y == 0.0 else 'ch', y, a))
    bands.append((n, a, b)); y = b
if H - y > 1.0: bands.append(('ch', y, H))
pitch, dirs = {}, {}
for ln in open(flog):
    q = re.search(r'Layer (M\d)\s+Track-Pitch = ([\d.]+)\s+line-2-Via Pitch: ([\d.]+)', ln)
    if q: pitch[q.group(1)] = max(float(q.group(2)), float(q.group(3)))
    q = re.match(r'\s*(M\d)\s+(Horizontal|Vertical)\s+\d+', ln)
    if q: dirs[q.group(1)] = q.group(2)[0]
L = [l for l in sorted(pitch, key=lambda s: int(s[1:])) if l != 'M1']
G = 3.0; ny = int(H // G) + 1
dem = {l: np.zeros(ny) for l in L}                      # um of guide along the preferred direction per 3-um y row
cuts = [xa + 195 + 390 * k for k in range(int((xb - xa) // 390))]
cr = {l: np.zeros((len(cuts), ny)) for l in L}
u = 2000.0
for ln in open(fg):
    f = ln.split()
    if len(f) != 5 or f[4] not in dem: continue
    x1, y1, x2, y2 = (int(s) / u for s in f[:4]); l = f[4]
    if dirs[l] == 'H':
        a, b = max(x1, xa), min(x2, xb)
        j0, j1 = int(y1 // G), max(int(y1 // G), int((y2 - 1e-6) // G))
        if b > a: dem[l][j0:j1 + 1] += (b - a)
        for k, c in enumerate(cuts):
            if x1 < c < x2: cr[l][k, j0:j1 + 1] += 1
    else:
        xc = (x1 + x2) / 2
        if not (xa <= xc < xb): continue
        nx = max(1, round((x2 - x1) / G))
        e = np.arange(int(y1 // G), int((y2 - 1e-6) // G) + 1)
        ov = np.minimum((e + 1) * G, y2) - np.maximum(e * G, y1)
        dem[l][e] += ov * nx
ovf = defaultdict(lambda: [0, 0, set(), set()])
cur = None
for ln in open(frpt):
    s = ln.strip()
    if s.startswith('violation type'): cur = 'H' if 'Horizontal' in s else 'V'
    elif s.startswith('congestion information'): o = int(re.search(r'overflow:(\d+)', s).group(1))
    elif s.startswith('bbox'):
        q = re.search(r'\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)', s)
        gx1, gy1, gx2, gy2 = map(float, q.groups()); yc = (gy1 + gy2) / 2; xc = (gx1 + gx2) / 2
        for n, a, b in bands:
            if a <= yc < b:
                key = (n, a)
                ovf[key][0 if cur == 'H' else 1] += o
                ovf[key][2 if cur == 'H' else 3].add((xc, yc))
                if xa <= xc < xb: ovf[('x', n, a)][0 if cur == 'H' else 1] += o
                break
W = xb - xa
rows = lambda a, b: slice(int(a // G), int((b - 1e-6) // G) + 1)
out = ['# R15 lay15: x %.0f-%.0f (columns 0-5), die H %.1f, GRT pitch %s' % (xa, xb, H, ' '.join('%s %.2f' % (l, pitch[l]) for l in L)),
       '# use %% = guide demand / nominal tracks x span (no derate / OBS); cut = H crossings at x %s / band H tracks (sum of H layers)' % ' '.join('%.0f' % c for c in cuts),
       '%-9s %6s %6s ' % ('band', 'y0', 'y1') + ' '.join('%5s' % l for l in L) + '  allH  allV | Htrk  cutH%% min-max | ovf H / V tracks (x-range H / V) gcells']
TH = {}
for n, a, b in bands:
    r = rows(a, b); h = b - a
    us = []
    for l in L:
        cap = (h / pitch[l]) * W if dirs[l] == 'H' else (W / pitch[l]) * h
        us.append(100.0 * dem[l][r].sum() / cap)
    hd = sum(dem[l][r].sum() for l in L if dirs[l] == 'H'); hc = sum((h / pitch[l]) * W for l in L if dirs[l] == 'H')
    vd = sum(dem[l][r].sum() for l in L if dirs[l] == 'V'); vc = sum((W / pitch[l]) * h for l in L if dirs[l] == 'V')
    htr = sum(h / pitch[l] for l in L if dirs[l] == 'H')
    cc = [sum(cr[l][k, r].sum() for l in L if dirs[l] == 'H') / htr * 100 for k in range(len(cuts))]
    TH[(n, a)] = (htr, [sum(cr[l][k, r].sum() for l in L if dirs[l] == 'H') for k in range(len(cuts))])
    o = ovf[(n, a)]; ox = ovf[('x', n, a)]
    out.append('%-9s %6.0f %6.0f ' % (n, a, b) + ' '.join('%5.1f' % x for x in us) + '  %4.1f  %4.1f | %5.0f  %3.0f-%3.0f | %6d / %6d (%6d / %6d) %d / %d'
               % (100 * hd / hc, 100 * vd / vc, htr, min(cc), max(cc), o[0], o[1], ox[0], ox[1], len(o[2]), len(o[3])))
# whole-height cut: H crossings over all bands vs all H tracks
tot = sum(v[0] for v in TH.values())
for k, c in enumerate(cuts):
    s = sum(v[1][k] for v in TH.values())
    sm = sum(v[1][k] for (n, a), v in TH.items() if n.startswith('S'))
    out.append('CUT x %6.0f  H crossings %6.0f of %6.0f tracks (die height) = %5.1f %% | over S rows %6.0f (%4.1f %% of all crossings)'
               % (c, s, tot, 100 * s / tot, sm, 100 * sm / max(1, s)))
# per-layer split of the over-S-row H use (the capacity the PI analysis says is idle)
for l in L:
    if dirs[l] != 'H': continue
    sr = [rows(a, b) for n, a, b in bands if n.startswith('S')]
    lb = [rows(a, b) for n, a, b in bands if n.startswith('band')]
    hs = sum(b - a for n, a, b in bands if n.startswith('S')); hl = sum(b - a for n, a, b in bands if n.startswith('band'))
    us = 100 * sum(dem[l][r].sum() for r in sr) / ((hs / pitch[l]) * W)
    ul = 100 * sum(dem[l][r].sum() for r in lb) / max(1e-9, (hl / pitch[l]) * W)
    out.append('LAYERH %s use over S rows %5.1f %% | in logic band(s) %5.1f %%' % (l, us, ul))
print('\n'.join(out))
