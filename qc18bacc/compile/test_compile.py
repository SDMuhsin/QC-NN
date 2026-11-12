"""QC18B-ACC compiler tests (exit 1 on any failure):

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.test_compile [CKPT ...] [--n 500]

1. block-code table: 129 legal states, distinct 10-b PE codes, encode / decode round trip of every state, illegal codes
   rejected.
2. per checkpoint (default E6_s0, E6_s1): program.build_program (its asserts: codes -> qc18b M and -> IntBin W8, ACC_W 20
   bound, r <= 17 b (block 6: 19 b), qb_lane_s8 exact on every domain value, lane / threshold widths, buffer sizes);
   dataflow logits == IntBin logits (torch.equal) on val[:n].
3. sensitivity (first checkpoint, val[:100]): the dataflow must NOT match IntBin for a wrong lane shift select (b0.c2
   sel + 1), a wrong 8-b block code (b3.c1, one block) and a missing two's-complement sign plane (stem plane 7 positive).
4. v1.1 (--v 11 programs): program build (fused-lane fit asserts, exhaustive pre-clamp exactness) and dataflow logits ==
   IntBin on val[:n] per checkpoint; v1.1 schedule (NL 256, val[:n]) hazard check + tile replay of val[:4] in the
   scheduled order == IntBin; sensitivity: packed-stem group / plane order swapped, hm pre-clamp lo raised, scheduler
   without the WAR hazards (hazard check and replay must fail), without the drain-read RAW hazards (same).
"""
import argparse
import copy
import sys
import traceback

import numpy as np
import torch

from . import cycles as Cy
from . import dataflow as D
from . import program as P

CKPTS = ["/tmp/root/qc18b/exc200/E6_s0/best.pt", "/tmp/root/qc18b/exc200/E6_s1/best.pt"]


def test_codes():
    assert len(P.STATES) == 129 and len(set(P.DEC[:129].tolist())) == 129 and (P.DEC[129:] == -1).all()
    C = np.zeros((129, P.B), np.int64)
    for i, st in enumerate(P.STATES):
        for s, t in st:
            C[i, s] = t
    codes = P.encode(C[None])[0]
    assert np.array_equal(codes, np.arange(129)) and np.array_equal(P.decode(codes), C)
    for bad in (129, 255):
        try:
            P.decode(np.array([bad]))
        except AssertionError:
            continue
        raise AssertionError("illegal code accepted")
    return "codes: 129 states, encode/decode round trip, illegal codes rejected: PASS"


def mismatch(prog, net, val, n=100):
    xv, _ = val
    try:
        lg, _ = D.run(prog, xv[:n])
    except AssertionError:
        return True
    return not torch.equal(lg, net(xv[:n]))


def test_sensitivity(prog, net, val):
    out = []
    m = copy.deepcopy(prog)
    p = next(q for q in m.passes if q.name == "b0.c2")
    p.p["sel"] = (p.p["sel"] + 1).clamp(max=P.NSEL - 1)
    out.append(("b0.c2 sel + 1", mismatch(m, net, val)))
    m = copy.deepcopy(prog)
    p = next(q for q in m.passes if q.name == "b3.c1")
    r, c = np.argwhere(p.codes != 0)[0]
    p.codes[r, c] = 1 if p.codes[r, c] != 1 else 2
    out.append(("b3.c1 one block code", mismatch(m, net, val)))
    orig = D.pe_array

    def nosign(p_, planes, skip, W):
        return orig(p_, [(a, False) for a, _ in planes], skip, W)
    D.pe_array = nosign
    try:
        out.append(("stem plane 7 positive", mismatch(prog, net, val)))
    finally:
        D.pe_array = orig
    bad = [k for k, v in out if not v]
    assert not bad, f"mutants not detected: {bad}"
    return "sensitivity: " + ", ".join(f"{k} detected" for k, _ in out) + ": PASS"


def test_v11_sensitivity(prog, net, val):
    out = []
    g0 = D.GROUP_PLANE
    D.GROUP_PLANE = lambda h, g: 4 * h + (g ^ 1)
    try:
        out.append(("packed stem groups 0/1 swapped", mismatch(prog, net, val)))
    finally:
        D.GROUP_PLANE = g0
    m = copy.deepcopy(prog)
    p = next(q for q in m.passes if q.name == "b6.hm")
    assert p.ppu == "fused"
    p.p["f"]["lo"] = p.p["f"]["lo"] + 64
    out.append(("b6.hm pre-clamp lo + 64", mismatch(m, net, val)))
    bad = [k for k, v in out if not v]
    assert not bad, f"mutants not detected: {bad}"
    return "v1.1 sensitivity: " + ", ".join(f"{k} detected" for k, _ in out) + ": PASS"


def test_v11_schedule(prog, net, val, st, nrep=4):
    rows, per, tim = Cy.list_schedule(prog, st, 256, check=True)
    Cy.replay_check(prog, net, val, st, 256, nrep)
    T, pairs = Cy.BASE[(id(prog), "tiles")]
    base = Cy._bufbase(prog)
    xv, _ = val
    res = []
    for drop in ("WAR", "RAW"):
        T2 = [dict(d) for d in T]
        for d in T2:
            d["deps"] = [(a, fa, fb) for a, fa, fb in d["deps"]
                         if not ((drop == "WAR" and fb == "ws" and fa in ("rad", "rdd")) or (drop == "RAW" and fb == "rds"))]
        Cy.BASE[(id(prog), "tiles")] = (T2, pairs)
        v0 = Cy.verify
        try:
            try:
                Cy.list_schedule(prog, {k: v[:1] for k, v in st.items()}, 256, check=True)
                chk = False
            except AssertionError:
                chk = True
            Cy.verify = lambda *a: 0
            _, _, tm = Cy.list_schedule(prog, {k: v[:1] for k, v in st.items()}, 256, check=True)
        finally:
            Cy.verify = v0
            Cy.BASE[(id(prog), "tiles")] = (T, pairs)
        try:
            rep = not torch.equal(D.replay(prog, xv[:1], T2, base, {f: v[0] for f, v in tm.items()}), net(xv[:1]))
        except AssertionError:
            rep = True
        res.append((drop, chk, rep))
    bad = [r for r in res if not (r[1] and r[2])]
    assert not bad, f"hazard mutants not detected: {bad}"
    return (f"{prog.run} v1.1 schedule NL 256: {len(pairs)} hazard pairs hold on val[:{len(per)}], tile replay of "
            f"val[:{nrep}] == IntBin; scheduler without WAR / drain RAW hazards detected by both: PASS "
            f"({per.mean():.1f} cycles / image)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="*", default=CKPTS)
    ap.add_argument("--n", type=int, default=500)
    a = ap.parse_args()
    fails = 0

    def run(name, f, *args):
        nonlocal fails
        try:
            print(f(*args), flush=True)
        except Exception:
            fails += 1
            print(f"FAIL {name}", flush=True)
            traceback.print_exc()

    run("codes", test_codes)
    first = None
    for ck in a.ckpts:
        try:
            prog, net, val = P.build_program(ck, v=1)
            print(f"{prog.run}: program build (all bound / exactness / buffer asserts): PASS", flush=True)
            D.run_val(prog, net, val, a.n)
            first = first or (prog, net, val)
        except Exception:
            fails += 1
            print(f"FAIL {ck}", flush=True)
            traceback.print_exc()
    if first:
        run("sensitivity", test_sensitivity, *first)
    first11 = None
    for ck in a.ckpts:
        try:
            prog, net, val = P.build_program(ck, v=11)
            print(f"{prog.run}: v1.1 program build (fused-lane fit / exactness asserts): PASS", flush=True)
            st, _ = D.run_val(prog, net, val, a.n)
            run("v11 schedule", test_v11_schedule, prog, net, val, st)
            first11 = first11 or (prog, net, val)
        except Exception:
            fails += 1
            print(f"FAIL v1.1 {ck}", flush=True)
            traceback.print_exc()
    if first11:
        run("v11 sensitivity", test_v11_sensitivity, *first11)
    print("ALL PASS" if not fails else f"{fails} FAILED")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
