#!/usr/bin/env python3
"""Sanity gate of a block ETM .lib against the netlist reference written in the same PrimeTime session
(signoff/etm/etm.tcl -> signoff/pt/common.tcl qb_etm_ref: <stem>_ref.txt beside <stem>.lib; clock period P, the design
max_transition, each port's netlist capacitance).  Exit 1 on any of:
  values     a table value or index that is not a finite number, an index that is negative or not increasing, a
             transition value <= 0, or any table value (delay, transition, setup / hold / recovery / removal, pulse
             width) with |v| >= P.  Why P: the blocks are single-cycle, so a boundary setup or hold >= P cannot be met by
             any input timing, a clk->out >= P cannot be captured in the next cycle and a slew >= P is no signal: such a
             value is a sign-off failure or garbage (R43's driving-cell outlier: act[2911] hold 7.26 ns at P 6.5 ns).
             R98 [M], why not the former fixed 3 ns: every value beyond 3 ns in the column's r97x ETMs (59 ss, 1230 wcl,
             13 wcl_rcw) is a setup_rising table of an s_rd bit at all 25 index points (wcl max 3.615 ns at data / clk
             slew 0.5 / 0); PrimeTime on the netlist gives the same path s_rd[306] -> register at slack +1.44 ns, data
             delay 4.227 - capture latency 0.751 + library setup 0.039 = 3.515 ns vs the ETM 3.485 at (0.5, 0.5).
             Largest |v| (col P 6.5 / rgr P 2.5): 3.615 / 0.849 ns.
  capacitance  a pin whose capacitance is not the reference's (input: port net total capacitance, output: port net
             wire capacitance, within the 6-decimal rounding), or pin sets that differ.  R98 [M], why not the former
             0.065 pF: the 127-352 r97x pins above it are the act feedthrough inputs (long nets, <= 0.079 pF) and the
             b2 / f_y / b2_vld / f_b / act_o outputs (wire <= 0.216 pF); PrimeTime's port nets equal all 12354 pins.
  max_transition  an input pin without it or with another value than the reference's (R63: the ETM context
             set_input_transition 0 gave 0 on all data inputs; it must be the context slew, signoff/pt/common.tcl
             qb_etm_context).
  no table values, or no reference.
Not detected: a timing table copied from another pin with the same capacitance (a timing comparison against PrimeTime
per port is not exact: R98 [M] 30 ps of 3.5 ns on s_rd[306], derate / slew handling of extract_model).
usage: etmcheck.py <etm.lib>"""
import math, re, sys
src = sys.argv[1]
if not src.endswith('.lib'): sys.exit('etmcheck.py: not a .lib: ' + src)
ref = src[:-4] + '_ref.txt'
CAP_TOL = 1.5e-6   # pF: both files round the same PrimeTime value to 6 decimals
try:
    with open(ref) as f: head, *rows = f.read().splitlines()
    P, MT = (float(x) for x in re.fullmatch(r'QB_ETM_REF period (\S+) max_transition (\S+)', head).groups())
    rcap = {p: float(c) for p, _, c in (r.split() for r in rows)}
except (OSError, ValueError, AttributeError) as e:
    print('ETMCHECK %s FAIL no reference %s (%s)' % (src, ref, e)); sys.exit(1)
t = open(src).read()
def nums(s): return [float(x) for q in re.findall(r'"([^"]*)"', s) for x in q.split(',')]
pins = list(re.finditer(r'\n\s*pin\s*\(\s*"?([^")]+)"?\s*\)\s*\{', t))
bad = {'values': [], 'capacitance': [], 'max_transition': []}; n = 0; vmax = (0.0, ''); seen = set()
def flag(k, what): bad[k].append(what)
for i, m in enumerate(pins):
    p = m.group(1); body = t[m.end():pins[i + 1].start() if i + 1 < len(pins) else len(t)]; seen.add(p)
    d = re.search(r'^\s*direction\s*:\s*"?(\w+)', body, re.M); c = re.search(r'^\s*capacitance\s*:\s*(\S+?)\s*;', body, re.M)
    if p not in rcap: flag('capacitance', p + ' not in the reference')
    elif not c or not abs(float(c.group(1)) - rcap[p]) <= CAP_TOL:
        flag('capacitance', '%s %s vs netlist %.6f' % (p, c.group(1) if c else 'none', rcap[p]))
    if d and d.group(1) == 'input':
        v = re.search(r'^\s*max_transition\s*:\s*(\S+?)\s*;', body, re.M)
        if not v or not abs(float(v.group(1)) - MT) <= 1e-6: flag('max_transition', '%s %s' % (p, v.group(1) if v else 'none'))
    for a in re.finditer(r'timing\s*\(\s*\)\s*\{(.*?)\}\s*/\* end of arc', body, re.S):
        tt = re.search(r'timing_type\s*:\s*(\w+)', a.group(1)).group(1)
        for g, tb in re.findall(r'(\w+)\s*\(\s*\w+\s*\)\s*\{(.*?)\}', a.group(1), re.S):
            w = '%s %s %s' % (p, tt, g)
            for ix in re.findall(r'index_\d\s*\((.*?)\)\s*;', tb, re.S):
                x = nums(ix)
                if not all(math.isfinite(y) and y >= 0 for y in x) or any(b <= a for a, b in zip(x, x[1:])):
                    flag('values', '%s index %s' % (w, ','.join('%g' % y for y in x)))
            v = re.search(r'values\s*\((.*?)\)\s*;', tb, re.S)
            if not v: continue
            x = nums(v.group(1)); n += len(x)
            if not all(math.isfinite(y) and abs(y) < P for y in x) or ('transition' in g and min(x) <= 0):
                flag('values', '%s %s' % (w, max(x, key=lambda y: abs(y) if math.isfinite(y) else math.inf)))
            vmax = max(vmax, (max(abs(y) for y in x), w), key=lambda z: z[0] if math.isfinite(z[0]) else math.inf)
miss = sorted(set(rcap) - seen)
if miss: flag('capacitance', '%d reference ports without a pin (%s)' % (len(miss), ' '.join(miss[:3])))
print('ETMCHECK %s reference %s: period %.3f ns, max_transition %.3f ns, %d ports' % (src, ref, P, MT, len(rcap)))
print('ETMCHECK %d pins, %d table values, largest |value| %.3f ns (%s), limit |value| < period %.3f' % (len(pins), n, vmax[0], vmax[1], P))
for k, l in bad.items(): print('ETMCHECK %-14s %d bad %s' % (k, len(l), '; '.join(l[:3])))
fail = ['%s %d' % (k, len(l)) for k, l in bad.items() if l] + (['no table values'] if not n else [])
print('ETMCHECK %s %s' % (src, 'FAIL ' + ', '.join(fail) if fail else 'PASS'))
sys.exit(1 if fail else 0)
