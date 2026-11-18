#!/usr/bin/env python3
"""R21: per-iteration DR summary from OpenROAD dr.log files (TritonRoute DRT-0195 / DRT-0199 / Viol/Layer tables / DRT-0267).
    python3 -I drlog.py <label>=<dr.log> [<label>=<dr.log> ...]
Per run and iteration: violations, elapsed, cumulative elapsed (h), shorts per layer M2..M7 and the M5 share of all shorts;
used for the M5 control (same netlist, GRT adjustment M5-M9 0.10 vs uniform 0.25)."""
import re, sys

def hms(s):
    h, m, x = (int(v) for v in s.split(":")); return h + m / 60.0 + x / 3600.0

for arg in sys.argv[1:]:
    lab, f = arg.split("=", 1)
    it = None; rows = []; cur = {}; tab = False; cum = 0.0
    for ln in open(f, errors="replace"):
        m = re.search(r"Start (\d+)(st|nd|rd|th) optimization iteration", ln)
        if m: it = int(m.group(1)); cur = {"it": it}; continue
        m = re.search(r"DRT-0199\]\s+Number of violations = (\d+)", ln)
        if m and it is not None: cur["viol"] = int(m.group(1)); continue
        if ln.startswith("Viol/Layer") and it is not None:
            tab = True; cur["layers"] = ln.split()[1:]; continue
        if tab:
            t = ln.split()
            if not t or not t[-1].isdigit(): tab = False
            elif t[0] == "Short":
                cur["short"] = dict(zip(cur["layers"], map(int, t[1:])))
        m = re.search(r"DRT-0267\] cpu time = \S+, elapsed time = (\d+:\d+:\d+)", ln)
        if m and it is not None and "viol" in cur and "el" not in cur:
            cur["el"] = hms(m.group(1)); cum += cur["el"]; cur["cum"] = cum; rows.append(cur); it = None
    print("# %s (%s)" % (lab, f))
    print("%-4s %9s %6s %6s | shorts %7s %7s %7s %7s %7s %7s | M5 share" % ("it", "viol", "h", "cum_h", "M2", "M3", "M4", "M5", "M6", "M7"))
    for r in rows:
        s = r.get("short", {}); tot = sum(s.values()) or 1
        print("%-4d %9d %6.2f %6.2f | shorts %7d %7d %7d %7d %7d %7d | %5.1f %%" % (r["it"], r["viol"], r["el"], r["cum"],
              s.get("M2", 0), s.get("M3", 0), s.get("M4", 0), s.get("M5", 0), s.get("M6", 0), s.get("M7", 0), 100.0 * s.get("M5", 0) / tot))
