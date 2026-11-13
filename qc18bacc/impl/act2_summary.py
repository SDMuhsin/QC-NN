#!/usr/bin/env python3
"""Area of a qb_act2 synthesis (R2b) by group, split into combinational / sequential (numbers only, safe to copy off
the server):  python3 -I qc18bacc/impl/act2_summary.py <syn_run_dir>
Groups (local cell areas of every hierarchy row summed by name prefix): line buffers g_ctx_*/u_lb (2 x 8 x 2048 flops
+ shift / write muxes), context control (rest of g_ctx_*: command, loaders, S-word FIFO counters, sequencers, 128-b
item / 64-b word priority encoders), S1 u_s1 (regs + chunk / context / S-word mux), S2 u_s2, act pipe u_ap, top
(flag store, map / S arbiters, rdq 512 b + sdq 2048 b input registers, descriptors).
"""
import os
import re
import sys


def kv(path, key):
    if not os.path.exists(path):
        return None
    m = re.search(key + r"\s+(\S+)", open(path).read())
    return m.group(1) if m else None


def group(name):
    if "u_lb" in name:
        return "line buffers u_lb (2 contexts x 8 x 2048 b)"
    if name.startswith("g_ctx"):
        return "context control (2: loaders, FIFO counters, sequencers)"
    if name.startswith("u_s1"):
        return "S1 u_s1 (regs + chunk / context / S-word mux)"
    if name.startswith("u_s2"):
        return "S2 u_s2 (act regs + static cfg mux)"
    if "u_ap" in name:
        return "act output pipe (ACT_PIPE regs)"
    return "top (flags, arbiters, rdq / sdq, descriptors)"


def main():
    d = sys.argv[1]
    rows = []
    for ln in open(os.path.join(d, "rpt", "area.rpt")):
        f = ln.split()
        if len(f) >= 6 and re.match(r"^[0-9.]+$", f[1]) and re.match(r"^[0-9.]+$", f[3]):
            rows.append((f[0], float(f[1]), float(f[3]), float(f[4])))
    total = rows[0][1]
    grp = {}
    for name, a, comb, seq in rows:
        g = group(name if name != rows[0][0] else "")
        v = grp.setdefault(g, [0.0, 0.0])
        v[0] += comb
        v[1] += seq
    print(f"{os.path.basename(d.rstrip('/'))} total_um2 {total:.0f} regs {kv(os.path.join(d, 'summary.txt'), 'regs')} "
          f"dc_wns {kv(os.path.join(d, 'summary.txt'), 'setup_wns_ns')} | " +
          " | ".join(f"{c} wns {kv(os.path.join(d, f'pt_{c}.txt'), 'wns_ns')} fmax "
                     f"{kv(os.path.join(d, f'pt_{c}.txt'), 'fmax_mhz')}" for c in ("tt", "ss")))
    s = 0.0
    for k, (c, q) in grp.items():
        s += c + q
        print(f"GROUP {k:<56} total_um2 {c + q:11.1f} comb {c:11.1f} seq {q:11.1f} pct {100 * (c + q) / total:5.1f}")
    print(f"CHECK sum_of_groups {s:.1f} total {total:.1f}")
    for c in ("tt", "ss"):
        p = os.path.join(d, f"pt_{c}.txt")
        if os.path.exists(p):
            m = re.search(r"path (\S+) -> (\S+)", open(p).read())
            if m:
                print(f"CRIT {c} {m.group(1)} -> {m.group(2)}")


if __name__ == "__main__":
    main()
