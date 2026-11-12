"""Exact cycle count of QC18B-ACC (ARCH.md v1) per pass and per image from the program's schedule and the dataflow
model's executed chunk items (plane skipping is data dependent):

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.cycles RUN1/best.pt [RUN2/best.pt ...] [--n 500] [--out MD]

Schedule of an array pass (tiles in order pixel tile outer, 64-channel tile inner):
  compute C_k = executed chunk items of tile k (binary: Cin / 32 chunks, 1x1: 1; stem: 8 planes; block 6: (chunk, plane)
  items whose patch is not all zero, measured per image by qc18bacc.compile.dataflow);
  drain D = ceil(1024 / units) with units = NCMP compare units (binary c1), NL fused lanes (stem, binary sc / c2) or
  NW wide lanes (block-6 c1 / sc / c2);
  shadow double buffering: tile k's drain overlaps tile k+1's compute; tile k+1 can capture only when the shadow is free:
  capture_k = capture_{k-1} + max(C_k, D_{k-1}) (capture_0 = C_0);  pass = capture_last + D + OVH.
PPU-only pass (block-6 hm): ceil(outputs / NW) + OVH.  Head (pool + FC) overlapped with the next image: 0.
Array cycles = sum C_k, PPU cycles = tiles x D; bound = array if array cycles >= PPU cycles else PPU.
Executed MAC = nonzero ternary terms x output positions (workload.py 'exec'); utilisation = MAC / (73 728 x cycles).
Every run first asserts the dataflow logits == IntBin logits (torch.equal) on the same images.
"""
import argparse
import os
import sys

import numpy as np

from . import dataflow as D
from . import program as P

SLOTS = P.ROWS * P.COLS * P.KB * 2 * P.B          # 73 728 MAC slots / cycle
NCMP, NW, OVH = 512, 16, 12
NLS = (64, 128, 192, 256, 384)


def cdiv(a, b):
    return -(-a // b)


def drain(p, NL, nw=NW):
    return cdiv(1024, {"compare": NCMP, "fused": NL, "wide": nw}[p.ppu])


def pass_cycles(p, items, NL, nw=NW, ovh=OVH):
    """items: [N, Tp] executed chunk items per pixel tile (None for the PPU-only pass).  Returns per-image arrays
    (cycles, array cycles, PPU cycles)."""
    if p.ppu == "wide-only":
        c = cdiv(p.cin * p.Hout * p.Wout, nw)
        return np.full(1, c + ovh), np.zeros(1), np.full(1, c)
    ncg = p.cout // P.NCH
    C = np.repeat(items, ncg, axis=1)                    # [N, tiles], pixel tile outer, channel tile inner
    d = drain(p, NL, nw)
    cap = C[:, 0].astype(np.int64)
    for k in range(1, C.shape[1]):
        cap = cap + np.maximum(C[:, k], d)
    return cap + d + ovh, C.sum(1), np.full(C.shape[0], d * C.shape[1])


def schedule(prog, st, NL, nw=NW, ovh=OVH):
    rows = []
    for p in prog.passes:
        cyc, arr, ppu = pass_cycles(p, st.get(p.name), NL, nw, ovh)
        if p.k:
            tot = p.nchunk * (8 if p.inb == 8 else 1) * p.tiles_px
            skip = 1 - st[p.name].sum(1).mean() / tot if p.inb == 8 else 0.0
            items = st[p.name].sum(1).mean() * (p.cout // P.NCH)
        else:
            skip, items = 0.0, 0.0
        rows.append(dict(name=p.name, ppu=p.ppu, tiles=p.tiles if p.k else 0, items=items, skip=skip, arr=arr.mean(), ppuc=ppu.mean(),
                         cyc=cyc.mean(), mac=p.mac, cyc_img=cyc))
    N = len(next(iter(st.values())))
    per_img = sum(np.broadcast_to(r["cyc_img"], (N,)) for r in rows)
    return rows, per_img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--out", default=os.path.join(P.RESULTS, "cycles.md"))
    a = ap.parse_args()
    md = ["# QC18B-ACC exact cycle count (compile/cycles.py)", "",
          f"Array 16 x 8 PEs, KB 36: {SLOTS} MAC slots / cycle. Drain 1024 outputs per tile: compare units {NCMP} "
          f"(binary c1), NL fused lanes (stem, binary sc / c2), {NW} wide lanes (block 6); shadow double buffering "
          f"(stall when drain > next tile's compute); per-pass overhead {OVH} cycles; head overlapped. Plane skipping "
          f"(block 6, patch = 16 px x 9 taps x 32 ch, or 16 px x 256 ch for the 1x1 sc) measured per image on val[:{a.n}] "
          f"by the bit-exact dataflow model (logits == IntBin logits, torch.equal, asserted before counting). "
          f"Executed MAC = nonzero ternary terms x output positions. Utilisation = executed MAC / ({SLOTS} x cycles).", ""]
    summary = []
    for ck in a.ckpts:
        prog, net, val = P.build_program(ck)
        st, correct = D.run_val(prog, net, val, a.n)
        md += [f"## {prog.run} ({ck})", "",
               f"Bit-exact: dataflow logits == IntBin logits on val[:{a.n}]: PASS (acc {100 * correct / a.n:.2f} %).", ""]
        rows, per = schedule(prog, st, 256)
        mac = sum(r["mac"] for r in rows)
        md += ["### Per pass, NL = 256 (means over images)", "",
               "| pass | PPU | tiles | chunk items | plane skip | array cyc | PPU cyc | cycles | bound | exec MAC | util |",
               "|---|---|---|---|---|---|---|---|---|---|---|"]
        for r in rows:
            bound = "PPU" if r["ppuc"] > r["arr"] else "array"
            md.append(f"| {r['name']} | {r['ppu']} | {r['tiles']} | {r['items']:.1f} | "
                      f"{100 * r['skip']:.1f} % | {r['arr']:.1f} | {r['ppuc']:.0f} | {r['cyc']:.1f} | {bound} | "
                      f"{r['mac']} | {r['mac'] / (SLOTS * r['cyc']):.3f} |")
        md.append(f"| **image** | | {sum(r['tiles'] for r in rows)} | {sum(r['items'] for r in rows):.1f} | | "
                  f"{sum(r['arr'] for r in rows):.1f} | {sum(r['ppuc'] for r in rows):.0f} | **{per.mean():.1f}** | | "
                  f"{mac} | **{mac / (SLOTS * per.mean()):.3f}** |")
        top = sorted(rows, key=lambda r: -r["cyc"])[:3]
        md += ["", "Most expensive passes (NL 256): " + ", ".join(
            f"{r['name']} {r['cyc']:.0f} ({'PPU' if r['ppuc'] > r['arr'] else 'array'}-bound)" for r in top), ""]
        md += ["### NL sweep (fused lanes; compare units 512, wide lanes 16)", "",
               "| NL | cycles / image (mean) | min | max | utilisation | images/s at 500 MHz |", "|---|---|---|---|---|---|"]
        sw = {}
        for NL in NLS:
            _, pi = schedule(prog, st, NL)
            sw[NL] = pi.mean()
            md.append(f"| {NL} | {pi.mean():.1f} | {pi.min()} | {pi.max()} | {mac / (SLOTS * pi.mean()):.3f} | "
                      f"{500e6 / pi.mean():.0f} |")
        md += ["", "### Wide-lane count sensitivity (NL 256; spec NW = 16)", "", "| NW | cycles / image | block-6 cycles | utilisation |",
               "|---|---|---|---|"]
        for nw in (16, 32, 64, 128):
            rws, pi = schedule(prog, st, 256, nw)
            b6 = sum(r["cyc"] for r in rws if r["name"].startswith("b6."))
            md.append(f"| {nw} | {pi.mean():.1f} | {b6:.1f} | {mac / (SLOTS * pi.mean()):.3f} |")
        sk = {r["name"]: r["skip"] for r in rows if r["skip"] > 0}
        md += ["", "Plane-skip ratio (skipped (chunk, plane) items / all 8-plane items): "
               + ", ".join(f"{k} {100 * v:.1f} %" for k, v in sk.items()), ""]
        summary.append((prog.run, sw, mac, top, sk))
    md += ["## Spec deviations / findings (compile/program.py, dataflow.py)", "",
           "1. sign(g): the integer weight sign(g) M is not QC per block, so the PE accumulates M x and the PPU input "
           "negates per output channel (acc' = sgn acc, 1 b / channel, already counted in ARCH's '+ sign(g) bits').",
           "2. Bias pre-add: IntBin adds the int32 BN bias BEFORE the requant for the stem (stem_b) and block 6 "
           "(c1b / scb / c2b); the lane export's stem domain includes it. The PPU needs a per-channel adder in front of the "
           "multiplier for these passes (qb_lane_s8 / qb_lane_w only add h after the product).",
           "3. qb_lane_w needs an output clamp to [0, 127] (hm, block-6 c1, pool) and input ReLU (hm, pool); qb_lane "
           "only saturates to +-32767.",
           "4. Block-6 sc r reaches 209 625 worst case (19 b; ARCH: r 17 b, 45 032 was the idm worst case). Exact "
           "solution used: r stored as two S entries (lo 16 b, hi signed; 8192 x 2 entries), qb_lane_w r port 19 b and "
           "y clamp 19 b instead of 18 b (sat16(clamp(y) + r) == sat16(y + r) needs 2^18 - 1 >= 32767 + max|r|). Binary "
           "blocks: r <= 40 160 / 45 032 (17 b), qb_lane_s8 r port 16 -> 17 b (its 19-b sum holds: |y + h + r| <= 162 004).",
           "5. Fused-lane idm: rs = window requant of relu(s_in) with the export's per-tensor (m', sel) = a second "
           "16 x 29 multiplier per fused lane (only identity-block c2 passes use it).",
           "6. Block 6 dominates: at NW = 16 wide lanes hm is a 1 024-cycle PPU-only pass and c1 / sc are PPU-bound "
           "(64 drain cycles per tile); ARCH's ~3 500 cycles / image is not reached with 16 wide lanes (see NW table).",
           "7. NL > 256 needs more than the 256 + 256 stream-buffer ports / cycle that ARCH sizes S for.",
           "8. Line buffer (estimate, not modelled): stride-2 passes b4.c1 / b4.sc and block-6 c1 / sc need up to "
           "18 kb per plane (ARCH: ~12 kb).",
           "9. Stem: 3 channels -> 1 group per tap, 9 of 36 bytes per chunk, 8 unskipped planes: 512 array cycles at 1 % "
           "utilisation (the PE's single per-cycle plane shift prevents packing planes into the idle groups).",
           "",
           "Observed max |r| over all seeds and val images run (worst case: program checks): "
           + ", ".join(f"{k} {v}" for k, v in D.OBS.items()), ""]
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        f.write("\n".join(md) + "\n")
    for run, sw, mac, top, sk in summary:
        print(run, " ".join(f"NL{k}: {v:.1f} cyc util {mac / (SLOTS * v):.3f}" for k, v in sw.items()))
        print("  top:", ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in top), "| skip", {k: round(v, 3) for k, v in sk.items()})
    print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
