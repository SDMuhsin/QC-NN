#!/usr/bin/env python3
"""impl/r7b (results/r7b.md): column slices of the south (S) group of an R6b / R6c group file.
    python3 -I slice.py DUMP GRP OUT_GRP OUT_AREA [T=0.6] [F=0.5]
DUMP = impl/r6a/net_dump.tcl output (the r6c_h prep netlist: no repair buffers), GRP = impl/r6a/cuts.py --groups file
('inst group sub').  Every S-group std cell is relabelled S0..S7 (column slice) or SX (shared); the other groups are
copied unchanged.
Column affinity = harmonic labelling over the netlist (nets with > 64 pins ignored, clique weight 1 / (pins - 1)):
  seeds (fixed one-hot vectors over the 8 columns)
    - pins of column block g_c_<c>__u_col                                 -> c   (f_y / b2 / w_y / pf / pw / s_rd / t2 ...)
    - S macro g_s_<k>__u_m (and its wrapper cells)                       -> k % 8 (impl/r6b/mplace.py: S[8r + c] under col c)
    - map macro g_map_<a>__g_mm_<b>__u_m (and wrapper cells)              -> 4a + b (mplace.py: sorted B, c-th under col c)
    - head per-channel registers u_head/{tacc,hold}_reg_<ch>__*           -> ch // 8 (qb_head.sv: s4 / tacc / hold [64])
  + every S cell whose direct block-pin / macro / head-channel neighbours all belong to one column (e.g. the prm
    staging register of a column's pf / pw / t2 pin, the f_y gather of one column)
  every other S cell: synchronous label propagation, one hop per round: column c if c holds >= T of its neighbours'
  column-labelled weight and the column-labelled weight is >= F of all its labelled neighbours (shared = SX neighbours
  count against it), else SX; cells of other groups, params / IMG / FC macros and chip ports are neutral; cells never
  reached are SX.
OUT_AREA: std area (um2-derived mm2) per slice / shared, by RTL sub (prm / head / glue) and sequential count."""
import re
import sys
from collections import defaultdict

SEQ = re.compile(r"^(DF|EDF|SDF|SEDF|LH|LN|CKLN|CKLH|DFKC|DFN|DFX|DFSN|DFCN)")
COL = re.compile(r"g_c_(\d+)__u_col")
SM = re.compile(r"u_top/g_s_(\d+)__u_m/")
BM = re.compile(r"u_top/g_map_(\d+)__g_mm_(\d+)__u_m/")
HC = re.compile(r"^u_head/(tacc|hold)_reg_(\d+)__")


def main():
    dump, grpf, outg, outa = sys.argv[1:5]
    T = float(sys.argv[5]) if len(sys.argv) > 5 else 0.6
    F = float(sys.argv[6]) if len(sys.argv) > 6 else 0.5
    grp = {}
    for ln in open(grpf):
        f = ln.split()
        grp[f[0]] = (f[1], f[2])
    area, master = {}, {}
    nets = []
    for ln in open(dump):
        f = ln.split()
        if f[0] == "I":
            area[f[1]] = float(f[3])
            master[f[1]] = f[2]
        elif f[0] == "N":
            nets.append([f[2]] + f[3:])
    seed = {}

    def term_seed(t):
        if t.startswith("PORT:") or t == "-":
            return None
        i = t.split(":")[0]
        m = COL.search(i)
        if m and ":" in t:
            return int(m.group(1))
        m = SM.search(i + "/")
        if m:
            return int(m.group(1)) % 8
        m = BM.search(i + "/")
        if m:
            return 4 * int(m.group(1)) + int(m.group(2))
        m = HC.match(i)
        if m:
            return int(m.group(2)) // 8
        return None

    S = [n for n, (g, s) in grp.items() if g == "S"]
    Sset = set(S)
    for n in S:
        c = term_seed(n)
        if c is not None:
            seed[n] = c
    # adjacency of S cells: neighbour terminals (S cell names or fixed seed column) with weights
    adj = defaultdict(list)       # S cell -> [(neighbour S cell or None, seed col or None, w)]
    nn = 0
    for ts in nets:
        if len(ts) > 65 or len(ts) < 2:
            continue
        w = 1.0 / (len(ts) - 1)
        loc = []
        for t in ts:
            if t == "-" or t.startswith("PORT:"):
                continue
            i = t.split(":")[0]
            if i in Sset and ":" not in t:
                loc.append((i, seed.get(i)))
            else:
                c = term_seed(t)
                if c is not None:
                    loc.append((None, c))
        if not any(x[0] for x in loc):
            continue
        nn += 1
        for a, ca in loc:
            if a is None or a in seed:
                continue
            for b, cb in loc:
                if b is a and b is not None:
                    continue
                if b is None or b in seed:
                    adj[a].append((None, cb if b is None else seed[b], w))
                else:
                    adj[a].append((b, None, w))
    # synchronous label propagation from the seeds outward (one hop per round): an unlabelled cell with labelled
    # neighbours takes column c if c has >= T of its column-labelled neighbour weight and the column-labelled weight
    # is >= F of all labelled neighbour weight (shared neighbours count against it), else SX; repeated until no change
    lab = {n: seed[n] for n in seed}
    # direct seeds: S cells whose direct block-pin / S / map macro neighbours all belong to one column
    for n in S:
        if n in seed:
            continue
        cs = {c for b, c, w in adj[n] if b is None}
        if len(cs) == 1:
            seed[n] = cs.pop()
    lab = {n: seed[n] for n in seed}
    free = [n for n in S if n not in seed]
    rounds = 0
    while True:
        new = {}
        for n in free:
            if n in lab:
                continue
            v = [0.0] * 9
            for b, c, w in adj[n]:
                if b is None:
                    v[c] += w
                elif b in lab:
                    v[lab[b]] += w
            tot = sum(v)
            if tot <= 0:
                continue
            colw = tot - v[8]
            k = max(range(8), key=lambda j: v[j])
            new[n] = k if (colw > 0 and v[k] >= T * colw and colw >= F * tot) else 8
        if not new:
            break
        lab.update(new)
        rounds += 1
    lab = {n: ("S%d" % lab[n] if lab.get(n, 8) < 8 else "SX") for n in S}
    with open(outg, "w") as fh:
        for n, (g, s) in grp.items():
            fh.write(f"{n} {lab.get(n, g)} {s}\n")
    ar = defaultdict(float)
    cnt = defaultdict(int)
    nseq = defaultdict(int)
    for n in S:
        g, sub = lab[n], grp[n][1]
        ar[(g, sub)] += area.get(n, 0.0)
        cnt[(g, sub)] += 1
        if SEQ.match(master.get(n, "")):
            nseq[(g, sub)] += 1
    with open(outa, "w") as fh:
        fh.write(f"# slice.py T={T} F={F}: S cells {len(S)}, seeds {len(seed)}, nets used {nn}, rounds {rounds}\n")
        fh.write("# slice sub cells n_seq std_mm2 (DC cell sizes, before repair buffers)\n")
        for k in sorted(ar):
            fh.write(f"{k[0]:3s} {k[1]:6s} {cnt[k]:7d} {nseq[k]:6d} {ar[k] / 1e6:8.4f}\n")
        for g in ["S%d" % c for c in range(8)] + ["SX"]:
            fh.write(f"SLICE {g} std_mm2 {sum(a for (gg, s), a in ar.items() if gg == g) / 1e6:.4f} "
                     f"cells {sum(c for (gg, s), c in cnt.items() if gg == g)}\n")
    print("SLICE done", len(S), len(seed))


if __name__ == "__main__":
    main()
