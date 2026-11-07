"""Tables of the array-level ablation from the fetched host summaries (qcacc/ablation/run.sh fetch).

    python3 -m qcacc.ablation.report <build/qcacc/ablation> <qcacc/results/ablation_logs>

Reads <B>/out (DC / PT summaries, hierarchy area, GLS results, PT PX power and per-hierarchy power) and
<B>/rtl.txt; writes <logs>/tables.md (markdown tables used in qcacc/results/ablation.md) and copies the small
summaries (no kit cell names) to <logs>/.
"""
import os
import re
import shutil
import sys

NAND2_UM2 = 1.44                    # ND2D1, tcbn65gplus (as impl/kulcluster/summarize.py)
SYN_P = 4.2
CLK_NS = 2.8
MACS = 4608 * 512                   # conv1: 4608 fires x 512 dense-equivalent MACs
VARIANTS = ["dense", "ternary", "qc"]
POINTS = [("dense_base", "dense", "dense, dense ResNet-8 conv1"), ("dense_s2", "dense", "dense, s2 conv1 (int8 ternary)"),
          ("ternary", "ternary", "ternary, s2 conv1"), ("qc", "qc", "QC, s2 conv1")]
TILE = {"dense": "Tile", "ternary": "TernaryTile", "qc": "QcTile"}


def rd(p):
    return open(p).read() if os.path.exists(p) else ""


def kv(text, key):
    m = re.search(rf"\b{key}\s+(-?[0-9.eE+-]+)", text)
    return float(m.group(1)) if m else None


def area(out, v, sfx="", per=SYN_P):
    d = f"{out}/abl_{v}{sfx}"
    s = rd(f"{d}/summary.txt")
    tot = kv(s, "cell_area_um2")
    rows = []
    for l in rd(f"{d}/area_hier.txt").splitlines():
        f = l.split()
        if len(f) >= 6 and re.match(r"^[0-9.]+$", f[1]):
            rows.append((f[0], float(f[1]), f[-1]))
    arr = sum(a for n, a, r in rows if n == "gemm_array")
    tiles = sum(a for n, a, r in rows if re.match(rf"^{TILE[v]}(_\d+)?$", r))
    bfly = sum(a for n, a, r in rows if r.startswith("QcRowButterfly"))
    dec = sum(a for n, a, r in rows if r.startswith("QcColumnDecoder"))
    t = {}
    for c in ("ss", "tt", "ff"):
        p = rd(f"{d}/pt_{c}.txt")
        w, r2 = kv(p, "setup_wns_ns"), kv(p, "reg2reg_setup_slack_ns")
        t[c] = (1e3 / (per - w) if w is not None else None, 1e3 / (per - r2) if r2 is not None else None)
    m = re.search(r"setup_worst_path (\S+) -> (\S+)", s)
    return dict(wp=f"{m.group(1)} -> {m.group(2)}" if m else "", tot=tot, arr=arr, tiles=tiles, bfly=bfly, dec=dec, rest=tot - arr if tot else None,
                regs=kv(s, "regs"), cells=kv(s, "cells"), dc_wns=kv(s, "setup_wns_ns"), fmax=t)


def power(out, pt, m, z=""):
    s = rd(f"{out}/power_{pt}_{m}{z}.txt")
    if not s:
        return None
    tot = re.search(r"Total Power\s*=\s*([0-9.eE+-]+)", s)
    leak = re.search(r"Cell Leakage Power\s*=\s*([0-9.eE+-]+)", s)
    groups = {}
    for l in s.splitlines():
        f = l.split()
        if len(f) >= 6 and f[0] in ("clock_network", "register", "combinational", "sequential", "memory",
                                     "io_pad", "black_box"):
            try:
                groups[f[0]] = float(f[4])
            except ValueError:
                pass
    cells = []
    for l in rd(f"{out}/power_{pt}_{m}{z}_cells.txt").splitlines():
        f = l.split()
        if len(f) == 6 and not l.startswith("#"):
            try:
                cells.append((f[0], f[1], float(f[5])))
            except ValueError:
                pass
    v = dict(POINTS_V)[pt]
    arr = sum(p for n, r, p in cells if n == "gemm_array")
    tiles = sum(p for n, r, p in cells if re.match(rf"^{TILE[v]}(_\d+)?$", r))
    bfly = sum(p for n, r, p in cells if r.startswith("QcRowButterfly"))
    g = rd(f"{out}/gls_{pt}_{m}.txt")
    res = re.search(r"ABL_RESULT (\w+) tiles (\d+)/(\d+) bad (\d+) busy_cycles (\d+)", g)
    cyc = int(res.group(5)) if res else None
    P = float(tot.group(1)) if tot else None
    return dict(P=P, leak=float(leak.group(1)) if leak else None, groups=groups, arr=arr, tiles=tiles, bfly=bfly,
                res=res.group(1) if res else "NA", bad=res.group(4) if res else "NA", cyc=cyc,
                E=P * cyc * CLK_NS * 1e-9 if P and cyc else None, tv=kv(g, "timing_violation_lines"))


POINTS_V = [(p, v) for p, v, _ in POINTS]


def main():
    B, logs = sys.argv[1], sys.argv[2]
    out = f"{B}/out"
    os.makedirs(logs, exist_ok=True)
    L = []
    A = {v: area(out, v) for v in VARIANTS}
    L.append("| core (standalone, DC 4.2 ns ss, WLM) | total um2 (kGE) | array | 64 tiles (per tile) | row x / butterflies + decoder | control + input cut | regs | fmax ss / tt (all paths) | fmax ss / tt (reg2reg) |")
    L.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    d0 = A["dense"]["tot"]
    for v in VARIANTS:
        a = A[v]
        if not a["tot"]:
            continue
        f = a["fmax"]
        fm = lambda i: " / ".join(f"{f[c][i]:.0f}" if f[c][i] else "NA" for c in ("ss", "tt"))
        L.append(f"| {v} | {a['tot']:.0f} ({a['tot'] / NAND2_UM2 / 1e3:.1f}), x{a['tot'] / d0:.2f} | {a['arr']:.0f} | "
                 f"{a['tiles']:.0f} ({a['tiles'] / 64:.0f}) | {a['bfly'] + a['dec']:.0f} | {a['rest']:.0f} | "
                 f"{a['regs']:.0f} | {fm(0)} MHz | {fm(1)} MHz |")
    L.append("")
    L.append("| core, DC at 2.0 ns ss (fmax runs) | total um2 (kGE) | DC ss WNS | fmax ss (DC) | fmax ss / tt (PT, all paths) | DC worst path |")
    L.append("|---|---:|---:|---:|---:|---|")
    for v in VARIANTS:
        a = area(out, v, "_p2.0", 2.0)
        if not a["tot"]:
            continue
        f = a["fmax"]
        L.append(f"| {v} | {a['tot']:.0f} ({a['tot'] / NAND2_UM2 / 1e3:.1f}) | {a['dc_wns']:.3f} | {1e3 / (2.0 - a['dc_wns']):.0f} MHz | "
                 f"{f['ss'][0]:.0f} / {f['tt'][0]:.0f} MHz | {a['wp']} |")
    L.append("")
    for m, z in (("sdf", ""), ("zd", ""), ("sdf", "_zwlm"), ("zd", "_zwlm")):
        L.append(f"| conv1, PT PX tt 2.8 ns, SAIF {m}, {'zero wire load' if z else 'WLM'} | GLS vs model | busy cyc | total mW | leak mW | array mW | tiles mW | "
                 f"clock net mW | regs mW | comb mW | conv1 energy nJ | pJ / dense MAC | vs dense base |")
        L.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        e0 = None
        for pt, v, lab in POINTS:
            p = power(out, pt, m, z)
            if not p or not p["E"]:
                L.append(f"| {lab} | {p['res'] if p else 'NA'} | | | | | | | | | | | |")
                continue
            e0 = e0 or p["E"]
            g = p["groups"]
            L.append(f"| {lab} | {p['res']} (bad {p['bad']}) | {p['cyc']} | {p['P'] * 1e3:.2f} | {p['leak'] * 1e3:.3f} | "
                     f"{p['arr'] * 1e3:.2f} | {p['tiles'] * 1e3:.2f} | {g.get('clock_network', 0) * 1e3:.2f} | "
                     f"{g.get('register', 0) * 1e3:.2f} | {g.get('combinational', 0) * 1e3:.2f} | {p['E'] * 1e9:.0f} | "
                     f"{p['E'] / MACS * 1e12:.3f} | x{p['E'] / e0:.2f} |")
        L.append("")
    print("\n".join(L))
    # small logs only: summaries, hierarchy area to depth 3 without clock gates, power groups + annotation
    shutil.rmtree(logs, ignore_errors=True)
    os.makedirs(logs)
    open(f"{logs}/tables.md", "w").write("\n".join(L) + "\n")
    for f in sorted(os.listdir(out)):
        src = f"{out}/{f}"
        if os.path.isdir(src):
            os.makedirs(f"{logs}/{f}")
            for g in sorted(os.listdir(src)):
                t = rd(f"{src}/{g}")
                if g == "area_hier.txt":
                    t = "".join(l + "\n" for l in t.splitlines() if "clk_gate" not in l and l.split()[:1]
                                and l.split()[0].count("/") < 3)
                elif g == "run.env":
                    continue
                open(f"{logs}/{f}/{g}", "w").write(t)
        elif f.startswith("power_") and not f.endswith("_cells.txt"):
            t = rd(src)
            keep = t.split("Switching Activity Overview")[0]
            ann = re.search(r"^ Nets .*$", t, re.M)
            open(f"{logs}/{f}", "w").write(keep + ("annotation " + " ".join(ann.group(0).split()) + "\n" if ann else ""))
        elif f.startswith(("gls_", "sdf_")):
            shutil.copy(src, logs)
    if os.path.exists(f"{B}/rtl.txt"):
        shutil.copy(f"{B}/rtl.txt", logs)


if __name__ == "__main__":
    main()
