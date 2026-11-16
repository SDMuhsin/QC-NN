#!/usr/bin/env python3
"""impl/r8: move the per-column head pool slices into their own groups.
    python3 -I pgrp.py <grp.txt in> <grp.txt out>
grp.txt lines '<inst> <group>' (impl/r6a/cuts.py --groups); every instance under u_head/g_pcol_<c>__u_pc/ -> group P<c>;
QB8_DIST_W 1: the act distribution registers u_top/g_dist_* -> W (next to the column-0 act pins, QB8_SWAP floorplan).
Prints the number of cells moved per slice and from which group."""
import os
import re
import sys
from collections import Counter

rx = re.compile(r"(?:^|/)g_pcol_(\d+)__u_pc/")
dist_w = os.environ.get("QB8_DIST_W", "0") == "1"   # QB8_SWAP floorplan: act distribution regs (u_top/g_dist_*) -> W
mv = Counter()
with open(sys.argv[1]) as fi, open(sys.argv[2], "w") as fo:
    for ln in fi:
        w = ln.split()
        if len(w) >= 2:
            m = rx.search(w[0])
            if m:
                mv[(w[1], "P" + m.group(1))] += 1
                w[1] = "P" + m.group(1)
            elif dist_w and w[0].startswith("u_top/g_dist_") and w[1] != "W":
                mv[(w[1], "W")] += 1
                w[1] = "W"
            fo.write(" ".join(w) + "\n")
for (a, b), n in sorted(mv.items()):
    print("PGRP %s -> %s %d cells" % (a, b, n))
print("PGRP total %d" % sum(mv.values()))
