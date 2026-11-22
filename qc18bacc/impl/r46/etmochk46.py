#!/usr/bin/env python3
"""R46 (results/r46.md): OpenROAD-only copy of a block ETM without timing checks on OUTPUT pins.
    python3 -I etmochk46.py <in.lib> <out.lib>
A block output port that the block also reads internally (qb_act2: d_plane, d_vld, ... -> dsc1) gets setup_* /
hold_* timing groups on the output pin from extract_model (the internal capture flop sees the port net).  In OpenSTA
that pin is then both a check endpoint and a driver vertex, and OpenROAD 2.0-12381 rsz::RepairHold::repairEndHold
reads expanded.path(i + 1) past the end of such a path (null PathRef, SIGSEGV; upstream later stops one vertex short).
The check is internal to the block (its path is clk -> output pin only), so the top repair can buffer nothing for it;
dropping it from the view OpenROAD reads leaves every other path unchanged.  Sign-off (PT) keeps the original ETM.
Every dropped group prints an ETMO46 line; the rest of the file is copied byte for byte."""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
txt = open(src).read()
PINRE = re.compile(r'pin\s*\(\s*"?([^")]+)"?\s*\)\s*\{')
TG = re.compile(r'\ttiming \(\) \{\n(.*?)\t\} /\* end of arc [^\n]*\*/\n', re.S)
TT = re.compile(r'timing_type : (\w+) ;')
DIR = re.compile(r'direction : (\w+) ;')
pins = [(m.start(), m.group(1)) for m in PINRE.finditer(txt)]
out, pos, ndrop, npin = [], 0, 0, set()
for k, (st, name) in enumerate(pins):
    en = pins[k + 1][0] if k + 1 < len(pins) else len(txt)
    seg = txt[st:en]
    d = DIR.search(seg)
    if not d or d.group(1) not in ('output', 'inout'):
        continue
    for m in TG.finditer(seg):
        t = TT.search(m.group(1))
        if t and re.match(r'(setup|hold|non_seq_setup|non_seq_hold|recovery|removal)_', t.group(1)):
            out.append(txt[pos:st + m.start()])
            pos = st + m.end()
            ndrop += 1
            npin.add(name)
            print(f'ETMO46 drop {name} {t.group(1)}')
out.append(txt[pos:])
open(dst, 'w').write(''.join(out))
print(f'ETMO46 {src} -> {dst}: {ndrop} check groups dropped on {len(npin)} output pins')
