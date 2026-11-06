#!/usr/bin/env python3
"""Summary of a gate-level ResNet-8 layer run (nn/gls/run_gls.sh), optionally against the RTL run of the same ELF.

    summary.py <gls dir> <step> [--rtl <rtl dir>]

<gls dir>: run.log (GEMMX_PROBE busy edges / counters, GLS_XCHECK, NN_SAIF_*), result.json (nn_result),
check.txt (tcdm_check.py byte compare of the step output).  <rtl dir>: nn/sim/run_rtl.sh output of the same
build flags (run.log NN_PROBE edges, result.json).  Exit 0 iff core 0 stopped after the step with no checksum
mismatch, every byte of the step output matches the reference, no X reached the AXI handshakes, and (with
--rtl) every step's cycle count and the GeMMX counters equal RTL.
"""
import json
import re
import sys
from pathlib import Path


def edges(log, tag):
    """[(value, time_ps)] of the gemm_busy probe ('GEMMX_PROBE' gate level, 'NN_PROBE' RTL)."""
    return [(v, int(t)) for v, t in re.findall(rf"{tag} gemm_busy (\S+) (\d+)", log)]


def windows(e):
    """busy windows [(rise, fall)] from the edge list (values '1' / '0')."""
    w, rise = [], None
    for v, t in e:
        if v == "1":
            rise = t
        elif v == "0" and rise is not None:
            w.append((rise, t))
            rise = None
    return w


def main():
    d, step = Path(sys.argv[1]), sys.argv[2]
    rtl = Path(sys.argv[sys.argv.index("--rtl") + 1]) if "--rtl" in sys.argv else None
    log = (d / "run.log").read_text(errors="replace")
    r = json.loads((d / "result.json").read_text())
    names = re.search(r"nn_step_names\[NN_N_STEPS\] = \{(.*?)\};",
                      (d / "gen/nn_net.c").read_text()).group(1).replace('"', "").split(", ")
    idx = names.index(step)
    ok = True

    def check(cond, msg):
        nonlocal ok
        ok &= bool(cond)
        print(f"  {'ok  ' if cond else 'FAIL'} {msg}")

    print(f"gate-level run {d.name}: step {step} (index {idx})")
    m = re.search(r"NN_SIM_END (\d+) wall (\d+)", log)
    clk = [int(t) for t in re.findall(r"GEMMX_PROBE clk_edge 1 (\d+)", log)]
    per = clk[1] - clk[0] if len(clk) == 2 else None
    print(f"  sim end {int(m.group(1)) / 1e6:.1f} us, wall {int(m.group(2)) / 60:.1f} min, cluster clock {per} ps"
          if m else "  no NN_SIM_END (run did not finish)")
    check(r["marker"] == 0xDEAD0000 | idx, f"core 0 stopped after {step} (marker 0x{r['marker']:08x})")
    check(r["errors"] == 0 and r["first_bad"] == 0xFFFFFFFF,
          f"step checksums vs PyTorch int8 reference: {r['errors']} mismatches")
    c = (d / "check.txt").read_text()
    b = re.search(rf"^{step}: .*?(\d+) of (\d+) interior bytes wrong \((\d+) X\)", c, re.M)
    check(b and b.group(1) == "0" and b.group(3) == "0",
          f"{step} output byte compare (TCDM dump): " + (f"{b.group(1)} of {b.group(2)} wrong, {b.group(3)} X" if b else "missing"))
    x = re.search(r"GLS_XCHECK cycles_checked (\d+) x_errors (\d+)", log)
    check(x and x.group(2) == "0", f"AXI X-check: {x.group(1)} cycles, {x.group(2)} X" if x else "AXI X-check missing")
    qe = re.search(r"Errors: (\d+), Warnings", log)
    check(qe and qe.group(1) == "0", f"Questa errors (incl. timing checks): {qe.group(1) if qe else '?'}")
    check(not re.search(r"GEMMX_PROBE gemm_busy [xXzZ]", log), "no X on the GeMMX busy nets")
    sa = re.findall(r"NN_SAIF_(ON|OFF) (?:call|win) (\d+) (\d+)", log)
    if len(sa) == 2:
        t0, t1 = int(sa[0][2]), int(sa[1][2])
        what = f"GeMMX call {sa[0][1]}" if sa[0][1] != "0" else "fixed"
        print(f"  SAIF window ({what}): {t0 / 1e6:.3f} .. {t1 / 1e6:.3f} us"
              + (f" = {(t1 - t0) / per:.0f} cycles" if per else ""))
    cyc = r["cycles"][0][:idx + 1]
    print("  step cycles (mcycle):   " + "  ".join(f"{n} {v}" for n, v in zip(names, cyc)))
    print("  GeMMX / streamer counters: " + "  ".join(f"{n} {g}/{s}" for n, g, s in
          zip(names, r["gemmx_perf"][:idx + 1], r["streamer_perf"][:idx + 1]) if n.startswith("conv")))
    gw = windows(edges(log, "GEMMX_PROBE"))
    if rtl:
        rr = json.loads((rtl / "result.json").read_text())
        rw = windows(edges((rtl / "run.log").read_text(errors="replace"), "NN_PROBE"))
        same = cyc == rr["cycles"][0][:idx + 1]
        check(same, "step cycles = RTL" + ("" if same else f" (RTL {rr['cycles'][0][:idx + 1]})"))
        same = (r["gemmx_perf"][:idx + 1], r["streamer_perf"][:idx + 1]) == (rr["gemmx_perf"][:idx + 1], rr["streamer_perf"][:idx + 1])
        check(same, "GeMMX / streamer busy counters = RTL")
        for k, (g, q) in enumerate(zip(gw, rw)):
            dg, dq = g[1] - g[0], q[1] - q[0]
            print(f"  GeMM busy window {k + 1}: GLS {g[0] / 1e6:.3f} .. {g[1] / 1e6:.3f} us ({dg} ps), "
                  f"RTL {q[0] / 1e6:.3f} .. {q[1] / 1e6:.3f} us ({dq} ps)" + ("  identical" if g == q else ""))
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
