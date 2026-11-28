#!/usr/bin/env python3
"""One machine verdict of a block run from its files alone (R92; run through signoff/verdict.sh, which supplies the
sign-off corners of the one corner table).  One line per gate, 'GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>'
(FAIL: the evidence shows a violation or a stale file; MISSING: the evidence was never produced), a VERDICT line
naming the gates that did not pass, and the last line 'SIGNOFF <top> PASS|FAIL'; exit status 1 on FAIL.  Only PASS
passes: a missing file or count, or a file older than what it was made from, can never sign off.
The criteria of the tools' own gates are not repeated here: PrimeTime log evidence = common/env.sh qb_pt -check,
ICC2 step logs = common/env.sh qb_icc2 -check, Calibre results = signoff/calibre/cal.sh check, ETM scan =
signoff/etm/etmcheck.py.
The block's committed flow knob defaults (-k: its BLK_KNOBS line of run.sh knobs in an empty environment, common/env.sh
qb_committed_knobs) are what the Calibre deck edits / add-ons must be; -b names the block (its LVS source calibre/<blk>_src.spi).
Opt-in gates (OPT_IN: the column's act feedthrough gates) are checked when the block declares them (-g, its run.sh
BLK_GATES) and also whenever the run has their evidence, so a block that has them cannot pass without them.
usage: verdict.py <run dir> <top> <flow dir> -b <blk> -k <committed BLK_KNOBS line> [-g <gate,...>] <corner> ..."""
import hashlib, os, re, subprocess, sys
run, top, flow = sys.argv[1:4]; corners = sys.argv[4:]; opt = {}
while corners[:1] in (['-b'], ['-k'], ['-g']) and len(corners) > 1: opt[corners[0]] = corners[1]; corners = corners[2:]
if '-b' not in opt or not opt.get('-k', '').startswith('BLK_KNOBS %s knobs ' % opt['-b']):
    sys.exit('usage: verdict.py <run dir> <top> <flow dir> -b <blk> -k <BLK_KNOBS <blk> knobs ... line> [-g <gate,...>] <corner> ...')
blk = opt['-b']; KNOBS = dict(w.split('=', 1) for w in opt['-k'].split()[6:])
OPT_IN = ('act_noise', 'abstract_abutment')
optin = set(opt.get('-g', '').split(',')) - {''}
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
def icc2_log(step, done, sub=''):   # common/env.sh qb_icc2 -check of <sub>/<step>.log: exit status, '^Error' lines, the tool's
    log = os.path.join(sub, step + '.log')   # error count, done marker; and the exact marker line <done> (the label it is of)
    if not have(log): return None, 'no ' + log
    rc, out = sh('. %s/common/env.sh; qb_icc2 -check %s %s' % (flow, os.path.join(run, sub), step))
    l = last(out, 'ICC2_STEP '); d = done in text(log).splitlines()
    return rc == 0 and bool(l) and d, '%s: %s; "%s" %d' % (log, l or out.strip()[-160:], done, d)
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
      'unannotated_pin_to_pin unconstrained_endpoints unclocked_inputs unclocked_register_pins loops unexpected_disabled_arcs floating_nets '
      'noise noise_undriven_ports noise_undriven_pins').split()
PT_OPT = ('act_noise', 'act_noise_unanalysed')   # (opt-in act_noise: gated when declared or logged)
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
    # (act_noise_unanalysed, R100: the act load pins on nets with an aggressor that PrimeTime gave no bump; without it the
    # act_noise count was over 0 analysed pins in 6 of 9 corners of r94 / r97)
    for k in PT + [k for k in PT_OPT if 'act_noise' in optin or 'act_noise' in v]:
        gate(k, c, v[k] == ['0'] if k in v else None,
             'violators %s%s' % (' '.join(v[k]), '; ' + last(text(txt), k + ' ') if last(text(txt), k + ' ') else '') if k in v else 'no QB_PT_SIGNOFF %s count in %s' % (k, log))
    # (R107; hunt round 11 on d1978e1: a QB_PT_SIGNOFF count of a new key, e.g. from a block hook, was never gated) every
    # key the session logged is a known one, until a new one is added to PT / PT_OPT deliberately
    unk = sorted(set(v) - set(PT) - set(PT_OPT))
    gate('pt_signoff_keys', c, not unk if v else None, ('QB_PT_SIGNOFF keys not gated here: ' + ', '.join('%s %s' % (k, ' '.join(v[k])) for k in unk))
         if unk else '%d keys, all gated' % len(v) if v else 'no QB_PT_SIGNOFF line in ' + log)
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
    done = ('QB_ETM_DONE %s' % c) in et.splitlines(); bad = len(re.findall(r'MEXT-6\)|\(MEXT-80\)|MEXT-81|MEXT-97', et))
    gate('etm_log', c, ok and done and not bad if ok is not None else None, '%s; QB_ETM_DONE %d; MEXT-6/80/81/97 lines %d' % (l, done, bad))
    db = lib[:-4] + '_lib.db'
    rc, out = sh('%s -I %s/signoff/etm/etmcheck.py %s' % (sys.executable, flow, lib)) if have(lib) else (None, '')
    gate('etmcheck', c, rc == 0 and have(db) if have(lib) else None, '%s; %s %d' % (last(out, 'ETMCHECK %s ' % lib) or out.strip()[-160:] or 'no ' + lib, db, have(db)))
    # (the .db in the chain, R104: extract_model writes .lib, then .db, then qb_etm_ref the _ref.txt; before, the .db
    # was only required to exist, so one of an earlier session passed)
    fresh('etm', c, [log, lib, db, lib[:-4] + '_ref.txt'])

# ICC2 gates recorded in summary.txt: dont_use of every step, the name / load gate of every ECO round, the abstract
s = text('summary.txt')
# the label of out/ (common/block.sh blk_out): out/label.txt, and no unfinished label (out/label.new)
label = text('out/label.txt').strip(); pend = text('out/label.new').strip()
# dont_use of the labels out/ was built through (icc2/common.tcl qb_done: "dont_use <label> ..."): init .. route, then the
# ECO labels eco, eco2, ... up to the label of out/; the latest line of each, which must be there (R109; hunt round 12:
# the latest line of every tag counted, so a later round's attempt that never became the label of out/, or a label of an
# earlier layout, could fail or pass a clean label, and a label of the chain without a line passed; R107: one line per tag)
def eco_chain(lab):   # the ECO labels up to lab (route: none); None for a label of no known form
    m = re.match(r'^eco(\d*)$', lab)
    return [] if lab == 'route' else None if not m else ['eco'] + ['eco%d' % k for k in range(2, int(m.group(1) or 1) + 1)]
chain = eco_chain(label)
du = dict((l.split()[1], l) for l in s.splitlines() if l.startswith('dont_use ') and len(l.split()) > 1)
want = ['init', 'floorplan', 'place', 'cts', 'route'] + (chain or [])
du_bad = ['%s: %s' % (k, du[k] if k in du else 'no line') for k in want if k not in du or not zeros(du[k], ('usable', 'design_cells'))]
gate('dont_use_icc2', '-', not du_bad if chain is not None else None,
     ('labels %s, latest line each; %s' % (' '.join(want), ' | '.join(du_bad) or du['route'])) if chain is not None else
     'label of out/ %s is not route / eco<n>' % (label or 'missing'))
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
# (route and the ECO label of out/, R107: hunt round 11 on d1978e1, nothing checked legality after route_opt / the fillers,
# and the verdict read place / cts only; the ECO round's line is its legality after place_eco_cells, icc2/eco.tcl)
# (R111; hunt round 13 on 1940fd4) every ECO label of out/'s chain, not only the label of out/: its line after
# place_eco_cells (pnr_legality_eco) and its "<label>_filled" line after route_eco + the refill (pnr_legality_eco_filled)
LEG = r'^%s check_legality: total (\S+) violations, cell overlaps (\S+), unplaced cells (\S+), verdict (\S+)$'
def legal(m): return m.groups() == ('0', '0', '0', 'succeeded')
for st in ('place', 'cts', 'route'):
    pnr('pnr_legality_' + st, st + ' check_legality: total / cell overlaps / unplaced cells / verdict', LEG % st, legal)
for name, suf in ((('eco', ''), ('eco_filled', '_filled')) if label != 'route' else ()):
    ls = [(lab + suf, list(re.finditer(LEG % re.escape(lab + suf), s, re.M))) for lab in chain or []]
    bad = ['%s: %s' % (st, m[-1].group(0) if m else 'no "%s check_legality" line' % st) for st, m in ls if not m or not legal(m[-1])]
    gate('pnr_legality_' + name, '-', not bad if chain else None, '; '.join(bad) or ' | '.join(m[-1].group(0) for _, m in ls) if chain else
         'label of out/ %s is not eco<n>' % (label or 'missing'))
for name, lab in [('pnr_route_gate', 'route')] + ([('pnr_eco_gate', label or 'eco')] if label != 'route' else []):
    pnr(name, lab + ' gate: ... closure pass(es): PASS|FAIL', r'^%s gate: check_routes .*; check_lvs .* closure pass\(es\): (PASS|FAIL.*)$' % re.escape(lab),
        lambda m: m.group(1) == 'PASS')
# PG connectivity of route and of the ECO label of out/ (R109, icc2/common.tcl qb_pg_connect)
for name, lab in [('pnr_pg_route', 'route')] + ([('pnr_pg_eco', label or 'eco')] if label != 'route' else []):
    pnr(name, lab + ' pg_connectivity: ... PASS|FAIL', r'^%s pg_connectivity: .*: (PASS|FAIL.*)$' % re.escape(lab), lambda m: m.group(1) == 'PASS')
for k in ('lef', 'obs', 'abutment', 'pg_pins'):
    l = last(s, 'abstract %s ' % k)
    if k == 'abutment' and not l and 'abstract_abutment' not in optin: continue   # opt-in (icc2/abstract.tcl P(ABUT_PAIR))
    n = re.findall(r'\b(?:bad|missing) (-?\d+)', l)
    gate('abstract_' + k, '-', set(n) == {'0'} if l else None, l or 'no "abstract %s" line in summary.txt' % k)
# The ICC2 step logs of out/'s label chain (R111; hunt round 13 on 1940fd4: only the abstract's was checked, and an
# ICC2 step saves its label (qb_done) before qb_icc2 judges the step, so a step that failed on an error under redirect,
# seen only in its QB_ICC2_MSG count, left a label that the next steps built on): init .. route in the run dir, the ICC2
# eco step of each ECO label of the chain from its round record out/eco/<label>/ (common/block.sh blk_eco), the outputs
# and extract of the label of out/ (their done marker names it), the abstract (its label: abstract_label below).
# Gate icc2_log, "corner" = the step or ECO label.
for c, st, done, sub in ([(x, x, 'QB_ICC2_DONE ' + x, '') for x in ('init', 'floorplan', 'place', 'cts', 'route')] +
                         [(x, 'eco', 'QB_ICC2_DONE ' + x, 'out/eco/' + x) for x in chain or []] +
                         [(x, x, 'QB_ICC2_DONE %s label %s' % (x, label), '') for x in ('outputs', 'extract')] +
                         [('abstract', 'abstract', 'QB_ICC2_DONE abstract', '')]):
    gate('icc2_log', c, *icc2_log(st, done, sub))
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
# (the fill chain, R104: out GDS -> Calibre's dummy metal DM.gds -> merged metal-filled GDS -> dummy OD / PO DODPO.gds ->
# merged GDS of LVS / DRC / antenna; before, DM.gds, which fill_def.py reads, was in no chain)
g = ['out/%s.gds' % top, 'calibre/fill/DM.gds', 'calibre/fill/%s_fill.gds' % top, 'calibre/odpo/DODPO.gds', 'calibre/odpo/%s_fill.gds' % top]
# (lvs_erc: the ERC of the LVS run, cal.sh check erc on its summary and signoff/calibre/erc_allow.txt)
for name, mode, d, dm in (('lvs', 'lvs', 'lvs', 'lvs'), ('lvs_erc', 'erc', 'lvs', 'lvs'), ('drc', 'drc', 'drcb', 'drc'), ('antenna', 'ant', 'ant', 'ant')):
    deck = 'calibre/%s/deck.%s' % (d, dm)
    rc, out = sh('bash %s/cal.sh check %s %s %s/calibre/%s' % (cal, mode, top, run, d))
    res = last(out, 'CAL36_RESULT '); fails = [x for x in out.splitlines() if x.startswith('CAL36_FAIL')]
    gate(name, '-', rc == 0 and ' PASS ' in res if have(deck) else None, ' | '.join([res] + fails))
    # (lvs: the extracted layout netlist svdb/<top>.sp, which cal.sh lvs_ports reads, between the deck copy and the report, R104)
    fresh('gds_fill_' + name, '-', g + [deck] + (['calibre/lvs/svdb/%s.sp' % top, 'calibre/lvs/lvs.rep'] if mode == 'lvs' else
                                        [named(deck, 'ERC SUMMARY REPORT' if mode == 'erc' else 'DRC SUMMARY REPORT')]))
qb = lambda t: set(re.findall(r'^(QB_[A-Za-z0-9_.]*) *\{', t, re.M))
want = qb(open('%s/drc_blk.sed' % cal).read()); got = qb(text('calibre/drcb/deck.drc'))
gate('drc_qb_rules', '-', bool(want) and want <= got if have('calibre/drcb/deck.drc') else None, 'block deck gate rules %s, in the deck copy %s' % (sorted(want), sorted(got)))
fresh('gds_fill_def', '-', g[:2] + ['out/%s_fill.def' % top])
# the deck copies (R106): per mode the edits / add-ons cal.sh applied (its deck_edits.txt, not older than the deck copy) =
# the block's committed defaults (-k; fill / odpo: and the run's chip window calibre/die_window.sed, four VARIABLE lines),
# and the layout the deck reads (every LAYOUT PATH / LAYOUT PRIMARY line) = the input of that mode in the chain above
def path_is(p, rel): return os.path.realpath(p) == os.path.realpath(os.path.join(run, rel))
def deck_lines(deck, key): return re.findall(r'^%s\s+"(.*?)"' % key, text(deck), re.M)
win = 'calibre/die_window.sed'
WIN = re.compile(r'^s#\^VARIABLE (xLB|yLB|xRT|yRT) \.\*#VARIABLE \1 -?[0-9.]+#$')
# (its sed lines; R109: + one "#@expect" line of each result, which cal.sh check deck holds against the deck copy)
wl = [l for l in text(win).splitlines() if not l.startswith('#@expect ')]
win_ok = sorted(m.group(1) if m else '' for m in map(WIN.match, wl)) == ['xLB', 'xRT', 'yLB', 'yRT'] and \
    len([l for l in text(win).splitlines() if l.startswith('#@expect ^VARIABLE ')]) == 4
for mode, sub, layout, edits in (('fill', 'fill', g[0], {'QB55_FILL_SED': 'BLK_FILL_SED', 'QB55_WINDOW': win}),
                                 ('odpo', 'odpo', g[2], {'QB77_ODPO_SED': 'BLK_ODPO_SED', 'QB55_WINDOW': win}),
                                 ('lvs', 'lvs', g[4], {'QB36_LVS_SED': 'BLK_LVS_SED', 'QB36_LVS_EXTRA': 'QB36_LVS_EXTRA', 'QB36_HCELL': 'QB36_HCELL'}),
                                 ('drc', 'drcb', g[4], {'QB36_DRC_SED': 'BLK_DRC_SED'}), ('ant', 'ant', g[4], {'QB36_ANT_SED': 'BLK_ANT_SED'})):
    deck, rec = 'calibre/%s/deck.%s' % (sub, mode), 'calibre/%s/deck_edits.txt' % sub
    if not have(deck): gate('deck_' + mode, '-', None, 'no ' + deck); continue
    w = text(rec).split(); got = dict(x.split('=', 1) for x in w[2:] if '=' in x)
    bad = ['%s %s (committed %s)' % (v, got.get(v, 'missing'), KNOBS.get(k, 'none')) for v, k in edits.items()
           if k != win and got.get(v) != KNOBS.get(k)]
    if win in edits.values() and not (path_is(got.get('QB55_WINDOW', ''), win) and win_ok): bad.append('QB55_WINDOW %s (the run\'s %s, 4 VARIABLE lines: %s)' % (got.get('QB55_WINDOW', 'missing'), win, win_ok))
    if w[:2] != ['deck_edits', mode] or set(got) != set(edits): bad.append('%s: %s' % (rec, ' '.join(w[:2] + sorted(got)) if w else 'none'))
    elif os.path.getmtime(os.path.join(run, rec)) < os.path.getmtime(os.path.join(run, deck)): bad.append('%s older than %s' % (rec, deck))
    lp, pr = deck_lines(deck, 'LAYOUT PATH'), deck_lines(deck, 'LAYOUT PRIMARY')
    if not lp or not all(path_is(x, layout) for x in lp) or set(pr) != {top}: bad.append('LAYOUT PATH %s PRIMARY %s (want %s, %s)' % (lp, pr, layout, top))
    # (R109) the edits took effect: every #@expect / #@absent line of the recorded sed files holds in the deck copy
    rc, out = sh('bash %s/cal.sh check deck %s %s/calibre/%s' % (cal, top, run, sub))
    if rc != 0: bad.append(last(out, 'CAL_DECK ') or out.strip()[-160:])
    gate('deck_' + mode, '-', not bad, '; '.join(bad) or '%s = committed defaults; LAYOUT %s %s; %s' % (' '.join(w[2:]), layout, top, last(out, 'CAL_DECK ')))
# the LVS source (R106): the deck's SOURCE PATH = the run's calibre/<blk>_src.spi (SOURCE PRIMARY <top>), built from
# out/<top>_pg.v as it is now (signoff/calibre/lvs_src.sh records the md5 of the netlist it read)
src, srec = 'calibre/%s_src.spi' % blk, 'calibre/%s_src.inputs.txt' % blk
sp, spr = deck_lines('calibre/lvs/deck.lvs', 'SOURCE PATH'), deck_lines('calibre/lvs/deck.lvs', 'SOURCE PRIMARY')
pg = 'out/%s_pg.v' % top
md5 = hashlib.md5(open(os.path.join(run, pg), 'rb').read()).hexdigest() if have(pg) else 'none'
r = [l.split() for l in text(srec).splitlines() if l.strip()]
bad = ([] if sp and all(path_is(x, src) for x in sp) and set(spr) == {top} else ['SOURCE PATH %s PRIMARY %s (want %s, %s)' % (sp, spr, src, top)]) + \
      ([] if len(r) == 1 and len(r[0]) == 4 and r[0][0] == 'input' and path_is(r[0][1], pg) and r[0][2:] == ['md5', md5] else
       ['%s %s (want one line: input %s md5 %s)' % (srec, ' | '.join(' '.join(x) for x in r) or 'none', pg, md5)])
gate('lvs_source_netlist', '-', not bad if have('calibre/lvs/deck.lvs') else None, '; '.join(bad) or '%s from %s md5 %s' % (src, pg, md5))
fresh('lvs_source', '-', [pg, named('calibre/lvs/deck.lvs', 'SOURCE PATH'), srec, 'calibre/lvs/lvs.rep'])

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
