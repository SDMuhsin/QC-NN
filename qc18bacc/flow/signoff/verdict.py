#!/usr/bin/env python3
"""One machine verdict of a block run from its files alone (R92; run through signoff/verdict.sh, which supplies the
sign-off corners of the one corner table).  One line per gate, 'GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>'
(FAIL: the evidence shows a violation or a stale file; MISSING: the evidence was never produced), a VERDICT line
naming the gates that did not pass, and the last line 'SIGNOFF <top> PASS|FAIL'; exit status 1 on FAIL.  Only PASS
passes: a missing file or count, or a file older than what it was made from, can never sign off.
The criteria of the tools' own gates are not repeated here: PrimeTime log evidence = common/env.sh qb_pt -check,
Calibre results = signoff/calibre/cal.sh check, ETM scan = signoff/etm/etmcheck.py.
usage: verdict.py <run dir> <top> <flow dir> <corner> ..."""
import os, re, subprocess, sys
run, top, flow = sys.argv[1:4]; corners = sys.argv[4:]
gates = []
def gate(name, corner, ok, evidence):   # ok: True / False / None (no evidence)
    st = 'MISSING' if ok is None else 'PASS' if ok else 'FAIL'
    gates.append((name, corner, st)); print('GATE %s %s %s %s' % (name, corner, st, evidence))
def have(p): return os.path.isfile(os.path.join(run, p))
def text(p):
    try:
        with open(os.path.join(run, p), errors='replace') as f: return f.read()
    except OSError: return ''
def sh(cmd):
    r = subprocess.run(['bash', '-c', cmd], cwd=run, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return r.returncode, r.stdout
def last(out, key):      # the last line starting with key ('' if none)
    l = [x for x in out.splitlines() if x.startswith(key)]
    return l[-1] if l else ''
def zeros(line, keys):   # None without the line, else: every '<key> N' is there and 0
    return None if not line else all(set(re.findall(r'\b%s (-?\d+)' % k, line)) == {'0'} for k in keys)
def pt_log(log):         # common/env.sh qb_pt -check: completion line, exit status, errors (workers too), coupling annotated
    if not have(log): return None, 'no ' + log
    l = last(sh('. %s/common/env.sh; qb_pt -check %s' % (flow, log))[1], 'PT_ERRORS ')
    return l.endswith(' evidence ok'), l
def fresh(name, corner, chain):   # every file exists and none is older than the one it was made from
    gone = [p for p in chain if not have(p)]
    if gone: return gate('fresh_' + name, corner, None, 'no ' + ', '.join(gone))
    t = [os.path.getmtime(os.path.join(run, p)) for p in chain]
    old = ['%s older than %s' % (b, a) for a, b, x, y in zip(chain, chain[1:], t, t[1:]) if y < x]
    gate('fresh_' + name, corner, not old, ', '.join(old) or ' -> '.join(chain))

# PrimeTime sign-off per corner: one QB_PT_SIGNOFF count per check (signoff/pt/common.tcl, col_blk.tcl), each 0
PT = ('setup hold max_transition max_capacitance clock_max_transition noise min_pulse_width min_period unannotated_pin_to_pin '
      'unconstrained_endpoints unclocked_register_pins loops unexpected_disabled_arcs floating_nets').split()
for c in corners:
    log, txt, spef, lib = 'pt_blk_%s.log' % c, 'pt_blk_%s.txt' % c, 'out/%s_%s_pt.spef.gz' % (top, c), 'out/etm/%s_%s.lib' % (top, c)
    gate('pt_log', c, *pt_log(log))
    v = {}
    for l in text(log).splitlines():
        if l.startswith('QB_PT_SIGNOFF '):
            t = l.split()[1:]
            for k, x in zip(t[0::2], t[1::2]): v.setdefault(k, []).append(x)
    for k in PT:
        gate(k, c, v[k] == ['0'] if k in v else None, 'violators ' + ' '.join(v[k]) if k in v else 'no QB_PT_SIGNOFF %s count in %s' % (k, log))
    m = re.search(r'spef_nets total (\d+) rc_network (\d+) coupled_network (\d+) not_annotated (\d+) \(driverless (\d+) loadless (\d+) pin_to_pin (-?\d+)\)', text(txt))
    n = [int(x) for x in m.groups()] if m else []
    gate('annotation', c, n[0] == n[1] + n[2] + n[3] and n[2] > 0 and n[3] == n[4] + n[5] and n[6] == 0 if m else None,
         m.group(0) if m else 'no spef_nets line in ' + txt)
    l = last(text(txt), 'dont_use post_%s ' % c)
    gate('dont_use', c, zeros(l, ('usable', 'design_cells')), l or 'no dont_use post_%s line in %s' % (c, txt))
    fresh('spef', c, ['out/%s.v' % top, 'out/%s_fill.def' % top, spef])
    fresh('pt', c, [spef, txt, log])
    # ETM of the corner: extraction log evidence + its own markers, the model files, the scan of signoff/etm/etmcheck.py
    e = 'etm_%s.log' % c; et = text(e); ok, l = pt_log(e)
    done = ('QB_ETM_DONE %s' % c) in et.splitlines(); bad = len(re.findall(r'MEXT-6\)|MEXT-81|MEXT-97', et))
    gate('etm_log', c, ok and done and not bad if ok is not None else None, '%s; QB_ETM_DONE %d; MEXT-6/81/97 lines %d' % (l, done, bad))
    db = have(lib[:-4] + '_lib.db')
    rc, out = sh('%s -I %s/signoff/etm/etmcheck.py %s' % (sys.executable, flow, lib)) if have(lib) else (None, '')
    gate('etmcheck', c, rc == 0 and db if have(lib) else None, '%s; %s_lib.db %d' % (last(out, 'ETMCHECK input pins') or out.strip()[-160:] or 'no ' + lib, lib[:-4], db))
    fresh('etm', c, [log, lib])

# ICC2 gates recorded in summary.txt: dont_use of every step, the name / load gate of every ECO round, the abstract
s = text('summary.txt')
du = [l for l in s.splitlines() if l.startswith('dont_use ')]
gate('dont_use_icc2', '-', all(zeros(l, ('usable', 'design_cells')) for l in du) if du else None, '%d step lines; %s' % (len(du), du[-1] if du else 'none in summary.txt'))
label = text('out/label.txt').strip(); en = [l for l in s.splitlines() if l.startswith('eco names ')]
for i, l in enumerate(en):
    gate('eco_names_round%d' % (i + 1), '-', zeros(l, ('missing', 'load_mismatch', 'record_mismatch', 'unparsed')), l)
if not en: gate('eco_names', '-', True if label == 'route' else None, 'no "eco names" line in summary.txt, label of out/ = %s' % (label or 'missing'))
for k in ('lef', 'obs', 'abutment', 'pg_pins'):
    l = last(s, 'abstract %s ' % k); n = re.findall(r'\b(?:bad|missing) (-?\d+)', l)
    gate('abstract_' + k, '-', set(n) == {'0'} if l else None, l or 'no "abstract %s" line in summary.txt' % k)
al = text('abstract.log'); ne = len(re.findall(r'^Error', al, re.M))
gate('abstract_log', '-', 'QB_ICC2_DONE abstract' in al and not ne if al else None, 'QB_ICC2_DONE abstract %d, Error lines %d' % ('QB_ICC2_DONE abstract' in al, ne) if al else 'no abstract.log')
fresh('abstract', '-', ['out/%s.def.gz' % top, 'out/%s.lef' % top])

# Calibre on the filled GDS: cal.sh check (LVS CORRECT; DRC / antenna 0 results, every QB_ gate rule of the deck copy
# run); the block deck's own gate rules (drc_blk.sed) must be in the deck copy
cal = '%s/signoff/calibre' % flow
def named(deck, key):   # a file the deck copy names (summary report, LVS source): as written if absolute, else in the deck's dir
    m = re.search(r'^%s "(.*?)"' % key, text(deck), re.M)
    return os.path.join(os.path.dirname(deck), m.group(1)) if m else '%s: no %s' % (deck, key)
g = ['out/%s.gds' % top, 'calibre/fill/%s_fill.gds' % top, 'calibre/odpo/%s_fill.gds' % top]
for name, mode, d in (('lvs', 'lvs', 'lvs'), ('drc', 'drc', 'drcb'), ('antenna', 'ant', 'ant')):
    deck = 'calibre/%s/deck.%s' % (d, mode)
    rc, out = sh('bash %s/cal.sh check %s %s %s/calibre/%s' % (cal, mode, top, run, d))
    res = last(out, 'CAL36_RESULT '); fails = [x for x in out.splitlines() if x.startswith('CAL36_FAIL')]
    gate(name, '-', rc == 0 and ' PASS ' in res if have(deck) else None, ' | '.join([res] + fails))
    fresh('gds_fill_' + name, '-', g + [deck, 'calibre/lvs/lvs.rep' if mode == 'lvs' else named(deck, 'DRC SUMMARY REPORT')])
qb = lambda t: set(re.findall(r'^(QB_[A-Za-z0-9_.]*) *\{', t, re.M))
want = qb(open('%s/drc_blk.sed' % cal).read()); got = qb(text('calibre/drcb/deck.drc'))
gate('drc_qb_rules', '-', bool(want) and want <= got if have('calibre/drcb/deck.drc') else None, 'block deck gate rules %s, in the deck copy %s' % (sorted(want), sorted(got)))
fresh('gds_fill_def', '-', g[:2] + ['out/%s_fill.def' % top])
fresh('lvs_source', '-', ['out/%s_pg.v' % top, named('calibre/lvs/deck.lvs', 'SOURCE PATH'), 'calibre/lvs/lvs.rep'])

def names(st):   # gate names of one status, corners grouped: noise@ml,ml_rcb
    d = {}
    for n, c, s in gates:
        if s == st: d.setdefault(n, []).append(c)
    return ' '.join(n if c == ['-'] else '%s@%s' % (n, ','.join(c)) for n, c in d.items()) or 'none'
n = {st: sum(s == st for _, _, s in gates) for st in ('PASS', 'FAIL', 'MISSING')}
ok = bool(corners) and n['PASS'] == len(gates)
print('VERDICT %s gates %d pass %d fail %d missing %d; FAIL: %s; MISSING: %s' % (top, len(gates), n['PASS'], n['FAIL'], n['MISSING'], names('FAIL'), names('MISSING')))
print('SIGNOFF %s %s' % (top, 'PASS' if ok else 'FAIL'))
sys.exit(0 if ok else 1)
