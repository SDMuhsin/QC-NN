#!/usr/bin/env python3
"""R11: proxy abstracts of the act-supply block qb_act2_blk (R9a has no routed abstract yet) and the hub (pins of the
R10b-recipe floorplan, impl/r11/run.sh hubfp), with OBS M1-M7 (M8 / M9 left to the top, as over the columns).
  act block W x H at chip (x0 - W, yh + 3110 - H) (R9a QB7_YOFF rule: block top = array top), pins:
    east   act[b]: column 0's act[b] shape / layer / y (col_act_pins.txt, R9a pins.tcl rule) -> abutted by construction
    south  every act pin whose net reaches a hub pin: the hub pin's x / layer / shape (straight above it; the
           hub-to-act gap is 3110 - H um of top-level wiring), x clamped into the block (counted: interface mismatch)
    north  the rest (sequencer / glue controls), M4, 2-um pitch from the middle
    python3 -I act_lef.py <col_act_pins.txt> <hub_abs.lef> <top_bpins.txt> <W> <H> <x0 array west> <hub H> <out dir>
Out: <out>/qb_act2_blk.lef, <out>/qb_hub.lef (hub pins + OBS M1-M7), <out>/act_pins.txt (pin side x y layer, block)."""
import os
import sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lefio import read_macro, write_macro

colp, hublef, bp, W, H, x0, yh, od = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]), \
    float(sys.argv[6]), float(sys.argv[7]), sys.argv[8]
OBS = ["M1", "M2", "M3", "M4", "M5", "M6", "M7"]
yoff = 3110.0 - H
xa = x0 - W
hn, hW, hH, hpins = read_macro(hublef)
# write_abstract_lef of a floorplan-only db: SIZE = shape bbox; the hub die is <hub H> (mplace10)
write_macro(os.path.join(od, "qb_hub.lef"), "qb_hub", 3990.0, yh, hpins, OBS)
net_of = defaultdict(dict)
hub_by_net = defaultdict(list)
for ln in open(bp):
    i, m, p, n = ln.split()
    net_of[m][p] = n
    if m == "qb_hub":
        hub_by_net[n].append(p)
pins, side = {}, {}
for ln in open(colp):
    b, ly, a, c, d, e = ln.split()
    a, c, d, e = map(float, (a, c, d, e))
    w, h, y = d - a, e - c, (c + e) / 2 - yoff
    pins["act[%s]" % b] = ("OUTPUT", ly, W - w, y - h / 2, W, y + h / 2); side["act[%s]" % b] = "E"
nclamp, nsouth, used = 0, 0, set()
north = []
for p, n in sorted(net_of["qb_act2_blk"].items()):
    if p.startswith("act["):
        continue
    d = "OUTPUT" if p.split("[")[0] in ("busy", "done", "l_pos0", "l_pos1", "m_ren", "m_ra", "m_ctx", "s_ren", "s_ra",
                                        "s_ctx", "err") or p.startswith("d_") or p.startswith("a_") else "INPUT"
    hp = hub_by_net.get(n)
    if hp and hpins.get(hp[0], (0, "",))[1] and p != "clk" and p != "rst_n":
        _, ly, x1, y1, x2, y2 = hpins[hp[0]]
        cx = (x1 + x2) / 2 - xa; w, h = x2 - x1, y2 - y1
        if cx < 1.0 or cx > W - 1.0:
            nclamp += 1; cx = min(max(cx, 1.0), W - 1.0)
        while (ly, round(cx, 1)) in used:
            cx += 0.4
        used.add((ly, round(cx, 1)))
        pins[p] = (d, ly, cx - w / 2, 0.0, cx + w / 2, h); side[p] = "S"; nsouth += 1
    else:
        north.append((p, d))
xm = W / 2 - len(north)
for k, (p, d) in enumerate(north):
    cx = round((xm + 2.0 * k) / 0.2) * 0.2
    pins[p] = (d, "M4", cx - 0.1, H - 0.8, cx + 0.1, H); side[p] = "N"
write_macro(os.path.join(od, "qb_act2_blk.lef"), "qb_act2_blk", W, H, pins, OBS)
with open(os.path.join(od, "act_pins.txt"), "w") as f:
    for p, (d, ly, x1, y1, x2, y2) in sorted(pins.items()):
        f.write("%s %s %s %.3f %.3f\n" % (p, side[p], ly, (x1 + x2) / 2, (y1 + y2) / 2))
print("ACT_LEF %s W %.1f H %.1f at chip (%.1f, %.1f): east act %d, south (hub-aligned) %d (clamped into the block %d), "
      "north %d; hub LEF %d pins, die 3990 x %.1f" % (od, W, H, xa, yh + yoff, sum(1 for s in side.values() if s == "E"),
                                                     nsouth, nclamp, len(north), len(hpins), yh))
