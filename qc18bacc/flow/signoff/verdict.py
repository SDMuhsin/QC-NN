#!/usr/bin/env python3
"""One machine verdict of a block run from its files alone (R92; run through signoff/verdict.sh, which supplies the
sign-off corners of the one corner table).  One line per gate, 'GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>'
(FAIL: the evidence shows a violation or a stale file; MISSING: the evidence was never produced), a VERDICT line
naming the gates that did not pass, and the last line 'SIGNOFF <top> PASS|FAIL'; exit status 1 on FAIL.  Only PASS
passes: a missing file or count, or a file older than what it was made from, can never sign off.
The criteria of the tools' own gates are not repeated here: PrimeTime log evidence = common/env.sh qb_pt -check,
Calibre results = signoff/calibre/cal.sh check, ETM scan = signoff/etm/etmcheck.py.
Opt-in gates (OPT_IN: the column's act feedthrough gates) are checked when the block declares them (-g, its run.sh
BLK_GATES) and also whenever the run has their evidence, so a block that has them cannot pass without them.
usage: verdict.py <run dir> <top> <flow dir> [-g <gate,...>] <corner> ..."""
import os, re, subprocess, sys
run, top, flow = sys.argv[1:4]; corners = sys.argv[4:]
OPT_IN = ('act_noise', 'abstract_abutment')
optin = set(corners[1].split(',')) - {''} if corners[:1] == ['-g'] else set()
corners = corners[2:] if corners[:1] == ['-g'] else corners
if optin - set(OPT_IN): sys.exit('verdict.py: unknown opt-in gate(s) %s (known: %s)' % (sorted(optin - set(OPT_IN)), ' '.join(OPT_IN)))
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

# PrimeTime sign-off per corner: one QB_PT_SIGNOFF count per check (signoff/pt/common.tcl, blk.tcl), each 0, and
# the clock latency file of the chip top = the session's own QB_PT_LAT line (gate clk_lat)
# (noise is judged on the block's noise state: noise_undriven_ports / noise_undriven_pins = port-driven nets / driver pins
# without a holding model in it; opt-in act_noise = the column's act load pins on the QB5_FT driver, signoff/pt/col_blk.tcl;
# their summary line as evidence)
PT = ('setup hold recovery removal max_transition max_capacitance clock_max_transition min_pulse_width min_period '
      'unannotated_pin_to_pin unconstrained_endpoints unclocked_register_pins loops unexpected_disabled_arcs floating_nets '
      'noise noise_undriven_ports noise_undriven_pins').split()
# sign-off limits (R99): the committed values, common/limits.txt (of the flow under test), against the session's
# QB_PT_LIMITS line (signoff/pt/blk.tcl: the values in force); an environment override of any of them fails
def num(x):   # a number, or the text itself (which then differs from any committed value)
    try: return float(x)
    except ValueError: return x
def limits_of(t):
    v = {}
    for l in t.splitlines():
        l = l.split('#')[0].split()
        if l: v[l[0]] = num(l[1])
    return v
LIMITS = limits_of(open('%s/common/limits.txt' % flow).read())
for c in corners:
    log, txt, spef, lib = 'pt_blk_%s.log' % c, 'pt_blk_%s.txt' % c, 'out/%s_%s_pt.spef.gz' % (top, c), 'out/etm/%s_%s.lib' % (top, c)
    gate('pt_log', c, *pt_log(log))
    l = last(text(log), 'QB_PT_LIMITS ').split()[1:]
    used = dict((k, num(x)) for k, x in zip(l[0::2], l[1::2])) if len(l) % 2 == 0 else {}
    diff = ['%s %s (committed %s)' % (k, used.get(k, 'missing'), LIMITS.get(k, 'none')) for k in sorted(set(LIMITS) | set(used)) if used.get(k) != LIMITS.get(k)]
    gate('limits', c, not diff if l else None, ('differ from common/limits.txt: ' + ', '.join(diff)) if diff and l else
         ' '.join(l) if l else 'no QB_PT_LIMITS line in ' + log)
    v = {}
    for l in text(log).splitlines():
        if l.startswith('QB_PT_SIGNOFF '):
            t = l.split()[1:]
            for k, x in zip(t[0::2], t[1::2]): v.setdefault(k, []).append(x)
    for k in PT + [k for k in ('act_noise',) if k in optin or k in v]:
        gate(k, c, v[k] == ['0'] if k in v else None,
             'violators %s%s' % (' '.join(v[k]), '; ' + last(text(txt), k + ' ') if last(text(txt), k + ' ') else '') if k in v else 'no QB_PT_SIGNOFF %s count in %s' % (k, log))
    # the chip top's clock latency (signoff/pt/common.tcl qb_pt_lat): out/clk_lat_<c>.txt holds the "p50 min max" this
    # sign-off session logged as written (a later setup-only or foreign session must not have replaced them)
    lf = 'out/clk_lat_%s.txt' % c; got = text(lf).split()
    m = [x for x in (re.match(r'QB_PT_LAT %s L (\S+) min (\S+) max (\S+) .* written to %s$' % (re.escape(c), re.escape(lf)), l)
                     for l in text(log).splitlines()) if x]
    gate('clk_lat', c, got == list(m[-1].groups()) if m and have(lf) else None,
         '%s "%s", %s logged "%s"' % (lf, ' '.join(got) if have(lf) else 'missing', log, ' '.join(m[-1].groups()) if m else
                                      'no QB_PT_LAT %s ... written to %s line' % (c, lf)))
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
    gate('etmcheck', c, rc == 0 and db if have(lib) else None, '%s; %s_lib.db %d' % (last(out, 'ETMCHECK %s ' % lib) or out.strip()[-160:] or 'no ' + lib, lib[:-4], db))
    fresh('etm', c, [log, lib, lib[:-4] + '_ref.txt'])

# ICC2 gates recorded in summary.txt: dont_use of every step, the name / load gate of every ECO round, the abstract
s = text('summary.txt')
du = [l for l in s.splitlines() if l.startswith('dont_use ')]
gate('dont_use_icc2', '-', all(zeros(l, ('usable', 'design_cells')) for l in du) if du else None, '%d step lines; %s' % (len(du), du[-1] if du else 'none in summary.txt'))
# the label of out/ (common/block.sh blk_out): out/label.txt, and no unfinished label (out/label.new)
label = text('out/label.txt').strip(); pend = text('out/label.new').strip()
gate('out_label', '-', bool(label) and not pend, 'out/label.txt %s, out/label.new %s' % (label or 'missing', pend or 'none'))
# the name / load gate of the ECO round that built the label of out/ (icc2/eco.tcl "<label> eco names ..."): its latest
# line only (a failed earlier attempt of that round, or an earlier round, is not the layout of out/)
en = [l for l in s.splitlines() if label and l.startswith('%s eco names ' % label)]
if label == 'route': gate('eco_names', '-', True, 'label of out/ = route (no ECO round)')
else: gate('eco_names', '-', zeros(en[-1], ('missing', 'load_mismatch', 'record_mismatch', 'unparsed')) if en else None,
           en[-1] if en else 'no "%s eco names" line in summary.txt (label of out/ = %s)' % (label, label or 'missing'))
# place-and-route gates (icc2/common.tcl qb_track_check, qb_legality, qb_route_close; the last ECO round's route gate under
# the label of out/): a database made before a gate existed has no line, which is MISSING
def pnr(name, what, rx, ok):   # the last line in the gate's own format; an older record of the same step is not the gate
    m = list(re.finditer(rx, s, re.M))
    gate(name, '-', bool(ok(m[-1])) if m else None, m[-1].group(0) if m else 'no "%s" gate line in summary.txt' % what)
pnr('pnr_tracks', 'floorplan tracks ok|FAIL', r'^floorplan tracks (\S+) row_origin .*$', lambda m: m.group(1) == 'ok')
for st in ('place', 'cts'):
    pnr('pnr_legality_' + st, st + ' check_legality: total / cell overlaps / unplaced cells / verdict',
        r'^%s check_legality: total (\S+) violations, cell overlaps (\S+), unplaced cells (\S+), verdict (\S+)$' % st,
        lambda m: m.groups() == ('0', '0', '0', 'succeeded'))
for name, lab in [('pnr_route_gate', 'route')] + ([('pnr_eco_gate', label or 'eco')] if label != 'route' else []):
    pnr(name, lab + ' gate: ... closure pass(es): PASS|FAIL', r'^%s gate: check_routes .*; check_lvs .* closure pass\(es\): (PASS|FAIL.*)$' % re.escape(lab),
        lambda m: m.group(1) == 'PASS')
for k in ('lef', 'obs', 'abutment', 'pg_pins'):
    l = last(s, 'abstract %s ' % k)
    if k == 'abutment' and not l and 'abstract_abutment' not in optin: continue   # opt-in (icc2/abstract.tcl P(ABUT_PAIR))
    n = re.findall(r'\b(?:bad|missing) (-?\d+)', l)
    gate('abstract_' + k, '-', set(n) == {'0'} if l else None, l or 'no "abstract %s" line in summary.txt' % k)
al = text('abstract.log'); ne = len(re.findall(r'^Error', al, re.M))
gate('abstract_log', '-', 'QB_ICC2_DONE abstract' in al and not ne if al else None, 'QB_ICC2_DONE abstract %d, Error lines %d' % ('QB_ICC2_DONE abstract' in al, ne) if al else 'no abstract.log')
# the label the abstract was made from (icc2/abstract.tcl, its last summary line) = the label of out/ (R99)
m = list(re.finditer(r'^abstract label (\S+) done\b.*$', s, re.M))
gate('abstract_label', '-', m[-1].group(1) == label if m else None,
     '%s; out/label.txt %s' % (m[-1].group(0) if m else 'no "abstract label ... done" line in summary.txt', label or 'missing'))
fresh('abstract', '-', ['out/%s.def.gz' % top, 'out/%s.lef' % top])

# Calibre on the filled GDS: cal.sh check (LVS CORRECT; the LVS run's ERC; DRC / antenna 0 results, every QB_ gate rule
# of the deck copy run); the block deck's own gate rules (drc_blk.sed) must be in the deck copy
cal = '%s/signoff/calibre' % flow
def named(deck, key):   # a file the deck copy names (summary report, LVS source): as written if absolute, else in the deck's dir
    m = re.search(r'^%s "(.*?)"' % key, text(deck), re.M)
    return os.path.join(os.path.dirname(deck), m.group(1)) if m else '%s: no %s' % (deck, key)
g = ['out/%s.gds' % top, 'calibre/fill/%s_fill.gds' % top, 'calibre/odpo/%s_fill.gds' % top]
# (lvs_erc: the ERC of the LVS run, cal.sh check erc on its summary and signoff/calibre/erc_allow.txt)
for name, mode, d, dm in (('lvs', 'lvs', 'lvs', 'lvs'), ('lvs_erc', 'erc', 'lvs', 'lvs'), ('drc', 'drc', 'drcb', 'drc'), ('antenna', 'ant', 'ant', 'ant')):
    deck = 'calibre/%s/deck.%s' % (d, dm)
    rc, out = sh('bash %s/cal.sh check %s %s %s/calibre/%s' % (cal, mode, top, run, d))
    res = last(out, 'CAL36_RESULT '); fails = [x for x in out.splitlines() if x.startswith('CAL36_FAIL')]
    gate(name, '-', rc == 0 and ' PASS ' in res if have(deck) else None, ' | '.join([res] + fails))
    fresh('gds_fill_' + name, '-', g + [deck, 'calibre/lvs/lvs.rep' if mode == 'lvs' else
                                        named(deck, 'ERC SUMMARY REPORT' if mode == 'erc' else 'DRC SUMMARY REPORT')])
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
print('VERDICT %s gates %d pass %d fail %d missing %d; FAIL: %s; MISSING: %s; opt-in declared: %s' % (top, len(gates), n['PASS'], n['FAIL'], n['MISSING'], names('FAIL'), names('MISSING'), ' '.join(sorted(optin)) or 'none'))
print('SIGNOFF %s %s' % (top, 'PASS' if ok else 'FAIL'))
sys.exit(0 if ok else 1)
