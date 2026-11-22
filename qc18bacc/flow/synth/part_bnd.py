#!/usr/bin/env python3
"""R9b: hub boundary table.  Parses the top module of the grouped chip netlist (qb_chip_r9b.v) and the qb_hub port
declarations, maps every hub port bit to the cells on its top-level net, and joins ports_reg.txt (ports.tcl).
    python3 -I bnd.py <qb_chip_r9b.v> <qb_hub.v> <ports_reg.txt> <outprefix>
Out: <out>_bits.txt (port bit, dir, registered, class, column, column pin), <out>_bus.txt (table by class / direction).
Classes: colK.<pin> (column block south / north pins), act (u_act + g_dist), seq, glueN (weight-address / code regs),
glueT (other top glue), host (chip host IO regs g_hpn_* / i_*), io (chip ports), clk / rst."""
import re
import sys
from collections import Counter, defaultdict

vchip, vhub, preg, out = sys.argv[1:5]


def module_text(path, name):
    t, on = [], False
    for ln in open(path):
        if ln.startswith("module " + name + " "):
            on = True
        if on:
            t.append(ln)
            if ln.startswith("endmodule"):
                break
    return "".join(t)


def decls(txt):
    w = {}
    for m in re.finditer(r"^\s*(input|output|wire|inout)\s+(\[(\d+):(\d+)\]\s+)?([^;]+);", txt, re.M):
        for n in m.group(5).split(","):
            n = n.strip()
            if n:
                w[n] = (int(m.group(3)), int(m.group(4))) if m.group(2) else None
    return w


def bits(expr, w):
    expr = expr.strip()
    if expr.startswith("{"):
        r = []
        for part in split_top(expr[1:-1]):
            r += bits(part, w)
        return r
    m = re.match(r"^(\\\S+|[\w$]+)\s*(\[(\d+)(:(\d+))?\])?$", expr)
    if not m:
        return ["CONST"]
    n = m.group(1)
    if m.group(2):
        a = int(m.group(3)); b = int(m.group(5)) if m.group(5) else a
        return ["%s[%d]" % (n, i) for i in (range(a, b - 1, -1) if a >= b else range(a, b + 1))]
    r = w.get(n)
    if r is None:
        return [n]
    a, b = r
    return ["%s[%d]" % (n, i) for i in (range(a, b - 1, -1) if a >= b else range(a, b + 1))]


def split_top(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch == "{":
            d += 1
        elif ch == "}":
            d -= 1
        if ch == "," and d == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


top = module_text(vchip, "qb_chip")
hubm = module_text(vhub, "qb_hub")
wtop, whub = decls(top), decls(hubm)
body = top[top.index(");") + 2:]
net_terms = defaultdict(list)
hub_conn = {}
for st in body.split(";"):
    m = re.match(r"\s*(\S+)\s+(\\\S+|\S+)\s*\((.*)\)\s*$", st, re.S)
    if not m or m.group(1) in ("input", "output", "wire", "assign", "endmodule", "inout"):
        continue
    mas, inst, conns = m.groups()
    for c in re.finditer(r"\.(\\\S+\s|[\w$]+)\s*\(", conns):
        pin = c.group(1).strip()
        i, d = c.end(), 1
        while d:
            d += {"(": 1, ")": -1}.get(conns[i], 0); i += 1
        e = conns[c.end():i - 1]
        if not e.strip():
            continue
        bl = bits(e, wtop)
        if mas == "qb_hub":
            pr = whub.get(pin)
            pb = ["%s[%d]" % (pin, k) for k in (range(pr[0], pr[1] - 1, -1) if pr and pr[0] >= pr[1] else (range(pr[0], pr[1] + 1) if pr else []))] if pr else [pin]
            for p, n in zip(pb, bl):
                hub_conn[p] = n
        elif mas == "qb_col_blk":
            cc = int(re.search(r"g_c_(\d+)__", inst).group(1))
            for k, n in enumerate(bl):
                net_terms[n].append(("col%d" % cc, pin, len(bl) - 1 - k))
        else:
            for n in bl:
                net_terms[n].append((inst, pin, 0))
for m in re.finditer(r"^\s*(input|output)\s+(\[(\d+):(\d+)\]\s+)?([^;]+);", top[:top.index(");") + 2] + top, re.M):
    pass
for n, r in wtop.items():
    pass
ioports = set()
for m in re.finditer(r"^\s*(input|output)\s+(\[(\d+):(\d+)\]\s+)?([^;]+);", top, re.M):
    for n in m.group(5).split(","):
        for b in bits(n.strip(), wtop):
            ioports.add(b)


def cls(inst):
    if inst.startswith("col"):
        return inst
    if re.match(r"u_top_u_act|u_top_g_dist", inst):
        return "act"
    if inst.startswith("u_top_g_r3b_g_rt_u_seq"):
        return "seq"
    if re.match(r"u_top_(cd_r|w_a_q|w_d_q|w_d_m|w_ren_q|ictl|g_wl|g_w_)", inst):
        return "glueN"
    if re.match(r"(g_hpn|i_we|i_sel|i_addr|clk_gate_g_hpn)", inst):
        return "host"
    return "glueT"


reg = {}
for ln in open(preg):
    f = ln.split()
    reg[f[0]] = (f[1], f[2])
rows = []
agg = defaultdict(lambda: [0, 0])
for p, n in hub_conn.items():
    d, r = reg.get(p, reg.get(p.replace("[0]", "") if p.endswith("[0]") else p, ("?", "?")))
    ts = net_terms.get(n, [])
    if p.startswith("clk"):
        c = "clk"
    elif p.startswith("rst_n"):
        c = "rst"
    elif n in ioports and not ts:
        c = "io"
    else:
        cs = sorted({cls(t[0]) if not t[0].startswith("col") else "col" for t in ts})
        c = "+".join(cs) if cs else ("io" if n in ioports else "none")
        if n in ioports:
            c += "+io"
    colpins = sorted({"%s.%s" % (t[0], t[1]) for t in ts if t[0].startswith("col")})
    bus = "col." + "/".join(sorted({t[1] for t in ts if t[0].startswith("col")})) if c.startswith("col") else c
    ncols = len({t[0] for t in ts if t[0].startswith("col")})
    rows.append((p, d, r, c, bus, ncols, ";".join("%s.%s[%d]" % t for t in ts if t[0].startswith("col"))))
    k = (bus, d, "multi-col" if ncols > 1 else "")
    agg[k][0] += 1; agg[k][1] += int(r == "1")
with open(out + "_bits.txt", "w") as f:
    for r in rows:
        f.write(" ".join(str(x) for x in r) + "\n")
with open(out + "_bus.txt", "w") as f:
    f.write("# bus (top-side class) | dir (hub view) | bits | registered on the hub side | %\n")
    for k, v in sorted(agg.items(), key=lambda kv: -kv[1][0]):
        f.write("%-28s %-3s %-9s %6d %6d %5.1f\n" % (k[0], k[1], k[2], v[0], v[1], 100.0 * v[1] / v[0]))
    tot = sum(v[0] for v in agg.values())
    f.write("TOTAL %d port bits, registered %d\n" % (tot, sum(v[1] for v in agg.values())))
print("BND ports mapped %d of %d" % (len(hub_conn), len(reg)))
