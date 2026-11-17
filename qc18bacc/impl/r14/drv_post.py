#!/usr/bin/env python3
"""R14: classify a report_check_types -max_slew -max_capacitance -violators dump (drv_post.tmp) like drv_post.tcl:
t2 (hub / column t2 pins), other block pins, split trunks / clock (q14*), top.    python3 -I drv_post.py <drv_post.tmp>"""
import sys
from collections import defaultdict
n = defaultdict(int); w = {}; k = "slew"
for l in open(sys.argv[1]):
    if "max slew" in l: k = "slew"
    elif "max capacitance" in l: k = "cap"
    if "VIOLATED" not in l: continue
    f = l.split(); pin, s = f[0], float(f[3])
    blk = pin.startswith("u_hub/") or "u_col/" in pin or pin.startswith("u_act_blk/")
    c = "t2" if ("t2" in pin and blk) else ("blockpin" if blk else ("q14" if pin.startswith("q14") else "top"))
    key = k + "/" + c; n[key] += 1; w[key] = min(w.get(key, 0), s)
print("# R14 DRV at GRT parasitics (%s): check/class violators worst_slack" % sys.argv[1])
for key in sorted(n): print("%-16s %7d %8.3f" % (key, n[key], w[key]))
