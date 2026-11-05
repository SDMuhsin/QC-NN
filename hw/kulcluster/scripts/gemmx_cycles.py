#!/usr/bin/env python3
"""Cycle breakdown of the SNAX GeMMX GeMM, in-chimera vs standalone.

In-chimera inputs (hw/kulcluster/sim/chimera_vsim.sh run):
  run.log   Questa transcript with the GEMMX_PROBE lines of sim/gemmx_probe.tcl
            (busy/handshake edges of the GeMM core, SIMD and streamer + their counters)
  trace     core-0 (hart 7) Snitch trace logs/trace_chip_00_hart_00007.dasm
  elf       host ELF (for the address of kul_result[], written by sw/chimera_gemmx/kul_gemm.c)
Standalone input (hw/kulcluster/run_standalone.sh): the GEMMX_PERF line printed by
  sw/standalone_gemmx_perf/gemmx_perf.c on the SNAX Verilator TB.

All numbers are cluster clock cycles.
  ideal   = M*N*K  (one 8x8x8 int8 block product per cycle on the 8x8x8 MAC array)
  util    = ideal / busy
"""
import argparse
import re
import shutil
import subprocess
from collections import defaultdict

KUL_RESULT = ["marker", "err", "window", "copy", "perf_gemmx", "perf_streamer",
              "setup_streamer", "setup_gemmx"]
FIELD = re.compile(r"'(\w+)': (0x[0-9a-f]+)")


def nm_addr(elf, sym):
    nm = shutil.which("llvm-nm") or shutil.which("nm")
    for line in subprocess.run([nm, elf], capture_output=True, text=True).stdout.splitlines():
        p = line.split()
        if len(p) == 3 and p[2] == sym:
            return int(p[0], 16)
    raise SystemExit(f"{sym} not found in {elf}")


def parse_trace(path, kul_base):
    """kul_result[] stores (address/data from the store's trace line) and the retire cycle of
    the GeMMX/streamer start CSR writes (to align the hardware probe edges with the core)."""
    res, marks, mcycle = {}, {}, []
    with open(path) as f:
        for line in f:
            p = line.split(None, 4)
            if len(p) < 5 or not p[3].startswith("0x"):
                continue
            t, cyc = int(p[0]), int(p[1])
            d = dict(FIELD.findall(p[4]))
            if d.get("stall") == "0x1":
                continue
            if d.get("is_store") == "0x1":
                a = int(d["alu_result"], 16)
                if kul_base <= a < kul_base + 4 * len(KUL_RESULT):
                    res[KUL_RESULT[(a - kul_base) // 4]] = int(d["gpr_rdata_1"], 16)
            m = re.search(r"DASM\(([0-9a-f]+)\)", p[4])
            if m and int(m.group(1), 16) & 0x7F == 0x73:
                ins = int(m.group(1), 16)
                csr, f3, imm = ins >> 20, (ins >> 12) & 7, (ins >> 15) & 31
                if f3 == 5 and imm == 1 and csr in (0x3FE, 0x413):   # csrwi <start>, 1
                    marks["streamer_start_csr" if csr == 0x3FE else "gemmx_start_csr"] = (t, cyc)
                if f3 == 2 and imm == 0 and csr == 0xB00:            # csrr rd, mcycle
                    mcycle.append((t, cyc))
                if f3 == 2 and imm == 0 and csr in (0x414, 0x3FF):  # busy polls (gemmx, streamer)
                    k = "first_gemmx_busy_poll" if csr == 0x414 else "first_streamer_busy_poll"
                    marks.setdefault(k, (t, cyc))
    if len(mcycle) >= 2:     # last two mcycle reads of kul_gemm = t2 / t3 (sw window)
        marks["t2 window start"], marks["t3 window end"] = mcycle[-2], mcycle[-1]
    return res, marks


def parse_probe(path):
    ev, ctr = defaultdict(dict), {}
    with open(path, errors="replace") as f:
        for line in f:
            m = re.search(r"GEMMX_PROBE (\w+)\s+(\S+) (\S+)", line)
            if not m:
                continue
            name, val, t = m.groups()
            if t == "end":
                ctr[name] = int(val)
            else:
                ev[name][int(t)] = int(val)          # last value per timestamp (no delta glitches)
    return {k: sorted(v.items()) for k, v in ev.items()}, ctr


def high_intervals(edges):
    out, start, prev = [], None, 0
    for t, v in edges:
        if v and not prev:
            start = t
        elif prev and not v and start is not None:
            out.append((start, t))
        prev = v
    return out


def chimera(a):
    ev, ctr = parse_probe(a.run_log)
    res, marks = parse_trace(a.trace, nm_addr(a.elf, "kul_result"))
    clk = [t for t, _ in ev.get("clk_edge", [])]
    period = clk[1] - clk[0] if len(clk) >= 2 else None
    out = {"sw": res, "ctr": ctr, "period_ps": period}
    if period:
        iv = {k: high_intervals(ev.get(k, [])) for k in
              ("gemm_busy", "simd_busy", "str_busy", "ab_fire", "addc_fire")}
        cyc = lambda dt: round(dt / period)
        out["busy"] = {k: sum(cyc(e - s) for s, e in v) for k, v in iv.items()}
        t_ref = marks.get("t2 window start", (None,))[0]
        out["span"] = {k: (cyc(v[0][0] - t_ref), cyc(v[-1][1] - t_ref)) for k, v in iv.items()
                       if v and t_ref is not None}
        out["marks"] = {k: cyc(t - t_ref) for k, (t, _) in marks.items()} if t_ref else {}
    return out


def standalone(path):
    with open(path) as f:
        for line in f:
            m = re.search(r"GEMMX_PERF (.*)", line)
            if m:
                return {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", m.group(1))}
    raise SystemExit(f"no GEMMX_PERF line in {path}")


def report(a):
    ideal = a.M * a.N * a.K
    L = [f"GeMMX int8 GeMM {8*a.M}x{8*a.K} x {8*a.K}x{8*a.N} (+C, SIMD rescale to int8), "
         f"KUL SNAX cluster, 8x8x8 MAC array",
         f"ideal = M*N*K = {a.M}*{a.N}*{a.K} = {ideal} cycles "
         f"({8*a.M*8*a.K*8*a.N} MACs / 512 MAC/cycle)", ""]
    ch = chimera(a) if a.run_log else None
    sa = standalone(a.standalone) if a.standalone else None
    row = lambda name, c, s, note="": L.append(
        f"  {name:<44}{'' if c is None else c:>12}{'' if s is None else s:>12}  {note}")
    L.append(f"  {'[cluster clock cycles]':<44}{'in-chimera':>12}{'standalone':>12}")
    sw = ch["sw"] if ch else {}
    sa = sa or {}
    if ch and ch.get("busy"):
        b = ch["busy"]
        row("GeMM core busy (BlockGemm sBUSY, probe)", b["gemm_busy"], None)
        row("  of which MAC-array A/B fires", b["ab_fire"], None, f"(ideal {ideal})")
        row("  of which add-C fires", b["addc_fire"], None, f"(= M*N = {a.M*a.N})")
        tail = b["simd_busy"] - b["gemm_busy"]
        est = sa.get("perf_gemmx") - tail if sa.get("perf_gemmx") else None
        row("SIMD busy (probe)", b["simd_busy"], None)
        row("GeMM core busy, est. = GeMMX ctr - SIMD tail", None, est,
            f"(standalone: no probes in Verilator; SIMD tail {tail} from chimera)")
        row("streamer busy (probe)", b["str_busy"], None)
    row("GeMM core counter  (BlockGemm perf ctr)", ch["ctr"].get("ctr_gemm") if ch else None, None)
    row("GeMMX counter      (CSR GEMMX_PERF = SIMD)", sw.get("perf_gemmx"), sa.get("perf_gemmx"))
    row("streamer counter   (CSR STREAMER_PERF)", sw.get("perf_streamer"), sa.get("perf_streamer"))
    row("sw window start CSR .. busy polls done", sw.get("window"), sa.get("window"))
    row("CSR setup: streamer", sw.get("setup_streamer"), sa.get("setup_streamer"))
    row("CSR setup: GeMMX", sw.get("setup_gemmx"), sa.get("setup_gemmx"))
    row("copy-in A,B,C -> TCDM", sw.get("copy"), sa.get("copy"),
        "(chimera: core 0 byte loop from mem island; standalone: DMA)")
    L.append("")
    gemm = ch["busy"]["gemm_busy"] if ch and ch.get("busy") else None
    gemm_sa = (sa.get("perf_gemmx") - ch["busy"]["simd_busy"] + gemm) if gemm and sa else None
    for name, c, s in (("GeMMX (SIMD-stage) counter", sw.get("perf_gemmx"), sa.get("perf_gemmx")),
                       ("streamer counter", sw.get("perf_streamer"), sa.get("perf_streamer")),
                       ("GeMM core busy (sa: est.)", gemm, gemm_sa),
                       ("sw window", sw.get("window"), sa.get("window"))):
        f = lambda x: f"{100*ideal/x:.1f}%" if x else "-"
        L.append(f"  MAC utilisation = ideal / {name:<30} in-chimera {f(c):>6}   "
                 f"standalone {f(s):>6}")
    if ch and ch.get("span"):
        L.append("")
        L.append("  in-chimera timeline, cycles after t2 (mcycle read opening the sw window):")
        for k, v in sorted(ch["marks"].items(), key=lambda x: x[1]):
            L.append(f"    {k:<26} retires at {v:>5}")
        for k, (s, e) in ch["span"].items():
            L.append(f"    {k:<26} high       {s:>5} .. {e:>5}")
        L.append(f"    (clock period {ch['period_ps']} ps; core-0 trace time aligned to the probes)")
    if sw:
        L.append(f"  in-chimera self-check: marker={sw.get('marker', 0):#x} mismatches={sw.get('err')}")
    txt = "\n".join(L) + "\n"
    print(txt, end="")
    if a.out:
        with open(a.out, "w") as f:
            f.write(txt)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run-log"), ap.add_argument("--trace"), ap.add_argument("--elf")
    ap.add_argument("--standalone", help="log with the GEMMX_PERF line")
    ap.add_argument("-M", type=int, default=1), ap.add_argument("-K", type=int, default=18)
    ap.add_argument("-N", type=int, default=2)
    ap.add_argument("-o", "--out")
    report(ap.parse_args())
