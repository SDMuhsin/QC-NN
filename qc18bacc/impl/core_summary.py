#!/usr/bin/env python3
"""Area of a qb_core synthesis by group (numbers only, safe to copy off the server):
    python3 -I qc18bacc/impl/core_summary.py <syn_run_dir>
Reads <run>/summary.txt, rpt/area.rpt (report_area -hierarchy -nosplit), pt_tt.txt / pt_ss.txt.
Groups (instances directly under the top): PEs (u_pe; split into S0 input regs u_in, popcount u_pop, accumulators u_acc,
comparators u_cmp, shadow / drain u_shd, PE-local control), column decoders (u_dec: 36 qbc_dec + NNw), broadcast
registers (u_br), fused lanes (u_lf), wide lanes (u_lw), parameter banks (u_pbf, u_pbw), top glue (rest).
"""
import os
import re
import sys


def kv(path, key):
    if not os.path.exists(path):
        return None
    m = re.search(key + r"\s+(\S+)", open(path).read())
    return m.group(1) if m else None


def main():
    d = sys.argv[1]
    rows = []
    for ln in open(os.path.join(d, "rpt", "area.rpt")):
        f = ln.split()
        if len(f) >= 6 and re.match(r"^[0-9.]+$", f[1]) and re.match(r"^[0-9.]+$", f[3]):
            rows.append((f[0], float(f[1]), float(f[3]), float(f[4])))
    if len(rows) > 1 and rows[1][0] == "u_core":                     # wrapper top (qb_core_s): strip u_core/
        rows = [rows[0]] + [(n[len("u_core/"):], a, c, q) for n, a, c, q in rows[2:]]
    top = rows[0]
    total = top[1]
    grp = {}

    def add(k, a, n=1):
        g = grp.setdefault(k, [0.0, 0])
        g[0] += a
        g[1] += n

    depth1 = 0.0
    for name, a, comb, seq in rows[1:]:
        parts = name.split("/")
        last = parts[-1]
        if len(parts) == 1:
            depth1 += a
            for key, g in (("u_pe", "PE (total)"), ("u_dec", "decoders (36 / column + NNw)"),
                           ("u_br", "broadcast regs (per 8-row group x column)"), ("u_lf", "fused lanes qb_lane_fn"),
                           ("u_lw", "wide lanes qbcw_lane"), ("u_pbf", "fused param bank P0 / P1"),
                           ("u_pbw", "wide param bank (rotating)")):
                if last.endswith(key):
                    add(g, a)
                    break
            else:
                add("other instance " + last, a)
        elif len(parts) == 2 and parts[0].endswith("u_pe"):
            sub = dict(u_in="PE S0 input regs", u_pop="PE popcount + s regs", u_acc="PE accumulators",
                       u_cmp="PE b2 comparators (8 / PE)", u_shd="PE shadow / drain").get(last)
            if sub:
                add("  " + sub, a)
    pe = grp.get("PE (total)", [0, 0])
    subs = sum(v[0] for k, v in grp.items() if k.startswith("  "))
    add("  PE control pipeline (rest)", pe[0] - subs, pe[1])
    add("top glue (PPU ctl regs, lane input muxes)", total - depth1)
    print(f"{os.path.basename(d.rstrip('/'))} total_um2 {total:.0f} regs {kv(os.path.join(d, 'summary.txt'), 'regs')} "
          f"dc_wns {kv(os.path.join(d, 'summary.txt'), 'setup_wns_ns')} | " +
          " | ".join(f"{c} wns {kv(os.path.join(d, f'pt_{c}.txt'), 'wns_ns')} fmax "
                     f"{kv(os.path.join(d, f'pt_{c}.txt'), 'fmax_mhz')}" for c in ("tt", "ss")))
    order = ["PE (total)"] + sorted(k for k in grp if k.startswith("  ")) + \
            [k for k in grp if k != "PE (total)" and not k.startswith("  ")]
    for k in order:
        a, n = grp[k]
        print(f"GROUP {k:<45} n {n:>4} total_um2 {a:12.1f} each_um2 {a / max(n, 1):9.1f} pct {100 * a / total:5.1f}")
    for c in ("tt", "ss"):
        p = os.path.join(d, f"pt_{c}.txt")
        if os.path.exists(p):
            m = re.search(r"path (\S+) -> (\S+)", open(p).read())
            if m:
                print(f"CRIT {c} {m.group(1)} -> {m.group(2)}")


if __name__ == "__main__":
    main()
