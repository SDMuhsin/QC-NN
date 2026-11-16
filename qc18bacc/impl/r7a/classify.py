#!/usr/bin/env python3
"""impl/r7a: which net classes use the routing capacity of the r6c_h hub hotspots (results/r7a.md).
    python3 -I classify.py DUMP GUIDE CONGRPT OBS OUTDIR
DUMP = impl/r7a/dump_grt.tcl output (impl/r6a/net_dump.tcl I / N lines + C / B / L / G / D), GUIDE = route.guide of
global_route, CONGRPT = global_route -congestion_report_file, OBS = impl/r7a/obs.tcl output.
1. Every net -> root net (repair / CTS buffer trees collapsed, impl/r6a/cuts.py RSZ names + clkbuf_*), root -> class
   from driver / sink kind (block pin names, macro type + pin, RTL hierarchy, glue register names) and, for the qb_top
   glue's flattened comb nets, the comb cone: source tags propagated forward (S macro Q, map Q, block f_y / w_y / b2,
   rq_r) and sink tags backward (act supply, S write port, ...) through glue comb cells.
2. Guides (gcell strips per layer; wire = gcell centre to gcell centre): H (M3/M5/M7) / V (M2/M4/M6) wirelength per
   class inside each hotspot window, and segments crossing the cut lines.
3. Capacity: GRT's per-gcell track capacity (0.2-um pitch, 3-um gcells, 30 % adjustment -> 10 tracks per layer) with
   block / macro obstructions per layer (OBS area fraction); congestion report: overflow per gcell split over the
   classes of the nets listed at that gcell (proportional to net count)."""
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "r6a"))
from cuts import RSZ, SEQ, HIER  # noqa: E402  (reuse the R6a labelling: rsz names, sequential masters, hierarchy)

WIN = {"west": (0.0, 2000.0, 1000.0, 4500.0), "south": (1000.0, 1000.0, 3500.0, 2000.0)}   # x0 y0 x1 y1 (um)
# cut lines: (name, orientation of the line, position, range along the line)
CUTS = [("x=2000 (y 1000-1700.6, south band below array)", "V", 2000.0, (1000.0, 1700.6)),
        ("x=2000 (y 1000-2000, as asked)", "V", 2000.0, (1000.0, 2000.0)),
        ("y=1700.6 (array bottom, x 860-3980)", "H", 1700.6, (860.0, 3980.0)),
        ("y=2000 (x 1000-3500, as asked)", "H", 2000.0, (1000.0, 3500.0)),
        ("x=860 (array west edge, y 1700.6-4810.6)", "V", 860.0, (1700.6, 4810.6)),
        ("x=1000 (y 2000-4500, as asked)", "V", 1000.0, (2000.0, 4500.0))]
HL, VL = {"M3", "M5", "M7"}, {"M2", "M4", "M6"}
DBU, GC, TPL = 2000.0, 3.0, 10            # guide DBU / um, gcell um, tracks per layer per gcell after 30 % adjust
CLKB = re.compile(r"^clkbuf_")
MACT = {"qb_s": "S", "qb_b": "map", "qb_i": "img", "qb_p": "par", "qb_w": "wgt", "qb_d": "desc", "qb_f": "fc"}

# source / sink tags (bit masks)
SQ, MQ, FY, WY, B2, RQ, OB = 1, 2, 4, 8, 16, 32, 64
K_ACT, K_SW, K_MW, K_BLK, K_SEQ, K_PRM, K_HEAD = 1, 2, 4, 8, 16, 32, 64
SW_REG = {"s_wd", "s_wa", "s_wm", "s_we"}
MW_REG = {"b_wd", "b_wa", "b_wm", "b_we", "b2f_d"}


def iname(t):
    return t if t.startswith("PORT:") else t.split(":")[0]


def main():
    dump, guide, cong, obsf, out = sys.argv[1:6]
    inst, nets, clk, box = {}, [], set(), []
    for ln in open(dump):
        f = ln.split()
        if not f:
            continue
        if f[0] == "I":
            inst[f[1]] = (f[2], float(f[4]), float(f[5]))
        elif f[0] == "N":
            nets.append((f[1], f[2], f[3:]))
        elif f[0] == "C":
            clk.add(f[1])
            nets.append((f[1], f[2], f[3:]))
        elif f[0] == "B":
            box.append((f[1], f[2], *map(float, f[3:7])))
    obs = {}
    for ln in open(obsf):
        f = ln.split()
        obs[f[1]] = {k: float(v) for k, v in (x.split("=") for x in f[2:])}

    def kind(n):     # rsz / clkbuf / blk / mac / hier sub / glue
        m = inst[n][0]
        last = n.split("/")[-1]
        if m == "qb_col_blk":
            return "blk"
        if m[:4] in MACT:
            return "mac"
        if RSZ.match(last) or CLKB.match(last):
            return "buf"
        for p, g, s in HIER:
            if n.startswith(p):
                return s
        return "glue"
    ik = {n: kind(n) for n in inst}

    # root nets
    drv = {}
    outn = {}                      # buffer inst -> output nets
    inn = {}                       # buffer inst -> input net
    for nm, d, ss in nets:
        drv[nm] = d
        di = iname(d)
        if di in ik and ik[di] == "buf":
            outn.setdefault(di, []).append(nm)
        for s in ss:
            si = iname(s)
            if si in ik and ik[si] == "buf":
                inn[si] = nm
    root = {}

    def get_root(nm):
        path = []
        while nm not in root:
            di = iname(drv.get(nm, "-"))
            if di in ik and ik[di] == "buf" and di in inn and len(path) < 200:
                path.append(nm)
                nm = inn[di]
            else:
                root[nm] = nm
                break
        r = root[nm]
        for p in path:
            root[p] = r
        return r
    for nm, _, _ in nets:
        get_root(nm)
    leaves = defaultdict(list)     # root -> non-buffer sink terminals
    for nm, d, ss in nets:
        r = root[nm]
        for s in ss:
            si = iname(s)
            if not (si in ik and ik[si] == "buf"):
                leaves[r].append(s)
    roots = [nm for nm, _, _ in nets if root[nm] == nm]
    clkroot = {root[n] for n in clk}

    # cell -> input roots / output roots (glue comb cells only matter for cone propagation)
    cin, cout = defaultdict(list), defaultdict(list)
    for r in roots:
        di = iname(drv[r])
        if di in ik:
            cout[di].append(r)
        for s in leaves[r]:
            cin[iname(s)].append(r)

    def is_comb_glue(c):
        return c in ik and ik[c] == "glue" and not SEQ.match(inst[c][0])

    def regbase(c):
        last = c.split("/")[-1]
        return re.sub(r"_reg.*", "", last) if "_reg" in last else None

    # forward source tags
    ft = defaultdict(int)
    work = []
    for r in roots:
        d = drv[r]
        di = iname(d)
        t = 0
        if di in ik and ik[di] == "mac":
            m, pin = inst[di][0][:4], d.split(":")[1]
            if m == "qb_s" and pin.startswith("QA"):
                t = SQ
            elif m in ("qb_b", "qb_i") and pin.startswith("Q"):
                t = MQ
        elif di in ik and ik[di] == "blk":
            pin = re.sub(r"\[.*", "", d.split(":")[1])
            t = {"f_y": FY, "w_y": WY, "b2": B2}.get(pin, OB)
        elif di in ik and regbase(di) == "rq_r":
            t = RQ
        if t:
            ft[r] = t
            work.append(r)
    dep = {r: 0 for r in roots if ft[r] & SQ}             # comb levels from S macro Q
    dpw = {r: 0 for r in roots if ft[r] & (FY | WY | B2)}  # comb levels from block f_y / w_y / b2
    while work:
        nxt = []
        for r in work:
            for s in leaves[r]:
                c = iname(s)
                if not is_comb_glue(c):
                    continue
                t = 0
                for x in cin[c]:
                    t |= ft[x]
                for o in cout[c]:
                    if (ft[o] | t) != ft[o]:
                        ft[o] |= t
                        nxt.append(o)
                    for dd in (dep, dpw):
                        if r in dd and (o not in dd or dd[o] > dd[r] + 1):
                            dd[o] = dd[r] + 1
                            nxt.append(o)
        work = nxt
    # backward sink tags
    bt = defaultdict(int)

    def sink_tag(s):
        c = iname(s)
        if s.startswith("PORT:") or c not in ik:
            return 0
        k = ik[c]
        if k == "act" or k == "dist":
            return K_ACT
        if k == "blk":
            return K_BLK
        if k == "seq":
            return K_SEQ
        if k == "prm":
            return K_PRM
        if k == "head":
            return K_HEAD
        if k == "mac":
            m = inst[c][0][:4]
            return K_SW if m == "qb_s" else (K_MW if m in ("qb_b", "qb_i") else 0)
        b = regbase(c)
        if b in SW_REG:
            return K_SW
        if b in MW_REG:
            return K_MW
        return 0
    for r in roots:
        t = 0
        for s in leaves[r]:
            t |= sink_tag(s)
        bt[r] = t
    order = [r for r in roots if is_comb_glue(iname(drv[r]))]
    for it in range(60):                                 # fixed point over the glue comb DAG
        ch = 0
        for r in order:
            t = bt[r]
            for s in leaves[r]:
                c = iname(s)
                if is_comb_glue(c):
                    for o in cout[c]:
                        t |= bt[o]
            if t != bt[r]:
                bt[r] = t
                ch += 1
        if not ch:
            break

    def blkpins(r):
        return Counter(re.sub(r"\[.*", "", s.split(":")[1].split("@")[0]) for s in leaves[r]
                       if iname(s) in ik and ik[iname(s)] == "blk")

    def classify(r):
        if r in clkroot or r.startswith("clknet"):
            return "clock"
        d = drv[r]
        if d.startswith("PORT:"):
            return "chip IO in (host port)"
        di = iname(d)
        if di not in ik:
            return "other (undriven)"
        k = ik[di]
        bp = blkpins(r)
        if k == "blk":
            pin = re.sub(r"\[.*", "", d.split(":")[1].split("@")[0])
            if pin == "act_o":
                return "act chain blk->blk"
            return {"f_y": "blk f_y out", "w_y": "blk w_y out", "b2": "blk b2 out"}.get(pin, "blk other out (f_b,w_b,vld)")
        if k == "mac":
            m, pin = inst[di][0][:4], d.split(":")[1]
            return {"qb_s": "S macro Q (s_mq)", "qb_b": "map/img Q", "qb_i": "map/img Q", "qb_p": "params Q -> prm",
                    "qb_w": "weight Q", "qb_d": "seq desc Q", "qb_f": "head FC Q"}[m]
        if k == "dist":
            return "act supply out (dist -> col0 act)"
        if k == "act":
            return "act supply internal" if not bp else "act supply out (dist -> col0 act)"
        if k == "seq":
            return "sequencer"
        if k == "head":
            return "head"
        if k == "prm":
            if bp:
                p = bp.most_common(1)[0][0]
                return {"pf": "prm -> blk pf", "pw": "prm -> blk pw", "t2": "prm -> blk t2"}.get(p, "prm -> blk other")
            return "prm staging internal"
        # glue (qb_top flat + qb_chip)
        if bp:
            p = bp.most_common(1)[0][0]
            return {"s_rd": "glue -> blk s_rd", "cd": "glue -> blk cd", "w_r": "glue -> blk w_r",
                    "act": "act supply out (dist -> col0 act)"}.get(p, "glue -> blk ctl/other")
        f, b = ft[r], bt[r]
        seq = SEQ.match(inst[di][0]) is not None
        if f & SQ and b & K_ACT and not seq:
            return "S-read rotator (s_q -> act)"
        if f & (FY | WY | B2) and b & (K_SW | K_MW) and not seq:
            return "write-back rotators (f_y/w_y/b2 -> S/map wr)"
        if any(sink_tag(s) & K_SW for s in leaves[r]) and seq:
            return "S write regs -> S macro (s_wd/wa/wm)"
        if any(sink_tag(s) & K_MW for s in leaves[r]) and seq:
            return "map write regs -> map macro"
        if f & MQ and b & K_ACT:
            return "map mux (m_q -> act)"
        if f & RQ:
            return "rq_r -> s_rd/w_r mux"
        if b & K_ACT:
            return "glue -> act supply (ctl)"
        if f & (FY | WY | B2 | OB):
            return "glue blk-out consumers (flags, b2f, other)"
        return "glue other"

    cls = {r: classify(r) for r in roots}
    rc = {nm: cls[root[nm]] for nm, _, _ in nets}

    # S-read rotator depth histogram, bits per class
    with open(os.path.join(out, "classes_bits.txt"), "w") as fh:
        fh.write("# class | root nets (bits) | physical nets (incl. buffer-tree nets)\n")
        cb = Counter(cls.values())
        cp = Counter(rc.values())
        for c, n in cb.most_common():
            fh.write(f"{c:48s} {n:8d} {cp[c]:8d}\n")
        fh.write("# S-read rotator nets by comb depth from S macro QA (1 = first glue gate output)\n")
        dh = Counter(dep.get(r, -1) for r in roots if cls[r] == "S-read rotator (s_q -> act)")
        fh.write(" ".join(f"d{k}:{v}" for k, v in sorted(dh.items())) + "\n")

    # ---- guides
    def wins_of(x0, y0, x1, y1):
        return x0, y0, x1, y1
    wl = defaultdict(float)        # (win, cls, H/V, layer) -> um
    bits_in = defaultdict(set)     # (win, cls) -> root nets with routing in window
    cut = defaultdict(int)         # (cut idx, cls) -> crossing segments
    cutn = defaultdict(set)
    hspan = defaultdict(float)     # rotator H wire per net (south window): span analysis
    layers = Counter()
    glob = defaultdict(lambda: [0.0, 0.0, 0.0])   # (cls, H/V) -> wl, sum x*wl, sum y*wl (whole die)
    dwl = defaultdict(float)                      # (rotator cls, comb depth, all/south) -> H wl
    nm, rect = None, []
    unk = 0

    def flush(nm, rect):
        c = rc.get(nm)
        if c is None:
            c = "clock" if nm.startswith("clknet") else "other (not in dump)"
        r = root.get(nm, nm)
        for (x0, y0, x1, y1, L) in rect:
            layers[L] += 1
            if L in HL or L in VL:
                h = L in HL
                ln = (x1 - x0 - GC) if h else (y1 - y0 - GC)
                if ln > 0:
                    g = glob[(c, "H" if h else "V")]
                    g[0] += ln; g[1] += ln * (x0 + x1) / 2; g[2] += ln * (y0 + y1) / 2
                    for dd, cc in ((dep, "S-read rotator (s_q -> act)"), (dpw, "write-back rotators (f_y/w_y/b2 -> S/map wr)")):
                        if c == cc and h:
                            ys = (y0 + y1) / 2
                            dwl[(cc, min(dd.get(r, -1), 9), "all")] += ln
                            if WIN["south"][1] <= ys < WIN["south"][3]:
                                a2 = max(x0 + GC / 2, WIN["south"][0]); b2 = min(x1 - GC / 2, WIN["south"][2])
                                if b2 > a2:
                                    dwl[(cc, min(dd.get(r, -1), 9), "south")] += b2 - a2
            if L in HL:
                a, b, yc = x0 + GC / 2, x1 - GC / 2, (y0 + y1) / 2
                for w, (wx0, wy0, wx1, wy1) in WIN.items():
                    if wy0 <= yc < wy1:
                        ln = min(b, wx1) - max(a, wx0)
                        if ln > 0:
                            wl[(w, c, "H", L)] += ln
                            bits_in[(w, c)].add(r)
                            if w == "south":
                                hspan[(r, c)] += ln
                for i, (_, o, pos, (lo, hi)) in enumerate(CUTS):
                    if o == "V" and a < pos < b and lo <= yc < hi:
                        cut[(i, c)] += 1
                        cutn[(i, c)].add(r)
            elif L in VL:
                a, b, xc = y0 + GC / 2, y1 - GC / 2, (x0 + x1) / 2
                for w, (wx0, wy0, wx1, wy1) in WIN.items():
                    if wx0 <= xc < wx1:
                        ln = min(b, wy1) - max(a, wy0)
                        if ln > 0:
                            wl[(w, c, "V", L)] += ln
                            bits_in[(w, c)].add(r)
                for i, (_, o, pos, (lo, hi)) in enumerate(CUTS):
                    if o == "H" and a < pos < b and lo <= xc < hi:
                        cut[(i, c)] += 1
                        cutn[(i, c)].add(r)
    with open(guide) as fh:
        for ln in fh:
            if ln[0] == "(":
                rect = []
            elif ln[0] == ")":
                flush(nm, rect)
            else:
                f = ln.split()
                if len(f) == 1:
                    nm = f[0]
                    if nm not in rc and not nm.startswith("clknet"):
                        unk += 1
                        if unk <= 20:
                            print("UNK", nm)
                else:
                    x0, y0, x1, y1 = (int(v) / DBU for v in f[:4])
                    rect.append((x0, y0, x1, y1, f[4]))

    # ---- capacity per window (per layer, gcell-resolution obstruction by footprint x OBS fraction)
    def cap_win(wx0, wy0, wx1, wy1):
        area = (wx1 - wx0) * (wy1 - wy0)
        cap = {}
        for L in sorted(HL | VL):
            blocked = 0.0
            for (n, m, bx0, by0, bx1, by1) in box:
                ox = max(0.0, min(bx1, wx1) - max(bx0, wx0))
                oy = max(0.0, min(by1, wy1) - max(by0, wy0))
                blocked += ox * oy * obs.get(m, {}).get(L, 0.0)
            # track-um per layer = (free area) x tracks per um (10 per 3 um)
            cap[L] = (area - blocked) * TPL / GC
        return cap
    capw = {w: cap_win(*v) for w, v in WIN.items()}

    # ---- congestion report: overflow split by class
    ovf = defaultdict(float)
    ovt = defaultdict(lambda: [0, 0, 0, 0])     # (win, H/V) -> entries, capacity, usage, overflow
    with open(cong) as fh:
        srcs, d = None, None
        for ln in fh:
            s = ln.strip()
            if s.startswith("violation type"):
                d = "H" if "Horizontal" in s else "V"
            elif s.startswith("srcs:"):
                srcs = [t[4:] for t in s[5:].split()]
            elif s.startswith("congestion information"):
                m = re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s)
                cu = tuple(int(v) for v in m.groups())
            elif s.startswith("bbox"):
                m = re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s)
                x, y = (float(m.group(1)) + float(m.group(3))) / 2, (float(m.group(2)) + float(m.group(4))) / 2
                for w, (wx0, wy0, wx1, wy1) in WIN.items():
                    if wx0 <= x < wx1 and wy0 <= y < wy1:
                        t = ovt[(w, d)]
                        t[0] += 1; t[1] += cu[0]; t[2] += cu[1]; t[3] += cu[2]
                        if srcs:
                            cc = Counter(rc.get(n, "clock" if n.startswith("clknet") else "other (not in dump)") for n in srcs)
                            for c, k in cc.items():
                                ovf[(w, d, c)] += cu[2] * k / len(srcs)

    # ---- outputs
    for w in WIN:
        wx0, wy0, wx1, wy1 = WIN[w]
        capH = sum(capw[w][L] for L in HL)
        capV = sum(capw[w][L] for L in VL)
        ng = (wx1 - wx0) * (wy1 - wy0) / GC / GC
        with open(os.path.join(out, f"hot_{w}.txt"), "w") as fh:
            fh.write(f"# hotspot {w} x {wx0}-{wx1} y {wy0}-{wy1} um; capacity [E from GRT rule + OBS] H {capH/1e3:.0f} mm "
                     f"V {capV/1e3:.0f} mm (per layer: " + " ".join(f"{L} {capw[w][L]/1e3:.0f}" for L in sorted(capw[w])) + ")\n")
            for d in "HV":
                t = ovt[(w, d)]
                fh.write(f"# GRT report [S] {d}: overflowed gcells {t[0]} of {ng:.0f}, sum capacity {t[1]} usage {t[2]} "
                         f"overflow {t[3]} (mean cap {t[1]/max(t[0],1):.1f}, usage {t[2]/max(t[0],1):.1f})\n")
            fh.write("# class | bits in window | H mm | %capH | V mm | %capV | H ovf share % | V ovf share %\n")
            cl = {c for (ww, c, _, _) in wl if ww == w}
            totH = sum(v for (ww, c, d, _), v in wl.items() if ww == w and d == "H")
            totV = sum(v for (ww, c, d, _), v in wl.items() if ww == w and d == "V")
            oH = sum(v for (ww, d, c), v in ovf.items() if ww == w and d == "H") or 1
            oV = sum(v for (ww, d, c), v in ovf.items() if ww == w and d == "V") or 1
            rows = []
            for c in cl:
                h = sum(v for (ww, cc, d, _), v in wl.items() if ww == w and cc == c and d == "H")
                v_ = sum(v for (ww, cc, d, _), v in wl.items() if ww == w and cc == c and d == "V")
                rows.append((h + v_, c, h, v_))
            for _, c, h, v_ in sorted(rows, reverse=True):
                fh.write(f"{c:48s} | {len(bits_in[(w, c)]):7d} | {h/1e3:8.1f} | {100*h/capH:5.1f} | {v_/1e3:8.1f} | "
                         f"{100*v_/capV:5.1f} | {100*ovf[(w,'H',c)]/oH:5.1f} | {100*ovf[(w,'V',c)]/oV:5.1f}\n")
            fh.write(f"{'TOTAL':48s} | {'':7s} | {totH/1e3:8.1f} | {100*totH/capH:5.1f} | {totV/1e3:8.1f} | {100*totV/capV:5.1f}\n")
            fh.write("# per layer mm: " + " ".join(f"{L} {sum(v for (ww,c,d,LL),v in wl.items() if ww==w and LL==L)/1e3:.0f}"
                                                for L in sorted(HL | VL)) + "\n")
    with open(os.path.join(out, "cuts.txt"), "w") as fh:
        fh.write("# cut line | class | nets crossing | segments crossing (= tracks used) ; capacity = tracks across the "
                 "line on the 3 perpendicular-crossing layers (10 per 3 um per layer, OBS-reduced) [E]\n")
        for i, (name, o, pos, (lo, hi)) in enumerate(CUTS):
            Ls = HL if o == "V" else VL
            cap = 0.0
            for L in Ls:
                blocked = 0.0
                for (n, m, bx0, by0, bx1, by1) in box:
                    if o == "V" and bx0 < pos < bx1:
                        blocked += max(0.0, min(by1, hi) - max(by0, lo)) * obs.get(m, {}).get(L, 0.0)
                    if o == "H" and by0 < pos < by1:
                        blocked += max(0.0, min(bx1, hi) - max(bx0, lo)) * obs.get(m, {}).get(L, 0.0)
                cap += (hi - lo - blocked) * TPL / GC
            tot = sum(v for (j, c), v in cut.items() if j == i)
            fh.write(f"CUT {name}: capacity {cap:.0f} tracks, used {tot} ({100*tot/cap:.0f} %)\n")
            for c, v in sorted(((c, v) for (j, c), v in cut.items() if j == i), key=lambda t: -t[1])[:12]:
                fh.write(f"    {c:48s} {len(cutn[(i, c)]):7d} {v:7d}\n")
    # rotator horizontal span (south window) per root net, in lane pitches (195 um)
    with open(os.path.join(out, "rot_span.txt"), "w") as fh:
        fh.write("# per root net H wire inside the south window, in lane pitches of 195 um (lane l under column l/2):\n")
        for c in ("S-read rotator (s_q -> act)", "write-back rotators (f_y/w_y/b2 -> S/map wr)", "S macro Q (s_mq)",
                  "rq_r -> s_rd/w_r mux", "S write regs -> S macro (s_wd/wa/wm)"):
            v = [h for (r, cc), h in hspan.items() if cc == c]
            hb = Counter(min(int(h / 195.0), 16) for h in v)
            fh.write(f"#   H wire of nets spanning >= 1 lane: {sum(h for h in v if h >= 195)/1e3:.1f} mm, < 1 lane: "
                     f"{sum(h for h in v if h < 195)/1e3:.1f} mm\n")
            fh.write(f"{c:48s} nets {len(v):6d} H {sum(v)/1e3:7.1f} mm mean {sum(v)/max(len(v),1):6.0f} um | "
                     + " ".join(f"{k}:{hb[k]}" for k in sorted(hb)) + "\n")
    with open(os.path.join(out, "whole_die.txt"), "w") as fh:
        fh.write("# whole die: class | H mm | V mm | WL-weighted centroid x y (um) of H+V wire\n")
        tot = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0, 0.0])
        for (c, d), g in glob.items():
            t = tot[c]; t[0 if d == "H" else 1] += g[0]; t[2] += g[1]; t[3] += g[2]
        for c, t in sorted(tot.items(), key=lambda kv: -(kv[1][0] + kv[1][1])):
            w = t[0] + t[1]
            fh.write(f"{c:48s} {t[0]/1e3:9.1f} {t[1]/1e3:9.1f} {t[2]/w:7.0f} {t[3]/w:7.0f}\n")
        fh.write("# rotator H wire (mm) by comb depth from the source (S macro QA / block f_y,w_y,b2; -1 = not reached):\n")
        for (cc, d, reg), v in sorted(dwl.items()):
            fh.write(f"DEPTH {cc[:22]:22s} d{d} {reg:5s} {v/1e3:8.1f}\n")
    with open(os.path.join(out, "meta.txt"), "w") as fh:
        fh.write(f"guide layers {dict(layers)}\nguide nets not in dump {unk}\nroots {len(roots)} nets {len(nets)}\n")
    print("R7A done")


if __name__ == "__main__":
    main()
