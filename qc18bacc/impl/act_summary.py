#!/usr/bin/env python3
"""Area of a qb_act synthesis by group, split into combinational / sequential (numbers only, safe to copy off the server):
    python3 -I qc18bacc/impl/act_summary.py <syn_run_dir>
Reads <run>/summary.txt, rpt/area.rpt (report_area -hierarchy -nosplit), pt_tt.txt / pt_ss.txt.
Groups: line buffer u_lb (8 x 2048 flops + shift / write muxes), S1 chunk select u_s1 (regs + dynamic chunk mux),
S2 patch network u_s2 (act regs + static cfg mux), act output pipe (g_pipe*/u_ap), skip detect u_flg (group ORs +
flags), control (rest: loader, map input register rdq, sequencer, descriptor pipe).
"""
import os
import re
import sys


def kv(path, key):
    if not os.path.exists(path):
        return None
    m = re.search(key + r"\s+(\S+)", open(path).read())
    return m.group(1) if m else None


GROUPS = (("u_lb", "line buffer (8 x 2048 b, shift / write mux)"), ("u_s1", "S1 chunk slice (regs + chunk mux)"),
          ("u_s2", "S2 patch network (act regs + cfg mux)"), ("u_ap", "act output pipe (ACT_PIPE regs)"),
          ("u_flg", "skip detect (group ORs + flags)"))


def main():
    d = sys.argv[1]
    rows = []
    for ln in open(os.path.join(d, "rpt", "area.rpt")):
        f = ln.split()
        if len(f) >= 6 and re.match(r"^[0-9.]+$", f[1]) and re.match(r"^[0-9.]+$", f[3]):
            rows.append((f[0], float(f[1]), float(f[3]), float(f[4])))
    total, tcomb, tseq = rows[0][1], rows[0][2], rows[0][3]
    grp = {}
    for name, a, comb, seq in rows[1:]:
        parts = name.split("/")
        last = parts[-1] if len(parts) <= 2 else None
        if last is None or (len(parts) == 2 and not parts[0].startswith("g_pipe")):
            continue
        for key, g in GROUPS:
            if last == key or last.endswith(key):
                v = grp.setdefault(g, [0.0, 0.0, 0.0])
                v[0] += a
                v[1] += comb
                v[2] += seq
    s = [sum(v[i] for v in grp.values()) for i in range(3)]
    # area.rpt comb / noncomb columns are local (not inclusive): the top row's are the control logic's
    grp["control (loader, rdq, sequencer, descriptors)"] = [total - s[0], tcomb, tseq]
    print(f"{os.path.basename(d.rstrip('/'))} total_um2 {total:.0f} regs {kv(os.path.join(d, 'summary.txt'), 'regs')} "
          f"dc_wns {kv(os.path.join(d, 'summary.txt'), 'setup_wns_ns')} | " +
          " | ".join(f"{c} wns {kv(os.path.join(d, f'pt_{c}.txt'), 'wns_ns')} fmax "
                     f"{kv(os.path.join(d, f'pt_{c}.txt'), 'fmax_mhz')}" for c in ("tt", "ss")))
    for k, (a, c, q) in grp.items():
        print(f"GROUP {k:<48} total_um2 {a:11.1f} comb {c:11.1f} seq {q:11.1f} pct {100 * a / total:5.1f}")
    for c in ("tt", "ss"):
        p = os.path.join(d, f"pt_{c}.txt")
        if os.path.exists(p):
            m = re.search(r"path (\S+) -> (\S+)", open(p).read())
            if m:
                print(f"CRIT {c} {m.group(1)} -> {m.group(2)}")


if __name__ == "__main__":
    main()
