#!/usr/bin/env python3
"""Verilator SAIF -> PrimeTime-readable SAIF with DC's flattened generate names (R4 RTL-SAIF power fallback).

    saif_fix.py <in.saif> > <out.saif>

* header: SAIFVERSION / DIRECTION / DESIGN / DATE / VENDOR / PROGRAM_NAME / VERSION / DIVIDER / TIMESCALE / DURATION
  in the order PrimeTime expects (Verilator's header fails read_saif with a syntax error);
* generate scopes (instances named g_*, the repo convention) are folded into their parent the way DC names them
  after change_names: g_q[0] / u_lq -> g_q_0__u_lq, g_r3b / u_seq -> g_r3b_u_seq, nets inside a scope get the same
  prefix (g_dmac / fc[2] -> g_dmac_fc[2]), so the register names match saif_map.ptpx (set_rtl_to_gate_name) and the
  hierarchical cell names of the netlist."""
import re
import sys

src = sys.argv[1]
lines = open(src).read().split("\n")
# header
dur = ts = None
i = 0
while not lines[i].lstrip().startswith("(INSTANCE"):
    m = re.match(r"\(DURATION (\d+)\)", lines[i]); dur = m.group(1) if m else dur
    m = re.match(r"\(TIMESCALE (\d+)\s*(\w+)\)", lines[i]); ts = (m.group(1), m.group(2)) if m else ts
    i += 1


class Node:
    __slots__ = ("name", "nets", "kids")

    def __init__(s, n):
        s.name, s.nets, s.kids = n, [], []


root = None
stack = []
in_net = False
for ln in lines[i:]:
    s = ln.strip()
    if not s:
        continue
    if s.startswith("(INSTANCE"):
        n = Node(s.split()[1])
        if stack:
            stack[-1].kids.append(n)
        else:
            root = n
        stack.append(n); in_net = False
    elif s == "(NET":
        in_net = True
    elif s == ")":
        if in_net:
            in_net = False
        elif stack:
            stack.pop()
    elif in_net and s.startswith("("):
        stack[-1].nets.append(s)


def pfx(name):
    m = re.match(r"^(.*)\[(\d+)\]$", name)
    return f"{m.group(1)}_{m.group(2)}__" if m else name + "_"


def fold(n):
    """returns (nets, kids) of n with its generate-scope children folded in"""
    nets, kids = list(n.nets), []
    for k in n.kids:
        if k.name.startswith("g_"):
            p = pfx(k.name)
            knets, kkids = fold(k)
            nets += ["(" + p + x[1:] for x in knets]
            for kk in kkids:
                kk.name = p + kk.name
                kids.append(kk)
        else:
            kids.append(k)
    return nets, kids


out = sys.stdout
out.write('(SAIFILE\n(SAIFVERSION "2.0")\n(DIRECTION "backward")\n(DESIGN )\n(DATE "R4")\n(VENDOR "Verilator")\n'
          '(PROGRAM_NAME "verilated_saif")\n(VERSION "5.050")\n(DIVIDER / )\n'
          f"(TIMESCALE {ts[0]} {ts[1]})\n(DURATION {dur})\n")


def emit(n, d):
    nets, kids = fold(n)
    ind = " " * d
    out.write(f"{ind}(INSTANCE {n.name}\n")
    if nets:
        out.write(f"{ind} (NET\n")
        for x in nets:
            out.write(f"{ind}  {x}\n")
        out.write(f"{ind} )\n")
    for k in kids:
        emit(k, d + 1)
    out.write(f"{ind})\n")


sys.setrecursionlimit(10000)
emit(root, 1)
out.write(")\n")
