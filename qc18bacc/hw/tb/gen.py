#!/usr/bin/env python3
"""Random stimulus + bit-exact Python reference for the qc18bacc microblocks (tb_qb_pe.sv, tb_qb_lane.sv).

    python3 -I qc18bacc/hw/tb/gen.py pe --kb 16 --accw 20 --n 200000 --seed 1 --out DIR
    python3 -I qc18bacc/hw/tb/gen.py lane_n|lane_w --n 200000 --seed 1 --out DIR

Writes DIR/stim.txt and DIR/exp.txt (one line per clock cycle; exp = outputs after that cycle's clock edge, with a
'defined' flag).  The references are written from the arithmetic definitions, not from the RTL structure:
  pe:   sum_i = sum_{j, n} t * a_j[(i + k) mod 8] (direct, not the popcount form); acc_i = (first ? 0 : acc_i) +/-
        sum_i * 2^plane mod 2^ACC_W at S2 (edge n+2), capture (shadow <= acc before the update) over shift.
  lane: y = floor((x*m + 2^(sh-1)) / 2^sh); y_sat = clip(y + h + r, -32767, 32767); b = y_sat > T; mode 1: b = x >= T;
        outputs after edge n+3.
"""
import argparse
import os
import random

TRIT = {0: 0, 1: 1, 3: -1, 2: 0}   # code -> trit (10 unused, = 0)
ROT = [[sum(((av >> ((i + k) % 8)) & 1) << (8 * i) for i in range(8)) for k in range(8)] for av in range(256)]


def hx(v, w):
    return format(v & ((1 << w) - 1), "0%dx" % ((w + 3) // 4))


def gen_pe(kb, accw, n, rng, fs, fe):
    M = (1 << accw) - 1
    acc = [None] * 8      # None = undefined (never started by first)
    shd = [None] * 8
    pipe = []             # inputs waiting for S2 (applied at edge n+2)
    seg, seg_left = 0, 0
    for cyc in range(n):
        rst_n = 0 if cyc < 4 else 1
        if seg_left == 0:
            seg = rng.choices([0, 1, 2, 3, 4], [70, 8, 8, 7, 7])[0]
            seg_left = rng.randint(1, 40)
        seg_left -= 1
        a, codes = [], []
        for j in range(kb):
            if seg == 0:
                aj = rng.getrandbits(8)
                ks = (rng.getrandbits(3), rng.getrandbits(3))
                ts = tuple(rng.choices([0, 1, 3, 2], [40, 30, 28, 2])[0] for _ in range(2))
            elif seg == 1:   # max positive: all ones, all +1
                aj, ks, ts = 0xFF, (rng.getrandbits(3), rng.getrandbits(3)), (1, 1)
            elif seg == 2:   # max negative
                aj, ks, ts = 0xFF, (rng.getrandbits(3), rng.getrandbits(3)), (3, 3)
            elif seg == 3:   # sparse activations, -1 heavy
                aj = rng.getrandbits(8) & rng.getrandbits(8) & rng.getrandbits(8)
                ks = (rng.getrandbits(3), rng.getrandbits(3))
                ts = tuple(rng.choices([0, 1, 3], [20, 10, 70])[0] for _ in range(2))
            else:            # dense activations, +1 heavy
                aj = rng.getrandbits(8) | rng.getrandbits(8) | rng.getrandbits(8)
                ks = (rng.getrandbits(3), rng.getrandbits(3))
                ts = tuple(rng.choices([0, 1, 3], [20, 70, 10])[0] for _ in range(2))
            a.append(aj)
            codes.append((ks, ts))
        plane = rng.getrandbits(3)
        neg = int(rng.random() < 0.2)
        valid = int(rng.random() < 0.85) if rst_n else 0
        first = int(rng.random() < 0.12) if rst_n else 0
        cap = int(rng.random() < 0.12) if rst_n else 0
        sft = int(rng.random() < 0.5) if rst_n else 0
        shin = rng.getrandbits(accw)
        A = sum(a[j] << (8 * j) for j in range(kb))
        C = 0
        for j, ((k1, k2), (t1, t2)) in enumerate(codes):
            C |= ((k1 << 7) | (t1 << 5) | (k2 << 2) | t2) << (10 * j)
        ctl = (rst_n << 8) | (plane << 5) | (neg << 4) | (valid << 3) | (first << 2) | (cap << 1) | sft
        fs.write("%s %s %s %s\n" % (hx(A, 8 * kb), hx(C, 10 * kb), hx(ctl, 9), hx(shin, accw)))
        # reference sums (direct definition)
        # (lane i's term count in byte i of P / N: ROT[a][k] has byte i = a[(i + k) mod 8])
        P = N = 0
        for j in range(kb):
            for k, t in zip(codes[j][0], codes[j][1]):
                if TRIT[t] == 1:
                    P += ROT[a[j]][k]
                elif TRIT[t] == -1:
                    N += ROT[a[j]][k]
        s = [((P >> (8 * i)) & 255) - ((N >> (8 * i)) & 255) for i in range(8)]
        # rst_n clears the control pipeline (valid / capture / shift at S0, S1) for the next 2 edges
        pipe.append(dict(rst=rst_n, s=s, plane=plane, neg=neg, valid=valid, first=first, cap=cap, sft=sft,
                         shin=shin))
        # edge cyc: S2 commits the input of cycle cyc-2 (its controls survive if rst_n was high at edges cyc-2, cyc-1)
        if cyc >= 2:
            p = pipe[cyc - 2]
            alive = p["rst"] and pipe[cyc - 1]["rst"]
            if alive:
                old = list(acc)
                if p["valid"]:
                    for i in range(8):
                        base = 0 if p["first"] else old[i]
                        if base is None:
                            acc[i] = None
                        else:
                            d = p["s"][i] << p["plane"]
                            acc[i] = (base - d if p["neg"] else base + d) & M
                if p["cap"]:
                    shd = old
                elif p["sft"]:
                    shd = [p["shin"]] + shd[:7]
            pipe[cyc - 2] = None
        o = shd[7]
        fe.write("0 0\n" if o is None else "1 %s\n" % hx(o, accw))


def gen_lane(xw, mw, tw, n, rng, fs, fe):
    def sx(w):
        return rng.getrandbits(w) - (1 << (w - 1))
    hist = []
    v0 = v1 = v2 = vo = 0
    for cyc in range(n):
        rst_n = 0 if cyc < 3 else 1
        vld = int(rng.random() < 0.9)
        mode = int(rng.random() < 0.15)
        kind = rng.random()
        if kind < 0.3:
            x = sx(xw)
        else:
            x = sx(rng.randint(1, xw))
        if rng.random() < 0.02:
            x = rng.choice([-(1 << (xw - 1)), (1 << (xw - 1)) - 1, 0, -1, 1])
        m = rng.getrandbits(rng.randint(0, mw))
        if rng.random() < 0.02:
            m = rng.choice([0, 1, (1 << mw) - 1])
        if rng.random() < 0.3:
            sh = rng.randint(1, 63)
        else:   # around the scale that lands y in / near the 16-b range
            sh = max(1, min(63, x.bit_length() + m.bit_length() - rng.randint(8, 20)))
        h = sx(16) if rng.random() < 0.5 else sx(rng.randint(1, 12))
        r = sx(16) if rng.random() < 0.3 else sx(rng.randint(1, 12))
        if mode:
            t = sx(tw) if rng.random() < 0.3 else x + rng.randint(-2, 2)
        else:
            t = sx(tw) if rng.random() < 0.3 else rng.randint(-32769, 32768)
        t = max(-(1 << (tw - 1)), min((1 << (tw - 1)) - 1, t))
        ctl = (rst_n << 2) | (vld << 1) | mode
        fs.write("%s %s %s %s %s %s %s\n" % (hx(ctl, 3), hx(x, xw), hx(m, mw), hx(sh, 6), hx(h, 16), hx(r, 16),
                                             hx(t, tw)))
        y = (x * m + (1 << (sh - 1))) >> sh
        ys = max(-32767, min(32767, y + h + r))
        if mode:
            yo, b = 0, int(x >= t)
        else:
            yo, b = ys, int(ys > t)
        hist.append((yo, b))
        # valid pipeline (synchronous reset at every stage)
        vo, v2, v1, v0 = rst_n & v2, rst_n & v1, rst_n & v0, rst_n & vld
        if cyc >= 3:
            yo3, b3 = hist[cyc - 3]
            fe.write("1 %d %s %d\n" % (vo, hx(yo3, 16), b3))
        else:
            fe.write("0 0 0 0\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dut", choices=["pe", "lane_n", "lane_w"])
    ap.add_argument("--kb", type=int, default=16)
    ap.add_argument("--accw", type=int, default=20)
    ap.add_argument("--n", type=int, default=200000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    g = ap.parse_args()
    rng = random.Random(g.seed)
    os.makedirs(g.out, exist_ok=True)
    with open(os.path.join(g.out, "stim.txt"), "w") as fs, open(os.path.join(g.out, "exp.txt"), "w") as fe:
        if g.dut == "pe":
            gen_pe(g.kb, g.accw, g.n, rng, fs, fe)
        elif g.dut == "lane_n":
            gen_lane(16, 27, 17, g.n, rng, fs, fe)
        else:
            gen_lane(20, 31, 21, g.n, rng, fs, fe)


if __name__ == "__main__":
    main()
