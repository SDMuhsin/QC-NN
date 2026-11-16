#!/usr/bin/env python3
"""R6b chip floorplan (results/r6b.md; the R6a group plan, results/r6a.md section 2): <run>/macros.txt (name master w h,
impl/r5b/dump_macros.tcl) -> <out.tcl> (P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE)) + <out>.groups (group rectangles).
Geometry (um, lower-left origin; env overrides in brackets):
  array  8 x qb_col_blk (390 x 3110) abutted, x0 = M + WEST [QB_WEST 850]; WA / W strip west of it
  south  params row (8, MX, right-aligned to the array's east edge), B row (one per column), 4 S rows (R0, pitch 392.4
         around the columns), channels CH [QB_CH 40]; then the south logic band SB [QB_SB 280] under the array.
         SW corner: FC (R90) at x M, IMG x 4 stacked + params 9 (R90) east of it; head / S logic in the rest
  north  logic band NB [QB_NB 120], 6 weight rows of 8 (slot c = lanes 2c, 2c+1), right-aligned; the NW corner left
         by the 3 588-um weight band belongs to W (sequencer)
  west   WA = act supply (y from the array bottom up to WA_H [QB_WAH 1830] above it), W = sequencer + 2 descriptor
         macros (R0, at the top of the strip) + NW corner
Groups (rectangles, std-cell placement regions of impl/r6b/grp_place.tcl): S, WA, W, N.
usage: mplace.py <macros.txt> <out.tcl>
impl/r8 copy (results/r8.md), identical by default; QB8_SWAP 1 swaps the SW-corner macros and the act supply: FC (R90),
IMG x 4 and params 9 go to the west strip (top-aligned at QB8_MTOP [1980] um above the array bottom = R6c's WA / W split),
so the SW corner + the lower west strip become act-supply rows next to the S band (impl/r8/groups.py QB8_SWAP)."""
import os, re, sys
E = lambda k, d: float(os.environ.get(k, d))
M, WEST, CH, SB, NB, HG = 10.0, E('QB_WEST', 850), E('QB_CH', 40), E('QB_SB', 280), E('QB_NB', 120), 10.0
WAH = E('QB_WAH', 1830)
BW, BH, NC = 390.0, 3110.0, 8
ROWH, SITE, CY0 = 1.8, 0.2, 5.0
snapx = lambda v: round(round(v / SITE) * SITE, 3)
snapy = lambda v: round(CY0 + round((v - CY0) / ROWH + 0.4999) * ROWH, 3)
inst = {}
for ln in open(sys.argv[1]):
    n, m, w, h = ln.split(); inst.setdefault(m, []).append((n, float(w), float(h)))
def idx(n, *keys):
    return tuple(int(re.search(k + r'_?(\d+)_', n).group(1)) for k in keys)
dim = {m: v[0][1:] for m, v in inst.items()}
place = []
def put(n, x, y, o):
    place.append((n, snapx(x), snapy(y), o))
x0 = M + WEST
xr = x0 + NC * BW
dieW = xr + M
# ---- south: params row right-aligned to the array east edge
P = sorted(inst['qb_p_240x144m2'], key=lambda t: idx(t[0], 'g_pm'))
pw, ph = dim['qb_p_240x144m2']
xs = xr - (8 * (pw + HG) - HG)
y = M
for k, (n, _, _) in enumerate(P[:8]): put(n, xs + k * (pw + HG), y, 'MX')
y = snapy(y + ph + CH)
ysw = y                                   # SW corner macros start here (above the params row's west end)
B = sorted(inst['qb_b_128x128m1'], key=lambda t: idx(t[0], 'g_map', 'g_mm'))
bw, bh = dim['qb_b_128x128m1']
for c, (n, _, _) in enumerate(B): put(n, x0 + c * BW + (BW - bw) / 2, y, 'MX')
y = snapy(y + bh + CH)
S = sorted(inst['qb_s_256x128m1'], key=lambda t: idx(t[0], 'g_s'))
sw, sh = dim['qb_s_256x128m1']
for r in range(4):
    for c in range(8):
        put(S[8 * r + c][0], x0 + c * BW + (BW - sw) / 2 + (sw + HG - BW) * (c - 3.5), y, 'R0')
    y = snapy(y + sh + CH)
ya = snapy(y - CH + SB)                   # array bottom
yt = ya + BH
for c in range(NC):
    put([t for t in inst['qb_col_blk'] if idx(t[0], 'g_c')[0] == c][0][0], x0 + c * BW, ya, 'R0')
# SW corner: FC (R90, 394 wide) at x M; east of it IMG x 4 stacked (MX) and params 9 (R90)
fw, fh = dim['qb_f_3232x128m8']
I = sorted(inst['qb_i_128x128m1'], key=lambda t: idx(t[0], 'g_img'))
iw, ih = dim['qb_i_128x128m1']
xi = M + fh + 2 * HG
SWAP = os.environ.get('QB8_SWAP', '0') == '1'
if SWAP:                                  # R8: the same column of macros, top-aligned in the west strip
    ytop = snapy(ya + E('QB8_MTOP', 1980)) - HG
    put(inst['qb_f_3232x128m8'][0][0], M, ytop - fw, 'R90')
    for k, (n, _, _) in enumerate(I): put(n, xi, ytop - (k + 1) * (ih + HG) + HG, 'MX')
    put(P[8][0], xi + iw + HG, ytop - pw, 'R90')
    assert ytop - fw >= ya + 5
else:
    put(inst['qb_f_3232x128m8'][0][0], M, ysw, 'R90')
    for k, (n, _, _) in enumerate(I): put(n, xi, ysw + k * (ih + HG), 'MX')
    put(P[8][0], xi + iw + HG, ysw, 'R90')
    assert ysw + fw <= ya - 5 and ysw + 4 * (ih + HG) <= ya
assert xi + iw + HG + ph <= x0 - HG, 'SW corner too narrow'
# ---- north: weights right-aligned, slot c = column c (lanes 2c, 2c+1), rows 0..5 = (lane parity, depth)
ww, wh = dim['qb_w_204x144m2']
W = sorted(inst['qb_w_204x144m2'], key=lambda t: idx(t[0], 'g_wl', 'g_wd'))
xw = xr - (8 * (ww + HG) - HG)
y = snapy(yt + NB)
yn = y
rows = []
for r in range(6):
    rows.append((y, 'R0' if r % 2 == 0 else 'MX'))
    y = snapy(y + wh + (HG if r % 2 == 0 else CH))
for n, _, _ in W:
    l, d = idx(n, 'g_wl', 'g_wd')
    c, r = l // 2, 3 * (l % 2) + d
    put(n, xw + c * (ww + HG), rows[r][0], rows[r][1])
top = snapy(y - CH + HG)
# ---- west strip: descriptors (R0) at its top, under the NB band level
dw, dh = dim['qb_d_624x80m8']
D = sorted(inst['qb_d_624x80m8'])
assert M + dw <= x0 - HG
for j, (n, _, _) in enumerate(D): put(n, M, yn - (j + 1) * (dh + 2 * HG), 'R0')
dieW, dieH = snapx(dieW), round(top + M, 1)
n_all = sum(len(v) for v in inst.values())
assert len(place) == n_all, (len(place), n_all)
yw = snapy(ya + WAH)
groups = {   # name: list of rects (x1 y1 x2 y2)
    'S':  [(0, 0, dieW, ya)],
    'WA': [(0, ya, x0, yw)],
    'W':  [(0, yw, x0, yn), (0, yn, xw - HG, dieH)],
    'N':  [(x0, yt, dieW, yn), (xw - HG, yn, dieW, dieH)],
}
with open(sys.argv[2], 'w') as f:
    f.write('# generated by impl/r8/mplace.py (WEST %g CH %g SB %g NB %g WAH %g SWAP %d)\n' % (WEST, CH, SB, NB, WAH, SWAP))
    f.write('set P(DIE_AREA) {0 0 %.1f %.1f}\nset P(CORE_AREA) {5 5 %.1f %.1f}\n' % (dieW, dieH, dieW - 5, dieH - 5))
    f.write('set P(MACRO_PLACE) {\n' + ''.join('  {%s %.3f %.3f %s}\n' % ((p[0].replace('\\', '\\\\'),) + p[1:]) for p in place) + '}\n')
    f.write('set ::QB_PIN_Y {%.1f %.1f}\n' % (yw + 200, yn - 400))
with open(sys.argv[2] + '.groups', 'w') as f:
    for g, rs in groups.items():
        f.write(g + ' ' + ' '.join('%.1f %.1f %.1f %.1f' % r for r in rs) + '\n')
print('MPLACE die %.1f x %.1f um = %.3f mm2, %d instances, array at (%.1f, %.1f), WA/W split y %.1f, N band y %.1f'
      % (dieW, dieH, dieW * dieH / 1e6, len(place), x0, ya, yw, yn))
