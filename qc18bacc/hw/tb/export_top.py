#!/usr/bin/env python3
"""R3a: descriptor + init-image export for the full-image bench of qb_top (hw/rtl/qb_top.sv, hw/tb/tb_qb_top.sv).

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top.py RUN/best.pt OUTDIR --cache DIR [--images 0 1] [--dist 1]

Schedule: compile/supply.py config C (two contexts, 512-b map port, block 6 from S) on the v1.1 list scheduler with the
RTL write-back latency `lat` (cycles.list_schedule hook, default off): a consumer's RAW gate (array load / drain read)
waits for the producer's last write to reach the macro, not for the model's abstract drain end.  Per image i (val[i],
never the test set), OUTDIR/img<i>/:
  core/      export_core.py files (exp_b2 / exp_f / exp_w = expected lane outputs per pass, in pass order)
  act/       export_act.py files (exp_<pi> = expected act-port items per array pass; mem_<stem> = image lines)
  d_pt.txt   pass table (one hex word per pass index, fields: see PT below)
  d_p0.txt d_p1.txt d_tq.txt d_cq.txt d_fq.txt d_wq.txt d_lt.txt   descriptor queues ('count' line, then hex words)
  w_rows.txt weight rows (2304 b each, row order = PT wbase + ct * wrow + chunk), p_sets.txt parameter sets (5189 b)
  img.txt    image map lines (stem source, compile/layout.py)
  s_final.txt  expected S lane words of block 7's output stream ('addr lane hex'), physical layout of qb_top
  sched.txt  model: 'X pi tp ct ce' per array tile, 'M per per0' (cycles with / without lat)
bub: an hm job directly after a c2 drain waits one cycle (shared s_rd port of qb_core, r1.md deviation 6).
Imports export_core / export_act / supply / cycles / layout (nothing copied).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
import torch  # noqa: E402

from qc18bacc.compile import cycles as Cy  # noqa: E402
from qc18bacc.compile import dataflow as D  # noqa: E402
from qc18bacc.compile import supply as SU  # noqa: E402
import export_act as EA  # noqa: E402
import export_core as EC  # noqa: E402

CFG_C = dict(width=512, b6="S", ctx=2)
AP = 1                                   # qb_act2 ACT_PIPE (as built)
KIND = dict(stem=0, bc1=1, bsc=2, bc2=3, hm=4, wc1=5, wsc=6, wc2=7)
SRC = dict(B1=0, B2=1, IMG=2, HQ=3, Z=3)


def lats(dist):
    """RTL write-back latency after the model's write-done time (qb_top.sv header), per consumer field.  D = 2 +
    ACT_PIPE + DIST.  'ras' (array load granted at g reads the macro at g + 1; the write request x reaches the macro at
    x + 1, so g >= x + 1): fused f_y at ds + D + 8 + k (k <= 3) -> D + 8; c1 b2 at cap + D + 4, then one line write per
    cycle (2 lines, W 4: 4) -> D + 7 / D + 9; wide w_y at ds + D + 9 + k (k <= 31) -> D + 9; hm / b6.c1 + 8 cycles of
    slice-flag queue margin (the RTL also gates the consumer's load on its flag bank being quiet).  'rds' (a drain or hm
    job reading what an earlier drain of the same tile / step mapping wrote): c2 reads at ds + D + 2 + k -> D - 1 after
    a fused producer, hm reads at ds + D + 1 + k -> D; wide producers 0.  'ws' (write after write): 0 (in-order
    write engines, later drain)."""
    D_ = 2 + AP + dist
    ras = dict(stem=D_ + 8, bsc=D_ + 8, bc2=D_ + 8, hm=D_ + 8 + 8, wc1=D_ + 9 + 8, wsc=D_ + 9, wc2=D_ + 9)
    return dict(D=D_, ras=ras)


def make_lat(prog, L):
    def f(a, fb, b):
        pa, pb = prog.passes[a["pi"]], prog.passes[b["pi"]]
        if fb == "ras":
            if pa.kind == "bc1":
                return L["D"] + 5 + (4 if pa.Wout == 4 else 2)
            return L["ras"][pa.kind]
        if fb == "rds":
            if pa.ppu == "wide" or pa.kind in ("wc1", "wsc", "wc2"):
                return 0
            assert pa.kind in ("stem", "bsc", "bc2") and pb.kind in ("bc2", "hm"), (pa.name, pb.name)
            assert (a["tp"], a["cg"]) == (b["tp"], b["cg"]) and pa.Hout * pa.Wout == pb.Hout * pb.Wout, (pa.name, pb.name)
            return L["D"] - 1 if pb.kind == "bc2" else L["D"]
        return 0
    return f


def hx(v):
    return format(int(v), "x")


def wq(path, words):
    with open(path, "w") as fh:
        fh.write(f"{len(words)}\n")
        fh.writelines(hx(w) + "\n" for w in words)


def pack(fields):
    """[(value, width)] LSB first -> int."""
    v, o = 0, 0
    for x, w in fields:
        assert 0 <= int(x) < (1 << w), (x, w)
        v |= int(x) << o
        o += w
    return v


def h2(a):
    return (a ^ (a >> 1)) & 3


def s_loc(e):
    """flat stream entry e -> (S address, physical lane, entry) of qb_top (XOR-swizzled lane groups)."""
    a = e >> 8
    return a, 8 * (((e >> 6) & 3) ^ h2(a)) + ((e >> 3) & 7), e & 7


def params_from_stim(prog, stim):
    """parameter sets per (pass, ct) from export_core's stim.txt (pf at fused drains / hm jobs, pw at wide drains, t2
    two cycles after each cmp capture), in export_core's pass / tile order."""
    rows = [ln.split() for ln in open(stim)]
    F = EC.Stim.FIELDS
    ix = {f: F.index(f) for f in F}
    fpf, fhm, wpw, t2 = [], [], [], []
    for t, r in enumerate(rows):
        fc = int(r[ix["fctl"]], 16)
        if fc & 8:
            (fhm if fc & 2 else fpf).append(int(r[ix["pf"]], 16))
        if int(r[ix["wctl"]], 16) & 4:
            wpw.append(int(r[ix["pw"]], 16))
        if int(r[ix["ctl"]], 16) & 0x200:
            t2.append(int(rows[t + 2][ix["t2"]], 16))
    sets, base = [], {}
    it = {"f": iter(fpf), "w": iter(wpw), "t": iter(t2)}
    for pi, p in enumerate(prog.passes):
        if p.kind == "hm":
            base[pi] = len(sets)
            assert all(v == fhm[0] for v in fhm)
            sets.append(fhm[0])
            continue
        src = {"bc1": "t", "wc1": "w", "wsc": "w", "wc2": "w"}.get(p.kind, "f")
        nct = p.cout // 64
        got = {}
        for tp in range(p.tiles_px):
            for ct in range(nct):
                v = next(it[src])
                if p.kind == "bc1":
                    got.setdefault(ct, v)
                    assert got[ct] == v
                else:
                    got.setdefault(ct, v)
                    assert got[ct] == v, (p.name, tp, ct)
        base[pi] = len(sets)
        sets.extend(got[ct] for ct in range(nct))
    for k in it.values():
        assert next(k, None) is None
    return sets, base


def weight_rows(prog):
    rows, base, wrow = [], {}, {}
    for pi, p in enumerate(prog.passes):
        if not p.k:
            continue
        stem = bool(p.p.get("pack"))
        base[pi], wrow[pi] = len(rows), (1 if stem else p.nchunk)
        for ct in range(p.cout // 64):
            for c in range(wrow[pi]):
                rows.append(EC.codes_item(p, ct, c, stem))
    assert len(rows) <= 612, len(rows)
    return rows, base, wrow


def pass_table(prog, wbase, wrow, pbase, lbase, lcnt):
    out = []
    for pi, p in enumerate(prog.passes):
        if p.kind == "hm":
            cfg = nch = ntile = int8 = stem = sbase = 0
            nct = p.cin // 64
            src = 0
            lgc = 2                                           # s5: C = 256
            lgw = 3
        else:
            cfg = EA.CFG[p.Win, p.stride, p.k]
            nch = 2 if p.p.get("pack") else p.nchunk
            nct, ntile = p.cout // 64, p.tiles_px
            int8 = int(p.inb == 8 and p.src != "IMG")
            stem = int(p.src == "IMG")
            sbase = 0 if not int8 else {8: 128, 9: 192, 10: 208}[cfg]
            src = SRC[p.src]
            lgc = {64: 0, 128: 1, 256: 2, 512: 3}[p.cout]
            lgw = {32: 5, 16: 4, 8: 3, 4: 2}[p.Wout]
        b1 = int("B1" in p.dst)
        out.append(pack([(cfg, 4), (nch, 5), (nct, 4), (ntile, 7), (int8, 1), (stem, 1), (sbase, 9), (KIND[p.kind], 4),
                         (src, 2), (wbase.get(pi, 0), 10), (wrow.get(pi, 0), 5), (lgc, 3), (lgw, 3), (pbase[pi], 10),
                         (b1, 1), (lbase.get(pi, 0), 10), (lcnt.get(pi, 0), 10)]))
    return out


def export_sched(prog, T, tim, log, img, od, lat):
    """descriptor queues of one image from the scheduled times (tim) and the supply log (commit order)."""
    g = lambda f, t: int(tim[f][img][t])          # noqa: E731
    p0, p1, tq, cq, fq, wqq = [], [], [], [], [], []
    lt, lbase, lcnt = [], {}, {}
    seen = set()
    t_sh = 0
    caps = {}
    for seq, e in enumerate(log):
        t, pi = e["t"], e["pi"]
        assert g("st", t) == e["s"] and g("ce", t) == e["ce"]
        p = prog.passes[pi]
        if pi not in seen:
            seen.add(pi)
            (p0 if e["ctx"] == 0 else p1).append(pack([(pi, 5), (e["cstart"] - 1, 16)]))
        tq.append(pack([(e["ctx"], 1), (e["s"], 16)]))
        if T[t]["u"] == "pecmp":
            cap = e["ce"]
        else:
            cap = max(e["ce"], t_sh)
            t_sh = g("de", t)
            assert g("ds", t) >= cap
        caps[t] = cap
        cq.append((cap, pack([(int(p.kind == "bc1"), 1), (pi, 5), (e["tp"], 7), (e["cg"], 4), (cap, 16)])))
    cq.sort()
    assert all(a[0] < b[0] for a, b in zip(cq, cq[1:])), "two captures in one cycle"
    # load-permission tables per pass (commit order, deduplicated by position)
    for pi in sorted({e["pi"] for e in log}):
        ent = [(e["pos"], e["ra"], seq) for seq, e in enumerate(log) if e["pi"] == pi]
        dd = []
        for x in ent:
            if not dd or x[0] != dd[-1][0]:
                dd.append(x)
        assert all(a[0] < b[0] for a, b in zip(dd, dd[1:]))
        lbase[pi], lcnt[pi] = len(lt), len(dd)
        lt.extend(pack([(pos, 10), (ra, 16), (sq, 16)]) for pos, ra, sq in dd)
    # PPU jobs
    for t, d in enumerate(T):
        p = prog.passes[d["pi"]]
        if d["u"] == "pecmp":
            continue
        ds = g("ds", t)
        w = pack([(d["pi"], 5), (d["tp"], 7), (d["cg"], 4), (ds, 16)])
        (fq if d["u"] == "fused" else wqq).append((ds, w))
    fq.sort()
    wqq.sort()
    assert all(b[0] - a[0] >= 4 for a, b in zip(fq, fq[1:])), "fused jobs closer than 4 cycles"
    assert all(b[0] - a[0] >= 32 for a, b in zip(wqq, wqq[1:])), "wide drains closer than 32 cycles"
    for nm, q in (("p0", p0), ("p1", p1), ("tq", tq), ("cq", [w for _, w in cq]), ("fq", [w for _, w in fq]),
                  ("wq", [w for _, w in wqq]), ("lt", lt)):
        wq(os.path.join(od, f"d_{nm}.txt"), q)
    with open(os.path.join(od, "sched.txt"), "w") as fh:
        for e in log:
            fh.write(f"X {e['pi']} {e['tp']} {e['cg']} {e['ce']}\n")
    return lbase, lcnt


def s_final(prog, x, dev, od):
    Ws = {p.name: D.PEWeights(p, dev) for p in prog.passes if p.k}
    bf = D.Bufs(1, dev)
    D.load_image(prog, bf, x, dev)
    with torch.no_grad():
        for p in prog.passes:
            p.p["dev"] = dev
            D.do_pass(prog, p, bf, Ws, dev, {})
    last = prog.passes[-1]
    n = last.Hout * last.Wout * last.cout
    s = bf.b["S"][0, :n].cpu().numpy()
    words = {}
    for e in range(n):
        a, ln, k = s_loc(e)
        words[(a, ln)] = words.get((a, ln), 0) | ((int(s[e]) & 0xFFFF) << (16 * k))
    with open(os.path.join(od, "s_final.txt"), "w") as fh:
        for (a, ln), v in sorted(words.items()):
            fh.write(f"{a} {ln} {v:x}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1])
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--dist", type=int, default=1)
    a = ap.parse_args()
    dev = "cuda"
    prog, net, val, st, correct, mk = SU.load(a.ckpt, a.n, a.cache)
    _, per0, _ = SU.run(prog, st, mk, 2, CFG_C)
    L = lats(a.dist)
    latf = make_lat(prog, L)
    sup = SU.Supply(prog, mk, **CFG_C)
    T0 = Cy.BASE[(id(prog), "tiles")][0]
    bubf = lambda prev, t: int(prev is not None and prog.passes[T0[prev]["pi"]].kind == "bc2"   # noqa: E731
                               and prog.passes[T0[t]["pi"]].kind == "hm")
    _, per, tim = Cy.list_schedule(prog, st, SU.NL, SU.NWD, ctx=2, sup=sup, check=True, lat=latf, bub=bubf)
    T = Cy.BASE[(id(prog), "tiles")][0]
    print(f"config C mean {per0.mean():.1f} -> with lat {per.mean():.1f} cycles / image (val[:{a.n}]), lat {L}",
          flush=True)
    rows, wbase, wrow = weight_rows(prog)
    xv, _ = val
    for i in a.images:
        od = os.path.join(a.out, f"img{i}")
        os.makedirs(os.path.join(od, "core"), exist_ok=True)
        x = xv[i:i + 1]
        n, gg = EC.export_image(prog, net, x, os.path.join(od, "core"), dev)
        meta, nit = EA.export_image(prog, net, x, os.path.join(od, "act"), dev)
        sets, pbase = params_from_stim(prog, os.path.join(od, "core", "stim.txt"))
        lbase, lcnt = export_sched(prog, T, tim, sup.final[i].log, i, od, latf)
        wq(os.path.join(od, "d_pt.txt"), pass_table(prog, wbase, wrow, pbase, lbase, lcnt))
        with open(os.path.join(od, "w_rows.txt"), "w") as fh:
            fh.writelines(format(r, "0576x") + "\n" for r in rows)
        with open(os.path.join(od, "p_sets.txt"), "w") as fh:
            fh.writelines(format(s, "x") + "\n" for s in sets)
        stem = next(pi for pi, p in enumerate(prog.passes) if p.src == "IMG")
        os.replace(os.path.join(od, "act", f"mem_{stem}.txt"), os.path.join(od, "img.txt"))
        s_final(prog, x, dev, od)
        with open(os.path.join(od, "sched.txt"), "a") as fh:
            fh.write(f"M {int(per[i])} {int(per0[i])}\n")
        print(f"img{i}: model cycles {int(per[i])} (config C without lat {int(per0[i])}), {len(rows)} weight rows, "
              f"{len(sets)} parameter sets, {nit} items", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
