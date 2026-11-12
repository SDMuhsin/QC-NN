#!/usr/bin/env python3
"""Stimulus + bit-exact Python reference for the qb_lane_s variants (tb_qb_lane_s.sv), written from the arithmetic
definitions, not from the RTL:

    python3 -I qc18bacc/hw/tb/gen_s.py rand --xw 16 --mw 29 --tw 16 --shw 3 --sb 17 --n 200000 --seed 1 --out DIR
    python3 -I qc18bacc/hw/tb/gen_s.py real --params lanep_s0.txt --mw 29 --tw 16 --shw 3 --sb 17 --seed 1 --out DIR
    (--base: qbs_base timing, all operands with x, latency 4; default qbs_new: h / r / t / sh one cycle after x, latency 3)

Per element: mode 0: s = SB + sel, y = floor((x m + 2^(s-1)) / 2^s), y_sat = clip(y + h + r, -32767, 32767),
b = y_sat > T;  mode 1: b = x >= T, y_o = 0.
rand: x uniform over XW bits (mixed bit lengths) + corners; m random (mixed bit lengths) under the measured-domain
  contract |y| < 2^17 (resampled until it holds); sel, h, r, T random over their fields + corners (T = y_sat, +-1);
  mode 1 with x in [-2^(XW-1), 32766].
real: every channel of every in-scope requant of one seed (workload.py --lane-export), EVERY x of its worst-case domain
  [lo, hi]; the reference uses IntBin's ORIGINAL 31-bit (m0, sh) (qc18.int8.requant), the DUT the converted (m', sel);
  h = the layer's bias (c2h / sch, 0 for stem / idm), r random 16 b on c2 rows (0 otherwise), T random among the
  network's T1 thresholds clamped to 16 b (+ random); plus mode 1 over each binary block's c1 accumulator domain
  against its T2 thresholds (clamped to 16 b).
Stimulus line per cycle: ctl{rst_n, vld, mode, ld} x m sh h r t (hex); expected line per cycle after the edge:
  <defined> <vld_o> <y_o> <b_o>.
"""
import argparse
import os
import random


def hx(v, w):
    return format(v & ((1 << w) - 1), "0%dx" % ((w + 3) // 4))


def clip(v, lo, hi):
    return max(lo, min(hi, v))


def rq(x, m, s):
    return (x * m + (1 << (s - 1))) >> s


def ref(e):
    if e["mode"]:
        return 0, int(e["x"] >= e["t"])
    ys = clip(e["y"] + e["h"] + e["r"], -32767, 32767)
    return ys, int(ys > e["t"])


def rand_elems(a, rng):
    X0, X1 = -(1 << (a.xw - 1)), (1 << (a.xw - 1)) - 1
    T0, T1 = -(1 << (a.tw - 1)), (1 << (a.tw - 1)) - 1
    K = 1 << a.shw
    for _ in range(a.n):
        mode = int(rng.random() < 0.15)
        x = rng.randint(X0, X1) if rng.random() < 0.4 else rng.getrandbits(rng.randint(1, a.xw)) - (1 << (rng.randint(1, a.xw) - 1))
        x = clip(x, X0, X1)
        if rng.random() < 0.03:
            x = rng.choice([X0, X1, 0, -1, 1, X0 + 1])
        sel = rng.randrange(K) if rng.random() > 0.05 else rng.choice([0, K - 1])
        if a.sb == 0:
            sel = max(sel, 1)                                  # qb_lane semantics: sh >= 1
        s = a.sb + sel
        if mode:
            x = min(x, 32766)
            m, y = rng.getrandbits(a.mw), 0
        else:
            m = rng.getrandbits(rng.randint(0, a.mw)) if rng.random() < 0.6 else rng.getrandbits(a.mw)
            if rng.random() < 0.03:
                m = rng.choice([0, 1, (1 << a.mw) - 1])
            y = rq(x, m, s)
            if not -(1 << 17) <= y < (1 << 17):          # contract |y| < 2^17: largest legal m, or random below it
                mmax = ((1 << 17) << s) // abs(x)
                while not -(1 << 17) <= rq(x, mmax, s) < (1 << 17):
                    mmax -= 1
                m = mmax if rng.random() < 0.3 else rng.randint(0, mmax)
                y = rq(x, m, s)
        h = rng.randint(-32768, 32767) if rng.random() < 0.5 else rng.randint(-200, 200)
        r = rng.randint(-32768, 32767) if rng.random() < 0.5 else rng.randint(-200, 200)
        if rng.random() < 0.03:
            h, r = rng.choice([(32767, 32767), (-32768, -32768), (32767, -32768)])
        e = dict(mode=mode, x=x, m=m, sel=sel, h=h, r=r, y=y)
        if mode:
            t = x + rng.randint(-2, 2) if rng.random() < 0.6 else rng.randint(T0, T1)
        else:
            ys = clip(y + h + r, -32767, 32767)
            t = ys + rng.randint(-1, 1) if rng.random() < 0.6 else rng.choice([T0, T1, rng.randint(T0, T1)])
        e["t"] = clip(t, T0, T1)
        yield e


def real_elems(a, rng):
    T0, T1 = -(1 << (a.tw - 1)), (1 << (a.tw - 1)) - 1
    R, T1s, T2s = [], [], []
    for ln in open(a.params):
        f = ln.split()
        if not f or f[0].startswith("#"):
            continue
        if f[0] == "R":
            R.append((f[1],) + tuple(int(v) for v in f[2:]))
        elif f[0] == "T1":
            T1s += [int(v) for v in f[2:]]
        elif f[0] == "T2":
            T2s.append((int(f[2]), int(f[3]), [int(v) for v in f[4:]]))
    tpool = [clip(v, T0, T1) for v in T1s]
    for nm, c, lo, hi, m0, sh, mp, sel, h in R:
        assert mp < (1 << a.mw) and sel < (1 << a.shw)
        c2 = nm.endswith("c2m")
        for x in range(lo, hi + 1):
            y = rq(x, m0, sh)                                     # IntBin requant, original 31-bit multiplier
            r = (rng.randint(-32768, 32767) if rng.random() < 0.5 else rng.randint(-3000, 3000)) if c2 else 0
            t = rng.choice(tpool) if rng.random() < 0.8 else rng.randint(T0, T1)
            yield dict(mode=0, x=x, m=mp, sel=sel, h=h, r=r, y=y, t=t)
    for lo, hi, t2 in T2s:                                         # mode 1: c1 accumulator vs T2
        for x in range(lo, hi + 1):
            for t in rng.sample(t2, min(8, len(t2))):
                yield dict(mode=1, x=x, m=rng.getrandbits(a.mw), sel=rng.randrange(1 << a.shw),
                           h=rng.randint(-32768, 32767), r=rng.randint(-32768, 32767), y=0, t=clip(t, T0, T1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["rand", "real"])
    ap.add_argument("--xw", type=int, default=16)
    ap.add_argument("--mw", type=int, required=True)
    ap.add_argument("--tw", type=int, default=16)
    ap.add_argument("--shw", type=int, required=True)
    ap.add_argument("--sb", type=int, required=True)
    ap.add_argument("--base", action="store_true")
    ap.add_argument("--params")
    ap.add_argument("--n", type=int, default=200000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    late, lat = (0, 4) if a.base else (1, 3)
    sw = max(a.shw, 1)
    elems = list(rand_elems(a, rng) if a.kind == "rand" else real_elems(a, rng))
    os.makedirs(a.out, exist_ok=True)
    NR = 3                                                         # reset cycles
    ncyc = NR + len(elems) + lat + 1
    # element at cycle n (n >= NR): early fields at n, late fields at n + late
    early, lfield = [None] * ncyc, [None] * ncyc
    for i, e in enumerate(elems):
        n = NR + i
        e["vld"] = int(rng.random() < 0.9)
        early[n] = e
        lfield[n + late] = e
    rst = [0 if n < NR else 1 for n in range(ncyc)]
    nmode = sum(e["mode"] for e in elems)
    with open(os.path.join(a.out, "stim.txt"), "w") as fs, open(os.path.join(a.out, "exp.txt"), "w") as fe:
        for n in range(ncyc):
            e, l = early[n], lfield[n]
            vld = e["vld"] if e else 0
            ctl = (rst[n] << 3) | (vld << 2) | ((e["mode"] if e else 0) << 1)
            x, m = (e["x"], e["m"]) if e else (0, 0)
            sh, h, r, t = (l["sel"], l["h"], l["r"], l["t"]) if l else (0, 0, 0, 0)
            fs.write("%s %s %s %s %s %s %s\n" % (hx(ctl, 4), hx(x, a.xw), hx(m, a.mw), hx(sh, sw), hx(h, 16),
                                                 hx(r, 16), hx(t, a.tw)))
            # outputs after edge n belong to the element of cycle n - (lat - 1)
            k = n - (lat - 1)
            if k >= NR and early[k] is not None:
                ee = early[k]
                vo = ee["vld"] & all(rst[k + j] for j in range(lat))
                yo, bo = ref(ee)
                fe.write("1 %d %s %d\n" % (vo, hx(yo, 16), bo))
            else:
                fe.write("0 0 0000 0\n")
    print("GEN_S %s elements %d (mode 1: %d) cycles %d" % (a.kind, len(elems), nmode, ncyc))


if __name__ == "__main__":
    main()
