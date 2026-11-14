#!/usr/bin/env python3
"""R3b: network program + per-image vectors for the full-image bench of qb_top with R3B = 1 (hw/rtl/qb_seq.sv).

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top2.py RUN/best.pt OUTDIR --cache DIR [--images 0 1] [--n 100]

OUTDIR/prog/ (one per network / seed, image independent; compile/static_seq.py on val[:n]):
  w_rows.txt   weight rows (as R3a)
  p_rows.txt   params bank rows (1296 b = 9 x rf_sp 240 x 144): per pass, per ct one set of 4 rows (pf 64 x 81 b / pw
               64 x 79 b) or 1 row (T2 64 x 17 b); hm one pf set
  d_pt.txt     pass table (R3a fields; pb = bank row base, lb / lc = load-permission entries; [93:89] common pf / pw bits)
  d_p0.txt d_p1.txt   per-context pass lists (pass index)
  d_lt.txt     load-permission entries {seq[15:0], raslat[4:0], rasdep[9:0], ras_v, pos[9:0]} per pass in commit order
               (binary: deduplicated by position; int8: one per channel tile, position from the flags)
  d_ds.txt     80-b tile descriptors in the static commit order (qb_seq dsc_t)
  d_ff.txt d_fw.txt d_ft.txt   params fetch lists of the fused / wide / T2 consumers {nuse[7:0], base row[7:0], tag}
  order.txt    static order (tile indices), model.txt per-image cycles (free list schedule vs static order, val[:n])
OUTDIR/img<i>/: core/, act/, img.txt, s_final.txt as R3a; sched.txt from the static-order model (the bench's reference:
  'X pi tp ct ce' per array tile, 'M <static-order cycles> <free list-schedule cycles>').
Imports export_top / export_core / export_act / static_seq (nothing copied).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from qc18bacc.compile import cycles as Cy  # noqa: E402
from qc18bacc.compile import static_seq as SS  # noqa: E402
from qc18bacc.compile import supply as SU  # noqa: E402
import export_act as EA  # noqa: E402
import export_core as EC  # noqa: E402
import export_top as ET  # noqa: E402

RW, NROW = 1296, 240                       # params bank row (9 x 144 b), depth
NR = dict(f=4, w=4, t=1)
UCODE = dict(pecmp=0, fused=1, wide=2)


def consumer(p):
    if p.kind == "bc1":
        return "t"
    return "w" if p.kind in ("wc1", "wsc", "wc2") else "f"


def bank(prog, sets, sbase):
    """params bank rows + row base per pass + common bits per pass."""
    rows, rbase, cmn = [], {}, {}
    for pi, p in enumerate(prog.passes):
        if not (p.k or p.kind == "hm"):
            continue
        c = consumer(p)
        nset = 1 if p.kind == "hm" else p.cout // 64
        rbase[pi] = len(rows)
        for ct in range(nset):
            v = sets[sbase[pi] + ct]
            nb = dict(f=5184, w=5056, t=1088)[c]
            cm = v >> nb
            assert cmn.setdefault(pi, cm) == cm, p.name
            v &= (1 << nb) - 1
            rows.extend((v >> (RW * r)) & ((1 << RW) - 1) for r in range(NR[c]))
    assert len(rows) <= NROW, len(rows)
    return rows, rbase, cmn


def dword(e, nxa):
    return ET.pack([(e["pi"], 5), (e["tp"], 7), (e["ct"], 4), (int(e["arr"]), 1), (UCODE[e["u"]], 2), (e["ctx"], 1),
                    (int(e["kind"] == "bc2"), 1), (int(e["kind"] == "hm"), 1), (int(e["first"]), 1), (e.get("C", 0), 6),
                    (e.get("i8", 0), 2),
                    (int(e["ras"] is not None), 1), (e["ras"][0] if e["ras"] else 0, 10), (e["ras"][1] if e["ras"] else 0, 5),
                    (int(e["rds"] is not None), 1), (e["rds"][0] if e["rds"] else 0, 10), (e["rds"][1] if e["rds"] else 0, 5),
                    (nxa if nxa is not None else 0, 10), (int(nxa is not None), 1)])


def load_perm(prog, desc, sup, n):
    """per pass entries in commit order; binary positions checked image independent on val[:n]."""
    kof = {e["t"]: e["k"] for e in desc}
    pos = {}
    for img in range(n):
        for le in sup.final[img].log:
            p = prog.passes[le["pi"]]
            if p.inb == 8 and p.kind != "stem":
                continue
            assert pos.setdefault(le["t"], le["pos"]) == le["pos"], "binary load position differs between images"
    lt, lbase, lcnt = [], {}, {}
    for pi, p in enumerate(prog.passes):
        ent = [e for e in desc if e["arr"] and e["pi"] == pi]
        if not ent:
            continue
        i8 = p.inb == 8 and p.kind != "stem"
        dd = []
        for e in ent:
            ps = 0 if i8 else pos[e["t"]]
            if i8 or not dd or ps != dd[-1][0]:
                dd.append((ps, e))
        if not i8:
            assert all(a[0] < b[0] for a, b in zip(dd, dd[1:]))
        lbase[pi], lcnt[pi] = len(lt), len(dd)
        for ps, e in dd:
            r = e["ras"]
            lt.append(ET.pack([(ps, 10), (int(r is not None), 1), (r[0] if r else 0, 10), (r[1] if r else 0, 5),
                               (kof[e["t"]], 16)]))
    return lt, lbase, lcnt


def fetch_lists(prog, desc, rbase):
    fl = dict(f=[], w=[], t=[])
    for e in desc:
        p = prog.passes[e["pi"]]
        c = consumer(p)
        ct = 0 if p.kind == "hm" else e["ct"]
        tag = (ct << 5) | e["pi"]
        base = rbase[e["pi"]] + ct * NR[c]
        L = fl[c]
        if L and L[-1][2] == tag:
            L[-1][0] += 1
        else:
            L.append([1, base, tag])
    out = {}
    for c, L in fl.items():
        assert all(x[0] <= 255 for x in L) and len(L) <= 255, (c, len(L), max(x[0] for x in L))
        out[c] = [ET.pack([(tag, 9), (base, 8), (nu, 8)]) for nu, base, tag in L]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1])
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", required=True)
    a = ap.parse_args()
    dev = "cuda"
    prog, net, val, st, correct, mk = SU.load(a.ckpt, a.n, a.cache)
    order, per, per2, tim, sup, nord = SS.static_order(prog, st, mk)
    desc, pl = SS.program(prog, st, order, sup)
    nmis, nbad = SS.check(prog, st, order, desc, tim, a.n)
    assert nmis == 0 and nbad == 0
    d = per2 - per
    print(f"{prog.run}: static order from {nord} distinct commit order(s) on val[:{a.n}]; free {per.mean():.2f} static "
          f"{per2.mean():.2f} delta mean {d.mean():.2f} min {d.min()} max {d.max()}; engine emulation 0 mismatches",
          flush=True)
    pd = os.path.join(a.out, "prog")
    os.makedirs(pd, exist_ok=True)
    xv, _ = val
    sets = None
    for n_, i in enumerate(a.images):
        od = os.path.join(a.out, f"img{i}")
        os.makedirs(os.path.join(od, "core"), exist_ok=True)
        x = xv[i:i + 1]
        EC.export_image(prog, net, x, os.path.join(od, "core"), dev)
        meta, nit = EA.export_image(prog, net, x, os.path.join(od, "act"), dev)
        s_i, sb_i = ET.params_from_stim(prog, os.path.join(od, "core", "stim.txt"))
        if sets is None:
            sets, sbase = s_i, sb_i
        assert s_i == sets and sb_i == sbase, "parameter sets differ between images"
        stem = next(pi for pi, p in enumerate(prog.passes) if p.src == "IMG")
        os.replace(os.path.join(od, "act", f"mem_{stem}.txt"), os.path.join(od, "img.txt"))
        ET.s_final(prog, x, dev, od)
        with open(os.path.join(od, "sched.txt"), "w") as fh:
            for le in sup.final[i].log:
                fh.write(f"X {le['pi']} {le['tp']} {le['cg']} {le['ce']}\n")
            fh.write(f"M {int(per2[i])} {int(per[i])}\n")
        print(f"img{i}: static-order model cycles {int(per2[i])} (free list schedule {int(per[i])}), {nit} items",
              flush=True)
    # ---- network program
    rows, rbase, cmn = bank(prog, sets, sbase)
    lt, lbase, lcnt = load_perm(prog, desc, sup, a.n)
    wr, wbase, wrow = ET.weight_rows(prog)
    pt = ET.pass_table(prog, wbase, wrow, {pi: rbase.get(pi, 0) for pi in range(len(prog.passes))}, lbase, lcnt)
    pt = [w | (cmn.get(pi, 0) << 89) for pi, w in enumerate(pt)]
    arr_k = [e["k"] for e in desc if e["arr"]]
    nxt = {k: (arr_k[j + 1] if j + 1 < len(arr_k) else None) for j, k in enumerate(arr_k)}
    assert desc[0]["arr"]
    ds = [dword(e, nxt.get(e["k"])) for e in desc]
    fl = fetch_lists(prog, desc, rbase)
    ET.wq(os.path.join(pd, "d_pt.txt"), pt)
    ET.wq(os.path.join(pd, "d_p0.txt"), pl[0])
    ET.wq(os.path.join(pd, "d_p1.txt"), pl[1])
    ET.wq(os.path.join(pd, "d_lt.txt"), lt)
    ET.wq(os.path.join(pd, "d_ds.txt"), ds)
    ET.wq(os.path.join(pd, "d_ff.txt"), fl["f"])
    ET.wq(os.path.join(pd, "d_fw.txt"), fl["w"])
    ET.wq(os.path.join(pd, "d_ft.txt"), fl["t"])
    with open(os.path.join(pd, "w_rows.txt"), "w") as fh:
        fh.writelines(format(r, "0576x") + "\n" for r in wr)
    with open(os.path.join(pd, "p_rows.txt"), "w") as fh:
        fh.writelines(format(r, "0324x") + "\n" for r in rows)
    with open(os.path.join(pd, "order.txt"), "w") as fh:
        fh.write(" ".join(map(str, order)) + "\n")
    with open(os.path.join(pd, "model.txt"), "w") as fh:
        fh.writelines(f"{i} {int(per[i])} {int(per2[i])}\n" for i in range(len(per)))
    bits = dict(ds=80 * len(ds), lt=42 * len(lt), fl=25 * sum(len(v) for v in fl.values()), pl=5 * (len(pl[0]) + len(pl[1])))
    print(f"program: {len(desc)} tiles, {len(lt)} load-permission entries, fetch lists f/w/t "
          f"{len(fl['f'])}/{len(fl['w'])}/{len(fl['t'])}, params rows {len(rows)} / {NROW}; descriptor bits {bits} "
          f"total {sum(bits.values())}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
