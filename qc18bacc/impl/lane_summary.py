#!/usr/bin/env python3
"""One line per qb_lane variant run (numbers only, safe to copy off the server):
  python3 -I qc18bacc/impl/lane_summary.py <syn_run_dir> [...]
summarize.py line + the report_area -hierarchy rows of u_lane's children (total area per instance, local comb / seq)."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from summarize import area_rows, kv   # noqa: E402


def main():
    for d in sys.argv[1:]:
        tag = os.path.basename(d.rstrip("/"))
        s = os.path.join(d, "summary.txt")
        fm = {c: kv(os.path.join(d, "pt_%s.txt" % c), "fmax_mhz") for c in ("tt", "ss")}
        line = "%s area %.1f regs %s dc_wns %s fmax_tt %s fmax_ss %s" % (
            tag, float(kv(s, "cell_area_um2") or "nan"), kv(s, "regs"), kv(s, "setup_wns_ns"), fm["tt"], fm["ss"])
        r = area_rows(os.path.join(d, "rpt", "area.rpt"))
        if "u_lane" in r:
            line += " | u_lane local comb %.1f seq %.1f" % r["u_lane"][1:]
        line += " | " + " ".join("%s=%.1f" % (k[len("u_lane/"):], v[0]) for k, v in r.items()
                                 if k.startswith("u_lane/") and k.count("/") == 1)
        log = os.path.join(d, "dc.log")
        if os.path.exists(log):
            hk = [ln.strip() for ln in open(log) if ln.startswith("QBS_HOOK")]
            if hk:
                line += " | " + "; ".join(hk)
        print(line)


if __name__ == "__main__":
    main()
