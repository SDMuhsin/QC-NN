#!/usr/bin/env python3
"""Post-process a morty pickle: morty -p only renames the design units reachable from --top;
other units that live in the same source files (e.g. axi_*_intf, tc_clk_*) are emitted with
their original names and would clash with chimera's own copies. Rename every remaining
module/interface/package/program declared in the pickle (and all references to it)."""
import re, sys
src, dst, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(src).read()
decl = re.compile(r'^\s*(?:module|interface|package|program)\s+(?:automatic\s+|static\s+)?([A-Za-z_]\w*)', re.M)
names = sorted({n for n in decl.findall(txt) if not n.startswith(prefix)})
if names:
    pat = re.compile(r'\b(' + '|'.join(map(re.escape, names)) + r')\b')
    txt = pat.sub(lambda m: prefix + m.group(1), txt)
# Chisel emits some small modules (ram_8x64, DataPathExtension_{Mux,Demux}_W512) in both the
# streamer and the xDMA output files: keep the first copy, drop later ones if they are identical
# modulo comments (fail otherwise).
blk = re.compile(r'^module\s+(\w+)\b.*?^endmodule\b[^\n]*\n', re.M | re.S)
strip = lambda b: re.sub(r'\s+', ' ', re.sub(r'//[^\n]*', '', b))
seen, out, pos, dropped = {}, [], 0, []
for m in blk.finditer(txt):
    n, b = m.group(1), m.group(0)
    if n in seen:
        assert strip(seen[n]) == strip(b), f"functionally different duplicate module {n}"
        out.append(txt[pos:m.start()]); pos = m.end(); dropped.append(n)
    else:
        seen[n] = b
out.append(txt[pos:]); txt = ''.join(out)
left = [n for n in decl.findall(txt) if not n.startswith(prefix)]
assert not left, left
open(dst, 'w').write(txt)
print(f"{dst}: renamed {len(names)} leftover units: {' '.join(names)}; dropped duplicate copies: {' '.join(dropped)}")
