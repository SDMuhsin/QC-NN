#!/usr/bin/env python3
"""Fastest clock-to-Q of a liberty's flip-flops (R77, results/r77.md): the minimum arrival of a signal launched by any
upstream register, the period-independent min (hold) input delay of a block (blocks/col/io_budget.tcl qb5_min_in).
    python3 -I lib_tcq.py <lib.lib> [dont_use glob ...]
Flops = cells with an ff group (latches, clock gates: no ff group) whose name matches no dont_use glob (site.tcl
QC_DONT_USE: an upstream block cannot use them either).  Arcs = timing groups of an output pin with timing_type
rising_edge / falling_edge (clock -> Q; clear / preset arcs excluded).  Value = the smallest entry of their cell_rise /
cell_fall tables: the lowest input slew and load the library characterises, a lower bound on any instance's delay.
Prints "<tcq_ns> <cell> <pin> <related_pin> <timing_type> <flops>" (time_unit converted to ns); error if no flop arc."""
import fnmatch
import re
import sys

lib, globs = sys.argv[1], sys.argv[2:]
GRP = re.compile(r'^\s*(\w+)\s*\(\s*"?([^")]*)"?\s*\)\s*\{')
ATT = re.compile(r'^\s*(\w+)\s*:\s*"?([^";]*)"?\s*;')
NUM = re.compile(r'-?[0-9]*\.?[0-9]+(?:[eE][+-]?\d+)?')
scale = 1.0
stack = []                      # open groups: (name, arg)
cell = pin = None
is_ff = out = False
tim = {}                        # current timing group: related_pin, timing_type, vmin
arcs = []                       # (value, pin, related_pin, timing_type) of the current cell
best = None
nflop = 0
invals = False
for s in open(lib, errors='replace'):
    if invals:                  # continuation lines of a values ( ... ) statement of cell_rise / cell_fall
        for v in NUM.findall(s.replace('\\', ' ')):
            tim['vmin'] = min(tim.get('vmin', 1e30), float(v))
        invals = ');' not in s
        continue
    m = GRP.match(s)
    if m:
        g, a = m.group(1), m.group(2).strip()
        stack.append((g, a))
        if g == 'cell':
            cell, is_ff, arcs = a, False, []
        elif g in ('ff', 'ff_bank'):
            is_ff = True
        elif g == 'pin' and len(stack) >= 2 and stack[-2][0] == 'cell':
            pin, out = a, False
        elif g == 'timing':
            tim = {}
        if s.count('}') >= s.count('{'):   # one-line group "name (a) { ... }"
            stack.pop()
        continue
    if stack and stack[-1][0] in ('cell_rise', 'cell_fall') and s.lstrip().startswith('values'):
        for v in NUM.findall(s.split('(', 1)[1].replace('\\', ' ')):
            tim['vmin'] = min(tim.get('vmin', 1e30), float(v))
        invals = ');' not in s
        continue
    m = ATT.match(s)
    if m:
        k, v = m.group(1), m.group(2).strip()
        if k == 'time_unit' and not stack[1:]:
            u = re.match(r'([0-9.]+)\s*(ns|ps)', v)
            scale = float(u.group(1)) * (1e-3 if u.group(2) == 'ps' else 1.0)
        elif k == 'direction' and stack and stack[-1][0] == 'pin':
            out = v == 'output'
        elif k in ('related_pin', 'timing_type') and stack and stack[-1][0] == 'timing':
            tim[k] = v
        continue
    for _ in range(s.count('}')):
        if not stack:
            break
        g, a = stack.pop()
        if g == 'timing' and out and tim.get('timing_type') in ('rising_edge', 'falling_edge') and 'vmin' in tim:
            arcs.append((tim['vmin'] * scale, pin, tim.get('related_pin', '?'), tim['timing_type']))
        elif g == 'cell':
            if is_ff and not any(fnmatch.fnmatchcase(cell, p) for p in globs) and arcs:
                nflop += 1
                c = min(arcs)
                if best is None or c[0] < best[0]:
                    best = (c[0], cell) + c[1:]
if best is None:
    sys.exit(f'lib_tcq: no flip-flop clock -> Q arc in {lib}')
print('%.5f %s %s %s %s %d' % (best + (nflop,)))
