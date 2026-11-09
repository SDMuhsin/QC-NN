#!/usr/bin/env python3
"""Flatten a hierarchical SAIF (VCS, qa_tb/dut/<module instances>/nets) for a flat (P&R) netlist.

    saif_flat.py <in.saif> <scope=qa_tb/dut> > <out.saif>

OpenROAD writes the routed netlist flat: hierarchical names become single names with '/' inside (u_array/u_pe_3/x).
Every NET entry below <scope> is re-emitted directly under <scope> with its instance path prefixed and the divider
escaped (u_array\\/u_pe_3\\/x), so PrimeTime's read_saif -strip_path <scope> matches the flat net names.  Nets of
the same physical wire at several hierarchy levels are all kept (PT annotates the name the netlist uses).
Prints the number of instances and nets to stderr.
"""
import re
import sys

src, scope = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "qa_tb/dut").split("/")
text = re.sub(r"/\*.*?\*/", "", open(src).read(), flags=re.S)
tok = re.compile(r"\(|\)|\"[^\"]*\"|(?:\\.|[^\s()\\])+")
toks = tok.findall(text)
out = sys.stdout
i, n = 0, len(toks)
# header: everything at depth 1 before the first INSTANCE
assert toks[0] == "(" and toks[1] == "SAIFILE"
i = 2
header = []
while i < n:
    if toks[i] == "(" and toks[i + 1] == "INSTANCE":
        break
    if toks[i] == "(":            # copy one balanced item
        d, j = 0, i
        while True:
            if toks[j] == "(":
                d += 1
            elif toks[j] == ")":
                d -= 1
            j += 1
            if d == 0:
                break
        header.append(" ".join(toks[i:j]).replace("( ", "(").replace(" )", ")"))
        i = j
    else:
        i += 1
nets = []
inst_path = []          # instance names from the root
stack = []              # kinds: INSTANCE, NET, net, other
ninst = 0
while i < n:
    t = toks[i]
    if t == "(":
        k = toks[i + 1]
        if stack and stack[-1] == "NET":
            # one net entry: capture to the matching ')'
            d, j = 0, i
            while True:
                if toks[j] == "(":
                    d += 1
                elif toks[j] == ")":
                    d -= 1
                j += 1
                if d == 0:
                    break
            p = inst_path[len(scope):]
            if inst_path[:len(scope)] == scope:
                name = "".join(x + "\\/" for x in p) + k
                body = " ".join(toks[i + 2:j - 1]).replace("( ", "(").replace(" )", ")")
                nets.append(f"         ({name}\n            {body}\n         )")
            i = j
            continue
        if k == "INSTANCE":
            inst_path.append(toks[i + 2]); stack.append("INSTANCE"); ninst += 1; i += 3; continue
        if k == "NET":
            stack.append("NET"); i += 2; continue
        stack.append("other"); i += 2; continue
    if t == ")":
        if not stack:
            break
        s = stack.pop()
        if s == "INSTANCE":
            inst_path.pop()
    i += 1
out.write("(SAIFILE\n" + "\n".join(header) + "\n")
ind = ""
for s in scope:
    out.write(f"{ind}(INSTANCE {s}\n"); ind += "   "
out.write(f"{ind}(NET\n" + "\n".join(nets) + f"\n{ind})\n")
for _ in scope:
    ind = ind[:-3]; out.write(f"{ind})\n")
out.write(")\n")
print(f"saif_flat: {ninst} instances, {len(nets)} nets under {'/'.join(scope)}", file=sys.stderr)
