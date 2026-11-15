#!/usr/bin/env python3
"""impl/r6a (H2): physical groups of the R5b top level and every bus crossing between them / to the column blocks,
from a placed-checkpoint dump (impl/r6a/net_dump.tcl; the DC netlist + OpenROAD repair buffers, which are collapsed).
    python3 -I cuts.py dump_v.txt OUTPREFIX
Groups: W = west strip (act supply qb_act2 + act distribution, sequencer + descriptor macros, head + FC macro, qb_chip
glue), S = south band (S / B / IMG / params macros, qb_prm, S read / write registers, write-back, B maps), N = north
band (weight macros, code register cd_r, weight address registers), BLK = the 8 column blocks, IO = chip ports.
Seeds: hierarchy (u_act, u_seq, u_head, g_dist, chip -> W; u_prm -> S), macros by type, blocks, and the u_top
registers with a fixed home (NAMED below); every other u_top glue cell (comb + remaining registers) by label
propagation over its nets (majority of already-labelled neighbours, nets with fanout > 64 ignored), iterated.
Outputs: OUT_area.txt (std-cell area per group, placed sizes, rsz buffers excluded), OUT_cuts.txt (bus table);
--groups FILE (R6b): one line per std cell 'inst group sub'."""
import re
import sys
from collections import Counter, defaultdict

RSZ = re.compile(r"^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer|gain)\d")
SEQ = re.compile(r"^(DF|EDF|SDF|SEDF|LH|LN|CKLN|CKLH|DFKC|DFN|DFX|DFSN|DFCN)")
NAMED = {  # u_top glue register base name -> group (home from the RTL role; results/r6a.md section 2)
    # north: weight-macro address / code output registers, item-control pipeline to the blocks' north ctl pins
    "cd_r": "N", "w_a_q": "N", "w_d_q": "N", "w_d_m": "N", "w_ren_q": "N", "ictl": "N",
    # south: S read output register, S / map write registers, b2 FIFO, write-back job / step delay lines, S read
    # rotation state, map read mux state
    "rq_r": "S", "s_wd": "S", "s_wa": "S", "s_wm": "S", "s_we": "S", "b_wd": "S", "b_wa": "S", "b_wm": "S", "b_we": "S",
    "b2f_d": "S", "b2f_tp": "S", "b2f_pi": "S", "b2f_ct": "S", "b2f_n": "S", "b2_j": "S", "b2_ovf": "S",
    "fdl": "S", "wdl": "S", "cdl": "S", "fjob": "S", "wjob": "S", "fk": "S", "wk": "S", "fbusy": "S", "wbusy": "S",
    "clr": "S", "fv_p": "S", "wv_p": "S", "f_pg1": "S", "f_pg2": "S", "f_pg3": "S", "k0_1": "S", "k0_2": "S",
    "k0_3": "S", "rd_a_q": "S", "rd_en_q": "S", "s_rot_q": "S", "s_grp_q": "S", "m_src_q": "S", "m_f_q": "S",
    # slice-flag queues: set from zero detects of the fused outputs f_y (south), read by the sequencer / act supply
    "fp_z": "S", "fs_z": "S", "fp_hq": "S", "fs_hq": "S", "fp_hqd": "S", "fs_hqd": "S",
    # west: pass table (static per program), time base, context state
    "pt": "W", "now": "W", "run": "W", "err": "W", "cpi": "W", "quiet": "W",
}
HIER = [("u_top/u_act/", "W", "act"), ("u_top/g_r3b_g_rt_u_seq/", "W", "seq"), ("u_head/", "W", "head"),
        ("u_top/g_dist_", "W", "dist"), ("u_top/g_r3b_u_prm/", "S", "prm")]
MAC = {"qb_w": "N", "qb_s": "S", "qb_b": "S", "qb_i": "S", "qb_p": "S", "qb_d": "W", "qb_f": "W"}


def bname(s):
    s = re.sub(r"\[\d+\]", "", s)
    s = re.sub(r"_\d+_", "_", s)
    s = re.sub(r"_\d+$", "", s)
    return re.sub(r"\d+", "N", s)


def main():
    dump, out = sys.argv[1], sys.argv[2]
    if "--head-south" in sys.argv:          # variant: head (pool + FC macro) in the south band
        HIER[2] = ("u_head/", "S", "head")
        MAC["qb_f"] = "S"
    if "--split-w" in sys.argv:             # variant: west strip as two blocks, WA = act supply + distribution
        HIER[0] = ("u_top/u_act/", "WA", "act")
        HIER[3] = ("u_top/g_dist_", "WA", "dist")
    inst = {}   # name -> [master, area, kind, group, sub]
    nets = []
    for ln in open(dump):
        f = ln.split()
        if f[0] == "I":
            n, m, a = f[1], f[2], float(f[3])
            last = n.split("/")[-1]
            if m == "qb_col_blk":
                k, g, sub = "blk", "BLK", "col" + re.search(r"g_c_(\d+)", n).group(1)
            elif m[:4] in MAC:
                k, g, sub = "mac", MAC[m[:4]], m[:4]
            elif RSZ.match(last):
                k, g, sub = "rsz", None, None
            else:
                k = "seq" if SEQ.match(m) else "comb"
                g = sub = None
                for p, gg, s in HIER:
                    if n.startswith(p):
                        g, sub = gg, s
                        break
                if g is None and "/" not in n:
                    g, sub = "W", "chip"
                if g is None and n.startswith("u_top/") and n.count("/") == 1 and "_reg" in last:
                    b = re.sub(r"_reg.*", "", last)
                    if b in NAMED:
                        g, sub = NAMED[b], "glue"
            inst[n] = [m, a, k, g, sub]
        elif f[0] == "N":
            nets.append((f[1], f[2], f[3:]))

    def iname(t):
        return t.split(":")[0] if not t.startswith("PORT:") else t

    # collapse rsz buffer trees into hypernets: root driver -> leaf sinks
    drv_of = {}
    for nm, d, ss in nets:
        drv_of.setdefault(iname(d), []).append((nm, d, ss))
    hyper = []
    for nm, d, ss in nets:
        di = iname(d)
        if di in inst and inst[di][2] == "rsz":
            continue
        leaves, stack = [], list(ss)
        while stack:
            t = stack.pop()
            ti = iname(t)
            if ti in inst and inst[ti][2] == "rsz":
                for _, _, s2 in drv_of.get(ti, []):
                    stack.extend(s2)
            else:
                leaves.append(t)
        hyper.append((nm, d, leaves))

    # unseeded u_top glue cells (comb + unnamed registers): label = majority of the labels of the cells they drive
    # (logic sits with its destination registers), iterated back from the seeded endpoints; cells that drive only
    # blocks / IO take the majority of their drivers' labels
    fo = defaultdict(list)
    fi = defaultdict(list)
    for nm, d, ls in hyper:
        di = iname(d)
        for t in ls:
            ti = iname(t)
            fo[di].append(ti)
            fi[ti].append(di)
    for n, v in inst.items():
        if v[2] in ("seq", "comb") and v[3] is None and not n.startswith("u_top/"):
            v[3], v[4] = "W", "chip"
    todo = [n for n, v in inst.items() if v[2] in ("seq", "comb") and v[3] is None]
    for direction in (fo, fi):
        for it in range(200):
            new_l = {}
            for n in todo:
                if inst[n][3] is not None:
                    continue
                c = Counter(inst[x][3] for x in direction.get(n, ()) if x in inst and inst[x][3] not in (None, "BLK"))
                if c:
                    new_l[n] = c.most_common(1)[0][0]
            for n, g in new_l.items():
                inst[n][3], inst[n][4] = g, "glue"
            if not new_l:
                break
    for v in inst.values():
        if v[3] is None and v[2] in ("seq", "comb"):
            v[3], v[4] = "W", "glue?"

    if "--groups" in sys.argv:              # R6b: per-instance group of every std cell (impl/r6b/grp_place.tcl)
        with open(sys.argv[sys.argv.index("--groups") + 1], "w") as fh:
            for n, v in inst.items():
                if v[2] in ("seq", "comb"):
                    fh.write(f"{n} {v[3]} {v[4]}\n")

    # areas
    ar = defaultdict(float)
    nseq = defaultdict(int)
    for n, v in inst.items():
        if v[2] in ("seq", "comb"):
            ar[(v[3], v[4])] += v[1]
            if v[2] == "seq":
                nseq[(v[3], v[4])] += 1
        elif v[2] in ("mac", "blk"):
            ar[(v[3], v[4])] += v[1]
    with open(out + "_area.txt", "w") as fh:
        fh.write("# group sub area_mm2 (placed cell sizes, rsz buffers excluded) n_seq\n")
        for k in sorted(ar):
            fh.write(f"{k[0]:4s} {k[1]:8s} {ar[k] / 1e6:8.4f} {nseq[k]}\n")
        for g in ("W", "WA", "S", "N"):
            std = sum(a for (gg, s), a in ar.items() if gg == g and s not in MAC and not s.startswith("qb_"))
            mac = sum(a for (gg, s), a in ar.items() if gg == g and s.startswith("qb_"))
            fh.write(f"GROUP {g} std_mm2 {std / 1e6:.4f} macro_mm2 {mac / 1e6:.4f}\n")

    # cuts
    def grp(t):
        if t.startswith("PORT:"):
            return "IO", ("port",), True
        ti, pin = (t.split(":", 1) + [None])[:2]
        v = inst.get(ti)
        if v is None:
            return "?", None, False
        if v[2] == "blk":
            pn, e = pin.split("@")
            return "BLK", (re.sub(r"\[.*", "", pn), e, v[4]), True
        if v[2] == "mac":
            return v[3], (v[4], re.sub(r"\[.*", "", pin.split("@")[0])), True
        return v[3], (v[4],), v[2] == "seq"

    bus = defaultdict(lambda: [0, 0, 0, set(), set(), Counter()])  # n, src_reg, dst_reg_all, edges, cols, sinksub
    for nm, d, ls in hyper:
        gd, dinfo, dreg = grp(d)
        if gd == "?":
            continue
        by = defaultdict(list)
        for t in ls:
            gs, sinfo, sreg = grp(t)
            if gs != "?":
                by[gs].append((sinfo, sreg))
        for gs, lst in by.items():
            if gs == gd and gs != "BLK":
                continue
            if gd == "BLK" and gs == "BLK":
                continue          # act chain between abutted blocks
            if gd == "BLK":
                key = (gd, gs, "blk." + dinfo[0], dinfo[1])
            elif gs == "BLK":
                key = (gd, gs, bname(nm.split("/")[-1]) if not d.startswith("PORT:") else bname(nm), lst[0][0][0])
                key = (gd, gs, "->blk." + lst[0][0][0] + " from " + (dinfo[0] if dinfo else "IO"), lst[0][0][1])
            else:
                src = dinfo[0] if dinfo else "IO"
                if d.startswith("PORT:"):
                    src = "port " + bname(d[5:])
                key = (gd, gs, src + " -> " + ",".join(sorted({x[0][0] for x in lst})), "")
            b = bus[key]
            b[0] += 1
            b[1] += int(dreg)
            b[2] += int(all(r for _, r in lst))
            if gs == "BLK":
                b[4].update(x[0][2] for x in lst)
    with open(out + "_cuts.txt", "w") as fh:
        fh.write("# from -> to | bus (driver sub -> sink subs; blk.<pin> = block port) | edge | bits | "
                 "src registered bits | dst registered bits (all sinks seq / macro / block)\n")
        tot = defaultdict(lambda: [0, 0, 0])
        for k, b in sorted(bus.items(), key=lambda kv: (kv[0][0], kv[0][1], -kv[1][0])):
            fh.write(f"{k[0]:3s} -> {k[1]:3s} | {k[2][:70]:70s} | {k[3]:2s} | {b[0]:6d} | {b[1]:6d} | {b[2]:6d}"
                     f"{' | cols ' + str(len(b[4])) if b[4] else ''}\n")
            t = tot[(k[0], k[1])]
            t[0] += b[0]; t[1] += b[1]; t[2] += b[2]
        fh.write("# totals per group pair: bits, src registered, dst registered, neither\n")
        for k, t in sorted(tot.items()):
            fh.write(f"TOTAL {k[0]:3s} -> {k[1]:3s} {t[0]:7d} {t[1]:7d} {t[2]:7d}\n")
    print("CUTS done", len(inst), len(hyper))


if __name__ == "__main__":
    main()
