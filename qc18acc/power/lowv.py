#!/usr/bin/env python3
"""QC18-ACC low-voltage point from qc18acc/power/lowv.sh results (qc18acc/results/lowv).

    python3 qc18acc/power/lowv.py [period_ns=3.3333] [lib_lo=tcbn65gplustc0d8_ccs] [v_lo=0.8] [lib_ref=tcbn65gplustc_ccs]

Same SDF SAIF (image 0, toggles per cycle), same clock, two cell libraries (lib_lo at v_lo, lib_ref at 1.0 V).
The macros keep their tt 1.0 V .db in both PT runs (the kit compilers stop at ss 0.9 V), so at v_lo the macro
numbers are MODELLED from the 1.0 V views:
  macro access energy   datatable energies x (v_lo / 1.0)^2      (macro_dat.py escale, lowv.sh)
  macro output-net switching   PT (1.0 V pins) x (v_lo / 1.0)^2
  macro leakage         PT (1.0 V .db) x k_leak, k_leak = logic leakage(v_lo) / logic leakage(1.0 V) of the same
                        netlist (cell libraries); bound shown with k = v_lo (no DIBL reduction)
Logic (all non-macro cells, incl. the macro clock gates) is PT at lib_lo as is.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import energy  # noqa: E402

P = sys.argv[1] if len(sys.argv) > 1 else "3.3333"
LO = sys.argv[2] if len(sys.argv) > 2 else "tcbn65gplustc0d8_ccs"
V = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8
REF = sys.argv[4] if len(sys.argv) > 4 else "tcbn65gplustc_ccs"
D = Path(__file__).resolve().parent.parent / "results" / "lowv"
energy.R = D


def load(lib):
    b, dat = {}, {}
    for line in (D / f"sdf_{P}ns_{lib}_blocks.txt").read_text().splitlines():
        if not line.startswith("#"):
            w = line.split()
            b[w[0].split(":", 1)[1]] = [float(x) for x in w[1:5]]
    for line in (D / f"sdf_{P}ns_{lib}_macros.txt").read_text().splitlines():
        if line.startswith("datmacro:qa_"):
            w = line.split()
            dat[w[0].split(":", 1)[1]] = {w[i]: float(w[i + 1]) for i in range(1, len(w) - 1, 2)}
    return b, dat


def split(b):
    m = [b[x] for x in energy.MACRO.values()]
    mac = [sum(v[i] for v in m) for i in range(4)]
    log = [b["qa_top"][i] - mac[i] for i in range(4)]
    return log, mac


def point(lib, v, kleak):
    b, dat = load(lib)
    log, mac = split(b)
    s = (v / 1.0) ** 2
    mdyn = sum(d["P_dyn"] for d in dat.values()) + mac[1] * s
    mleak = mac[2] * kleak
    return dict(log=log, mac=mac, mdyn=mdyn, mleak=mleak, tot=log[3] + mdyn + mleak, b=b, dat=dat)


def main():
    per = float(P)
    t = energy.CYCLES * per * 1e-9
    ref = point(REF, 1.0, 1.0)
    lo0 = load(LO)
    k = split(lo0[0])[0][2] / ref["log"][2]
    lo = point(LO, V, k)
    lob = point(LO, V, V)
    mw = lambda x: f"{x * 1e3:.2f}"
    print(f"clock {per} ns ({1e3 / per:.0f} MHz), SDF SAIF image 0 ({energy.CYCLES} cycles, {t * 1e6:.1f} us / inference)")
    print(f"k_leak (logic leakage {V} V / 1.0 V) = {k:.3f}\n")
    print(f"| quantity | 1.0 V ({REF}) | {V} V ({LO}) | ratio |")
    print("|---|---|---|---|")
    rows = [("logic internal mW", ref["log"][0], lo["log"][0]), ("logic switching mW", ref["log"][1], lo["log"][1]),
            ("logic leakage mW", ref["log"][2], lo["log"][2]), ("logic total mW (PT)", ref["log"][3], lo["log"][3]),
            ("macro dynamic mW (datatable + output nets)", ref["mdyn"], lo["mdyn"]),
            ("macro leakage mW", ref["mleak"], lo["mleak"]),
            ("**total mW (+dat)**", ref["tot"], lo["tot"]),
            ("leakage mW (logic + macro)", ref["log"][2] + ref["mleak"], lo["log"][2] + lo["mleak"])]
    for n, a, c in rows:
        print(f"| {n} | {mw(a)} | {mw(c)} | {c / a:.3f} |")
    e = lambda p: p["tot"] * t * 1e6
    lsh = lambda p: 100 * (p["log"][2] + p["mleak"]) / p["tot"]
    print(f"| **uJ / inference** | {e(ref):.2f} | {e(lo):.2f} | {e(lo) / e(ref):.3f} |")
    print(f"| leakage share % | {lsh(ref):.1f} | {lsh(lo):.1f} | |")
    print(f"| pJ / dense-equivalent MAC | {ref['tot'] * t / energy.MACS * 1e12:.4f} | {lo['tot'] * t / energy.MACS * 1e12:.4f} | |")
    print(f"\nbound with macro leakage x {V} (no DIBL reduction): {mw(lob['tot'])} mW, {e(lob):.2f} uJ / inference, "
          f"leakage share {lsh(lob):.1f} %")
    print("\nper block at the low voltage (PT logic; macros modelled as above) mW:")
    b = lo["b"]
    for n in ("u_array", "u_ppu", "u_drain", "u_head", "u_xbar", "u_agu", "u_seq", "u_host"):
        print(f"  {n} {mw(b[n][3])} (ref {mw(ref['b'][n][3])})", end=";")
    print()


if __name__ == "__main__":
    main()
