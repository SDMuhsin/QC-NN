#!/usr/bin/env python3
"""R45 minimal repro generator: random local-connectivity netlist of kit std cells (mix like the act / hub blocks,
incl. the strong drivers BUFFD16 / CKBD16 / MUX2D4 / INVD16 whose wide M1 output pins carry the Calibre VIA1.R markers).
usage: gen45.py <cell.lef> <out_dir> [n_insts=4000] [seed=1]  -> <out_dir>/t45.v, t45.sdc"""
import sys, random, os
lef, od = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 4000
random.seed(int(sys.argv[4]) if len(sys.argv) > 4 else 1)
MIX = {'DFQD1': 16, 'AOI22D1': 16, 'BUFFD1': 8, 'INVD1': 8, 'ND2D1': 8, 'OAI222D1': 3, 'BUFFD16': 4, 'DFQD4': 3,
       'CKBD16': 3, 'CKBD4': 2, 'MUX2D4': 2, 'AO21D4': 1, 'INVD16': 1, 'AO211D4': 1, 'IOA21D4': 1, 'CKND16': 1,
       'BUFFD8': 1, 'INVD8': 1, 'AOI22D4': 2, 'NR2D1': 3, 'XNR2D1': 2, 'OAI21D1': 2}
pins, cur = {}, None
for line in open(lef):
    t = line.split()
    if not t: continue
    if t[0] == 'MACRO': cur = t[1] if t[1] in MIX else None; pin = None
    elif cur and t[0] == 'PIN': pin = t[1]
    elif cur and pin and t[0] == 'DIRECTION': pins.setdefault(cur, []).append((pin, t[1]))
    elif cur and pin and t[0] == 'USE' and t[1] in ('POWER', 'GROUND'): pins[cur] = [p for p in pins[cur] if p[0] != pin]
missing = [m for m in MIX if m not in pins]
assert not missing, missing
cells = random.choices(list(MIX), weights=list(MIX.values()), k=N)
outs = ['in%d' % k for k in range(32)]
lines, used = [], set()
for i, m in enumerate(cells):
    conns = []
    for p, d in pins[m]:
        if d == 'OUTPUT':
            n = 'n%d_%s' % (i, p); conns.append('.%s(%s)' % (p, n)); new = n
        elif p == 'CP':
            conns.append('.CP(clk)')
        else:
            src = random.choice(outs[-60:]); used.add(src); conns.append('.%s(%s)' % (p, src))
    outs.append(new)
    lines.append('  %s u%d (%s);' % (m, i, ', '.join(conns)))
dangling = [o for o in outs[32:] if o not in used]
nets = sorted(set(o for o in outs[32:]))
os.makedirs(od, exist_ok=True)
dset = set(dangling)
with open(od + '/t45.v', 'w') as f:
    f.write('module t45 (clk, %s, %s);\n' % (', '.join('in%d' % k for k in range(32)), ', '.join(dangling)))
    f.write('  input clk;\n' + ''.join('  input in%d;\n' % k for k in range(32)))
    f.write(''.join('  output %s;\n' % n for n in dangling))
    f.write(''.join('  wire %s;\n' % n for n in nets if n not in dset))
    f.write('\n'.join(lines) + '\nendmodule\n')
with open(od + '/t45.sdc', 'w') as f:
    f.write('create_clock -name clk -period 5.0 [get_ports clk]\nset_input_delay 0.5 -clock clk [delete_from_list [all_inputs] [get_ports clk]]\n'
            'set_output_delay 0.5 -clock clk [all_outputs]\n')
print('gen45: %d insts, %d outputs, cells %s' % (N, len(dangling), {m: cells.count(m) for m in MIX}))
