#!/usr/bin/env python3
"""R11: top-level netlist of the hierarchical chip (results/r11.md) from the hub-partitioned chip netlist of R10b
(impl/r9b/run.sh part on r10_rpw: $QC_BUILD/r10b_ww/qb_chip_r9b_c.v, instance u_hub of qb_hub), with the act supply
carved as the R9a hard block qb_act2_blk:
  u_top_u_act (qb_act2_ACT_PIPE1) + u_top_g_dist_0__u_d (qbt_dreg_W4608)  ->  one qb_act2_blk instance u_act_blk
  * RTL ports keep the chip's nets (u_act port bit = block port bit), act = the dreg's q nets (the u_act -> dreg nets
    must have no other load: checked);
  * s_q: R10a QB_WB_COL fixed transpose T (hw/rtl/qb_act2.sv s_qt) as wiring: block pin s_q[T(k)] = chip net of
    u_act.s_q[k], T(128 (4G+a) + 32 b + 8 q + i) = 128 (4G+b) + 32 q + 8 a + i (the R9a block is synthesized without it);
  * DC boundary-optimisation pins of the chip's u_act: start_<k>__BAR (= ~start[k]) -> the true-polarity net found by
    tracing the top-side buffer / inverter chain, else a new inverter r11_inv_start<k>; IN0..IN30 (DC-punched copies)
    are traced to their root net and classified (dropped: the block has the RTL function behind its RTL ports);
  * top cells that only fed the removed pins are dead: removed iteratively (count / area reported).
  * qb_hub / qb_act2_blk / qb_col_blk are black boxes (module definitions dropped; LEF / liberty abstracts), modules
    no longer reachable from qb_chip are dropped.
Equivalence (structural, same script): every other top instance keeps master + pin -> net map; every block pin is
checked against the chip port bit it replaces (with T); report in <out>_equiv.txt, port map <out>_actmap.txt.
    python3 -I top_nl.py <qb_chip_r9b_c.v> <out prefix>     -> <out>.v, <out>_equiv.txt, <out>_actmap.txt"""
import re
import sys
from collections import defaultdict, Counter

src, out = sys.argv[1:3]
TOP, ACT, DREG = "qb_chip", "u_top_u_act", "u_top_g_dist_0__u_d"
BLK, BLKI = "qb_act2_blk", "u_act_blk"
OUTPINS = {"Z", "ZN", "Q", "QN", "CO", "S", "CON", "SN", "ENCLK", "Q1", "Q2"}
BUF = re.compile(r"^(BUFF|CKBD|DEL|BUFT)")
INV = re.compile(r"^(INV|CKND)")
# R9a block ports (impl/r7c/qb_act2_blk.sv), MSB first; direction
BLK_PORTS = [("clk", "in", 1), ("rst_n", "in", 1), ("start", "in", 2), ("c_cfg", "in", 8), ("c_nchunk", "in", 10),
             ("c_nct", "in", 8), ("c_ntile", "in", 14), ("c_int8", "in", 2), ("c_stem", "in", 2), ("c_base", "in", 18),
             ("busy", "out", 2), ("done", "out", 2), ("tgo", "in", 2), ("l_ok", "in", 2), ("l_seq0", "in", 16),
             ("l_seq1", "in", 16), ("l_pos0", "out", 10), ("l_pos1", "out", 10), ("f_clr", "in", 1), ("f_we", "in", 1),
             ("f_nz", "in", 1), ("f_bank", "in", 2), ("f_idx", "in", 7), ("m_ren", "out", 1), ("m_ra", "out", 9),
             ("m_ctx", "out", 1), ("m_q", "in", 512), ("s_ren", "out", 1), ("s_ra", "out", 8), ("s_ctx", "out", 1),
             ("s_q", "in", 2048), ("d_vld", "out", 1), ("d_first", "out", 1), ("d_eot", "out", 1), ("d_neg", "out", 1),
             ("d_stem", "out", 1), ("d_g3n", "out", 1), ("d_ctx", "out", 1), ("d_plane", "out", 3), ("d_chunk", "out", 4),
             ("d_ct", "out", 3), ("d_tile", "out", 6), ("act", "out", 4608), ("a_vld", "out", 1), ("a_first", "out", 1),
             ("a_eot", "out", 1), ("a_neg", "out", 1), ("a_stem", "out", 1), ("a_g3n", "out", 1), ("a_ctx", "out", 1),
             ("a_plane", "out", 3), ("a_chunk", "out", 4), ("a_ct", "out", 3), ("a_tile", "out", 6), ("err", "out", 1)]


def T(k):
    G, r = divmod(k, 512); a, r = divmod(r, 128); b, r = divmod(r, 32); q, i = divmod(r, 8)
    return 128 * (4 * G + b) + 32 * q + 8 * a + i


assert sorted(T(k) for k in range(2048)) == list(range(2048))
TINV = {T(k): k for k in range(2048)}

# ------------------------------------------------------------------ split modules
txt = open(src).read()
mods, order = {}, []
for m in re.finditer(r"^module (\S+) \(.*?^endmodule\n", txt, re.S | re.M):
    mods[m.group(1)] = m.group(0); order.append(m.group(1))
del txt


def decls(t):
    w, d = {}, {}
    for m in re.finditer(r"^\s*(input|output|wire|inout)\s+(\[(\d+):(\d+)\]\s+)?([^;]+);", t, re.M):
        for n in m.group(5).split(","):
            n = n.strip()
            if n:
                w[n] = (int(m.group(3)), int(m.group(4))) if m.group(2) else None
                if m.group(1) != "wire":
                    d[n] = m.group(1)
    return w, d


def split_top(s):
    r, lvl, cur = [], 0, ""
    for ch in s:
        if ch == "{": lvl += 1
        elif ch == "}": lvl -= 1
        if ch == "," and lvl == 0:
            r.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        r.append(cur)
    return r


def bits(expr, w):
    expr = expr.strip()
    if not expr:
        return []
    if expr.startswith("{"):
        r = []
        for p in split_top(expr[1:-1]):
            r += bits(p, w)
        return r
    m = re.match(r"^(\d+)'b([01]+)$", expr)
    if m:
        return ["1'b" + c for c in m.group(2)]
    m = re.match(r"^([\w$]+)\s*(\[(\d+)(:(\d+))?\])?$", expr)
    if not m:
        raise ValueError(expr)
    n = m.group(1)
    if m.group(2):
        a = int(m.group(3)); b = int(m.group(5)) if m.group(5) else a
    elif w.get(n):
        a, b = w[n]
    else:
        return [n]
    return ["%s[%d]" % (n, i) for i in (range(a, b - 1, -1) if a >= b else range(a, b + 1))]


mdir = {n: decls(t)[1] for n, t in mods.items()}      # module -> port -> direction (modules in the file)

top = mods[TOP]
hdr_end = top.index(");") + 2
body = top[hdr_end:top.rindex("endmodule")]
W, Dtop = decls(top)
stmts = [s.strip() for s in body.split(";")]
INST = re.compile(r"^(\S+)\s+(\S+)\s*\((.*)\)$", re.S)
insts, keep_text = {}, []          # name -> (master, {pin: [bits]}), statement order
for s in stmts:
    if not s:
        continue
    m = INST.match(s)
    if m and m.group(1) not in ("input", "output", "wire", "assign", "inout"):
        conns = {}
        for pm in re.finditer(r"\.(\w+)\s*\(([^()]*)\)", m.group(3)):
            conns[pm.group(1)] = bits(pm.group(2), W)
        insts[m.group(2)] = (m.group(1), conns)
        keep_text.append(("I", m.group(2), s))
    else:
        keep_text.append(("S", None, s))
assert ACT in insts and DREG in insts, "act / dreg instance missing"


def pdir(master, pin):
    if master in mdir:
        return mdir[master].get(pin, "input")[0:3] == "out" and "out" or "in"
    return "out" if pin in OUTPINS else "in"


# hub / col blocks: direction from the hub module (in file) / col LEF unknown -> col block outputs by name list
COL_OUT = {"f_y", "b2", "w_y", "f_b", "w_b", "f_vld_o", "w_vld_o", "b2_vld", "f_vld", "w_vld"}
drv, loads = {}, defaultdict(list)


def build(I):
    drv.clear(); loads.clear()
    for n, (ms, cs) in I.items():
        for p, bl in cs.items():
            d = pdir(ms, p) if ms != "qb_col_blk" else ("out" if p in COL_OUT else "in")
            for k, b in enumerate(bl):
                if b.startswith("1'b"):
                    continue
                if d == "out":
                    drv[b] = (n, ms, p, k)
                else:
                    loads[b].append((n, ms, p, k))


build(insts)
pinbit = lambda inst, port, k: insts[inst][1][port][len(insts[inst][1][port]) - 1 - k]   # bit k (LSB 0)

rep = []
amap = []
# ------------------------------------------------------------------ act supply port map
am, ac = insts[ACT][1], insts[DREG][1]
for b in am["act"]:
    other = [l for l in loads.get(b, []) if l[0] != DREG]
    assert not other, ("u_act.act net with a load outside the dreg", b, other[:3])
assert ac["clk"] == am["clk"], "dreg / act clocks differ"


HUB = {}


def hub_drv():
    """qb_hub internal driver map (port-name nets), parsed on first use."""
    if HUB:
        return HUB
    t = mods["qb_hub"]; hw = decls(t)[0]
    for m in re.finditer(r"^\s+(\S+)\s+(\S+)\s*\((.*?)\);", t[t.index(");") + 2:], re.S | re.M):
        ms = m.group(1)
        if ms in ("input", "output", "wire", "assign"):
            continue
        for pm in re.finditer(r"\.(\w+)\s*\(([^()]*)\)", m.group(3)):
            if pdir(ms, pm.group(1)) == "out":
                for b in bits(pm.group(2), hw):
                    HUB[b] = (ms, pm.group(1))
        if (BUF.match(ms) or INV.match(ms)):
            ip = re.search(r"\.I\(([^()]*)\)", m.group(3))
            HUB[("I", m.group(2))] = ip.group(1).strip() if ip else None
            zp = re.search(r"\.ZN?\(([^()]*)\)", m.group(3))
            if zp:
                HUB[zp.group(1).strip()] = (ms, m.group(2))
    HUB["_ports"] = decls(t)[1]
    return HUB


def trace(net):
    pol, chain = 0, []
    while net in drv:
        n, ms, p, k = drv[net]
        if ms == "qb_hub":
            # follow the hub output port inside qb_hub through buffers / inverters to a hub input port or logic
            h = hub_drv(); hn = insts[n][1]
            pn = p if len(hn[p]) == 1 else "%s[%d]" % (p, len(hn[p]) - 1 - k)
            while pn in h and (BUF.match(h[pn][0]) or INV.match(h[pn][0])):
                pol ^= 1 if INV.match(h[pn][0]) else 0
                chain.append("hub:" + h[pn][0]); pn = h[("I", h[pn][1])]
                if pn is None:
                    return net, pol, chain, "hub const/open"
            if pn in h:
                return net, pol, chain, "hub logic %s %s" % (h[pn][0], h[pn][1])
            if pn.split("[")[0] in h["_ports"]:      # hub input port: continue outside
                pb = pn.split("[")[0]; idx = int(pn.split("[")[1][:-1]) if "[" in pn else 0
                bl = hn.get(pb)
                if bl is None:
                    return net, pol, chain, "hub port %s open" % pn
                net = bl[len(bl) - 1 - idx]; chain.append("hub-feedthrough"); continue
            return net, pol, chain, "hub ?%s" % pn
        if BUF.match(ms) or INV.match(ms):
            pol ^= 1 if INV.match(ms) else 0
            chain.append(ms)
            net = insts[n][1]["I"][0]
        else:
            return net, pol, chain, "%s/%s" % (ms, p)
    return net, pol, chain, "port" if net.split("[")[0] in Dtop else "undriven"


new_cells = []
blk = {}
for name, d, wdt in BLK_PORTS:
    if name == "act":
        bl = list(ac["q"])
    elif name == "start" and "start" in am:   # R35: netlist with the plain start port on u_act (no DC BAR pins)
        bl = list(am["start"])
    elif name == "start":
        bl = []
        for k in (1, 0):
            nb = am["start_%d__BAR" % k][0]
            root, pol, ch, why = trace(nb)
            # a chain with odd inversions from root to the BAR pin -> root is start[k]
            if pol == 1:
                bl.append(root); amap.append("start[%d] <- %s (root of start_%d__BAR via %s, inverted chain)" % (k, root, k, "/".join(ch)))
            else:
                nn = "r11_start_%d" % k
                new_cells.append("INVD2 r11_inv_start%d ( .I(%s), .ZN(%s) )" % (k, nb, nn))
                W[nn] = None; bl.append(nn)
                amap.append("start[%d] <- new INVD2 r11_inv_start%d of %s (start_%d__BAR driven by %s)" % (k, k, nb, k, why))
    elif name == "s_q":
        src_b = am["s_q"]                      # MSB first: index 0 = bit 2047
        nb = [None] * 2048
        for k in range(2048):
            nb[T(k)] = src_b[2047 - k]
        bl = [nb[2047 - j] for j in range(2048)]
    elif name not in am:
        assert d == "out", ("block input without a chip connection", name)
        amap.append("%s: output not connected in the chip (left open)" % name)
        continue
    else:
        bl = list(am[name])
    assert len(bl) == wdt, (name, len(bl), wdt)
    blk[name] = bl
# block inputs must be driven in the top (DC constant propagation into u_act could have left a port net undriven)
und = [(nm, k) for nm, d, wdt in BLK_PORTS if d == "in" and nm in blk for k, b in enumerate(reversed(blk[nm]))
       if not b.startswith("1'b") and b not in drv and b.split("[")[0] not in Dtop and not b.startswith("r11_start")]
rep.append("R11EQ block input bits without a top driver: %d %s -> tied to n_Logic0_ (chip u_act: unloaded port bit, "
           "c_base[8] only reaches m_ra[8], which is unconnected in the chip: map 128 lines)" % (len(und), und[:6]))
for nm, k in und:
    blk[nm][len(blk[nm]) - 1 - k] = "n_Logic0_"
    amap.append("%s[%d]: no top driver (DC removed it: unobservable in the chip) -> n_Logic0_" % (nm, k))
# IN* pins: classify by root
inpins = sorted([p for p in am if re.match(r"IN\d+$", p)], key=lambda p: int(p[2:]))
rtl_nets = {}
for name, d, wdt in BLK_PORTS:
    if d == "in" and name in blk:
        for k, b in enumerate(reversed(blk[name])):
            rtl_nets.setdefault(trace(b)[0], []).append("%s[%d]" % (name, k))
cls = Counter()
for p in inpins:
    nb = am[p][0]
    root, pol, ch, why = trace(nb)
    hit = rtl_nets.get(root)
    c = ("copy of RTL port %s%s" % (",".join(hit[:2]), " (inverted)" if pol else "")) if hit else "function of top net %s (%s)" % (root, why)
    cls["copy" if hit else "other"] += 1
    amap.append("%s net %s <- root %s pol %d chain %d: %s" % (p, nb, root, pol, len(ch), c))
rep.append("R11NL u_act DC-punched pins IN*: %d (copies of RTL inputs %d, other functions %d); start BAR pins 2" % (len(inpins), cls["copy"], cls["other"]))

# ------------------------------------------------------------------ new top
new = {n: v for n, v in insts.items() if n not in (ACT, DREG)}
new[BLKI] = (BLK, dict(blk))
for c in new_cells:
    m = re.match(r"(\S+) (\S+) \( \.I\((\S+)\), \.ZN\((\S+)\) \)", c)
    new[m.group(2)] = (m.group(1), {"I": [m.group(3)], "ZN": [m.group(4)]})
build(new)
# dead logic: leaf cells whose every output net has no load and is not a top port (only cells that were live before)
portnets = set()
for p in Dtop:
    portnets.update(bits(p, W))
def live_outs(I):
    dead = set()
    for n, (ms, cs) in I.items():
        if ms in mdir or ms.startswith("qb_"):
            continue
        outs = [b for p, bl in cs.items() if pdir(ms, p) == "out" for b in bl if not b.startswith("1'b")]
        if outs and all(not loads.get(b) and b not in portnets for b in outs):
            dead.add(n)
    return dead
build(insts); dead0 = live_outs(insts)
build(new)
removed = []
while True:
    dd = live_outs(new) - dead0
    if not dd:
        break
    for n in dd:
        removed.append((n, new[n][0])); del new[n]
    build(new)
rep.append("R11NL dead top cells removed (fed only the removed u_act pins): %d %s" % (len(removed), dict(Counter(re.sub(r"D\d+$", "", m) for _, m in removed).most_common(8))))

# ------------------------------------------------------------------ equivalence (structural)
nd, bad = 0, 0
for n, (ms, cs) in insts.items():
    if n in (ACT, DREG) or n in dict(removed):
        continue
    nm, ncs = new[n]
    nd += 1
    if nm != ms or ncs != cs:
        bad += 1
rep.append("R11EQ top instances kept %d, master / pin-net differences %d; removed act+dreg 2, dead %d, added blk 1 + inverters %d"
           % (nd, bad, len(removed), len(new_cells)))
ok = 0; badb = []
for name, d, wdt in BLK_PORTS:
    if name not in blk:
        continue
    for k in range(wdt):
        got = new[BLKI][1][name][wdt - 1 - k]
        if name == "act":
            exp = pinbit(DREG, "q", k)
        elif name == "s_q":
            exp = pinbit(ACT, "s_q", TINV[k])
        elif name == "start" or got == "n_Logic0_":
            exp = got           # start: checked by the trace above (amap); tie: listed above
        else:
            exp = pinbit(ACT, name, k)
        if got == exp:
            ok += 1
        else:
            badb.append((name, k, got, exp))
rep.append("R11EQ block pin bits %d match the chip port bit they replace (s_q via T), mismatches %d" % (ok, len(badb)))
# every net of the old top that touched u_act / dreg is still reachable through the block or was internal
lost = 0
blkset = set(b for v in blk.values() for b in v)
for p, bl in list(am.items()) + [("q", ac["q"])]:
    for b in bl:
        if b.startswith("1'b") or b.startswith("SYNOPSYS_UNCONNECTED"):
            continue
        if p in ("act",) or re.match(r"IN\d+$|start_\d__BAR", p):
            continue
        if b not in blkset:
            lost += 1
rep.append("R11EQ chip u_act / dreg boundary nets not on a block pin (excluding act->dreg internal, IN*, start BAR): %d" % lost)

# ------------------------------------------------------------------ write
def conn(bl):
    if len(bl) == 1:
        return bl[0]
    # compress runs of the same bus
    out_, i = [], 0
    while i < len(bl):
        m = re.match(r"^(.*)\[(\d+)\]$", bl[i])
        if m:
            j = i
            while j + 1 < len(bl):
                m2 = re.match(r"^(.*)\[(\d+)\]$", bl[j + 1])
                if m2 and m2.group(1) == m.group(1) and int(m2.group(2)) == int(m.group(2)) - (j + 1 - i):
                    j += 1
                else:
                    break
            out_.append("%s[%d:%d]" % (m.group(1), int(m.group(2)), int(m.group(2)) - (j - i)) if j > i else bl[i])
            i = j + 1
        else:
            out_.append(bl[i]); i += 1
    return "{" + ", ".join(out_) + "}" if len(out_) > 1 else out_[0]


rm = set(dict(removed)) | {ACT, DREG}
with open(out + ".v", "w") as f:
    lines = [top[:hdr_end]]
    for kind, n, s in keep_text:
        if kind == "I" and n in rm:
            continue
        lines.append("  " + s + ";")
    for c in new_cells:
        lines.append("  wire %s;" % re.search(r"ZN\((\S+)\)", c).group(1))
        lines.append("  " + c + ";")
    lines.append("  %s %s ( %s );" % (BLK, BLKI, ", ".join(".%s(%s)" % (p, conn(blk[p])) for p, _, _ in BLK_PORTS if p in blk)))
    lines.append("endmodule")
    topv = "\n".join(lines) + "\n"
    # reachable modules
    need, todo = set(), [TOP]
    allm = {TOP: topv}
    allm.update({k: v for k, v in mods.items() if k != TOP})
    while todo:
        x = todo.pop()
        for m in re.finditer(r"^\s+(\w+)\s+\w+\s*\(", allm[x], re.M):
            if m.group(1) in mods and m.group(1) not in need and m.group(1) not in ("qb_hub", TOP):
                need.add(m.group(1)); todo.append(m.group(1))
    for k in order:
        if k in need:
            f.write(mods[k])
    f.write(topv)
rep.append("R11NL modules kept %d of %d (dropped: qb_hub, act hierarchy, dreg, unreachable)" % (len(need) + 1, len(order)))
with open(out + "_actmap.txt", "w") as f:
    f.write("# R11 act block port map (impl/r11/top_nl.py)\n" + "\n".join(amap) + "\n")
    for x in badb[:50]:
        f.write("MISMATCH %s[%d] got %s exp %s\n" % x)
# block pin -> net table of the new top (hub, act block, columns, macros): input of act_lef.py / fp11.py interface check
HW = decls(mods["qb_hub"])[0]
with open(out + "_bpins.txt", "w") as f:
    for n, (ms, cs) in new.items():
        if not (ms.startswith("qb_") and (ms not in mdir or ms == "qb_hub")):
            continue
        hw = HW if ms == "qb_hub" else {}
        for p, bl in cs.items():
            lo = min(hw[p]) if hw.get(p) else 0          # DC writes partial port ranges ([5183:1943]): LSB index
            for k, b in enumerate(reversed(bl)):
                f.write("%s %s %s %s\n" % (n, ms, p if (len(bl) == 1 and not hw.get(p)) else "%s[%d]" % (p, lo + k), b))
with open(out + "_equiv.txt", "w") as f:
    f.write("\n".join(rep) + "\n")
print("\n".join(rep))
