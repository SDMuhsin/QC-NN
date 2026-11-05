#!/usr/bin/env python3
"""Short result files of one DC / PrimeTime run of the KUL cluster (numbers only, safe to copy off the server).
  python3 -I impl/kulcluster/summarize.py <syn_run_dir> <out_dir>
Reads <run>/summary.txt, rpt/area.rpt (report_area -hierarchy), rpt/macro_cells.rpt, pt_<corner>.txt and writes:
  area.txt     total / logic / macro area; area per block (GeMMX, Snitch cores, DMA, TCDM, interconnect, ...): every
               hierarchy's local area goes to the block of its deepest matching ancestor; hierarchy rows (depth <= 3)
  timing.txt   DC summary, per corner: WNS, fmax, worst paths, vectorless power
  netlist.txt  host and path of the netlist / ddc / sdc
"""
import collections
import glob
import os
import re
import socket
import sys

NAND2_UM2 = 1.44            # ND2D1 of tcbn65gplus (gate equivalent)
G = r"i_snax_core_0_acc_0_snax_streamer_gemmX"
HIVE = r"i_cluster/gen_hive_0_i_snitch_hive"
# (block, regex on the normalised hierarchy prefix: runs of [].,_ -> '_'), first match of the deepest prefix wins
BLOCKS = [
    ("gemmx_compute (GeMM 8x8x8 + SIMD)", G + r"/i_snax_streamer_gemmX_shell_wrapper"),
    ("gemmx_streamer",                    G + r"/i_snax_streamer_gemmX_streamer_wrapper"),
    ("gemmx_csr_ctrl",                    G),
    ("dma_xdma (Chisel xDMA)",            r"i_snax_core_1_xdma"),
    ("dma_snitch_idma",                   r"i_cluster/gen_core_\d+_i_snitch_cc/gen_dma_i_axi_dma_tc_snitch_fe"),
    ("snitch_cores (2x rv32ima + cc)",    r"i_cluster/gen_core_\d+_\w+"),
    ("snitch_shared_muldiv",              HIVE + r"/i_(snitch_shared_muldiv|spill_register_muldiv)"),
    ("icache (8 KiB, 2 way)",             HIVE),
    ("tcdm_banks (32x 512x64 + hold)",    r"i_cluster/i_snitch_data_mem"),
    ("tcdm_interconnect (narrow+wide)",   r"i_cluster/(gen_yes_snax_tcdm_interconnect\w*|gen_yes_wide_acc_connect\w*|gen_tcdm_super_bank\w*|i_axi_to_tcdm)"),
    ("axi_interconnect (xbars, cuts)",    r"i_cluster/(i_cluster_xbar|i_axi_dma_xbar|i_cut_ext\w*|i_axi_to_mem_dma|i_axi_zeromem|i_axi_to_reg|i_reqrsp_\w*|\w*axi\w*)"),
    ("cluster_periph_ctrl",               r"i_cluster/(i_snitch_cluster_peripheral|i_snitch_barrier|gen_snax_control_connection\w*|i_popcount\w*)"),
]
BLOCKS = [(n, re.compile(r)) for n, r in BLOCKS]


def norm(p):
    return re.sub(r"[\[\]._]+", "_", p)


def area_rows(path):
    """report_area -hierarchy -nosplit rows: (name, total, pct, local comb, local seq, local black-box)"""
    rows, started = [], False
    if not os.path.exists(path):
        return rows
    for line in open(path):
        if line.startswith("-----"):
            started = True
            continue
        if not started:
            continue
        f = line.split()
        if len(f) >= 6 and all(re.match(r"^[0-9.]+$", x) for x in f[1:6]):
            rows.append((f[0], *map(float, f[1:6])))
        elif line.startswith("Total"):
            break
    return rows


def block_of(name, top):
    parts = [] if name == top else name.split("/")
    for k in range(len(parts), 0, -1):
        pre = norm("/".join(parts[:k]))
        for n, r in BLOCKS:
            if r.fullmatch(pre):
                return n
    return "other (top / cluster glue)"


def main():
    run, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    rd = lambda p: open(os.path.join(run, p)).read() if os.path.exists(os.path.join(run, p)) else ""
    summ = rd("summary.txt")
    m = re.search(r"\btop (\S+)", summ)
    top = m.group(1) if m else "KULCluster_snax_KUL_cluster_wrapper"
    head = rd("rpt/area.rpt")
    rows = area_rows(os.path.join(run, "rpt", "area.rpt"))
    hv = lambda k: float(re.search(r"^" + re.escape(k) + r"\s+([0-9.]+)", head, re.M).group(1))
    with open(os.path.join(out, "area.txt"), "w") as fh:
        if not rows:
            fh.write("no area report\n")
        else:
            tot, bb = hv("Total cell area:"), hv("Macro/Black Box area:")
            fh.write("# um2 at ss (DC report_area, pre-P&R, no wires); macro = ARM RF macros (area from their .db, incl. ring)\n")
            fh.write(f"total_um2 {tot:.0f}  logic_um2 {tot - bb:.0f} ({(tot - bb) / NAND2_UM2 / 1e3:.0f} kGE)  "
                     f"macro_um2 {bb:.0f}  macro_share {100 * bb / tot:.1f} %\n")
            fh.write(f"logic_comb_um2 {hv('Combinational area:'):.0f}  logic_seq_um2 {hv('Noncombinational area:'):.0f}  "
                     f"macros {int(hv('Number of macros/black boxes:'))}  cells {int(hv('Number of cells:'))}\n")
            mc = collections.Counter(l.split()[1] for l in rd("rpt/macro_cells.rpt").splitlines()
                                     if len(l.split()) == 2 and l.split()[1].startswith("kul_"))
            fh.write("macro_list " + ", ".join(f"{n} x {c}" for c, n in sorted(mc.items())) + "\n\n")
            blk = collections.OrderedDict((n, [0.0, 0.0]) for n, _ in BLOCKS)
            blk["other (top / cluster glue)"] = [0.0, 0.0]
            for name, a, pct, comb, seq, bx in rows:
                b = blk[block_of(name, top)]
                b[0] += comb + seq; b[1] += bx
            fh.write(f"{'block':<40} {'total':>10} {'%':>6} {'logic':>10} {'%logic':>7} {'macro':>10}\n")
            for n, (lg, mc_) in blk.items():
                fh.write(f"{n:<40} {lg + mc_:10.0f} {100 * (lg + mc_) / tot:6.1f} {lg:10.0f} "
                         f"{100 * lg / (tot - bb):7.1f} {mc_:10.0f}\n")
            g = sum(v[0] + v[1] for k, v in blk.items() if k.startswith("gemmx"))
            gl = sum(v[0] for k, v in blk.items() if k.startswith("gemmx"))
            fh.write(f"{'= GeMMX accelerator (all gemmx_*)':<40} {g:10.0f} {100 * g / tot:6.1f} {gl:10.0f} "
                     f"{100 * gl / (tot - bb):7.1f}\n")
            fh.write(f"{'check: sum of blocks':<40} {sum(v[0] + v[1] for v in blk.values()):10.0f}\n\n")
            # subtree macro area for the hierarchy dump
            macro = collections.Counter()
            for name, a, pct, comb, seq, bx in rows:
                parts = [] if name == top else name.split("/")
                for k in range(len(parts) + 1):
                    macro["/".join(parts[:k]) or top] += bx
            fh.write(f"{'hierarchy (depth <= 3, >= 0.5 % of total)':<84} {'total':>10} {'%':>6} {'logic':>10} {'macro':>10}\n")
            for name, a, pct, comb, seq, bx in rows:
                depth = 0 if name == top else name.count("/") + 1
                if depth <= 3 and pct >= 0.5:
                    mm = macro.get(name, 0.0)
                    label = "  " * depth + (name.split("/")[-1] if depth else name)
                    fh.write(f"{label:<84} {a:10.0f} {pct:6.1f} {a - mm:10.0f} {mm:10.0f}\n")

    with open(os.path.join(out, "timing.txt"), "w") as fh:
        fh.write("# DC wire-load mode, ideal clocks, pre-CTS; PT: same netlist, no parasitics, per corner library\n")
        fh.write("".join("dc " + l + "\n" for l in summ.splitlines() if l.strip()))
        for c in ("ss", "tt", "ff"):
            t = rd(f"pt_{c}.txt")
            if t:
                fh.write(f"\n# PrimeTime {c}\n" + "".join(f"pt_{c} {l}\n" for l in t.splitlines() if l.strip()))
        for c in ("ss", "tt", "ff"):
            cp = rd(f"rpt/pt_{c}_clu_clk_max.rpt")
            if "Startpoint:" not in cp:
                continue
            # worst path of the corner, compact: end points, cell count, arrival, slack, hierarchy blocks traversed
            body = cp.split("Startpoint:")[1].split("Startpoint:")[0]
            sp = body.split()[0]
            ep = re.search(r"Endpoint:\s+(\S+)", body).group(1)
            cells, blocks = 0, []
            for l in body.split("data arrival time")[0].splitlines():
                f = l.split()
                if len(f) >= 3 and re.match(r"^\([A-Z0-9]+\)$", f[1]) and "/" in f[0]:
                    cells += 1
                    h = "/".join(f[0].split("/")[:-2][:5])
                    if not blocks or blocks[-1] != h:
                        blocks.append(h)
            arr = re.search(r"data arrival time\s+(-?[0-9.]+)", body)
            sl = re.search(r"slack \((?:VIOLATED|MET)\)\s+(-?[0-9.]+)", body)
            fh.write(f"\n# worst {c} path (PrimeTime): {cells} pins, arrival {arr.group(1) if arr else 'NA'} ns, "
                     f"slack {sl.group(1) if sl else 'NA'} ns\n  from {sp}\n  to   {ep}\n")
            fh.write("".join(f"  via  {b}\n" for b in blocks))
        pr = rd("rpt/power.rpt")
        m = re.search(r"^Total\s+(.+)$", pr, re.M)
        if m:
            fh.write(f"\n# DC report_power (ss, default activity)\ndc_power Total {m.group(1).strip()}\n")

    with open(os.path.join(out, "netlist.txt"), "w") as fh:
        host = socket.gethostname().split(".")[0]
        for ext in ("v", "ddc", "sdc", "spef"):
            f = os.path.join(os.path.realpath(run), f"{top}.{ext}")
            if os.path.exists(f):
                fh.write(f"{ext} {host}:{f} {os.path.getsize(f) / 1e6:.1f} MB\n")
        fh.write(f"macro_views {host}:{os.environ.get('KUL_MC_OUT', '/tmp/' + os.environ.get('USER', '') + '/qcnn_kulsyn/macros')}"
                 " (<inst>/<inst>.lef, _<corner>_syn.lib/.db, .v)\n")
        for l in rd("run.env").splitlines():
            fh.write("env " + l + "\n")
    print("SUMMARY", out, *sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
