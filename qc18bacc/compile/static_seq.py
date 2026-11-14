"""R3b: image-independent sequencer program of QC18B-ACC + its hardware-semantics check, and the params-path model.

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.static_seq RUN/best.pt [RUN2/best.pt] --cache DIR [--n 100]

Static issue order: the list scheduler (compile/cycles.list_schedule, supply config C, RTL write-back latency `lat`,
`bub`; as hw/tb/export_top.py) is run free on val[:n]; its commit order (all tiles, array + PPU-only) is recorded per
image (hook `rec`).  The most frequent order is the network's static order; the schedule is then re-run with the order
forced (hook `order`) and the per-image delta reported (0 when every image commits in that order).

Hardware sequencer (hw/rtl/qb_top.sv, SEQ = 1) = an in-order commit engine over that order, `emulate()` here is its
event-level mirror (checked against the forced-order model's times on every image):
  * stamp table: per committed tile the time its writes are done (de; pecmp: capture), valid bit cleared at go;
  * RAW gate of an array tile (its 'ras' hazards): ra = stamp[rasdep] + raslat, rasdep = the producer tile committed
    last among its hazards (producers of one pass drain in order, so its stamp is the max); 'rds' (drain-time read
    after write) likewise with rdsdep / rdslat.  WAR / WAW hazards ('ws') are implied by the in-order array / lane
    FIFOs and the RAW chain (checked: dropping them changes no time);
  * start (tile token) of array tile k, evaluated every cycle once the previous array tile has ended:
    now >= t_arr, now >= ra (+ OVH at a pass switch when ra > t_arr), drained tiles now + C >= t_sh (C: binary =
    chunk items, static; int8 = executed slices from the writer-side flags, final before ra);
  * end of array tile k at its ce (last item + 1, from the act supply): cap = max(ce, t_sh), ds = max(cap, lane, rw),
    de = ds + drain; PPU-only tiles (hm) end when reached: ds = max(lane + bub, rw) (+ OVH first of pass if rw >
    lane + bub).  One tile per cycle; an event (capture, PPU job) at or after its processing cycle;
  * act-supply contexts: per-context static pass list, next pass started the cycle after the context's done pulse;
    load permissions: per pass (pos, rasdep, raslat, seq) entries (binary: pos = virtual rows, static; int8: pos =
    (j + 1) x executed S words per channel tile, from the flags).
"""
import argparse
import collections
import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "hw", "tb")))

from . import cycles as Cy  # noqa: E402
from . import supply as SU  # noqa: E402
import export_top as ET  # noqa: E402

DR = dict(fused=4, wide=32, pecmp=0)


def hooks(prog, dist=1):
    latf = ET.make_lat(prog, ET.lats(dist))
    T0 = Cy.tiles_of(prog)[0]
    bubf = lambda prev, t: int(prev is not None and prog.passes[T0[prev]["pi"]].kind == "bc2"   # noqa: E731
                               and prog.passes[T0[t]["pi"]].kind == "hm")
    return latf, bubf


def run(prog, st, mk, order=None, rec=None, dist=1):
    latf, bubf = hooks(prog, dist)
    sup = SU.Supply(prog, mk, **ET.CFG_C)
    _, per, tim = Cy.list_schedule(prog, st, SU.NL, SU.NWD, ctx=2, sup=sup, check=True, lat=latf, bub=bubf,
                                   order=order, rec=rec)
    return per, tim, sup


def static_order(prog, st, mk):
    rec = {}
    per, tim, sup = run(prog, st, mk, rec=rec)
    c = collections.Counter(tuple(v) for v in rec.values())
    order = list(c.most_common(1)[0][0])
    per2, tim2, sup2 = run(prog, st, mk, order=order)
    return order, per, per2, tim2, sup2, len(c)


def program(prog, st, order, sup, dist=1):
    """static descriptors in commit order: list of dicts (see the module doc), context pass lists."""
    latf, _ = hooks(prog, dist)
    T = Cy.BASE[(id(prog), "tiles")][0]
    pos = {t: k for k, t in enumerate(order)}
    first = {}
    for t, d in enumerate(T):
        first.setdefault(d["pi"], t)
    ctx = {}
    for e in sup.final[0].log:
        ctx.setdefault(e["pi"], e["ctx"])
    desc = []
    for k, t in enumerate(order):
        d = T[t]
        p = prog.passes[d["pi"]]
        e = dict(k=k, t=t, pi=d["pi"], tp=d["tp"], ct=d["cg"], arr=d["arr"], u=d["u"], kind=p.kind,
                 ctx=ctx.get(d["pi"], 0), first=(t == first[d["pi"]]))
        for f in ("ras", "rds"):
            dep = [(pos[a], latf(T[a], f, d)) for a, fa, fb in d["deps"] if fb == f]
            assert all(fa == "wd" for a, fa, fb in d["deps"] if fb == f)
            if dep:
                assert len({x[1] for x in dep}) == 1, (p.name, f, dep)
                assert len({T[order[x[0]]]["pi"] for x in dep}) == 1
                e[f] = max(dep)
            else:
                e[f] = None
        if d["arr"]:
            int8 = p.inb == 8 and p.kind != "stem"
            e["i8"] = {"wc1": 1, "wsc": 2, "wc2": 3}[p.kind] if int8 else 0
            if not int8:
                C = Cy.tile_items(p, st[p.name], Cy.FL_ALL)[:, d["tp"] * (p.cout // 64) + d["cg"]]
                assert (C == C[0]).all()
                e["C"] = int(C[0])
        desc.append(e)
    pl = [[], []]
    for k, e in enumerate(desc):
        if e["arr"] and (k == 0 or e["pi"] not in pl[e["ctx"]]):
            pl[e["ctx"]].append(e["pi"])
    return desc, pl


def emulate(desc, ce, C, ovh=Cy.OVH):
    """event-level mirror of the RTL commit engine for one image.  ce[k], C[k]: runtime compute end / items of array
    tile k (from the act supply / the flags).  Returns {k: (s, ce, ds, de)} and a list of timing violations (an
    event needed before the engine could know it)."""
    st = [None] * len(desc)
    stamp = [None] * len(desc)
    proc = [None] * len(desc)
    t_arr = t_sh = 0
    lane = dict(fused=0, wide=0)
    lbc2 = False
    last_arr, prev_arr = None, None
    bad = []
    tprev = -1
    out = {}
    for k, e in enumerate(desc):
        rw = 0 if e["rds"] is None else stamp[e["rds"][0]] + e["rds"][1]
        if not e["arr"]:
            ln = lane[e["u"]] + int(lbc2 and e["kind"] == "hm")
            ds = max(ln, rw) + (ovh if (e["first"] and rw > ln) else 0)
            de = ds + DR[e["u"]]
            lane[e["u"]] = de
            lbc2 = False if e["u"] == "fused" else lbc2
            proc[k] = tprev + 1
            if ds < proc[k]:
                bad.append(("ppu late", k))
            stamp[k] = de
            out[k] = (None, None, ds, de)
            tprev = proc[k]
            continue
        # start (token)
        ev = 0 if prev_arr is None else proc[prev_arr]
        ra = 0
        if e["ras"] is not None:
            ra = stamp[e["ras"][0]] + e["ras"][1]
            ev = max(ev, proc[e["ras"][0]] + 1)
        if e["pi"] != last_arr and ra > t_arr:
            ra += ovh
        s = max(t_arr, ra, (t_sh - C[k]) if e["u"] != "pecmp" else 0)
        if s < ev:
            bad.append(("start late", k, s, ev))
        # end at ce
        proc[k] = max(ce[k], tprev + 1)
        if e["u"] == "pecmp":
            cap = ds = de = ce[k]
        else:
            cap = max(ce[k], t_sh)
            ds = max(cap, lane[e["u"]], rw)
            de = ds + DR[e["u"]]
            t_sh = de
            lane[e["u"]] = de
            if e["u"] == "fused":
                lbc2 = e["kind"] == "bc2"
        if cap < proc[k] or ds < proc[k]:
            bad.append(("end late", k))
        t_arr, last_arr, prev_arr = cap, e["pi"], k
        stamp[k] = de
        out[k] = (s, ce[k], ds, de)
        tprev = proc[k]
    return out, bad


def check(prog, st, order, desc, tim, n):
    T = Cy.BASE[(id(prog), "tiles")][0]
    nbad = nmis = 0
    for img in range(n):
        ce = {k: int(tim["ce"][img][e["t"]]) for k, e in enumerate(desc) if e["arr"]}
        C = {}
        for k, e in enumerate(desc):
            if e["arr"]:
                p = prog.passes[e["pi"]]
                C[k] = int(Cy.tile_items(p, st[p.name], Cy.FL_ALL)[img, e["tp"] * (p.cout // 64) + e["ct"]])
        out, bad = emulate(desc, ce, C)
        nbad += len(bad)
        for k, e in enumerate(desc):
            s, c, ds, de = out[k]
            t = e["t"]
            ref = (int(tim["st"][img][t]) if e["arr"] else None, int(tim["ce"][img][t]) if e["arr"] else None,
                   int(tim["ds"][img][t]), int(tim["de"][img][t]))
            if (s, c, ds, de) != ref:
                nmis += 1
                if nmis <= 5:
                    print("EMU MISMATCH img", img, k, prog.passes[e["pi"]].name, e["tp"], e["ct"], (s, c, ds, de), ref)
        if bad and nbad <= 5:
            print("EMU LATE img", img, bad[:3])
    return nmis, nbad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", required=True)
    a = ap.parse_args()
    for ck in a.ckpts:
        prog, net, val, st, correct, mk = SU.load(ck, a.n, a.cache)
        order, per, per2, tim2, sup2, nord = static_order(prog, st, mk)
        d = per2 - per
        print(f"{prog.run}: free {per.mean():.2f} static {per2.mean():.2f} delta mean {d.mean():.2f} min {d.min()} "
              f"max {d.max()} nonzero {(d != 0).sum()} / {len(d)}; distinct commit orders {nord}", flush=True)
        desc, pl = program(prog, st, order, sup2)
        nmis, nbad = check(prog, st, order, desc, tim2, a.n)
        print(f"{prog.run}: hardware engine emulation vs forced-order model: {nmis} time mismatches, {nbad} late events "
              f"over {a.n} images x {len(desc)} tiles; ctx pass lists {pl}", flush=True)


if __name__ == "__main__":
    main()
