"""Stream buffer S macro choice per fused-lane count NL (results/nl_sweep.md), on top of mem_opt.py's enumeration.

  python3 -I qc18bacc/impl/mem/s_nl.py shapes SWEEP...   > list    (shapes not yet in the given sweep files)
  python3 -I qc18bacc/impl/mem/s_nl.py report SWEEP...            (tables + choice per NL, markdown)

S requirement per NL (16-b entries under golden p2; capacity = max S occupancy of the program = 64 x 32 x 32 entries,
the block-6 HQ / HQD / Z int8 slices and the block-6 r / s stream fit beside the block-6 stream, see nl_sweep.md):
  read  NL x 16 b / cycle (drain s_in / r, hm s) and >= 2048 b at one address (block-6 int8 word, r2b);
  write NL x 16 b / cycle (s_out);  NL 128 "cf" variant: read 3072 b = int8 word + b6.c2 wide r (1024 b) conflict-free.
Configurations as mem_opt.configs: N lanes (N x bits >= bandwidth) x k deep x copies; 2P = rf_2p 1R + 1W per macro;
SP 2x cap = single-port double bank (tile parity); SP split = 1x capacity, read / write banks (conditional on the drain
phase / lag, mem.md note 2).  Timing gate as mem_opt (500 MHz tt).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mem_opt as M  # noqa: E402

CAP = 65536 * 16                 # bits
EW = 16                          # entry width
REQ = {  # name: (read b / cycle, write b / cycle)
    "NL 256": (256 * EW, 256 * EW),
    "NL 192": (192 * EW, 192 * EW),
    "NL 128": (128 * EW, 128 * EW),
    "NL 128 cf": (3072, 128 * EW),
}


def cfgs(rd, wr):
    bw = max(rd, wr)
    cs = []
    for g in (1, 2, 4, 8):
        b = EW * g
        rows = lambda b_, n: -(-CAP // (n * b_))
        cs += M.configs(M.TP, bw, rows=rows, bits=[b], note=f"2P g{g}")
        cs += M.configs(M.SP, bw, rows=rows, bits=[b], copies=2, note=f"SP 2x cap g{g}")
        cs += M.configs(M.SP, rd + wr, rows=rows, bits=[b], note=f"SP split g{g}")
    return [c for c in cs if c[4] * c[3] >= 2048]          # int8 word: 2048 b from distinct macros


def table(R, rd, wr):
    rows = []
    for c, m, w, b, n, k, cp, note in cfgs(rd, wr):
        r = R.get(M.key(c, m, w, b))
        if not r:
            continue
        cnt = n * k * cp
        ok = r["tt_cyc"] <= M.TCYC_MAX and r["tt_ta"] <= M.TA_MAX
        bw = "cond" if "split" in note else "yes"
        rows.append((cnt * r["area"], c, m, w, b, n, k, cp, cnt, note, r, ("ok" if ok else "FAIL") + "/" + bw))
    rows.sort(key=lambda x: x[0])
    return rows


def main():
    R = M.read_sweep(sys.argv[2:])
    if sys.argv[1] == "shapes":
        seen = set()
        for rd, wr in REQ.values():
            for c, m, w, b, n, k, cp, _ in cfgs(rd, wr):
                if M.key(c, m, w, b) in R or (c, m, w, b) in seen:
                    continue
                seen.add((c, m, w, b))
                print(f"s{len(seen):03d} {c} {w} {b} {m}")
        return
    for name, (rd, wr) in REQ.items():
        rows = table(R, rd, wr)
        best = next((x for x in rows if x[-1] == "ok/yes"), None)
        print(f"\n### S {name}: {CAP} b, read {rd} b + write {wr} b / cycle\n")
        if best:
            a, c, m, w, b, n, k, cp, cnt, note, r, ok = best
            print(f"CHOICE {name}: {c} {w} x {b} mux {m}, {n} x {k} x {cp} = {cnt} macros, {a / 1e6:.3f} mm2, "
                  f"tt ta {r['tt_ta']:.3f} / tcyc {r['tt_cyc']:.3f}, ss ta {r['ss_ta']:.3f} / tcyc {r['ss_cyc']:.3f}\n")
        print("| total mm2 | um2/bit | compiler | mux | words x bits | lanes x deep x copies = macros | note |"
              " macro um2 (w x h um) | tt ta / tcyc ns | ss ta / tcyc ns | 500 MHz tt / bandwidth |")
        print("|---|---|---|---|---|---|---|---|---|---|---|")
        for a, c, m, w, b, n, k, cp, cnt, note, r, ok in rows[:12]:
            print(f"| {a / 1e6:.3f} | {a / CAP:.2f} | {c} | {m} | {w} x {b} | {n} x {k} x {cp} = {cnt} | {note} | "
                  f"{r['area']:.0f} ({r['w_um']:.0f} x {r['h_um']:.0f}) | {r['tt_ta']:.3f} / {r['tt_cyc']:.3f} | "
                  f"{r['ss_ta']:.3f} / {r['ss_cyc']:.3f} | {ok} |")


if __name__ == "__main__":
    main()
