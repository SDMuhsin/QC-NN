#!/usr/bin/env python3
"""One line per DC / PT run of the qc18bacc microblocks (numbers only, safe to copy off the server).
  python3 -I qc18bacc/impl/summarize.py <syn_run_dir> [...]
Reads <run>/summary.txt (DC), rpt/area.rpt (report_area -hierarchy), pt_tt.txt / pt_ss.txt (pt_hook fmax line).
PE tops: area split by instance: u_in (S0 input regs), u_pop (rotate/xor/popcount + u, nneg regs), u_acc (sum,
shift, add/sub + acc + shadow regs + ICGs; comb / seq given), rest = u_pe local (control pipeline).
"""
import os
import re
import sys


def area_rows(path):
    rows = {}
    for ln in open(path):
        f = ln.split()
        if len(f) >= 7 and re.match(r"^[0-9.]+$", f[1]) and re.match(r"^[0-9.]+$", f[3]):
            rows[f[0]] = (float(f[1]), float(f[3]), float(f[4]))   # total, local comb, local seq
    return rows


def kv(path, key):
    if not os.path.exists(path):
        return None
    m = re.search(key + r"\s+(\S+)", open(path).read())
    return m.group(1) if m else None


def main():
    for d in sys.argv[1:]:
        tag = os.path.basename(d.rstrip("/"))
        s = os.path.join(d, "summary.txt")
        area = float(kv(s, "cell_area_um2") or "nan")
        regs = kv(s, "regs")
        dcw = kv(s, "setup_wns_ns")
        fm = {c: kv(os.path.join(d, "pt_%s.txt" % c), "fmax_mhz") for c in ("tt", "ss")}
        ws = {c: kv(os.path.join(d, "pt_%s.txt" % c), "wns_ns") for c in ("tt", "ss")}
        line = "%s area_um2 %.0f regs %s dc_wns %s | tt wns %s fmax %s | ss wns %s fmax %s" % (
            tag, area, regs, dcw, ws["tt"], fm["tt"], ws["ss"], fm["ss"])
        ap = os.path.join(d, "rpt", "area.rpt")
        r = area_rows(ap) if os.path.exists(ap) else {}
        if "u_pe/u_pop" in r:
            ui, up, ua = r["u_pe/u_in"][0], r["u_pe/u_pop"][0], r["u_pe/u_acc"]
            acc_seq = sum(v[2] for k, v in r.items() if k.startswith("u_pe/u_acc"))
            line += " | in %.0f pop %.0f acc %.0f (comb %.0f seq %.0f) ctl %.0f" % (
                ui, up, ua[0], ua[1], acc_seq, area - ui - up - ua[0])
        print(line)


if __name__ == "__main__":
    main()
