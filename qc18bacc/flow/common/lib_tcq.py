#!/usr/bin/env python3
"""Fastest clock-to-Q of a liberty's flip-flops (R77, results/r77.md): the minimum arrival of a signal launched by any
upstream register, the period-independent min (hold) input delay of a block (blocks/col/io_budget.tcl qb5_min_in).
    python3 -I lib_tcq.py <lib.lib> [dont_use glob ...]
Flops = cells with an ff group (latches, clock gates: no ff group) whose name matches no dont_use glob (site.tcl
QC_DONT_USE: an upstream block cannot use them either).  Arcs = timing groups of an output pin with timing_type
rising_edge / falling_edge (clock -> Q; clear / preset arcs excluded).  Value = the smallest entry of their cell_rise /
cell_fall tables: the lowest input slew and load the library characterises, a lower bound on any instance's delay.
Prints "<tcq_ns> <cell> <pin> <related_pin> <timing_type> <flops>" (time_unit converted to ns); error if no flop arc.
The liberty is read as tokens, not lines (R117; round-17 finding: a statement and a closing brace on one line, e.g.
"values (...); }", left the group open): comments and line continuations removed, then group headers "name (args) {",
complex attributes "name (args) ;", simple attributes "name : value ;" and braces, in text order."""
import fnmatch
import re
import sys

lib, globs = sys.argv[1], sys.argv[2:]
text = re.sub(r'/\*.*?\*/', ' ', open(lib, errors='replace').read(), flags=re.S).replace('\\\n', ' ')
TOK = re.compile(r'(\w+)\s*\(([^()]*)\)\s*([{;])|(\w+)\s*:\s*([^;{}\n]*?)\s*;|([{}])')
NUM = re.compile(r'-?[0-9]*\.?[0-9]+(?:[eE][+-]?\d+)?')
scale = 1.0
stack = []                      # open groups: (name, arg)
cell = pin = None
is_ff = out = False
tim = {}                        # current timing group: related_pin, timing_type, vmin
arcs = []                       # (value, pin, related_pin, timing_type) of the current cell
best = None
nflop = 0
for m in TOK.finditer(text):
    g, a, end, k, v, brace = m.groups()
    if g and end == '{':        # group header
        a = a.strip().strip('"')
        stack.append((g, a))
        if g == 'cell':
            cell, is_ff, arcs = a, False, []
        elif g in ('ff', 'ff_bank'):
            is_ff = True
        elif g == 'pin' and len(stack) >= 2 and stack[-2][0] == 'cell':
            pin, out = a, False
        elif g == 'timing':
            tim = {}
    elif g:                     # complex attribute: the values of a cell_rise / cell_fall table
        if g == 'values' and stack and stack[-1][0] in ('cell_rise', 'cell_fall'):
            for x in NUM.findall(a):
                tim['vmin'] = min(tim.get('vmin', 1e30), float(x))
    elif k:                     # simple attribute
        v = v.strip().strip('"')
        if k == 'time_unit' and not stack[1:]:
            u = re.match(r'([0-9.]+)\s*(ns|ps)', v)
            scale = float(u.group(1)) * (1e-3 if u.group(2) == 'ps' else 1.0)
        elif k == 'direction' and stack and stack[-1][0] == 'pin':
            out = v == 'output'
        elif k in ('related_pin', 'timing_type') and stack and stack[-1][0] == 'timing':
            tim[k] = v
    elif brace == '{':          # a brace without a header of the forms above: kept balanced
        stack.append(('?', ''))
    elif stack:                 # '}'
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
