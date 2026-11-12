"""Buffer -> macro-configuration enumeration and choice for qc18bacc (macro sweep, results/mem.md).

  python3 -I qc18bacc/impl/mem/mem_opt.py shapes  > qc18bacc/impl/mem/shapes_all.txt   (every shape any config needs)
  python3 -I qc18bacc/impl/mem/mem_opt.py report sweep.txt [...] > qc18bacc/results/mem.md

Legal ranges (probed from the kit generators' own error messages + user guides; see mem.md):
  rf_sp_adv  mux 1: words 8-128 step 2,  bits 8-144, <= 16 kb; mux 2: 16-256 step 4, bits 4-144, <= 32 kb;
             mux 4: 32-512 step 8, bits 2-72, <= 32 kb; bits divisible by 4 / mux
  rf_2p_adv  (1R + 1W port) mux 1: 8-256 step 2, bits 2-144; mux 2: 16-512 step 8, bits 2-144; mux 4: 32-1024 step 32,
             bits 2-72; <= 64 kb
  sram_sp_adv mux 8: 256-8192 step 16, bits 2-144; mux 16: 512-16384 step 32, bits 2-72; mux 32: 1024-32768 step 64,
             bits 2-36
A configuration = lanes N (one access per macro per cycle, so N x bits >= the per-cycle bandwidth) x k macros deep per
lane (depth split; only one of the k is accessed in a cycle) x copies (2 for the 2x-capacity double bank).
Timing gate: 500 MHz at tt: tcyc_tt <= 2.0 ns and ta_tt <= 1.2 ns (the .lib CLK->Q at 0.09 ns slew / 0.07 pF).
"""
import math
import sys

LIM = {  # (compiler, mux): (wmin, wmax, wstep, bmin, bmax, totmax)
    ("rf_sp_adv", 1): (8, 128, 2, 8, 144, 16384), ("rf_sp_adv", 2): (16, 256, 4, 4, 144, 32768),
    ("rf_sp_adv", 4): (32, 512, 8, 2, 72, 32768),
    ("rf_2p_adv", 1): (8, 256, 2, 2, 144, 65536), ("rf_2p_adv", 2): (16, 512, 8, 2, 144, 65536),
    ("rf_2p_adv", 4): (32, 1024, 32, 2, 72, 65536),
    ("sram_sp_adv", 8): (256, 8192, 16, 2, 144, 1 << 20), ("sram_sp_adv", 16): (512, 16384, 32, 2, 72, 1 << 20),
    ("sram_sp_adv", 32): (1024, 32768, 64, 2, 36, 1 << 20),
}
SP = [k for k in LIM if k[0] != "rf_2p_adv"]
TP = [k for k in LIM if k[0] == "rf_2p_adv"]
TCYC_MAX, TA_MAX = 2.0, 1.2


def shape(c, m, rows, b):
    """Smallest legal words >= rows for (c, m, b), or None."""
    wmin, wmax, st, bmin, bmax, tot = LIM[(c, m)]
    if not bmin <= b <= bmax or (c == "rf_sp_adv" and b % (4 // m)):
        return None
    w = max(wmin, -(-rows // st) * st)
    if w > wmax or w * b > tot:
        return None
    return w


def configs(kinds, bw, rows_total_bits=None, rows=None, bits=None, copies=1, note=""):
    """Enumerate (c, m, words, b, N lanes, k deep, copies). rows: words per lane at width b (callable b -> rows)."""
    out = []
    for (c, m) in kinds:
        for b in bits:
            n = -(-bw // b)
            r = rows(b, n)
            for k in range(1, 65):
                w = shape(c, m, -(-r // k), b)
                if w:
                    out.append((c, m, w, b, n, k, copies, note))
                    if k > 1 and len(out) and out[-1][5] == k:
                        pass
                    break
    return out


def buffers():
    B = {}
    # a) weights: 611 rows of 2304 b (8 col x 36 codes); per lane 611 words whatever the width split
    wb = [144, 128, 96, 72, 64, 48, 36, 32]
    B["a_weights"] = dict(desc="611 x 2304 b (1 407 744 b incl. 1x1/stem row padding), 2304 b/cycle", need=611 * 2304,
                          cfg=configs(SP, 2304, rows=lambda b, n: -(-611 * 2304 // (n * b)), bits=wb, note="sp"))
    # b) stream S: g entries per word, 256 R + 256 W entries / cycle, 65536 x 17 b
    cs = []
    for g in (1, 2, 4, 8):
        b = 17 * g
        cs += configs(TP, 256 * 17, rows=lambda b_, n: 65536 * 17 // (n * b_), bits=[b], note=f"2P g{g}")
        cs += configs(SP, 256 * 17, rows=lambda b_, n: 65536 * 17 // (n * b_), bits=[b], copies=2,
                      note=f"SP 2x cap g{g}")
        cs += configs(SP, 512 * 17, rows=lambda b_, n: 65536 * 17 // (n * b_), bits=[b], note=f"SP split g{g}")
    B["b_stream"] = dict(desc="65536 x 17 b, 256 R + 256 W entries / cycle", need=65536 * 17, cfg=cs)
    # c) one binary map (64 kb), 512 b R + W / cycle
    mb = [144, 128, 72, 64, 32]
    cs = configs(TP, 512, rows=lambda b, n: -(-65536 // (n * b)), bits=mb, note="2P")
    cs += configs(SP, 512, rows=lambda b, n: -(-65536 // (n * b)), bits=mb, note="SP R/W shared")
    cs += configs(SP, 1024, rows=lambda b, n: -(-65536 // (n * b)), bits=mb, note="SP split")
    B["c_binmap"] = dict(desc="one 64 kb binary map, 512 b R + 512 b W / cycle", need=65536, cfg=cs)
    # d) params 3904 x 110, >= 110 b / cycle
    cs = configs(SP, 110, rows=lambda b, n: 3904, bits=[110], note="1 ch/cyc")
    cs += configs(SP, 110, rows=lambda b, n: 3904, bits=[55], note="1 ch/cyc")
    cs += configs(SP, 110, rows=lambda b, n: 3904, bits=[28], note="1 ch/cyc")
    cs += configs(SP, 220, rows=lambda b, n: 3904 // 2, bits=[110], note="2 ch/cyc")
    B["d_params"] = dict(desc="3904 x 110 b, >= 1 channel / cycle", need=3904 * 110, cfg=cs)
    # sign(g): 4800 b, 64 b / tile
    cs = configs(SP, 64, rows=lambda b, n: -(-4800 // (n * b)), bits=[64, 32, 16], note="")
    B["d_sign"] = dict(desc="sign(g) 4800 b, 64 b per tile", need=4800, cfg=cs)
    # e) FC 409600 + 3200 b, 512 b / cycle
    cs = configs(SP, 512, rows=lambda b, n: -(-412800 // (n * b)), bits=[144, 128, 72, 64, 32], note="")
    B["e_fc"] = dict(desc="409 600 b int8 + 3 200 b bias, 512 b / cycle", need=412800, cfg=cs)
    # f) image 65536 b at 512 b / cycle (stem row supply) and at 128 b / cycle
    cs = configs(SP, 512, rows=lambda b, n: -(-65536 // (n * b)), bits=[144, 128, 72, 64, 32], note="512 b/cyc")
    cs += configs(SP, 128, rows=lambda b, n: -(-65536 // (n * b)), bits=[128, 64, 32], note="128 b/cyc")
    B["f_image"] = dict(desc="32 x 32 x 8 ch x 8 b = 65536 b", need=65536, cfg=cs)
    return B


def key(c, m, w, b):
    return (c, m, w, b)


def read_sweep(files):
    R = {}
    for f in files:
        for ln in open(f):
            if not ln.startswith("MS ") or "FAIL" in ln:
                continue
            t = ln.split()
            c, w, b, m = t[2], int(t[3]), int(t[4]), int(t[5])
            g = dict(zip(t, t[1:]))
            area = float(g["area_um2"])
            i = t.index("tt")
            tt_ta, tt_cyc, tt_lib = float(t[i + 2]), float(t[i + 3]), float(t[i + 5])
            i = t.index("ss")
            ss_ta, ss_cyc, ss_lib = float(t[i + 2]), float(t[i + 3]), float(t[i + 5])
            R[key(c, m, w, b)] = dict(area=area, w_um=float(g["w_um"]), h_um=float(g["h_um"]), tt_ta=tt_lib,
                                      tt_cyc=tt_cyc, ss_ta=ss_lib, ss_cyc=ss_cyc)
    return R


def main():
    B = buffers()
    if sys.argv[1] == "shapes":
        seen = set()
        for cfgs in (v["cfg"] for v in B.values()):
            for c, m, w, b, n, k, cp, _ in cfgs:
                if (c, m, w, b) in seen:
                    continue
                seen.add((c, m, w, b))
                print(f"q{len(seen):03d} {c} {w} {b} {m}")
        return
    R = read_sweep(sys.argv[2:])
    out = []
    for name, v in B.items():
        rows = []
        for c, m, w, b, n, k, cp, note in v["cfg"]:
            r = R.get(key(c, m, w, b))
            if not r:
                continue
            cnt = n * k * cp
            ok = r["tt_cyc"] <= TCYC_MAX and r["tt_ta"] <= TA_MAX
            bw = "no" if ("shared" in note or "128 b/cyc" in note) else "cond" if "split" in note else "yes"
            ok = ("ok" if ok else "FAIL") + "/" + bw
            rows.append((cnt * r["area"], c, m, w, b, n, k, cp, cnt, note, r, ok))
        rows.sort(key=lambda x: x[0])
        out.append((name, v, rows))
    return out


def report(out):
    p = print
    for name, v, rows in out:
        p(f"\n### {name}: {v['desc']}\n")
        p("| total mm2 | um2/bit (need) | compiler | mux | words x bits | lanes x deep x copies = macros | note |"
          " macro um2 (w x h um) | tt ta / tcyc ns | ss ta / tcyc ns | 500 MHz tt / bandwidth met |")
        p("|---|---|---|---|---|---|---|---|---|---|---|")
        for a, c, m, w, b, n, k, cp, cnt, note, r, ok in rows:
            p(f"| {a / 1e6:.3f} | {a / v['need']:.2f} | {c} | {m} | {w} x {b} | {n} x {k} x {cp} = {cnt} | {note} | "
              f"{r['area']:.0f} ({r['w_um']:.0f} x {r['h_um']:.0f}) | {r['tt_ta']:.3f} / {r['tt_cyc']:.3f} | "
              f"{r['ss_ta']:.3f} / {r['ss_cyc']:.3f} | {ok} |")


if __name__ == "__main__":
    o = main()
    if o:
        report(o)
