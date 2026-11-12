"""QC18B-ACC compiler tests (exit 1 on any failure):

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.test_compile [CKPT ...] [--n 500]

1. block-code table: 129 legal states, distinct 10-b PE codes, encode / decode round trip of every state, illegal codes
   rejected.
2. per checkpoint (default E6_s0, E6_s1): program.build_program (its asserts: codes -> qc18b M and -> IntBin W8, ACC_W 20
   bound, r <= 17 b (block 6: 19 b), qb_lane_s8 exact on every domain value, lane / threshold widths, buffer sizes);
   dataflow logits == IntBin logits (torch.equal) on val[:n].
3. sensitivity (first checkpoint, val[:100]): the dataflow must NOT match IntBin for a wrong lane shift select (b0.c2
   sel + 1), a wrong 8-b block code (b3.c1, one block) and a missing two's-complement sign plane (stem plane 7 positive).
"""
import argparse
import copy
import sys
import traceback

import numpy as np
import torch

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
            prog, net, val = P.build_program(ck)
            print(f"{prog.run}: program build (all bound / exactness / buffer asserts): PASS", flush=True)
            D.run_val(prog, net, val, a.n)
            first = first or (prog, net, val)
        except Exception:
            fails += 1
            print(f"FAIL {ck}", flush=True)
            traceback.print_exc()
    if first:
        run("sensitivity", test_sensitivity, *first)
    print("ALL PASS" if not fails else f"{fails} FAILED")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
