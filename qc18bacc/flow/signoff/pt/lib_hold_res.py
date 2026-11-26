#!/usr/bin/env python3
"""Holding resistance of the constant drivers of a liberty library (R92): the kit's tie cells (TIEL / TIEH) have no timing
arc and no CCS-noise group, so PrimeTime's noise analysis has no driver model for the nets they hold (check_noise:
"none").  What the kit does give is the CCS-power intrinsic_parasitic group: intrinsic_resistance (<rail>) {
related_output : <pin>; value : R; } = the resistance between the output and the rail it is tied to, in the library's
resistance unit.  One line per output pin whose function is the constant 0 or 1 and that has such a value:
    <cell> <pin> <low|high> <R>
(low: function 0, held to ground; high: function 1, held to the supply; several when-states: the largest R).
signoff/pt/common.tcl qb_pt_const_hold gives it to PrimeTime as the pin's steady-state resistance.
usage: lib_hold_res.py <library.lib>"""
import re, sys
cell = None; const = {}; res = {}; pin = None; out = None
def flush():
    for p in sorted(const):
        if p in res: print(cell, p, const[p], '%g' % res[p])
with open(sys.argv[1], errors='replace') as f:
    for l in f:
        s = l.lstrip()
        if s[:1] not in 'cpfirv' or s.startswith('values'): continue     # (table data: most of a CCS library)
        if s.startswith('cell'):
            m = re.match(r'cell\s*\(\s*"?([^")\s]+)"?\s*\)', s)
            if m:
                if cell: flush()
                cell = m.group(1); const = {}; res = {}; pin = None; out = None
        elif s.startswith('pin'):
            m = re.match(r'pin\s*\(\s*"?([^")\s]+)"?\s*\)', s)
            if m: pin = m.group(1)
        elif s.startswith('function'):
            m = re.match(r'function\s*:\s*"\s*([01])\s*"', s)
            if m and pin: const[pin] = 'high' if m.group(1) == '1' else 'low'
        elif s.startswith('intrinsic_resistance'): out = ''
        elif s.startswith('related_output') and out is not None:
            m = re.match(r'related_output\s*:\s*"?([^";\s]+)', s)
            if m: out = m.group(1)
        elif s.startswith('value') and out is not None:
            m = re.match(r'value\s*:\s*"?([-0-9.eE+]+)', s)
            if m and out: res[out] = max(res.get(out, 0.0), float(m.group(1)))
            out = None
if cell: flush()
