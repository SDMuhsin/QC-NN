#!/usr/bin/env python3
"""Remove the hardened block module (and every module only it instantiates) from a DC hierarchical netlist, so P&R
links the block instances to the LEF / liberty (ETM) view (results/pnr_pe.md).
usage: strip_blocks.py <in.v> <out.v> <block_module> [<block_module> ...]"""
import re, sys
src, dst, blocks = sys.argv[1], sys.argv[2], set(sys.argv[3:])
text = open(src).read()
mods = {}
for m in re.finditer(r'^module\s+(\S+)\s*\(.*?^endmodule\s*$', text, re.S | re.M):
    mods[m.group(1)] = (m.start(), m.end(), m.group(0))
inst_re = re.compile(r'^\s*(\S+)\s+(\\?\S+)\s*\(', re.M)
children = {n: {r for r, _ in inst_re.findall(body) if r in mods} for n, (_, _, body) in mods.items()}
parents = {n: set() for n in mods}
for p, cs in children.items():
    for c in cs: parents[c].add(p)
drop = set(b for b in blocks if b in mods)
changed = True
while changed:
    changed = False
    for n in mods:
        if n not in drop and parents[n] and parents[n] <= drop:
            drop.add(n); changed = True
out = ''.join(body + '\n' for n, (_, _, body) in sorted(mods.items(), key=lambda kv: kv[1][0]) if n not in drop)
open(dst, 'w').write(out)
print(f'strip_blocks: {len(mods)} modules, dropped {len(drop)} ({", ".join(sorted(blocks))} + sub-modules), kept {len(mods) - len(drop)}')
