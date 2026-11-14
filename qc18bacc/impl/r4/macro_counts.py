#!/usr/bin/env python3
"""Macro accesses in a SAIF window (R4 power): per memory wrapper (qbt_rfsp / qbt_rf2p of hw/tech/qb_mem_tech.sv)
the cycles with ren / we high = T1 / period (both are registered, cycle-aligned enables; rf_sp: a write cycle is not
a read, the host never writes a macro in a cycle it is read).

    macro_counts.py <window.saif> <period_ps> > counts.txt
Output: per macro type: instances, reads, writes in the window (sum over instances), window cycles."""
import re
import sys
from collections import defaultdict

TYPES = [("qb_w_204x144m2", r"/u_top/g_wl\[\d+\]/g_wd\[\d+\]/u_m$"),
         ("qb_s_256x128m1", r"/u_top/g_s\[\d+\]/u_m$"),
         ("qb_b_128x128m1", r"/u_top/g_map\[\d+\]/g_mm\[\d+\]/u_m$"),
         ("qb_i_128x128m1", r"/u_top/g_img\[\d+\]/u_m$"),
         ("qb_p_240x144m2", r"/u_prm/g_pm\[\d+\]/u_m$"),
         ("qb_f_408x64m4", r"/u_head/g_fl\[\d+\]/g_fd\[\d+\]/u_m$"),
         ("qb_d_624x80m8", r"/u_seq/g_dmac/u_d[es]$")]
f, per = sys.argv[1], float(sys.argv[2])
path, dur = [], None
acc = defaultdict(lambda: [0, 0.0, 0.0])
cur_t = None
inst_re = re.compile(r"^\s*\(INSTANCE (\S+)")
net_re = re.compile(r"^\s*\((ren|we) \(T0 (\d+)\) \(T1 (\d+)\)")
depth_stack = []
with open(f) as fh:
    for line in fh:
        if line.startswith("(DURATION"):
            dur = int(line.split()[1].rstrip(")"))
        m = inst_re.match(line)
        if m:
            path.append(m.group(1)); depth_stack.append(0)
            p = "/" + "/".join(path)
            cur_t = None
            for t, r in TYPES:
                if re.search(r, p):
                    cur_t = t; acc[t][0] += 1
            continue
        s = line.strip()
        if cur_t:
            n = net_re.match(line)
            if n:
                acc[cur_t][1 if n.group(1) == "ren" else 2] += int(n.group(3)) / per
        # track closing parens of INSTANCE blocks: an INSTANCE block ends with a line ' )' at its indentation
        if s == ")" and path:
            ind = len(line) - len(line.lstrip())
            if ind == len(path):          # verilated_saif: INSTANCE at indent k closes with ')' at indent k
                path.pop(); depth_stack.pop(); cur_t = None
print(f"# window cycles {dur / per:.1f} (duration {dur}, period {per})")
for t, _ in TYPES:
    n, r, w = acc[t]
    print(f"{t} n {n} reads {r:.1f} writes {w:.1f}")
