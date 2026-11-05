#!/usr/bin/env python3
"""Static check of the undriven implicit nets that vopt reports in the DC netlist (vopt-2958).
Each such net is connected to an input port bit of a submodule instance. The net is harmless (Z
on a bit nobody reads) iff that port bit has no load inside the submodule, i.e. the bit (or the
whole bus) is not referenced except in the port list and the declaration.
  undriven_check.py <netlist.v> <vsim run.log>      (Python >= 3.6, run on the host)
Prints: nets checked, nets whose port bit is loaded (must be 0), nets not resolved (the instance
connection is a concatenation whose element widths could not all be derived).
"""
import collections
import re
import sys

V, LOG = sys.argv[1], sys.argv[2]
src = open(V).read()
off = [0]
for line in src.split("\n"):
    off.append(off[-1] + len(line) + 1)
undriven = collections.defaultdict(set)   # netlist line -> nets
for m in re.finditer(r"\.v\((\d+)\): \(vopt-2958\) Implicit wire .(net\d+). does not", open(LOG).read()):
    undriven[int(m.group(1))].add(m.group(2))

DECL = re.compile(r"^\s*(?:input|output|wire|inout)\s+(\[(\d+):(\d+)\]\s+)?([^;]+);", re.M)
bodies, widths = {}, {}


def module_text(start):
    return src[start:src.find("endmodule", start)]


def body(mod):
    if mod not in bodies:
        a = src.find("module %s (" % mod)
        bodies[mod] = module_text(a) if a >= 0 else ""      # "" = leaf cell
    return bodies[mod]


def decl_widths(text):
    d = {}
    for m in DECL.finditer(text):
        w = abs(int(m.group(2)) - int(m.group(3))) + 1 if m.group(1) else 1
        for n in m.group(4).split(","):
            d[n.strip()] = w
    return d


def elem_width(x, parent):
    m = re.match(r"^(\d+)'[bhd]", x)
    if m:
        return int(m.group(1))
    m = re.match(r"^\S+?\[(\d+):(\d+)\]$", x)
    if m:
        return abs(int(m.group(1)) - int(m.group(2))) + 1
    if re.match(r"^\S+\[\d+\]$", x):
        return 1
    return parent.get(x, 1)


checked = loaded = unresolved = 0
examples = []
for ln, nets in undriven.items():
    pos = off[ln - 1]
    stmt = src[src.rfind(";", 0, pos) + 1:src.find(";", pos)]
    mod = re.match(r"\s*(\S+)", stmt).group(1)
    pstart = src.rfind("\nmodule ", 0, pos) + 1
    if pstart not in widths:
        widths[pstart] = decl_widths(module_text(pstart))
    b = body(mod)
    child = decl_widths(b) if b else {}
    for port, expr in re.findall(r"\.(\w+)\(((?:[^()]|\([^()]*\))*)\)", stmt):
        e = expr.strip()
        els = [x.strip() for x in e[1:-1].split(",")] if e.startswith("{") else [e]
        if not nets & set(els):
            continue
        W = child.get(port, 1)
        whole = len(re.findall(r"(?<![.\w])%s(?![\w\[])" % port, b)) > 2   # bus used as a whole
        bit, hits, n = W, [], 0
        for x in els:
            bit -= elem_width(x, widths[pstart])
            if x in nets:
                n += 1
                if W > 1:
                    k = len(re.findall(r"(?<![.\w])%s\[%d\]" % (port, bit), b)) + (1 if whole else 0)
                else:
                    k = len(re.findall(r"(?<![.\w])%s(?!\w)" % port, b)) - 2
                if k > 0:
                    hits.append((mod[:60], port, bit))
        if bit != 0:
            unresolved += n
            continue
        checked += n
        loaded += len(hits)
        examples += hits
print(f"undriven nets {sum(len(v) for v in undriven.values())}: checked {checked}, "
      f"loaded {loaded}, not resolved {unresolved}")
for x in examples[:15]:
    print("  loaded:", x)
