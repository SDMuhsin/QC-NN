#!/usr/bin/env python3
"""Summarise one kernel run: self-check verdict, error stats and cycle counts.

Cycle counts come from the upstream trace post-processing (util/trace/gen_trace.py),
which splits each hart's trace into regions at every `mcycle` CSR read. Kernels
bracket their compute phases with snrt_mcycle(), so the regions listed in
--regions (indices into hart 0's region list) are the measured kernel phases.
"""
import argparse
import csv
import glob
import json
import os


def load_perf(run):
    perf = {}
    for f in sorted(glob.glob(os.path.join(run, 'logs', 'hart_*_perf.json'))):
        hart = int(os.path.basename(f).split('_')[1])
        with open(f) as fh:
            perf[hart] = json.load(fh)
    return perf


def error_stats(run):
    path = os.path.join(run, 'results.csv')
    if not os.path.exists(path):
        return None
    n, max_abs, max_rel = 0, 0.0, 0.0
    with open(path) as fh:
        for row in csv.DictReader(fh):
            exp, err = abs(float(row['expected'])), float(row['error'])
            n += 1
            max_abs = max(max_abs, err)
            if exp:
                max_rel = max(max_rel, err / exp)
    return n, max_abs, max_rel


def main():
    ap = argparse.ArgumentParser()
    for a in ('kernel', 'sim', 'cfg', 'params', 'run'):
        ap.add_argument('--' + a, required=True)
    ap.add_argument('--rc', type=int, required=True)
    ap.add_argument('--regions', default='', help='comma-separated hart-0 region indices')
    args = ap.parse_args()

    sims = {'vlt': 'Verilator 5.044 (local)', 'vsim': 'Questa 2022.1_2 (tau)'}
    print(f'kernel     : {args.kernel}')
    print(f'simulator  : {sims.get(args.sim, args.sim)}')
    print(f'cluster cfg: sim/cfg/{args.cfg}.hjson')
    with open(args.params) as fh:
        params = ' '.join(l.strip() for l in fh if not l.strip().startswith('//'))
    print(f'params     : {params}')
    print(f'self-check : {"PASS" if args.rc == 0 else "FAIL (rc=%d)" % args.rc}')
    stats = error_stats(args.run)
    if stats:
        print(f'checked    : {stats[0]} outputs, max abs err {stats[1]:.3e}, '
              f'max rel err {stats[2]:.3e}')

    perf = load_perf(args.run)
    if not perf:
        print('cycles     : n/a (no traces)')
        return
    end = max(r['tend'] for regs in perf.values() for r in regs)
    print(f'cycles     : {int(end)} total (last instruction retired, any hart)')
    h0 = perf[min(perf)]
    sel = [int(i) for i in args.regions.split(',') if i.strip()]
    if sel:
        k = sum(h0[i]['cycles'] for i in sel if i < len(h0))
        print(f'cycles     : {k} kernel (hart 0 regions {args.regions})')
    print('\nhart 0 regions (split at mcycle reads):')
    print(f'{"idx":>4} {"tstart":>8} {"tend":>8} {"cycles":>8} {"ipc":>6} {"fpu_occ":>8}')
    for i, r in enumerate(h0):
        mark = ' *' if i in sel else ''
        print(f'{i:>4} {int(r["tstart"]):>8} {int(r["tend"]):>8} {r["cycles"]:>8} '
              f'{r.get("total_ipc", 0):>6.3f} {r.get("fpss_fpu_occupancy", 0):>8.3f}{mark}')
    if sel:
        print('(* = kernel compute regions)')


if __name__ == '__main__':
    main()
