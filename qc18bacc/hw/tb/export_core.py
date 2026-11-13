#!/usr/bin/env python3
"""Tile-level stimulus + expected outputs of qb_core (hw/rtl/qb_core.sv) for whole images, from the compiler's
bit-exact dataflow model (compile/dataflow.py, golden p2 = qc18bacc.golden_p2.IntBin2):

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_core.py RUN/best.pt OUTDIR [--images 0 1] [--golden p2]

Per image i (val[i], never the test set) writes OUTDIR/img<i>/{stim.txt, exp_b2.txt, exp_f.txt, exp_w.txt, passes.txt}.
Every program pass runs on qb_core tile by tile (16 output pixels x 64 output channels): array passes stream their
executed chunk items (patch bytes per row, 8-b codes per column, controls; int8 sources plane-major with the
dataflow's all-zero-patch skip), captured by the shadow (stem / sc / c2: fused-lane drain, 4 cycles; block-6 c1 / sc /
c2: wide-lane drain, 32 cycles) or by the per-PE comparators (binary c1: b2); b6.hm runs as fused-lane jobs (x = the
stream read).  Inputs of each pass = the dataflow buffers before the pass, expected outputs = the dataflow buffers
after it (S / B1 / B2 / HQ / Z), so every compared word is the golden's own value.
stim.txt, one line per port cycle (hex fields, '0' = idle):
  ctl cd act t2 fctl pf s_rd wctl pw w_r
  ctl {cmp, cap, g3n, stem, neg, plane[2:0], first, valid}; fctl {p_ld, f_sh, f_src, f_vld}; wctl {w_ld, w_sh, w_vld}
Port timing (qb_core.sv header): codes / ctl at n-1, act at n, T2 at n+1; PPU controls at t, lane cycle e = t + 1,
late operands (s_rd as sv, w_r) at e + 1, hm x (s_rd) at e.
exp_*.txt: '<pass index> <hex ...>' in output order (b2 per capture: 1024 b; fused per lane cycle: 256 x 17-b y + 256 b;
wide per lane cycle: 32 x 19-b y + 32 b).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))

import numpy as np  # noqa: E402
import torch  # noqa: E402

from qc18bacc.compile import dataflow as D  # noqa: E402
from qc18bacc.compile import program as P  # noqa: E402

ROWS, COLS, KB = 16, 8, 36
NLF, NLW = 4 * COLS * 8, 4 * COLS
MWF = 28
Q16 = 32767


def hx(v, w):
    return format(int(v) & ((1 << w) - 1), "x")


def pack_bits(bits):
    """[..., nbits] 0/1 -> int with bit k = bits[..., k] (flattened row-major)."""
    b = np.packbits(np.asarray(bits, dtype=np.uint8).reshape(-1), bitorder="little")
    return int.from_bytes(b.tobytes(), "little")


def pack_words(vals, w):
    v = 0
    for k, x in enumerate(vals):
        v |= (int(x) & ((1 << w) - 1)) << (w * k)
    return v


class Stim:
    FIELDS = ("ctl", "cd", "act", "t2", "fctl", "pf", "srd", "wctl", "pw", "wr")

    def __init__(self):
        self.c = {}

    def put(self, t, f, v, merge=False):
        d = self.c.setdefault(t, {})
        if f in d and not merge:
            raise AssertionError(f"cycle {t}: field {f} written twice")
        d[f] = (d.get(f, 0) | v) if merge else v

    def write(self, path):
        n = max(self.c) + 12
        with open(path, "w") as fh:
            for t in range(n):
                d = self.c.get(t, {})
                fh.write(" ".join(format(d.get(f, 0), "x") for f in self.FIELDS) + "\n")
        return n


def codes_item(p, ct, chunk, stem):
    """8 columns x 36 bytes of 8-b codes for (channel tile ct, chunk)."""
    nb = p.cinp // 8
    out = np.zeros((COLS, KB), np.uint8)
    for col in range(COLS):
        ob = ct * COLS + col
        for j in range(KB):
            tap, g = divmod(j, 4)
            if p.k == 3:
                if stem:
                    blk = tap * nb                      # group-0 codes replicated into the 4 groups
                else:
                    cb = 4 * chunk + g
                    blk = tap * nb + cb if cb < nb else None
            else:
                blk = j if j < nb else None
            out[col, j] = 0 if blk is None else p.codes[ob, blk]
    return int.from_bytes(out.tobytes(), "little")


def ctlw(valid=0, first=0, plane=0, neg=0, stem=0, g3n=0, cap=0, cmp=0):
    return valid | first << 1 | plane << 2 | neg << 5 | stem << 6 | g3n << 7 | cap << 8 | cmp << 9


class Gen:
    def __init__(self):
        self.st = Stim()
        self.ta = 2                 # next free array ctl cycle
        self.pending = None         # capture of the last array tile: (kind, info)
        self.shadow_free = 0        # earliest ctl cycle of the next shadow capture
        self.lane_f = 2             # earliest fused lane cycle e
        self.lane_w = 2
        self.last_f_drain = -10     # last fused drain lane cycle (hm gap rule)
        self.eb2, self.ef, self.ew = [], [], []
        self.drains = []            # (kind, capture ctl cycle, payload)
        self.stats = dict(items=0, zero_tiles=0, caps=0, cmps=0)

    # ---- array
    def tile(self, items, kind, payload):
        """items: list of (ctl word without first / cap / cmp, cd int, act int); kind 'shadow' | 'cmp'."""
        st = self.ta
        if self.pending is not None and self.pending[0] == "shadow":
            st = max(st, self.shadow_free)       # the pending capture overwrites the shadow at st
        self.flush(st)
        for k, (cw, cd, act) in enumerate(items):
            t = st + k
            self.st.put(t, "ctl", cw | (2 if k == 0 else 0), merge=True)
            self.st.put(t, "cd", cd)
            self.st.put(t + 1, "act", act)
        self.stats["items"] += len(items)
        self.ta = st + len(items)
        self.pending = (kind, payload)

    def flush(self, t):
        """issue the pending capture at ctl cycle t (merged with the next tile's first item if t == its start)."""
        if self.pending is None:
            return
        kind, payload = self.pending
        self.pending = None
        if kind == "cmp":
            self.st.put(t, "ctl", ctlw(cmp=1), merge=True)
            self.st.put(t + 2, "t2", payload["t2"])
            self.eb2.append((payload["pi"], payload["b2"]))
            self.stats["cmps"] += 1
        else:
            self.st.put(t, "ctl", ctlw(cap=1), merge=True)
            self.stats["caps"] += 1
            self.drain(t, payload)
        self.ta = max(self.ta, t + 1)

    def end_array(self):
        if self.pending is not None:
            t = self.ta
            if self.pending[0] == "shadow":
                t = max(t, self.shadow_free)
            self.flush(t)

    # ---- PPU
    def drain(self, c, pl):
        if pl["lane"] == "f":
            e = max(c + 4, self.lane_f)
            t = e - 1
            self.st.put(t, "pf", pl["pf"])
            for k in range(4):
                self.st.put(t + k, "fctl", 1 | (4 if k < 3 else 0) | (8 if k == 0 else 0))
                self.st.put(e + k + 1, "srd", pl["srd"][k])
                self.ef.append((pl["pi"], pl["fy"][k], pl["fb"][k]))
            self.lane_f = e + 4
            self.last_f_drain = e + 3
            self.shadow_free = e
        else:
            e = max(c + 4, self.lane_w)
            t = e - 1
            self.st.put(t, "pw", pl["pw"])
            for k in range(32):
                self.st.put(t + k, "wctl", 1 | (2 if k < 31 else 0) | (4 if k == 0 else 0))
                self.st.put(e + k + 1, "wr", pl["wr"][k])
                self.ew.append((pl["pi"], pl["wy"][k], pl["wb"][k]))
            self.lane_w = e + 32
            self.shadow_free = e + 28

    def hm_job(self, pi, pf, x, fy):
        e = max(self.lane_f, self.last_f_drain + 2)
        t = e - 1
        self.st.put(t, "pf", pf)
        self.st.put(t, "fctl", 1 | 2 | 8)
        self.st.put(e, "srd", x)
        self.ef.append((pi, fy, 0))
        self.lane_f = e + 1


def f_record(sgn, bias, m, sel, h, T):
    assert -2 ** 15 <= bias < 2 ** 15 and 0 <= m < 2 ** MWF and 0 <= sel < 16 and -2 ** 15 <= h < 2 ** 15
    assert -2 ** 15 <= T < 2 ** 15
    v = (sgn & 1) | (bias & 0xFFFF) << 1 | m << 17 | sel << (17 + MWF) | (h & 0xFFFF) << (21 + MWF) | \
        (T & 0xFFFF) << (37 + MWF)
    return v


def pf_word(recs, relu, rmode, omode):
    rw = 37 + MWF + 16
    v = 0
    for ch, r in enumerate(recs):
        v |= r << (rw * ch)
    return v | (relu | rmode << 1 | omode << 3) << (rw * len(recs))


def w_record(sgn, bias, m, sh, T):
    assert -2 ** 19 <= bias < 2 ** 19 and 0 <= m < 2 ** 31 and 1 <= sh < 64 and -2 ** 20 <= T < 2 ** 20
    return (sgn & 1) | (bias & 0xFFFFF) << 1 | m << 21 | sh << 52 | (T & 0x1FFFFF) << 58


def pw_word(recs, relu, omode):
    v = 0
    for ch, r in enumerate(recs):
        v |= r << (79 * ch)
    return v | (relu | omode << 1) << (79 * len(recs))


def lst(t):
    return [int(v) for v in torch.as_tensor(t).reshape(-1).tolist()]


def export_image(prog, net, x, outdir, dev):
    """x: [1, 32, 32, 3] uint8 image."""
    Ws = {p.name: D.PEWeights(p, dev) for p in prog.passes if p.k}
    bf = D.Bufs(1, dev)
    D.load_image(prog, bf, x, dev)
    g = Gen()
    names = []
    for pi, p in enumerate(prog.passes):
        names.append(p.name)
        before = {k: v.clone() for k, v in bf.b.items()}
        p.p["dev"] = dev
        D.do_pass(prog, p, bf, Ws, dev, {})
        after = bf.b
        L, Li = p.Hout * p.Wout, p.Hin * p.Win
        sgn = None if p.sgn is None else lst(p.sgn)
        if p.kind == "hm":
            f = p.p["f"]
            assert f["relu"] and f["mode"] == "u8"
            for k in ("bias", "m", "sel"):
                assert (f[k] == f[k][0]).all(), "hm parameters not per tensor"
            rec = f_record(0, int(f["bias"][0]), int(f["m"][0]), int(f["sel"][0]), 0, 0)
            pf = pf_word([rec] * 64, 1, 0, 2)
            s = before["S"][0, :L * p.cin].view(L, p.cin).cpu().numpy()
            y = sum(after["HQ"][0, b * L * p.cin:(b + 1) * L * p.cin].view(L, p.cin).cpu().numpy() << b
                    for b in range(8))
            assert p.cin == NLF
            for jb in range(L):
                g.hm_job(pi, pf, pack_words(s[jb], 17), pack_words(y[jb], 17))
            continue
        assert p.k, p.name
        # ---- array inputs (as dataflow.do_pass)
        if p.inb == 8:
            C = 8 if p.src == "IMG" else p.cin
            planes = [(D.nchw(D.Bufs.read(_wrap(before), p.src, Li, C, plane=b), p.Hin, p.Win).float(), b == 7)
                      for b in range(8)]
        else:
            planes = [(D.nchw(D.Bufs.read(_wrap(before), p.src, Li, p.cin), p.Hin, p.Win).float(), False)]
        stem = bool(p.p.get("pack"))
        if stem:
            pt = []
            for h in range(2):
                a = torch.cat([D.patches(planes[4 * h + gg][0], p)[:, :, 0].view(1, L, 9, P.CH)[..., :8]
                               for gg in range(4)], -1).reshape(1, L, 9 * P.CH)
                pt.append(a[0].cpu().numpy().astype(np.uint8))
            items_px = []
            for tp in range(p.tiles_px):
                items_px.append([(ctlw(valid=1, plane=4 * h, stem=1, g3n=int(h == 1)), 0, pt[h][16 * tp:16 * tp + 16])
                                 for h in range(2)])
        else:
            pts = [D.patches(a, p)[0].cpu().numpy().astype(np.uint8) for a, _ in planes]     # [L, nchunk, 288]
            skip = p.inb == 8
            items_px = []
            for tp in range(p.tiles_px):
                its = []
                for pl, (_, neg) in enumerate(planes):
                    for c in range(p.nchunk):
                        a = pts[pl][16 * tp:16 * tp + 16, c]
                        if skip and not a.any():
                            continue
                        its.append((ctlw(valid=1, plane=pl, neg=int(neg)), c, a))
                if not its:                                     # all skipped: one zero item clears acc
                    its.append((ctlw(valid=1), 0, np.zeros((16, KB * 8), np.uint8)))
                    g.stats["zero_tiles"] += 1
                items_px.append(its)
        ct_n = p.cout // 64
        for tp in range(p.tiles_px):
            for ct in range(ct_n):
                chs = list(range(64 * ct, 64 * ct + 64))
                pix = list(range(16 * tp, 16 * tp + 16))
                items = [(cw, codes_item(p, ct, c, stem), pack_bits(a)) for cw, c, a in items_px[tp]]
                if p.kind == "bc1":
                    T = lst(p.p["T"])
                    t2 = 0
                    for k, ch in enumerate(chs):
                        if sgn[ch] > 0:
                            tt, inv = T[ch], 0
                        else:
                            tt, inv = min(max(1 - T[ch], -2 ** 15), 2 ** 15 - 1), 1
                        t2 |= ((tt & 0xFFFF) | inv << 16) << (17 * k)
                    b2 = after["B2"][0, :L * p.cout].view(L, p.cout)[pix][:, chs].cpu().numpy()
                    g.tile(items, "cmp", dict(pi=pi, t2=t2, b2=pack_bits(b2)))
                    continue
                Sa = after["S"][0]
                if p.kind in ("stem", "bsc", "bc2"):
                    if p.kind == "stem":
                        bias, h, T, om, rm = lst(p.p["bias"]), [0] * p.cout, lst(p.p["T"]), 0, 0
                    elif p.kind == "bsc":
                        bias, h, T, om, rm = [0] * p.cout, lst(p.p["h"]), [0] * p.cout, 1, 0
                    else:
                        bias, h, om = [0] * p.cout, lst(p.p["h"]), 0
                        T = [Q16] * p.cout if p.p["T"] is None else lst(p.p["T"])
                        rm = 1 if p.p["res"] == "r" else (2 if p.p["idm_j"] == 0 else 3)
                    m, sel = lst(p.p["m"]), lst(p.p["sel"])
                    recs = [f_record(int(sgn[ch] < 0), bias[ch], m[ch], sel[ch], h[ch], T[ch]) for ch in chs]
                    pf = pf_word(recs, 0, rm, om)
                    sv = before["S"][0, :L * p.cout].view(L, p.cout).cpu().numpy()
                    so = Sa[:L * p.cout].view(L, p.cout).cpu().numpy()
                    b1 = after["B1"][0, :L * p.cout].view(L, p.cout).cpu().numpy() \
                        if (p.kind == "stem" or (p.kind == "bc2" and p.p["T"] is not None)) else None
                    srd, fy, fb = [], [], []
                    for k in range(4):
                        ys, bs, ss = [], [], []
                        for q in range(4):
                            px = 16 * tp + 4 * k + q
                            for ch in chs:
                                ys.append(so[px, ch])
                                bs.append(0 if b1 is None else b1[px, ch])
                                ss.append(sv[px, ch] if (p.kind == "bc2") else 0)
                        srd.append(pack_words(ss, 17))
                        fy.append(pack_words(ys, 17))
                        fb.append(pack_words(bs, 1))
                    g.tile(items, "shadow", dict(lane="f", pi=pi, pf=pf, srd=srd, fy=fy, fb=fb))
                    continue
                # ---- block 6 on the wide lanes
                assert p.kind in ("wc1", "wsc", "wc2") and "f" not in p.p and p.ppu == "wide", p.name
                bias, m0, sh = lst(p.p["bias"]), lst(p.p["m0"]), lst(p.p["sh"])
                T = lst(p.p["T"]) if p.kind == "wc2" else [0] * p.cout
                om = dict(wc1=2, wsc=1, wc2=0)[p.kind]
                recs = [w_record(int(sgn[ch] < 0), bias[ch], m0[ch], sh[ch], T[ch]) for ch in chs]
                pw = pw_word(recs, 0, om)
                if p.kind == "wc1":
                    yv = sum(after["Z"][0, b * L * p.cout:(b + 1) * L * p.cout].view(L, p.cout).cpu().numpy() << b
                             for b in range(8))
                elif p.kind == "wsc":
                    assert not p.p.get("r1")
                    yv = (Sa[:L * p.cout] + (Sa[L * p.cout:2 * L * p.cout] << 16)).view(L, p.cout).cpu().numpy()
                else:
                    yv = Sa[:L * p.cout].view(L, p.cout).cpu().numpy()
                if p.kind == "wc2":
                    sc = next(q for q in prog.passes if q.block == p.block and q.kind == "wsc")
                    assert not sc.p.get("r1")
                    Sb = before["S"][0]
                    rv = (Sb[:L * p.cout] + (Sb[L * p.cout:2 * L * p.cout] << 16)).view(L, p.cout).cpu().numpy()
                    b1 = after["B1"][0, :L * p.cout].view(L, p.cout).cpu().numpy()
                wr, wy, wb = [], [], []
                for k in range(32):
                    ys, bs, rs = [], [], []
                    for q in range(4):
                        px = 16 * tp + q + 4 * (k // 8)
                        for col in range(COLS):
                            ch = 64 * ct + 8 * col + 7 - k % 8
                            ys.append(yv[px, ch])
                            bs.append(b1[px, ch] if p.kind == "wc2" else 0)
                            rs.append(rv[px, ch] if p.kind == "wc2" else 0)
                    wr.append(pack_words(rs, 19))
                    wy.append(pack_words(ys, 19))
                    wb.append(pack_words(bs, 1))
                g.tile(items, "shadow", dict(lane="w", pi=pi, pw=pw, wr=wr, wy=wy, wb=wb))
        g.end_array()
    os.makedirs(outdir, exist_ok=True)
    n = g.st.write(os.path.join(outdir, "stim.txt"))
    with open(os.path.join(outdir, "exp_b2.txt"), "w") as fh:
        fh.writelines(f"{pi} {v:x}\n" for pi, v in g.eb2)
    with open(os.path.join(outdir, "exp_f.txt"), "w") as fh:
        fh.writelines(f"{pi} {y:x} {b:x}\n" for pi, y, b in g.ef)
    with open(os.path.join(outdir, "exp_w.txt"), "w") as fh:
        fh.writelines(f"{pi} {y:x} {b:x}\n" for pi, y, b in g.ew)
    with open(os.path.join(outdir, "passes.txt"), "w") as fh:
        fh.writelines(f"{i} {nm}\n" for i, nm in enumerate(names))
    return n, g


class _wrap:
    """read-only view of a buffer snapshot dict through Bufs.read."""

    def __init__(self, b):
        self.b = b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1])
    ap.add_argument("--golden", default="p2", choices=P.GOLDENS)
    a = ap.parse_args()
    dev = "cuda"
    prog, net, (xv, yv) = P.build_program(a.ckpt, dev, v=11, golden=a.golden)
    for i in a.images:
        x = xv[i:i + 1]
        lg, _ = D.run(prog, x, dev)
        assert torch.equal(lg, net(x)), "dataflow != golden"
        n, g = export_image(prog, net, x, os.path.join(a.out, f"img{i}"), dev)
        print(f"img{i}: {n} cycles, {len(g.eb2)} b2 words, {len(g.ef)} fused lane cycles, {len(g.ew)} wide lane cycles, "
              f"{g.stats}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
