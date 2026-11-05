#!/usr/bin/env python3
"""Summary of one gls.sh run: verifier verdict, kernel cycles and a retire-by-retire comparison
of every hart's instruction stream (time, pc, insn from gls_trace.sv) against the RTL reference.

Kernel cycles use the definition of the upstream trace tools (util/trace/gen_trace.py): hart 0 is
split into regions at each `csrr mcycle`; region i spans mcycle reads i..i+1 and has
mcycle[i+1] - mcycle[i] - 1 cycles, the last one runs to hart 0's last traced instruction.
In mode rtl the monitor stream is first checked against the upstream tracer's own .dasm (core
instructions, i.e. source 0 and not stalled), which validates the monitor's retire rule.
"""
import argparse
import glob
import os
import re


def events(path):
    with open(path) as f:
        return [(int(t), int(pc, 16), int(i, 16)) for t, pc, i in (l.split() for l in f if l.strip())]


DASM = re.compile(r"^\s*(\d+)\s+\d+\s+\d+\s+0x([0-9a-f]+)\s+DASM\(([0-9a-f]+)\).*'source': 0x0, 'stall': 0x0,")


def dasm_events(path):
    out = []
    with open(path) as f:
        for l in f:
            m = DASM.match(l)
            if m:
                out.append((int(m[1]), int(m[2], 16), int(m[3], 16)))
    return out


def first_diff(a, b):
    for k, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return k
    return None if len(a) == len(b) else min(len(a), len(b))


def kernel_cycles(ev, regions, tck):
    reads = [t for t, _, i in ev if i & 0xfff0707f == 0xb0002073]   # csrr rd, mcycle
    bounds = reads + [ev[-1][0] + tck]   # last region: to the last instruction (inclusive)
    return sum((bounds[r] - bounds[r - 1]) // tck - 1 for r in regions if 1 <= r < len(bounds)), len(reads)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--mode", required=True)
    ap.add_argument("--run", required=True, help="local copy of the run (logs/, verify.log)")
    ap.add_argument("--rtl", required=True, help="RTL reference run (logs/gls_hart_*.txt of mode rtl)")
    ap.add_argument("--rtl-summary", required=True, help="sim/results/<kernel>_vsim_<cfg>.txt")
    ap.add_argument("--regions", required=True)
    ap.add_argument("--tck", type=int, default=1000)
    a = ap.parse_args()
    regions = [int(r) for r in a.regions.split(",")]

    vlog = open(os.path.join(a.run, "verify.log")).read()
    rc = re.search(r"GLS_RC (\d+)", vlog)
    rc = int(rc[1]) if rc else -1
    slog = open(os.path.join(a.run, "sim.log")).read()
    xline = re.search(r"GLS_TRACE retired .* x_errors (\d+)", slog)
    qerr = re.search(r"# Errors: (\d+), Warnings: (\d+)", slog)
    rtl_k = re.search(r"cycles\s*:\s*(\d+) kernel", open(a.rtl_summary).read())
    res = os.path.join(a.run, "results.csv")
    ncsv = sum(1 for _ in open(res)) - 1 if os.path.exists(res) else 0

    harts = sorted(glob.glob(os.path.join(a.run, "logs", "gls_hart_*.txt")))
    ev = {os.path.basename(h): events(h) for h in harts}
    h0 = ev["gls_hart_00000.txt"]
    k, nreads = kernel_cycles(h0, regions, a.tck)

    out = [f"[{a.kernel} / {a.mode}]"]
    out.append(f"  self-check (verifier exit {rc}, {ncsv} outputs compared): {'PASS' if rc == 0 else 'FAIL'}")
    out.append(f"  Questa errors {qerr[1] if qerr else '?'}, GLS_X (X check) {xline[1] if xline else '?'}")
    ok = rc == 0 and xline and xline[1] == "0" and qerr and qerr[1] == "0"
    out.append(f"  kernel cycles {k} (hart 0 regions {a.regions}, {nreads} mcycle reads); "
               f"RTL {rtl_k[1] if rtl_k else '?'}: {'match' if rtl_k and int(rtl_k[1]) == k else 'MISMATCH'}")
    ok = ok and rtl_k and int(rtl_k[1]) == k

    if a.mode == "rtl":   # monitor vs upstream tracer, same run
        for h, e in ev.items():
            d = dasm_events(os.path.join(a.run, "logs", h.replace("gls_hart_", "trace_hart_").replace(".txt", ".dasm")))
            k_ = first_diff(e, d)
            ok = ok and k_ is None
            if k_ is not None:
                out.append(f"  {h}: monitor != tracer at retire {k_}: {e[k_:k_+1]} vs {d[k_:k_+1]}")
        out.append(f"  retire monitor == upstream tracer (core instructions, all 9 harts): {'yes' if ok else 'NO'}")
    else:                 # every retire (time, pc, insn) vs the RTL run
        same = 0
        for h, e in ev.items():
            r = events(os.path.join(a.rtl, "logs", h))
            if a.tck != 1000 and e and r:   # slower clock (sdf): compare in cycles from the first retire
                e = [((t - e[0][0]) * 1000 // a.tck + r[0][0], pc, i) for t, pc, i in e]
            k_ = first_diff(e, r)
            same += k_ is None
            if k_ is not None:
                out.append(f"  {h}: differs from RTL at retire {k_} of {len(r)}: {e[k_:k_+1]} vs {r[k_:k_+1]}")
        ok = ok and same == len(ev)
        out.append(f"  harts with a retire stream (time, pc, insn) identical to RTL: {same}/{len(ev)} "
                   f"({sum(len(e) for e in ev.values())} retires)")
    wall = re.search(r"Elapsed time: ([\d:]+)", slog)
    out.append(f"  wall time {wall[1] if wall else '?'}, clock {a.tck} ps")
    out.append(f"  => {'PASS' if ok else 'FAIL'}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
