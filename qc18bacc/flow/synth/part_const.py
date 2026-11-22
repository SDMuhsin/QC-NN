#!/usr/bin/env python3
"""R9b: DC writes 1'b0 / 1'b1 literals on hierarchical-instance pins after `group` (the original tie nets became
constants at the new boundaries); OpenROAD's Verilog reader drops literal connections (pins left floating, e.g. ICG
TE).  Rewrite every literal as the module's n_Logic0_ / n_Logic1_ net (declared if missing), which the P&R flow ties
(flow/tsmc65/pnr/or/lib.tcl qc_tie_constants).
    python3 -I const.py <in.v> <out.v>"""
import re
import sys

src, dst = sys.argv[1:3]
n = {"0": 0, "1": 0}
mods = 0
with open(src) as fi, open(dst, "w") as fo:
    buf = []
    for ln in fi:
        buf.append(ln)
        if ln.startswith("endmodule"):
            txt = "".join(buf); buf = []
            hdr_end = txt.index(");") + 2
            body = txt[hdr_end:]
            used = set()
            def rep(m):
                used.add(m.group(1)); n[m.group(1)] += 1
                return "n_Logic%s_" % m.group(1)
            body = re.sub(r"1'b([01])", rep, body)
            decl = "".join("  wire n_Logic%s_;\n" % v for v in sorted(used)
                           if not re.search(r"^\s*(wire|input|output)\b[^;]*\bn_Logic%s_\b" % v, body, re.M))
            if used:
                mods += 1
            fo.write(txt[:hdr_end] + "\n" + decl + body.lstrip("\n"))
    fo.write("".join(buf))
print("CONST literals 1'b0 %d 1'b1 %d in %d modules" % (n["0"], n["1"], mods))
