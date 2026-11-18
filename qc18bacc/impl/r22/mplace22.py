#!/usr/bin/env python3
"""R22 (results/r22.md): hub floorplan variants on the taller die (H from QB_SB, e.g. 649 -> 1950.2 um), built on
impl/r15/mplace15.py (run unchanged via runpy, same env QB15_FP / QB15_NG / QB_SB ...) and post-processed:
  QB22_FP a    mplace15 output unchanged (R15 mid with the taller logic band: only QB_SB differs)
  QB22_FP pn   "params north": the 8 column params macros (P, qb_p) move from the south edge to the north edge,
               MX (pins on the macro's north edge, facing the north-edge pf / pw column pins), with a prm logic band of
               QB22_G [110] um between the P row and the core top; S row 3 sits QB22_PS [10] um under the P row
               (QB15_NG = PS + P height + G is set for mplace15); B / S0 / S1 / FC / IMG / params 8 (west strip,
               above FC) shift south by the vacated P row + channel (B row at the core bottom).  The logic band
               between S1 and S2 keeps the rest of the height.  S rows / x positions / P x positions unchanged.
    pn options (opt-in, default off):
      QB22_S2S 1   S row 2 moves to the south side, MX (pins up, facing the band), QB22_S12 [10] um above S1 (no pins
                   on the facing edges); S row 3 alone under the P row: the north-bound V traffic crosses one S row and
                   S3 reads / writes no longer cross S2 (R22 r22_pn5: S2 pin-edge V cut 90 %, S Q 35 %)
      QB22_P0W 1   params 0 to the west strip above params 8 (MX, x 10, QB22_PS above it), params 1-7 right-aligned
                   at the core east edge with QB22_PG [7] um gaps (x >= 860: no params macro over the west boundary at
                   the north; r22_pn5: x 860 north H cut 88 %)
Writes the same <out.tcl> keys as mplace15 (P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE), ::QB9_H, ::QB9_X0,
::QB15_BANDS + 'prow' / 'prmband' bands for pn) and prints 'MPLACE22 ...' lines.
    python3 -I mplace22.py <macros.txt> <out.tcl>"""
import math
import os
import re
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
mac, out = sys.argv[1], sys.argv[2]
fp = os.environ.get('QB22_FP', 'a')
G, PS, CY0, ROWH = float(os.environ.get('QB22_G', 110)), float(os.environ.get('QB22_PS', 10)), 5.0, 1.8
dims = {}
for ln in open(mac):
    n, m, w, h = ln.split(); dims[m] = (float(w), float(h))
pw, ph = dims['qb_p_240x144m2']
if fp == 'pn':
    os.environ['QB15_NG'] = '%.3f' % (PS + ph + G)
elif fp != 'a':
    sys.exit('QB22_FP %s' % fp)
os.environ.setdefault('QB15_FP', 'mid')
tmp = out + '.mplace15'
sys.argv = [os.path.join(here, '../r15/mplace15.py'), mac, tmp]
runpy.run_path(sys.argv[0], run_name='__main__')
t = open(tmp).read(); os.remove(tmp)
if fp == 'pn':
    H = float(re.search(r'set ::QB9_H ([\d.]+)', t).group(1))
    pl = re.search(r'set P\(MACRO_PLACE\) \{\n(.*?)\n\}', t, re.S)
    rows = [ln.strip()[1:-1].split() for ln in pl.group(1).split('\n')]
    pidx = lambda n: (lambda m: int(m.group(1)) if m else None)(re.search(r'g_pm_?(\d+)_', n))
    isS = lambda n: re.search(r'g_s_(\d+)__u_m', n) is not None
    srow = lambda n: int(re.search(r'g_s_(\d+)__u_m', n).group(1)) // 8
    S2S, P0W = os.environ.get('QB22_S2S', '0') == '1', os.environ.get('QB22_P0W', '0') == '1'
    S12, PG = float(os.environ.get('QB22_S12', 10)), float(os.environ.get('QB22_PG', 7))
    ys = sorted({float(r[2]) for r in rows if isS(r[0])})
    yP = min(float(r[2]) for r in rows if pidx(r[0]) is not None and pidx(r[0]) < 8)
    yB = min(float(r[2]) for r in rows if 'qb_b' in r[0] or re.search(r'g_map', r[0]))
    dy = round(math.floor((yB - yP) / ROWH + 1e-6) * ROWH, 3)          # B row -> old P row y (row multiple)
    ypn = CY0 + math.floor((H - CY0 - G - ph - CY0) / ROWH + 1e-6) * ROWH  # P row y (row grid, top <= core top - G)
    s3top = ys[3] + dims['qb_s_256x128m1'][1]
    assert s3top + PS <= ypn + 1e-6, (s3top, ypn)
    sh = dims['qb_s_256x128m1'][1]
    snapu = lambda v: round(CY0 + math.ceil((v - CY0) / ROWH - 1e-6) * ROWH, 3)
    y2s = snapu(ys[1] - dy + sh + S12)                                    # S2 on the south side (QB22_S2S)
    pos = {}
    for r in rows:
        n, x, y, o = r[0], float(r[1]), float(r[2]), r[3]
        k = pidx(n)
        if k is not None and k < 8:
            y, o = ypn, 'MX'
            if P0W:
                if k == 0: x, y = None, None                                 # placed below (west strip)
                else: x = round(round((3985.0 - (8 - k) * pw - (7 - k) * PG) / 0.2) * 0.2, 3)
        elif S2S and isS(n) and srow(n) == 2:
            y, o = y2s, 'MX'
        elif y < ys[2] or k == 8:                                         # south group: B, S0, S1, FC, IMG, params 8
            y = round(y - dy, 3)
        pos[n] = [x, y, o]
    if P0W:
        n0 = [n for n in pos if pidx(n) == 0][0]; n8 = [n for n in pos if pidx(n) == 8][0]
        pos[n0] = [10.0, snapu(pos[n8][1] + ph + PS), 'MX']
        assert pos[n0][1] + ph <= ys[3] - 1e-6 or pos[n0][0] + pw < 860, pos[n0]
        assert min(pos[n][0] for n in pos if pidx(n) is not None and 0 < pidx(n) < 8) >= 860, 'params row over the west strip'
    body = ['  {%s %.3f %.3f %s}' % (n, v[0], v[1], v[2]) for n, v in pos.items()]
    t = t[:pl.start(1)] + '\n'.join(body) + t[pl.end(1):]
    if S2S:
        bands = [('S0', ys[0] - dy, ys[0] - dy + sh), ('S1', ys[1] - dy, ys[1] - dy + sh), ('S2', y2s, y2s + sh),
                 ('band_mid', y2s + sh, ys[3]), ('S3', ys[3], ys[3] + sh), ('prow', ypn, ypn + ph), ('prmband', ypn + ph, H - CY0)]
    else:
        bands = [('S0', ys[0] - dy, ys[0] - dy + sh), ('S1', ys[1] - dy, ys[1] - dy + sh), ('band_mid', ys[1] - dy + sh, ys[2]),
                 ('S2', ys[2], ys[2] + sh), ('S3', ys[3], ys[3] + sh), ('prow', ypn, ypn + ph), ('prmband', ypn + ph, H - CY0)]
    t = re.sub(r'set ::QB15_BANDS \{.*\}\n', 'set ::QB15_BANDS {%s}\n' % ' '.join('%s %.1f %.1f' % b for b in bands), t)
    t = t.replace('(QB15_FP', '+ impl/r22/mplace22.py pn (QB15_FP', 1)
    for b in bands: print('MPLACE22 band %s %.1f %.1f (%.1f um)' % (b + (b[2] - b[1],)))
    lb = [b for b in bands if b[0] == 'band_mid'][0]
    print('MPLACE22 pn (S2S %d P0W %d): south shift %.1f, P row y %.1f MX, S3 top %.1f, prm band %.1f um, logic band %.1f um' % (
        S2S, P0W, dy, ypn, s3top, H - CY0 - ypn - ph, lb[2] - lb[1]))
    if P0W: print('MPLACE22 params 0 west strip x 10 y %.1f, params 1-7 x %s' % (pos[n0][1], ' '.join(
        '%.1f' % pos[n][0] for n in sorted((n for n in pos if pidx(n) is not None and 0 < pidx(n) < 8), key=pidx))))
open(out, 'w').write(t)
print('MPLACE22 %s written %s' % (fp, out))
