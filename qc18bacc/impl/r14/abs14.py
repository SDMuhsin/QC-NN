#!/usr/bin/env python3
"""R14 block proxies (results/r14.md): hub and act-supply abstracts for the R14 west-strip floorplan + budget liberty.
Floorplan (fp14.py): array x0 = X0 [900] (R9a act block F2 is 900 wide, east edge on column 0's west edge), hub at
(0, 0) widened to 3990 + (X0 - 860) = 4030 (its west strip x 0..X0; R11 pin plan shifted east by X0 - 860), act
900 x 1970 at (0, yh + 3110 - 1970) (top = array top), sequencer / host IOs in the gap below the act block.
  hub   R11 hub LEF (impl/r11 run.sh hubfp: R10b recipe pins9.py / pins10.tcl) shifted by dx = X0 - 860, plus
        * t2 (1 056 hub M8 pins -> column t2 M2 pins on the column NORTH edge): each hub t2 pin moved to the M8 track
          nearest its column pin's chip x (greedy, sorted, PDN M8 straps avoided) -> straight M8 over the column,
          no M9 jog (R11: hub pins spread over the column width, dx median 127 / max 344 um vs pins in x 215..365)
        * clk: from the north edge under column 7 (x 3973, M8) to the west strip north edge (x QB14_HCLK [450], M4),
          i.e. into the gap where the top clock root is (the real hub routes clk from there to its tree root)
  act   900 x 1970 proxy (R13 is rebuilding the real block, ACT_PIPE 1 + dist reg, with this pin plan):
        east  act[b]: column 0's act pin shape / layer / y - (3110 - H)   (abutted by construction)
        south every other pin: s_q / m_q / read-port pins straight above their hub pin (same layer / x; hub s_q pin
              order = top net order after the WB_COL transpose T, which the top netlist carries: act pin T(k) is on
              hub net s_q[k]); controls (sequencer side) + clk on M4 at free x around QB14_ACLK [450]
Liberty: impl/r11/blk_lib.py budgets, then (a) block clock insertion in the arcs (as an ETM with propagated clock):
  out clk->pin += ins, setup -= ins, hold += ins; hub QB14_HINS [0.90 ns, E: column-class tree, R8d], act
  QB14_AINS [0.55 ns, R9a IO latency]; (b) t2 output max_capacitance 1.0 pF (hub interface spec: t2 pin drivers sized
  for the 3.1-mm M8 net, e.g. BUFFD16).
    python3 -I abs14.py <r11 hub LEF> <col LEF> <col_act_pins.txt> <top_bpins.txt> <hub H> <out dir> <period>"""
import os
import re
import subprocess
import sys
from collections import defaultdict
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "r11"))
from lefio import read_macro, write_macro

E = lambda k, d: float(os.environ.get(k, d))
hublef, colef, colp, bp, yh, od, per = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5]), sys.argv[6], sys.argv[7]
X0 = E("QB14_X0", 900.0); DX = X0 - 860.0
AW, AH = E("QB14_ACT_W", 900.0), E("QB14_ACT_H", 1970.0)
HW = 3990.0 + DX
OBS = ["M1", "M2", "M3", "M4", "M5", "M6", "M7"]
_, _, _, hp0 = read_macro(hublef)
_, CW, CH, cp = read_macro(colef)
hp = {p: (d, ly, x1 + DX, y1, x2 + DX, y2) for p, (d, ly, x1, y1, x2, y2) in hp0.items()}
net_of = defaultdict(dict); by_net = defaultdict(list)
for ln in open(bp):
    i, m, p, n = ln.split()
    net_of[m][p] = n; by_net[n].append((i, m, p))
# ---------------------------------------------------------------- hub t2 pins on the column pin's M8 track
P8, OFF8 = 0.8, 0.4
# QB14_T2SP [2]: t2 pins on every SP-th M8 track (GRT: a 3-um gcell holds ~2.8 M8 tracks after the 0.25 layer
# adjustment; 136 bits on consecutive tracks overflowed every gcell along the 3.1-mm column in r14_h / r14_i)
SP = int(E("QB14_T2SP", 2))
def strap(x):   # PDN M8 straps (impl/hard/col_pdn.tcl: width 3, pitch 40, offset 10; VDD + VSS -> every 20 um)
    r = (x - 10.0) % 20.0
    return r < 4.5 or r > 18.5
want = []
# 32 column t2 pins hang off a top buffer (DC's u_arr BUFFD8, removed by remove_buffers before placement) whose input
# is a hub t2 pin that the R10b pin plan put in the WEST STRIP (no column pin on its net): trace hub net -> buffer ->
# column net through the top netlist (QB14_TOPV) so those hub pins also go onto their column's M8 track.
thru = {}
if os.environ.get("QB14_TOPV"):
    bi = {}
    for m in re.finditer(r"\n\s*(?:BUFF|CKBD)\w*\s+(\S+)\s*\(\s*\.I\(\s*([^)\s]+)\s*\)\s*,\s*\.Z\(\s*([^)\s]+)\s*\)", open(os.environ["QB14_TOPV"]).read()):
        bi[m.group(2)] = bi.get(m.group(2), []) + [m.group(3)]
    for p, n in net_of["qb_hub"].items():
        if p.startswith("u_top_g_r3b_t2_s") and not any(m == "qb_col_blk" for i, m, q in by_net[n]):
            for zn in bi.get(n, []):
                if any(m == "qb_col_blk" and q.startswith("t2") for i, m, q in by_net[zn]):
                    thru[p] = zn
for p, n in net_of["qb_hub"].items():
    if not p.startswith("u_top_g_r3b_t2_s"):
        continue
    n = thru.get(p, n)
    cols = [(i, q) for i, m, q in by_net[n] if m == "qb_col_blk" and q.startswith("t2")]
    if not cols:
        continue
    i, q = cols[0]
    c = int(re.search(r"g_c_(\d+)_", i).group(1))
    g = cp[q]
    want.append((X0 + 390.0 * c + (g[2] + g[4]) / 2, p))
want.sort()
used, moved, dxs = set(), 0, []
for x, p in want:
    k0 = int(round((x - OFF8) / P8)); best = None
    for d in range(0, 800):
        for k in (k0 - d, k0 + d):
            tx = OFF8 + P8 * k
            if all(k + j not in used for j in range(-SP + 1, SP)) and not strap(tx) and X0 + 1.0 < tx < X0 + 8 * 390.0 - 1.0:
                best = k; break
        if best is not None:
            break
    used.add(best); tx = OFF8 + P8 * best; dxs.append(abs(tx - x))
    d_, ly, x1, y1, x2, y2 = hp[p]
    hp[p] = (d_, "M8", tx - 0.2, yh - 0.8, tx + 0.2, yh); moved += 1
dxs.sort()
# hub clk into the west strip: north edge, M8 (the west-strip M2 / M4 / M6 pin rows are dense; M8 is free there)
hx = E("QB14_HCLK", 450.0)
while strap(hx):
    hx += 0.8
hp["clk"] = ("INPUT", "M8", hx - 0.2, yh - 0.8, hx + 0.2, yh)
write_macro(os.path.join(od, "qb_hub.lef"), "qb_hub", HW, yh, hp, OBS)
# ---------------------------------------------------------------- act block
yoff = 3110.0 - AH
pins, side = {}, {}
for ln in open(colp):
    b, ly, a, c, d, e = ln.split()
    a, c, d, e = map(float, (a, c, d, e))
    w, h, y = d - a, e - c, (c + e) / 2 - yoff
    pins["act[%s]" % b] = ("OUTPUT", ly, AW - w, y - h / 2, AW, y + h / 2); side["act[%s]" % b] = "E"
OUTS = ("busy", "done", "l_pos0", "l_pos1", "m_ren", "m_ra", "m_ctx", "s_ren", "s_ra", "s_ctx", "err", "l_ok", "l_seq0", "l_seq1", "tgo")
used = defaultdict(set); ctl = []; nal = 0
for p, n in sorted(net_of["qb_act2_blk"].items()):
    if p.startswith("act["):
        continue
    d = "OUTPUT" if p.split("[")[0] in OUTS or p.startswith("d_") or p.startswith("a_") else "INPUT"
    hpn = [q for i, m, q in by_net[n] if m == "qb_hub"]
    if hpn and p not in ("clk", "rst_n") and hpn[0] in hp:
        _, ly, x1, y1, x2, y2 = hp[hpn[0]]
        cx = (x1 + x2) / 2; w = x2 - x1
        assert 0.5 < cx < AW - 0.5, (p, cx)
        while round(cx, 1) in used[ly]:
            cx += 0.4
        used[ly].add(round(cx, 1))
        pins[p] = (d, ly, cx - w / 2, 0.0, cx + w / 2, 0.5); side[p] = "S"; nal += 1
    else:
        ctl.append((p, d))
# controls + clk: south edge M4 at free x nearest QB14_ACLK, 1.0-um pitch, clk first (middle)
ctl.sort(key=lambda z: (z[0] != "clk", z[0]))
xc = E("QB14_ACLK", 450.0); occ = sorted(used["M4"]); cand = []
k = 0
while len(cand) < len(ctl):
    for s in ((1,) if k == 0 else (1, -1)):
        x = round(xc + s * k * 1.0, 1)
        if 1.0 < x < AW - 1.0 and all(abs(x - o) >= 0.8 for o in occ):
            cand.append(x)
    k += 1
for (p, d), x in zip(ctl, cand):
    pins[p] = (d, "M4", x - 0.1, 0.0, x + 0.1, 0.5); side[p] = "S"
write_macro(os.path.join(od, "qb_act2_blk.lef"), "qb_act2_blk", AW, AH, pins, OBS)
with open(os.path.join(od, "act_pins.txt"), "w") as f:
    for p, (d, ly, x1, y1, x2, y2) in sorted(pins.items()):
        f.write("%s %s %s %.3f %.3f\n" % (p, side[p], ly, (x1 + x2) / 2, (y1 + y2) / 2))
print("ABS14 t2 hub pins traced through a top buffer: %d" % len(thru))
print("ABS14 hub %.1f x %.1f: t2 pins moved %d (|track - column pin x| median %.2f max %.2f um), clk at x %.1f M8; "
      "act %.0f x %.0f: east %d, south hub-aligned %d, south controls %d (x %.1f..%.1f)"
      % (HW, yh, moved, dxs[len(dxs) // 2], dxs[-1], hx, AW, AH, sum(1 for s in side.values() if s == "E"), nal, len(ctl),
         min(cand[:len(ctl)]), max(cand[:len(ctl)])))
# ---------------------------------------------------------------- liberty
def lib(lef, bits, kind, name, ins):
    subprocess.check_call([sys.executable, "-I", os.path.join(here, "..", "r11", "blk_lib.py"), per, lef, bits, kind, name], cwd=od)
    for c, s in (("tt", 1.0), ("ss", 1.6), ("ff", 0.8)):
        fn = os.path.join(od, "%s_%s.lib" % (name, c)); t = open(fn).read()
        a = ins * s
        t = re.sub(r'(cell_(?:rise|fall) \(scalar\) \{ values \(")([\d.\-]+)', lambda m: m.group(1) + "%.4f" % (float(m.group(2)) + a), t)
        t = re.sub(r'(setup_rising ;\n\s*rise_constraint \(scalar\) \{ values \(")([\d.\-]+)("\) ; \} fall_constraint \(scalar\) \{ values \(")([\d.\-]+)',
                   lambda m: m.group(1) + "%.4f" % (float(m.group(2)) - a) + m.group(3) + "%.4f" % (float(m.group(4)) - a), t)
        t = re.sub(r'(hold_rising ;\n\s*rise_constraint \(scalar\) \{ values \(")([\d.\-]+)("\) ; \} fall_constraint \(scalar\) \{ values \(")([\d.\-]+)',
                   lambda m: m.group(1) + "%.4f" % (float(m.group(2)) + a) + m.group(3) + "%.4f" % (float(m.group(4)) + a), t)
        if kind == "hub":
            t = re.sub(r'(pin \("u_top_g_r3b_t2_s[^"]*"\) \{ direction : output ; max_capacitance : )0\.3', r"\g<1>1.0", t)
        open(fn, "w").write(t)
lib("qb_hub.lef", sys.argv[8] if len(sys.argv) > 8 else "-", "hub", "qb_hub", E("QB14_HINS", 0.90))
lib("qb_act2_blk.lef", "-", "act", "qb_act2_blk", E("QB14_AINS", 0.55))
print("ABS14 liberty: hub insertion %.2f, act %.2f ns (tt; ss x1.6, ff x0.8)" % (E("QB14_HINS", 0.90), E("QB14_AINS", 0.55)))
