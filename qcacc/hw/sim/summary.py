"""Summary of a QC-GeMMX chimera RTL run (qcacc/hw/sim/run_rtl_qc.sh), also for -DNN_STOP_AFTER runs.

    python3 -m qcacc.hw.sim.summary build/qcacc/rtl/<tag> [--qparams S2]

Reads result.json (nn_result from the memory island), gen/nn_net.c (step names) and run.log.
Prints per executed step of image 0: cycles, GeMMX / streamer busy counters, array fires (K*M*N of
the call) and fires / busy, then the per-conv sums.  Exit 0 iff the run reached its end (or its
NN_STOP_AFTER marker) with 0 checksum / byte errors (and bit-exact logits for a full run).
"""
import argparse
import json
import re
from pathlib import Path

S2 = "/tmp/root/qc/final/int8/s2.pt"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--qparams", default=S2)
    a = ap.parse_args()
    d = Path(a.run)
    r = json.loads((d / "result.json").read_text())
    net = (d / "gen/nn_net.c").read_text()
    names = re.search(r"nn_step_names\[NN_N_STEPS\] = \{(.*?)\};", net).group(1).replace('"', "").split(", ")
    log = (d / "run.log").read_text(errors="replace")
    end = re.search(r"NN_SIM_END (\d+)", log)

    import torch
    from qcacc.compile.lower import QCProgram
    prog = QCProgram(torch.load(a.qparams, weights_only=False), "qc")
    fires = {st.name: st.cfg["K"] * st.cfg["M"] * st.cfg["N"] for st in prog.steps if st.kind == "conv"}

    marker = r["marker"]
    stop = (marker >> 16) == 0xDEAD
    last = (marker & 0xFFFF) if stop else len(names) - 1
    full = marker == 0xC0FFEE00
    ok = r["errors"] == 0 and (stop or full) and not any(r["full_err"])
    if full:
        exp = re.search(r"nn_expect_logits[^=]*=\s*\{\s*\{([-\d, ]+)\}", net)
        ok &= exp is not None and [int(v) for v in exp.group(1).split(",")] == r["logits"][0]
    print(f"run {d.name}: marker 0x{marker:08x} ({'stopped after ' + names[last] if stop else 'complete' if full else 'NOT FINISHED'}), "
          f"errors {r['errors']}, NN_FULL_CHECK bad bytes {sum(r['full_err'])}, sim end "
          f"{int(end.group(1)) / 1e9 if end else -1:.3f} ms -> {'BIT-EXACT' if ok else 'FAIL'}")
    print("step         cycles  gemm_busy  streamer   fires  fires/busy")
    per = {}
    for s in range(last + 1):
        n = names[s]
        g, st, c = r["gemmx_perf"][s], r["streamer_perf"][s], r["cycles"][0][s]
        line = f"  {n:10s} {c:7d}"
        if n in fires:
            line += f"  {g:9d} {st:9d} {fires[n]:7d}  {100 * fires[n] / g if g else 0:5.1f} %"
            p = per.setdefault(n.split("_g")[0], [0, 0, 0, 0])
            for i, v in enumerate((c, g, st, fires[n])):
                p[i] += v
        print(line)
    print("per conv (sum of its group calls):  cycles  gemm_busy  streamer  fires")
    for n, (c, g, st, f) in per.items():
        print(f"  {n:6s} {c:8d} {g:9d} {st:9d} {f:6d}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
