#!/usr/bin/env python3
"""conv1 power / energy and energy per image of dense baseline, s2 gemmx control and s2 QC (nn/gls/energy.py method).

    python3 -m qcacc.gls.energy_qc [--qc-tag T] [--ctl-tag T] [--dense-run D] [--clock ps]

Per design: the conv1 SAIF window(s) of the gate-level run (one per GeMMX call: QC 1, control 2, dense 1) through
PrimeTime PX (power_*.txt + the qcacc/gls/pt_blocks.tcl hierarchy, *_hook.txt), and the add1 zero-delay window
of the same netlist and software for the core work.  Inputs (local, build/qcacc/gls/<tag>/): run.log (NN_SAIF_ON /
OFF edges), power_<p>ns.txt, power_<p>ns_hook.txt (control conv1: two runs, _c3 / _c4, one per group call); the dense conv1 run.log from build/nn_gls/<dense run>.
  E_conv(layer) = (conv1 window energy / conv1 window cycles) x GeMMX busy cycles of that layer (RTL)
  E_other       = (add1 dynamic energy per cycle + leakage x period) x (image cycles - GeMMX busy cycles)
MACs: dense-equivalent array MACs (fires x 512; conv1 2 359 296, all convs 13.24 M incl. conv0 padding);
whole-image TOPS/W with the 12.50 M useful MACs (25.0 M ops) of nn/results/gls_power.md.
"""
import argparse
import re
from pathlib import Path

from nn.gls.energy import power

ROOT = Path(__file__).resolve().parents[2]
G = "i_snax_core_0_acc_0_snax_streamer_gemmX"
BG = G + "/i_snax_streamer_gemmX_shell_wrapper/inst_block_gemm_simd"
LAYERS = ["conv0", "conv1", "conv2", "conv3", "conv5", "conv4", "conv6", "conv8", "conv7"]
FIRES = dict(conv0=2304, conv1=4608, conv2=4608, conv3=2304, conv5=256, conv4=4608, conv6=2304, conv8=256, conv7=4608)
USEFUL_OPS = 2 * 12.50e6
# GeMMX busy cycles per layer and cycles per image, RTL at 2 ns (nn/results/rtl.md, qcacc/results/rtl.md)
BUSY = {
    "dense": [3050, 6162, 6180, 3231, 1036, 6242, 3084, 529, 6066],
    "gemmx": [3228, 5985, 6021, 3243, 1072, 6216, 3284, 639, 6329],
    "qc":    [2701, 5475, 5431, 2732, 1034, 5509, 2693, 525, 5592],
}
IMG = {"dense": 401698, "gemmx": 474310, "qc": 400346}
NAMES = {"dense": "dense baseline (nn/, kul_w4.2p)", "gemmx": "s2 gemmx control (kul_w4.2p)", "qc": "s2 QC (qc_w4.2)"}


def hook(f):
    h = {}
    for l in f.read_text().splitlines():
        p = l.split()
        if len(p) == 5 and not l.startswith("#"):
            h[p[0]] = float(p[4]) if p[4] != "NA" else 0.0
    s = lambda pat: sum(v for k, v in h.items() if re.fullmatch(pat, k))
    return dict(array=h.get(BG + "/gemm", 0.0), tiles=s(re.escape(BG) + r"/gemm/gemm_array/mesh/mesh_\d+_\d+"),
                bfly=s(re.escape(BG) + r"/gemm/gemm_array/mesh/rows_\d+"), dec=h.get(BG + "/gemm/gemm_array/mesh/decoder", 0.0),
                simd=h.get(BG + "/simd", 0.0), table=s(re.escape(BG) + r"/simd/table_\d+"),
                csr=h.get(G + "/i_snax_streamer_gemmX_csrman_wrapper", 0.0),
                stream=h.get(G + "/i_snax_streamer_gemmX_streamer_wrapper", 0.0), gx=h.get(G, 0.0))


def windows(log):
    on = {int(c): int(t) for c, t in re.findall(r"NN_SAIF_ON (?:call|win) (\d+) (\d+)", log)}
    off = {int(c): int(t) for c, t in re.findall(r"NN_SAIF_OFF (?:call|win) (\d+) (\d+)", log)}
    return {c: (on[c], off[c]) for c in on if c in off}


def measure(runs):
    """Sum over the SAIF windows [(power dir, run.log dir)] (one SAIF window per run): energy split (J), cycles."""
    acc = dict(E=0.0, dyn=0.0, leak=0.0, cyc=0, T=0.0)
    for pdir, logdir in runs:
        w = windows((logdir / "run.log").read_text(errors="replace"))
        t0, t1 = w[min(w)]                                   # the first window = the SAIF of the run
        files = sorted(pdir.glob("power_*ns.txt"))
        p = power(files[0])
        hk = hook(files[0].with_name(files[0].stem + "_hook.txt"))
        T = (t1 - t0) * 1e-12
        acc["per"] = p["per"]
        acc["cyc"] += round((t1 - t0) / (p["per"] * 1000))
        acc["T"] += T
        acc["E"] += p["tot"]["Total"] * T
        acc["dyn"] += (p["tot"]["Net Switching"] + p["tot"]["Cell Internal"]) * T
        acc["leak"] += p["tot"]["Cell Leakage"] * T
        for k, v in dict(mem=p["mem"][3], clk=p["clk"][3], **hk).items():
            acc[k] = acc.get(k, 0.0) + v * T
    return acc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clock", type=int, default=2800)
    ap.add_argument("--dense-run", default=str(ROOT / "build/nn_gls/conv1_sdf_2800ps"))
    a = ap.parse_args()
    B = ROOT / "build/qcacc/gls"
    runs = {
        "dense": ([(B / f"dense_conv1_sdf_{a.clock}ps", Path(a.dense_run))],
                  (B / "dense_add1_zd_2000ps", ROOT / "build/nn_gls/add1_zd_2000ps")),
        "gemmx": ([(B / f"gemmx_conv1_sdf_{a.clock}ps_c{k}",) * 2 for k in (3, 4)], (B / "gemmx_add1_zd_2000ps",) * 2),
        "qc":    ([(B / f"qc_conv1_sdf_{a.clock}ps",) * 2], (B / "qc_add1_zd_2000ps",) * 2),
    }
    macs1 = 512 * FIRES["conv1"]
    macs_all = 512 * sum(FIRES.values())
    res = {}
    for d, (conv, other) in runs.items():
        miss = [str(c) for c, _ in conv + [other] if not list(c.glob("power_*ns.txt"))]
        if miss:
            print(f"{d}: missing power of {miss}")
            continue
        m = measure(conv)
        per = m["per"]
        o = measure([other])
        e_cyc = m["E"] / m["cyc"]
        o_cyc = o["dyn"] / o["cyc"] + (o["leak"] / o["T"]) * per * 1e-9
        busy = BUSY[d]
        e_conv = [e_cyc * b for b in busy]
        e_other = o_cyc * (IMG[d] - sum(busy))
        res[d] = dict(m=m, e_conv=e_conv, e_other=e_other, per=per, o=o)
        P = lambda x: x / m["T"] * 1e3
        print(f"== {NAMES[d]}: conv1 SAIF {m['cyc']} cycles at {per} ns ({1e3 / per:.1f} MHz)")
        print(f"  power {P(m['E']):.1f} mW = dyn {P(m['dyn']):.1f} + leak {P(m['leak']):.2f}; GeMMX {P(m['gx']):.1f} "
              f"(array {P(m['array']):.1f}: tiles {P(m['tiles']):.1f}, butterflies {P(m['bfly']):.1f}, decoder {P(m['dec']):.1f}; "
              f"SIMD {P(m['simd']):.1f} incl. table {P(m['table']):.2f}; CSR mgr {P(m['csr']):.2f}; streamer {P(m['stream']):.1f})")
        print(f"  RF macros {P(m['mem']):.1f}, rest of cluster logic {P(m['E'] - m['gx'] - m['mem']):.1f}, "
              f"clock network {P(m['clk']):.1f} ({100 * m['clk'] / m['E']:.1f} %)")
        print(f"  conv1 energy {m['E'] * 1e6:.2f} uJ (GeMMX {m['gx'] * 1e6:.2f}, array {m['array'] * 1e6:.2f}); "
              f"{m['E'] / macs1 * 1e12:.2f} pJ/MAC cluster, {m['gx'] / macs1 * 1e12:.3f} GeMMX, {m['array'] / macs1 * 1e12:.3f} array; "
              f"{2 * macs1 / m['E'] / 1e12:.3f} TOPS/W cluster, {2 * macs1 / m['gx'] / 1e12:.3f} GeMMX")
        print(f"  add1 window: {o['cyc']} cycles, {o['dyn'] / o['cyc'] * 1e12:.1f} pJ dynamic / cycle, "
              f"other energy {o_cyc * 1e12:.1f} pJ / cycle at {per} ns")
        print("  per layer conv energy (uJ): " + "  ".join(f"{n} {e * 1e6:.2f}" for n, e in zip(LAYERS, e_conv)))
        ec, et = sum(e_conv), sum(e_conv) + e_other
        lat = IMG[d] * per * 1e-6
        print(f"  per image: {et * 1e6:.1f} uJ = convs {ec * 1e6:.1f} + other {e_other * 1e6:.1f}; latency {lat:.3f} ms, "
              f"avg {et / lat * 1e6:.1f} mW; convs {ec / macs_all * 1e12:.2f} pJ/MAC, {2 * macs_all / ec / 1e12:.3f} TOPS/W; "
              f"image {USEFUL_OPS / et / 1e12:.3f} TOPS/W")
    if "dense" in res:
        b = res["dense"]
        for d in ("gemmx", "qc"):
            if d in res:
                r = res[d]
                print(f"  {d} vs dense: conv1 window energy x{r['m']['E'] / b['m']['E']:.3f}, GeMMX x{r['m']['gx'] / b['m']['gx']:.3f}, "
                      f"array x{r['m']['array'] / b['m']['array']:.3f}; convs/image x{sum(r['e_conv']) / sum(b['e_conv']):.3f}; "
                      f"image x{(sum(r['e_conv']) + r['e_other']) / (sum(b['e_conv']) + b['e_other']):.3f}")


if __name__ == "__main__":
    main()
