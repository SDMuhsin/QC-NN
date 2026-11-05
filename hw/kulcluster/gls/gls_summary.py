#!/usr/bin/env python3
"""Summary of a gate-level chimera run (gls.sh summary): PASS/FAIL of the self-checking GeMM
test, accelerator busy cycles from the GEMMX_PROBE edges and counters, compared to the RTL run
(results/gemmx_cycles.txt), and the X / error checks.

  gls_summary.py --mode zd|sdf --run-log run.log [--rtl results/gemmx_cycles.txt]
"""
import argparse
import re

ap = argparse.ArgumentParser()
ap.add_argument("--mode", required=True)
ap.add_argument("--run-log", required=True)
ap.add_argument("--rtl")
a = ap.parse_args()
log = open(a.run_log, errors="replace").read()

edges, ctr, clk = {}, {}, []
for m in re.finditer(r"GEMMX_PROBE (\w+)\s+(\S+) (\S+)", log):
    name, val, t = m.groups()
    if t == "end":
        ctr[name] = val
    elif name == "clk_edge":
        clk.append(int(t))
    else:
        edges.setdefault(name, []).append((val, int(t)))

period = clk[1] - clk[0] if len(clk) >= 2 else 2000
xs = [f"{n}={v}@{t}" for n, ev in edges.items() for v, t in ev if not re.fullmatch(r"[01]+", v)]


def busy(name):
    """cycles between the first 0->1 and the following 1->0 of a busy net."""
    ev = edges.get(name, [])
    t1 = next((t for v, t in ev if v == "1"), None)
    t0 = next((t for v, t in ev if v == "0" and t1 is not None and t > t1), None)
    return None if t1 is None or t0 is None else (t0 - t1) / period, t1, t0


rtl = {}
if a.rtl:
    for line in open(a.rtl):
        for key, pat in [("gemm_busy", r"GeMM core busy \(BlockGemm sBUSY, probe\)\s+(\d+)"),
                         ("simd_busy", r"SIMD busy \(probe\)\s+(\d+)"),
                         ("str_busy", r"streamer busy \(probe\)\s+(\d+)"),
                         ("ctr_gemm", r"GeMM core counter.*?\)\s+(\d+)"),
                         ("ctr_simd", r"GeMMX counter.*?\)\s+(\d+)"),
                         ("ctr_stream", r"streamer counter.*?\)\s+(\d+)")]:
            m = re.search(pat, line)
            if m:
                rtl[key] = int(m.group(1))

jtag_ok = "[JTAG] SUCCESS" in log
m = re.findall(r"Errors: (\d+), Warnings: (\d+)", log)   # last = end of simulation
nerr = int(m[-1][0]) if m else -1
gls_x = re.findall(r"GLS_X [^\n]*", log)
xchk = re.search(r"GLS_XCHECK cycles_checked[^\n]*", log)
fatal = re.findall(r"\*\* (?:Fatal|Error)[^\n]*", log)
el = re.search(r"Elapsed time: ([\d:]+)", log)

rows, match = [], True
for key, label in [("gemm_busy", "GeMM core busy (BlockGemm io_busy_o)"),
                   ("simd_busy", "SIMD busy (io_busy_o)"),
                   ("str_busy", "streamer busy (cstate)")]:
    b = busy(key)
    v = None if b is None or b[0] is None else b[0]
    r = rtl.get(key)
    ok = v is not None and r is not None and round(v) == r
    match &= ok
    rows.append(f"  {label:<40} {('-' if v is None else f'{v:g}'):>6} {r if r is not None else '-':>6}  {'ok' if ok else 'DIFF'}")
for key, label in [("ctr_gemm", "GeMM core perf counter"), ("ctr_simd", "GeMMX (SIMD) perf counter"),
                   ("ctr_stream", "streamer perf counter")]:
    v, r = ctr.get(key), rtl.get(key)
    ok = v is not None and r is not None and v == str(r)
    match &= ok
    rows.append(f"  {label:<40} {v or '-':>6} {r if r is not None else '-':>6}  {'ok' if ok else 'DIFF'}")

xok = bool(xchk) and re.search(r"x_errors 0\b", xchk.group(0)) is not None
passed = jtag_ok and nerr == 0 and not gls_x and not xs and not fatal and xok
print(f"KUL cluster gate-level simulation in chimera ({a.mode}): {'PASS' if passed else 'FAIL'}"
      f", cycles {'match' if match else 'DIFFER from'} RTL")
print(f"  self-check (host exit code 0 = kernel ran, 0 mismatches vs golden D8): "
      f"{'JTAG SUCCESS' if jtag_ok else 'no JTAG SUCCESS'}")
print(f"  Questa errors {nerr}, X on probed busy nets {len(xs)}, GLS_X (AXI X-check) {len(gls_x)}"
      f", {xchk.group(0) if xchk else 'no GLS_XCHECK line'}")
print(f"  wall time {el.group(1) if el else '?'}, cluster clock period {period} ps")
print(f"  [cluster cycles]                         {'GLS':>6} {'RTL':>6}")
print("\n".join(rows))
for x in (xs + gls_x + fatal)[:10]:
    print("  !", x)
b = busy("gemm_busy")
if b and b[1] is not None:
    print(f"  GeMM busy {b[1]} .. {b[2]} ps")
