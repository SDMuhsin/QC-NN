#!/usr/bin/env python3
"""Stimulus + bit-exact Python references for qb_lane_f (tb_qb_lane_f.sv), written from the definitions, not from the RTL:

    python3 -I qc18bacc/hw/tb/gen_f.py rand --mw 29 --n 200000 --seed 1 --out DIR
    python3 -I qc18bacc/hw/tb/gen_f.py real --params lanef_E6_s0.txt --mw 29 --seed 1 --out DIR

rand: reference = the lane arithmetic (qb_lane_f header): x = clamp(relu?(sgn ? -acc : acc) + bias, lo, hi),
  s' = 17 + sel, y = (x m + 2^(s'-1)) >> s', rs by rmode (0 | sv | relu(sv) | (relu(sv) + 1) >> 1), s = y + h + rs,
  omode 0: sat16(s), b = sat16(s) > t;  1: s (b 0);  2: clamp(s, 0, 127) (b 0).  Fields random over their widths
  (mixed bit lengths) + corners, under the contracts |y| < 2^17 and (omode 1) |s| < 2^16 (resampled).
real: reference = IntBin2 itself (qc18b.int_bin.IntBin.__call__ semantics with IntBin2's ORIGINAL 31-b (m0, sh) and
  idm (m0, sh)), one row per channel of every fused-lane requant of one seed's p2 program (hw/tb/export_f.py): EVERY
  x' = acc' + bias of the channel's worst-case domain; the DUT gets the raw accumulator acc = sign(g) (x' - bias),
  sign(g), bias, the compiler's pre-clamp (lo, hi) and window parameters (m', sel):
    stem: s0 = sat16(rq(x')), b = s0 > T1_0;   sc: r = rq(acc') + sch;
    c2:   s = sat16(rq(acc') + c2h + rs), rs = sv (sc blocks: sv uniform over the channel's worst-case r range + ends) or
          rq(relu(sv), idm) (identity blocks: sv = s_in uniform over [-32767, 32767] + corners), b = s > T1_next;
    hm:   hq = clamp(rq(relu(s)), 0, 127) for every s in [-32767, 32767] (per-tensor multiplier: identical rows deduplicated).
Stimulus line per cycle: ctl{rst_n, vld, relu, sgn} acc bias lo hi m (early) sh h sv rmode omode t (late, one cycle
after its element), hex.  Expected per cycle after the edge: <defined> <vld_o> <y_o> <b_o>.
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


SB, AW, BW, XW, TW, SHW = 17, 20, 16, 16, 16, 4


def lane(e):
    """lane arithmetic reference -> (y_o, b_o)."""
    a = -e["acc"] if e["sgn"] else e["acc"]
    xb = a + e["bias"]
    if e["relu"]:
        xb = max(xb, 0)
    x = clip(xb, e["lo"], e["hi"])
    y = rq(x, e["m"], SB + e["sel"])
    sv = e["sv"]
    rs = [0, sv, max(sv, 0), (max(sv, 0) + 1) >> 1][e["rmode"]]
    s = y + e["h"] + rs
    if e["omode"] == 0:
        ys = clip(s, -32767, 32767)
        return ys, int(ys > e["t"]), y, s
    return (s if e["omode"] == 1 else clip(s, 0, 127)), 0, y, s


def rbits(rng, w):
    """signed value of a random bit length <= w (mixed magnitudes)."""
    k = rng.randint(1, w)
    return clip(rng.getrandbits(k) - (1 << (k - 1)), -(1 << (w - 1)), (1 << (w - 1)) - 1)


def rand_elems(a, rng):
    for _ in range(a.n):
        while True:
            e = dict(acc=rbits(rng, AW) if rng.random() < 0.7 else rng.choice([-(1 << 19), (1 << 19) - 1, 0, -1, 1]),
                     sgn=rng.getrandbits(1), bias=rbits(rng, BW), relu=int(rng.random() < 0.3))
            if rng.random() < 0.4:
                e["lo"], e["hi"] = -32768, 32767
            else:
                u, v = rbits(rng, XW), rbits(rng, XW)
                e["lo"], e["hi"] = min(u, v), max(u, v)
            e["sel"] = rng.randrange(1 << SHW) if rng.random() > 0.05 else rng.choice([0, (1 << SHW) - 1])
            e["m"] = rng.getrandbits(rng.randint(0, a.mw)) if rng.random() < 0.6 else rng.getrandbits(a.mw)
            if rng.random() < 0.03:
                e["m"] = rng.choice([0, 1, (1 << a.mw) - 1])
            e["h"] = rbits(rng, 16) if rng.random() < 0.7 else rng.choice([32767, -32768, 0])
            e["sv"] = rbits(rng, 17) if rng.random() < 0.7 else rng.choice([65535, -65536, 32767, -32767, 0, 1, -1, 2])
            e["rmode"], e["omode"] = rng.randrange(4), rng.randrange(3)
            e["t"] = rbits(rng, TW)
            _, _, y, s = lane(e)
            if not -(1 << 17) <= y < (1 << 17):
                e["m"] >>= rng.randint(1, a.mw)              # resample a smaller multiplier
                _, _, y, s = lane(e)
            if -(1 << 17) <= y < (1 << 17) and (e["omode"] != 1 or -(1 << 16) <= s < (1 << 16)):
                break
        if e["omode"] == 0 and rng.random() < 0.5:
            e["t"] = clip(clip(s, -32767, 32767) + rng.randint(-1, 1), -(1 << 15), (1 << 15) - 1)
        e["y"], e["b"] = lane(e)[:2]
        yield e


def real_elems(a, rng):
    seen = set()
    for ln in open(a.params):
        f = ln.split()
        if not f or f[0] != "R":
            continue
        kind, name = f[1], f[2]
        (c, sgn, bias, dlo, dhi, lo, hi, m, sel, m0, sh, h, relu, omode, rmode, im0, ish, rlo, rhi) = map(int, f[3:22])
        T = None if f[22] == "N" else int(f[22])
        key = (kind, sgn, bias, dlo, dhi, lo, hi, m, sel, m0, sh, h, relu, omode, rmode, im0, ish, rlo, rhi, T)
        if kind == "hm" and key in seen:
            continue
        seen.add(key)
        assert m < (1 << a.mw) and sel < (1 << SHW), (name, c)
        for xp in range(dlo, dhi + 1):
            acc = (xp - bias) * (-1 if sgn else 1)
            assert -(1 << (AW - 1)) <= acc < (1 << (AW - 1))
            t = T if T is not None and rng.random() < 0.8 else rng.randint(-(1 << 15), (1 << 15) - 1)
            sv, rs = 0, 0
            if kind == "stem":
                y = clip(rq(xp, m0, sh), -32767, 32767)
                b = int(y > t)
            elif kind == "sc":
                y, b = rq(xp, m0, sh) + h, 0
            elif kind == "c2":
                if rmode == 1:
                    sv = rng.choice([rlo, rhi]) if rng.random() < 0.05 else rng.randint(rlo, rhi)
                    rs = sv
                else:
                    sv = rng.choice([-32767, 32767, 0, 1, 2, -1]) if rng.random() < 0.05 else rng.randint(-32767, 32767)
                    rs = rq(max(sv, 0), im0, ish)
                y = clip(rq(xp, m0, sh) + h + rs, -32767, 32767)
                b = int(y > t)
            elif kind == "hm":
                y, b = clip(rq(max(xp, 0), m0, sh), 0, 127), 0
            else:
                raise ValueError(kind)
            yield dict(acc=acc, sgn=sgn, bias=bias, relu=relu, lo=lo, hi=hi, m=m, sel=sel, h=h, sv=sv, rmode=rmode,
                       omode=omode, t=t, y=y, b=b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["rand", "real"])
    ap.add_argument("--mw", type=int, required=True)
    ap.add_argument("--params")
    ap.add_argument("--n", type=int, default=200000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    elems = list(rand_elems(a, rng) if a.kind == "rand" else real_elems(a, rng))
    os.makedirs(a.out, exist_ok=True)
    NR, late, lat = 3, 1, 3
    ncyc = NR + len(elems) + lat + 1
    early, lfield = [None] * ncyc, [None] * ncyc
    for i, e in enumerate(elems):
        e["vld"] = int(rng.random() < 0.9)
        early[NR + i] = e
        lfield[NR + i + late] = e
    rst = [0 if n < NR else 1 for n in range(ncyc)]
    cnt = {}
    with open(os.path.join(a.out, "stim.txt"), "w") as fs, open(os.path.join(a.out, "exp.txt"), "w") as fe:
        for n in range(ncyc):
            e, l = early[n], lfield[n]
            ctl = (rst[n] << 3) | ((e["vld"] if e else 0) << 2) | ((e["relu"] if e else 0) << 1) | (e["sgn"] if e else 0)
            ev = (e["acc"], e["bias"], e["lo"], e["hi"], e["m"]) if e else (0, 0, 0, 0, 0)
            lv = (l["sel"], l["h"], l["sv"], l["rmode"], l["omode"], l["t"]) if l else (0, 0, 0, 0, 0, 0)
            fs.write(" ".join([hx(ctl, 4), hx(ev[0], AW), hx(ev[1], BW), hx(ev[2], XW), hx(ev[3], XW), hx(ev[4], a.mw),
                               hx(lv[0], SHW), hx(lv[1], 16), hx(lv[2], 17), hx(lv[3], 2), hx(lv[4], 2), hx(lv[5], TW)])
                     + "\n")
            k = n - (lat - 1)
            if k >= NR and early[k] is not None:
                ee = early[k]
                vo = ee["vld"] & all(rst[k + j] for j in range(lat))
                fe.write("1 %d %s %d\n" % (vo, hx(ee["y"], 17), ee["b"]))
                cnt[(ee["omode"], ee["rmode"])] = cnt.get((ee["omode"], ee["rmode"]), 0) + 1
            else:
                fe.write("0 0 00000 0\n")
    print("GEN_F %s elements %d cycles %d (omode, rmode) counts %s" % (a.kind, len(elems), ncyc, sorted(cnt.items())))


if __name__ == "__main__":
    main()
