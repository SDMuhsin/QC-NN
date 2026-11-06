#!/usr/bin/env python3
"""Layer energy from PrimeTime PX SAIF power (nn/gls/power.sh) of a gate-level ResNet-8 layer run.

    energy.py [--other <gls dir of a non-GeMMX window>] <gls dir> [<gls dir> ...]

Per run: power_<p>ns.txt (power groups, hierarchy, annotation), run.log (SAIF window = GeMM busy
edges), compile.txt (MACs of the layer).  Prints total / dynamic / leakage power, the GeMMX accelerator
(i_snax_core_0_acc_0_snax_streamer_gemmX = streamer + GeMM array + SIMD) vs the rest of the cluster, the
RF macros (power group "memory"), the energy of the layer window, pJ/MAC and TOPS/W (2 ops per MAC,
useful MACs of the layer), and an energy-per-image extrapolation with the RTL cycle counts:
  GeMMX part  = (layer energy / layer busy cycles) x GeMMX busy cycles of the whole image (all 9 convs)
  other part  = energy per cycle of a residual-add window (--other: dynamic energy per cycle, which does
                not depend on the clock, plus leakage at this clock) x all non-GeMMX cycles of the image
                (adds, pool+FC, DMA waits, border fills, CSR setup); without --other, the rest-of-cluster
                power of the layer window is used instead (an upper-bound proxy: the streamer keeps the
                TCDM macros busy).
"""
import re
import sys
from pathlib import Path

GEMMX = "i_snax_core_0_acc_0_snax_streamer_gemmX"
IMG_CYCLES, IMG_GEMMX_BUSY = 401698, 35580          # RTL, mean of 30 images (nn/results/rtl.md)


def fnum(s):
    return float(s)


def power(txt):
    t = txt.read_text()
    tot = {k: fnum(v) for k, v in re.findall(r"^\s*(Net Switching|Cell Internal|Cell Leakage|Total) Power\s*=\s*(\S+)", t, re.M)}
    mem = re.search(r"^memory\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", t, re.M)
    clk = re.search(r"^clock_network\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", t, re.M)
    hier = {}
    for m in re.finditer(r"^\s*(\S+)(?: \(\S+\))?\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$", t, re.M):
        try:
            hier[m.group(1)] = [fnum(m.group(i)) for i in range(2, 6)]     # internal, switching, leakage, total
        except ValueError:
            pass
    per = fnum(re.search(r"period_ns (\S+)", t).group(1))
    ann = re.search(r"^ Nets\s+\d+\((\S+)%\)", t, re.M)
    return dict(tot=tot, mem=[fnum(x) for x in mem.groups()], clk=[fnum(x) for x in clk.groups()],
                gx=hier[GEMMX], arr=hier["i_snax_streamer_gemmX_shell_wrapper"],
                stream=hier["i_snax_streamer_gemmX_streamer_wrapper"], clu=hier["i_cluster"], per=per, ann=ann.group(1) if ann else "?")


def main():
    args = sys.argv[1:]
    other = None
    if "--other" in args:
        i = args.index("--other")
        o = power(sorted(Path(args[i + 1]).glob("power_*ns.txt"))[0])
        other = ((o["tot"]["Net Switching"] + o["tot"]["Cell Internal"]) * o["per"] * 1e-9, o["tot"]["Cell Leakage"])
        del args[i:i + 2]
    for d in map(Path, args):
        log = (d / "run.log").read_text(errors="replace")
        on, off = (int(re.search(rf"NN_SAIF_{k} (?:call|win) \d+ (\d+)", log).group(1)) for k in ("ON", "OFF"))
        name = (d / "summary.txt").read_text().split("step ")[1].split()[0] if (d / "summary.txt").exists() else "conv1"
        comp = (d / "compile.txt").read_text()
        for f in sorted(d.glob("power_*ns.txt")):
            p = power(f)
            T = (off - on) * 1e-12                                     # s
            ncyc = round((off - on) / (p["per"] * 1000))
            fires = re.search(rf"^\s+{name}\s.*fires=(\d+)", comp, re.M)
            macs = 512 * int(fires.group(1)) if fires else None                        # 8x8x8 per fire
            tot, dyn = p["tot"]["Total"], p["tot"]["Net Switching"] + p["tot"]["Cell Internal"]
            leak = p["tot"]["Cell Leakage"]
            gx = p["gx"][3]
            E = tot * T
            print(f"{d.name}  {f.name}: clock {p['per']} ns ({1e3 / p['per']:.1f} MHz), window {T * 1e6:.3f} us = {ncyc} cycles, "
                  f"SAIF annotation {p['ann']} % of nets")
            print(f"  power total {tot * 1e3:.1f} mW = dynamic {dyn * 1e3:.1f} + leakage {leak * 1e3:.2f} mW")
            print(f"  GeMMX {gx * 1e3:.1f} mW ({100 * gx / tot:.1f} %), rest of cluster {(tot - gx) * 1e3:.1f} mW; "
                  f"RF macros {p['mem'][3] * 1e3:.1f} mW, clock network (ICGs) {p['clk'][3] * 1e3:.1f} mW")
            print(f"    GeMMX = GeMM array + SIMD {p['arr'][3] * 1e3:.1f} mW + streamer {p['stream'][3] * 1e3:.1f} mW; "
                  f"i_cluster (cores, TCDM + macros, interconnect, iDMA, icache) {p['clu'][3] * 1e3:.1f} mW")
            if macs is None:                                          # window without GeMMX work
                print(f"  energy per cycle {E / ncyc * 1e12:.1f} pJ (dynamic {dyn * p['per'] * 1e3:.1f} pJ)")
                continue
            print(f"  layer energy {E * 1e6:.2f} uJ (GeMMX {gx * T * 1e6:.2f} uJ) for {macs} MACs: "
                  f"{E / macs * 1e12:.2f} pJ/MAC cluster, {gx * T / macs * 1e12:.2f} pJ/MAC GeMMX; "
                  f"{2 * macs / E / 1e12:.3f} TOPS/W cluster, {2 * macs / (gx * T) / 1e12:.3f} TOPS/W GeMMX")
            e_gx = E / ncyc * IMG_GEMMX_BUSY
            if other:
                e_rest = (other[0] + other[1] * p["per"] * 1e-9) * (IMG_CYCLES - IMG_GEMMX_BUSY)
            else:
                e_rest = (tot - gx) * p["per"] * 1e-9 * (IMG_CYCLES - IMG_GEMMX_BUSY)
            print(f"  per image (extrapolated): {(e_gx + e_rest) * 1e6:.1f} uJ = convs {e_gx * 1e6:.1f} + other "
                  f"{e_rest * 1e6:.1f}; latency {IMG_CYCLES * p['per'] * 1e-6:.3f} ms")


if __name__ == "__main__":
    main()
