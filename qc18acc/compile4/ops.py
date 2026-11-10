"""Executed-op count of the QC18-ACC v4 program (ARCH.md v4 addendum "Metric of record: executed ops").

    python3 -m qc18acc.compile4.ops EXPORT_DIR [cycles_per_image] [f_MHz ...]
    python3 -m qc18acc.compile4.ops --writes EXPORT_DIR      (act-buffer words written per image)

ops = 2 x executed MACs.  An 8x8 QC block code has <= 2 nonzero terms; each nonzero term (a signed shifted identity)
is 8 MACs (one per block output row), so a block executes 8 x (nonzero terms) <= 16 MACs, never 64.  A ternary x
int8 MAC counts 1 op pair (MAC = 2 ops), like a 1b x 1b MAC.  The count is read from the weight image (even / odd
halves, as the array consumes it, incl. the stem's codes on its zero-padded input channels) and the descriptors:
per conv pass, H_out W_out x sum over the pass's codes of 8 x nonzero terms (every code is applied once per output
pixel); plus the head FC (dense int8 x uint7, C x ncls MACs).  Peak: every PE applies Kb = 2 blocks of 2 terms per
cycle: PEs x Kb x 16 MACs per cycle.
"""
import sys

import numpy as np

from qc18acc.compile import codes as K
from qc18acc.compile.program import read_program

from .layout import cinp

PES, KB = 128, 2
PEAK_MACS_PER_CYCLE = PES * KB * 16


def hexwords(path):
    return [int(l, 16) for l in open(path) if l.strip() and "x" not in l]


def executed(d):
    desc = np.array(hexwords(f"{d}/desc.hex"), dtype=np.uint32)
    we, wo = (np.array(hexwords(f"{d}/weights_{h}.hex"), dtype=object) for h in "eo")
    prog = read_program(desc)
    rows, tot_terms_px, tot_blocks_px = [], 0, 0
    for p in prog[:-1]:
        S = p.k * p.k * cinp(p.cin8)
        n = p.cout64 * S
        cds = np.concatenate([K.word_codes(K.to_wide([int(x) for x in w[p.wbase:p.wbase + n]])) for w in (we, wo)])
        k, t = K.decode(cds)
        terms = int((t != 0).sum())
        px = p.Hout * p.Wout
        rows.append((p, px, terms, cds.size))
        tot_terms_px += terms * px
        tot_blocks_px += cds.size * px
    h = prog[-1]
    fc = 8 * h.cin8 * h.ncls
    conv_macs = 8 * tot_terms_px
    return dict(rows=rows, conv_macs=conv_macs, fc_macs=fc, macs=conv_macs + fc, block_slots=tot_blocks_px,
                peak_block_macs=16 * tot_blocks_px)


def act_writes(d):
    """128-b activation words written per image (every output word of every pass exactly once; RAW16: 2 byte planes
    per pair).  v4 act macros: one macro write per word."""
    from qc18acc.compile.program import RAW16
    desc = np.array(hexwords(f"{d}/desc.hex"), dtype=np.uint32)
    return sum((8 if p.mode == RAW16 else 4) * p.cout64 * p.Hout * p.Wout for p in read_program(desc)[:-1])


def main():
    if sys.argv[1] == "--writes":
        print(act_writes(sys.argv[2]))
        return
    d = sys.argv[1]
    cyc = int(sys.argv[2]) if len(sys.argv) > 2 else None
    fs = [float(v) for v in sys.argv[3:]] or [400.0]
    e = executed(d)
    print(f"{'pass':5s} {'HxW':>5s} {'codes':>7s} {'terms':>7s} {'terms/code':>10s} {'MACs':>11s}")
    for p, px, terms, ncodes in e["rows"]:
        print(f"{p.k}x{p.k}s{p.stride} {px:5d} {ncodes:7d} {terms:7d} {terms / ncodes:10.3f} {8 * terms * px:11d}")
    print(f"executed MACs / image: conv {e['conv_macs']} + FC {e['fc_macs']} = {e['macs']} "
          f"(ops = {2 * e['macs']}); block slots x pixels {e['block_slots']} (x16 = {e['peak_block_macs']} at 2 terms "
          f"each; executed / that = {e['conv_macs'] / e['peak_block_macs']:.4f})")
    print(f"peak executed MACs / cycle = {PES} PEs x Kb {KB} x 16 = {PEAK_MACS_PER_CYCLE} (ops / cycle {2 * PEAK_MACS_PER_CYCLE})")
    for f in fs:
        line = f"f {f:.1f} MHz: peak {2 * PEAK_MACS_PER_CYCLE * f * 1e6 / 1e12:.3f} executed TOPS"
        if cyc:
            ips = f * 1e6 / cyc
            line += f"; {cyc} cycles / image -> {ips:.0f} img/s, workload-average {2 * e['macs'] * ips / 1e12:.3f} executed TOPS"
        print(line)


if __name__ == "__main__":
    main()
