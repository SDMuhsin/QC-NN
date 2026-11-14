"""Exact cycle count of QC18B-ACC (ARCH.md v1) per pass and per image from the program's schedule and the dataflow
model's executed chunk items (plane skipping is data dependent):

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.cycles RUN1/best.pt [RUN2/best.pt ...] [--n 500] [--out MD]
        [--v 11 (default: v1 sections + v1.1 section) | --v 1 (v1 only)] [--nrep 20] [--cache DIR]
v1.1 (changes 1-3, list scheduler): see list_schedule / tiles_of and the v1.1 section of results/cycles.md.

Schedule of an array pass (tiles in order pixel tile outer, 64-channel tile inner):
  compute C_k = executed chunk items of tile k (binary: Cin / 32 chunks, 1x1: 1; stem: 8 planes; block 6: (chunk, plane)
  items whose patch is not all zero, measured per image by qc18bacc.compile.dataflow);
  drain D = ceil(1024 / units) with units = NCMP compare units (binary c1), NL fused lanes (stem, binary sc / c2) or
  NW wide lanes (block-6 c1 / sc / c2);
  shadow double buffering: tile k's drain overlaps tile k+1's compute; tile k+1 can capture only when the shadow is free:
  capture_k = capture_{k-1} + max(C_k, D_{k-1}) (capture_0 = C_0);  pass = capture_last + D + OVH.
PPU-only pass (block-6 hm): ceil(outputs / NW) + OVH.  Head (pool + FC) overlapped with the next image: 0 (its own
cycles: head_cycles, FC weight port FC_BITS, checked <= the image's cycles in the p2 section).
--golden p2 (default): p2_md / p2_section (IntBin2 program, v1.1 schedule at NW 16 / 32, head) spliced into --out;
--golden intbin: the v1 / v1.1 sections (IntBin) as before.
Array cycles = sum C_k, PPU cycles = tiles x D; bound = array if array cycles >= PPU cycles else PPU.
Executed MAC = nonzero ternary terms x output positions (workload.py 'exec'); utilisation = MAC / (73 728 x cycles).
Every run first asserts the dataflow logits == IntBin logits (torch.equal) on the same images.
"""
import argparse
import os
import sys

import numpy as np
import torch

from . import dataflow as D
from . import program as P

SLOTS = P.ROWS * P.COLS * P.KB * 2 * P.B          # 73 728 MAC slots / cycle
NCMP, NW, OVH = 512, 16, 12
NLS = (64, 128, 192, 256, 384)
BLK = 64                                           # dependency / version-check granularity (buffer entries)
WIN = 4                                            # list scheduler: tiles of the first WIN unfinished passes
FL_ALL = frozenset((1, 2, 3))                      # v1.1 changes: 1 block 6 on fused lanes, 2 stem packing,
                                                   # 3 per-PE c1 comparators + interleaved list schedule


def cdiv(a, b):
    return -(-a // b)


def unit(p, fl):
    """PPU unit draining pass p under the v1.1 change set fl (empty = v1)."""
    if p.kind == "bc1":
        return "pecmp" if 3 in fl else "compare"
    if p.kind in ("stem", "bsc", "bc2"):
        return "fused"
    return "fused" if (1 in fl and p.ppu == "fused") else "wide"


def drain(p, NL, nw=NW, fl=frozenset()):
    u = unit(p, fl)
    return 0 if u == "pecmp" else cdiv(1024, {"compare": NCMP, "fused": NL, "wide": nw}[u])


def tile_items(p, items, fl):
    """[N, tiles] compute cycles (pixel tile outer, 64-channel tile inner).  Stem: 8 plane cycles (v1) or 2 packed."""
    if p.kind == "stem":
        items = np.full_like(items, 2 if 2 in fl else 8)
    return np.repeat(items, p.cout // P.NCH, axis=1)


def pass_cycles(p, items, NL, nw=NW, ovh=OVH, fl=frozenset()):
    """v1 pass-serial schedule.  items: [N, Tp] executed chunk items per pixel tile (None for the PPU-only pass).
    Returns per-image arrays (cycles, array cycles, PPU cycles)."""
    if p.kind == "hm":
        c = cdiv(p.cin * p.Hout * p.Wout, NL if unit(p, fl) == "fused" else nw)
        return np.full(1, c + ovh), np.zeros(1), np.full(1, c)
    C = tile_items(p, items, fl)
    d = drain(p, NL, nw, fl)
    cap = C[:, 0].astype(np.int64)
    for k in range(1, C.shape[1]):
        cap = cap + np.maximum(C[:, k], d)
    return cap + d + ovh, C.sum(1), np.full(C.shape[0], d * C.shape[1])


def _rows(prog, st, fl):
    out = []
    for p in prog.passes:
        if p.k:
            tot = p.nchunk * (8 if p.inb == 8 else 1) * p.tiles_px
            skip = 1 - st[p.name].sum(1).mean() / tot if (p.inb == 8 and p.kind != "stem") else 0.0
            items = tile_items(p, st[p.name], fl).sum(1).mean()
        else:
            skip, items = 0.0, 0.0
        out.append(dict(name=p.name, ppu=unit(p, fl), tiles=p.tiles if p.k else 0, items=items, skip=skip, mac=p.mac))
    return out


def schedule(prog, st, NL, nw=NW, ovh=OVH, fl=frozenset(), check=False):
    """per-pass rows + per-image cycles.  Without change 3: v1 pass-serial schedule; with it: list scheduler."""
    if 3 in fl:
        return list_schedule(prog, st, NL, nw, ovh, fl, check)
    rows = _rows(prog, st, fl)
    for r, p in zip(rows, prog.passes):
        cyc, arr, ppu = pass_cycles(p, st.get(p.name), NL, nw, ovh, fl)
        r.update(arr=arr.mean(), ppuc=ppu.mean(), cyc=cyc.mean(), cyc_img=cyc)
    N = len(next(iter(st.values())))
    per_img = sum(np.broadcast_to(r["cyc_img"], (N,)) for r in rows)
    return rows, per_img


# ------------------------------------------------------------------------------------------------ v1.1 list scheduler
BASE = {}


def _bufbase(prog):
    o, base = 0, {}
    for k, (n, _) in prog.buffers.items():
        base[k] = o
        o += cdiv(n, BLK)
    return base


def _blk(base, buf, a, b):
    """blocks of entries [a, b) of buffer buf."""
    return range(base[buf] + a // BLK, base[buf] + cdiv(b, BLK))


def tiles_of(prog):
    """Static tile list with footprints (sets of BLK-entry blocks; IMG is input, never overwritten in an image):
    ar  array-time reads (the full input rows of the tile's patch, incl. halo / stride / phase, all channels, all planes:
        row-granular, as the line buffer loads them), dr drain-time reads (c2: s_in / r in place; block-6 c2: r lo / hi;
        hm: s), wr writes (outputs of every destination buffer, int8 maps: all 8 planes; block-6 r: lo + hi entries)."""
    base = _bufbase(prog)
    T = []
    for pi, p in enumerate(prog.passes):
        if p.kind == "hm":
            C, L = p.cin, p.Hout * p.Wout
            for tp in range(L // P.ROWS):
                for cg in range(C // P.NCH):
                    px = range(tp * P.ROWS, (tp + 1) * P.ROWS)
                    dr = {b for x in px for b in _blk(base, "S", x * C + cg * P.NCH, x * C + (cg + 1) * P.NCH)}
                    wr = {b for pl in range(8) for x in px
                          for b in _blk(base, "HQ", pl * L * C + x * C + cg * P.NCH, pl * L * C + x * C + (cg + 1) * P.NCH)}
                    T.append(dict(pi=pi, arr=False, tp=tp, cg=cg, ar=set(), dr=dr, wr=wr))
            continue
        L, Li = p.Hout * p.Wout, p.Hin * p.Win
        Cs = 8 if p.src == "IMG" else p.cin
        npl = 8 if p.src in D.PLANAR else 1
        sc = next((q for q in prog.passes if q.block == p.block and q.kind == "wsc"), None)
        for tp in range(p.tiles_px):
            px = range(tp * P.ROWS, (tp + 1) * P.ROWS)
            oys = sorted({x // p.Wout for x in px})
            rows = sorted({oy * p.stride + dy - p.pad for oy in oys for dy in range(p.k)} & set(range(p.Hin)))
            ar = set() if p.src == "IMG" else {b for pl in range(npl) for r in rows
                                              for b in _blk(base, p.src, pl * Li * Cs + r * p.Win * Cs,
                                                            pl * Li * Cs + (r + 1) * p.Win * Cs)}
            for cg in range(p.cout // P.NCH):
                own = lambda buf, off=0: {b for x in px for b in _blk(base, buf, off + x * p.cout + cg * P.NCH,
                                                                       off + x * p.cout + (cg + 1) * P.NCH)}
                dr = set()
                if p.kind == "bc2":
                    dr = own("S")
                elif p.kind == "wc2":
                    dr = own("S") | (set() if sc.p.get("r1") else own("S", L * p.cout))
                wr = set()
                for buf in p.dst:
                    if buf in ("HQ", "Z"):
                        wr |= {b for pl in range(8) for b in own(buf, pl * L * p.cout)}
                    else:
                        wr |= own(buf)
                if p.kind == "wsc" and not p.p.get("r1"):
                    wr |= own("S", L * p.cout)
                T.append(dict(pi=pi, arr=True, tp=tp, cg=cg, ar=ar, dr=dr, wr=wr))
    # hazards in program order: RAW (read start >= producer's write done), WAR (write start >= earlier readers' read
    # done, the in-place self read excluded), WAW (write start >= previous writer's write done)
    last_w, rdrs, pairs = {}, {}, set()
    for t, d in enumerate(T):
        for kind, fs in (("a", d["ar"]), ("d", d["dr"])):
            for b in fs:
                if b in last_w:
                    pairs.add((last_w[b], "wd", t, "r" + kind + "s"))
                rdrs.setdefault(b, set()).add((t, kind))
        for b in d["wr"]:
            for r, kind in rdrs.get(b, ()):
                if r != t:
                    pairs.add((r, "r" + kind + "d", t, "ws"))
            if b in last_w:
                pairs.add((last_w[b], "wd", t, "ws"))
            last_w[b] = t
            rdrs[b] = set()
    for d in T:
        d["deps"] = []
    for a, fa, b, fb in sorted(pairs):
        T[b]["deps"].append((a, fa, fb))
    return T, sorted(pairs)


FIELDS = ("st", "ce", "ds", "de")          # array start, compute end (= capture if no stall), drain start, drain end


def _field(f, arrtile):
    """time field of a pair endpoint: ras / rad array read start / done, rds / rdd drain read start / done,
    ws / wd write start / done (pecmp tiles write at capture: ds = de = capture)."""
    return {"ras": "st", "rad": "ce", "rds": "ds", "rdd": "de", "ws": "ds", "wd": "de"}[f]


class Sched:
    """List scheduler state for one image (see list_schedule)."""

    def __init__(self, n, npass):
        self.t = {f: [None] * n for f in FIELDS}
        self.cap = [None] * n
        self.done = [False] * n
        self.heads = None
        self.t_arr = self.t_sh = 0
        self.lane = {"fused": 0, "wide": 0}
        self.last_arr = None
        self.sh_pass = None
        self.attr = [0] * npass
        self.sup = None                          # supply-model state (compile/supply.py), None without a supply hook
        self.seq = []                            # commit order (tile indices)

    def copy(self):
        c = Sched.__new__(Sched)
        c.t = {f: list(v) for f, v in self.t.items()}
        c.cap, c.done, c.heads = list(self.cap), list(self.done), list(self.heads)
        c.t_arr, c.t_sh, c.lane, c.last_arr, c.sh_pass, c.attr = (self.t_arr, self.t_sh, dict(self.lane), self.last_arr,
                                                                  self.sh_pass, list(self.attr))
        c.sup = None if self.sup is None else self.sup.copy()
        c.seq = list(self.seq)
        return c


def list_schedule(prog, st, NL, nw=NW, ovh=OVH, fl=FL_ALL, check=False, win=None, ctx=None, sup=None, lat=None,
                  bub=None, order=None, rec=None):
    """v1.1 event-driven list scheduler over tiles (per image):
    resources: array (one tile at a time, compute = executed chunk items), shadow (one per PE: a drained tile captures
    only when the previous drain has finished; the array stalls holding its accumulators otherwise), fused lanes (NL
    outputs / cycle) and wide lanes (NW / cycle), shared in FIFO order by shadow drains and PPU-only jobs (hm, 1024
    outputs each); per-PE comparators (change 3: binary c1, b2 written at capture, no shadow, no lanes).
    A tile may start when every hazard pair (tiles_of: RAW row-granular input rows incl. halo / stride / phase; WAR of
    the in-place stream and every re-used buffer; WAW) is satisfied: array reads after the producers' drains complete,
    writes (drain start; pecmp: capture) after earlier readers / writers.  Tiles of one pass issue in order; at each
    decision the candidate (head tile of each of the first WIN unfinished passes, all hazards scheduled) with the
    earliest feasible start wins, ties in program order.  Pass overhead OVH only where the array idles at a pass
    boundary (start = ready + OVH); end of image = last write + OVH.  Cycles are attributed to passes (array compute ->
    own pass, idle -> pass of the binding hazard, shadow stall -> pass holding the shadow, tail -> last drain) so the
    per-pass attribution sums to the image cycles.  lat (R3a, default None = unchanged): function (producer tile, consumer
    field 'ras' / 'rds' / 'ws', consumer tile) -> extra cycles added to the producer's write-done time ('wd') in that
    hazard (the RTL write-back pipeline after the drain / capture).  bub (R3a, default None = unchanged): function (previous tile on the unit or None, tile) -> idle cycles
    between two PPU-only jobs / drains on one lane unit (qb_core: an hm job reads s_rd early, so it cannot directly
    follow a drain that reads s_rd late).  order (R3b, default None = unchanged): static issue order (sequence of all tile
    indices, e.g. one image's commit order); the scheduler commits tiles in exactly that order (an image-independent
    hardware sequencer) instead of picking the earliest candidate; times follow the same rules.  rec (R3b, default
    None): dict filled with {image: commit order}.  check: verify the hazard pairs on the scheduled times of every image
    (every read sees the program-order version) and return the time arrays."""
    key = (id(prog), "tiles")
    if key not in BASE:
        BASE[key] = tiles_of(prog)
    T, pairs = BASE[key]
    n, npass = len(T), len(prog.passes)
    N = len(next(iter(st.values())))
    rows = _rows(prog, st, fl)
    # per tile durations [N, n]
    dur = np.zeros((N, n), np.int64)
    dd = np.zeros(n, np.int64)
    k0 = {}
    for t, d in enumerate(T):
        p = prog.passes[d["pi"]]
        u = unit(p, fl)
        if d["arr"]:
            if d["pi"] not in k0:
                k0[d["pi"]] = (t, tile_items(p, st[p.name], fl))
            t0, C = k0[d["pi"]]
            dur[:, t] = C[:, t - t0]
            dd[t] = drain(p, NL, nw, fl)
        else:
            dd[t] = cdiv(1024, NL if u == "fused" else nw)
        d["u"] = u
    var = (dur != dur[:1]).any(0)
    win = WIN if win is None else win
    is_arr = [None] * npass
    for d in T:
        is_arr[d["pi"]] = d["arr"]
    if sup is not None:                                  # supply hook (compile/supply.py): image-dependent tiles
        var |= np.array([sup.varies(T[t]) for t in range(n)], bool)
    first = [None] * npass
    for t, d in enumerate(T):
        if first[d["pi"]] is None:
            first[d["pi"]] = t
    nt = [sum(1 for d in T if d["pi"] == pi) for pi in range(npass)]

    def ready(S, t, fsel):
        best, bt = 0, None
        for a, fa, fb in T[t]["deps"]:
            if fb in fsel:
                v = S.t[_field(fa, T[a]["arr"])][a]
                if lat is not None and fa == "wd":
                    v += lat(T[a], fb, T[t])
                if v > best:
                    best, bt = v, a
        return best, bt

    def _start(S, t, C, d):
        """array start of tile t and the pass binding it (None: no idle).  Data: ready + OVH at a pass switch;
        drained tiles start just in time to capture when the shadow frees (the array is not held meanwhile);
        pecmp tiles capture (= write b2) after the WAR / WAW hazards of their writes."""
        rw, bw = ready(S, t, ("ws", "rds"))
        ra, ba = ready(S, t, ("ras",))
        if d["pi"] != S.last_arr and ra > S.t_arr:
            ra += ovh
        c = [(S.t_arr, None), (ra, T[ba]["pi"] if ba is not None else None)]
        if d["u"] == "pecmp":
            c.append((rw - C, T[bw]["pi"] if bw is not None else None))
        else:
            c.append((S.t_sh - C, S.sh_pass))
        s, b = max(c, key=lambda x: x[0])
        return s, (b if s > S.t_arr else None)

    def est(S, t, C):
        d = T[t]
        rw, _ = ready(S, t, ("ws", "rds"))
        if d["arr"]:
            return _start(S, t, C, d)[0]
        ln = S.lane[d["u"]]
        if bub is not None:
            ln += bub(S.lane.get(d["u"] + "_last"), t)
        return max(ln, rw) + (ovh if (t == first[d["pi"]] and rw > ln) else 0)

    def step(S, img, stop_var=False):
        if order is not None:                            # R3b hook: static issue order
            t = order[len(S.seq)]
            pi = T[t]["pi"]
            assert t == first[pi] + S.heads[pi] and all(S.done[a] for a, _, _ in T[t]["deps"]), "order violates deps"
            if stop_var and var[t]:
                return None
            return est(S, t, int(dur[img, t])), t
        lo = min(pi for pi in range(npass) if S.heads[pi] < nt[pi])
        best = None
        narr = 0
        for pi in range(lo, min(lo + win, npass)):
            if S.heads[pi] >= nt[pi]:
                continue
            if ctx is not None and is_arr[pi]:           # at most ctx array passes in flight (qb_act contexts)
                narr += 1
                if narr > ctx:
                    continue
            t = first[pi] + S.heads[pi]
            if not all(S.done[a] for a, _, _ in T[t]["deps"]):
                continue
            if stop_var and var[t]:
                return None                              # a per-image duration enters the decision
            e = est(S, t, int(dur[img, t]))
            k = e                                        # supply hook: select by the supply-ready start too
            if sup is not None and T[t]["arr"]:
                k = max(e, sup.probe(S.sup, T, t, ready(S, t, ("ras",))[0]))
            if best is None or k < best[0]:
                best = (k, t, e)
        assert best is not None, "list scheduler deadlock"
        return best[2], best[1]

    def commit(S, t, s, img):  # noqa
        d = T[t]
        pi, u = d["pi"], d["u"]
        C, D_ = int(dur[img, t]), int(dd[t])
        rw, bw = ready(S, t, ("ws", "rds"))
        if d["arr"]:
            s_, b = _start(S, t, C, d)
            assert s_ == s
            if s > S.t_arr:
                S.attr[b if b is not None else pi] += s - S.t_arr
            if sup is not None:                          # supply-stretched compute (last item issue - start)
                C = sup.dur(S.sup, T, t, s, C, img, ready(S, t, ("ras",))[0])
            ce = s + C
            S.attr[pi] += C
            if u == "pecmp":
                cap, ds, de = ce, ce, ce
            else:
                cap = max(ce, S.t_sh)
                if cap > ce:
                    S.attr[S.sh_pass] += cap - ce
                ds = max(cap, S.lane[u], rw)
                de = ds + D_
                S.t_sh, S.lane[u], S.sh_pass = de, de, pi
                S.lane[u + "_last"] = t
            S.t_arr, S.last_arr = cap, pi
        else:
            ce = cap = None
            ds = s
            de = ds + D_
            S.lane[u] = de
            S.lane[u + "_last"] = t
        S.t["st"][t], S.t["ce"][t], S.t["ds"][t], S.t["de"][t] = s, ce, ds, de
        S.done[t] = True
        S.heads[pi] += 1
        S.seq.append(t)

    def run(S, img, stop_var):
        while not all(S.heads[pi] >= nt[pi] for pi in range(npass)):
            b = step(S, img, stop_var)
            if b is None:
                return False
            commit(S, *b[::-1], img)
        return True

    S0 = Sched(n, npass)
    S0.heads = [0] * npass
    if sup is not None:
        S0.sup = sup.new(T, nt)
    complete = run(S0, 0, True)                          # common prefix (durations equal for every image)
    per = np.zeros(N, np.int64)
    attr = np.zeros((N, npass), np.int64)
    tim = {f: np.zeros((N, n), np.int64) for f in FIELDS}
    for img in range(N):
        S = S0.copy() if not complete else S0
        if not complete:
            run(S, img, False)
        end = max(v for v in S.t["de"] if v is not None)
        tail = end + ovh - S.t_arr
        last = max(range(n), key=lambda t: (S.t["de"][t], t))
        S.attr[T[last]["pi"]] += tail
        per[img] = end + ovh
        attr[img] = S.attr
        if rec is not None:
            rec[img] = list(S.seq)
        assert sum(S.attr) == per[img]
        if complete:
            S.attr[T[last]["pi"]] -= tail
        for f in FIELDS:
            tim[f][img] = [(-1 if v is None else v) for v in S.t[f]]
    for r, pi in zip(rows, range(npass)):
        p = prog.passes[pi]
        ts = [t for t in range(n) if T[t]["pi"] == pi]
        r.update(arr=dur[:, ts].sum(1).mean() if T[ts[0]]["arr"] else 0.0,
                 ppuc=float(dd[ts].sum()), cyc=attr[:, pi].mean(), cyc_img=attr[:, pi])
    if check:
        verify(T, pairs, tim)
        return rows, per, tim
    return rows, per


def verify(T, pairs, tim):
    """every hazard pair (a, field_a) <= (b, field_b) holds on the scheduled times of every image: each read sees, over its
    whole read interval, exactly the version of its program-order producer; writes are ordered."""
    for a, fa, b, fb in pairs:
        ta = tim[_field(fa, T[a]["arr"])][:, a]
        tb = tim[_field(fb, T[b]["arr"])][:, b]
        assert (ta >= 0).all() and (tb >= 0).all() and (ta <= tb).all(), f"hazard {a}.{fa} <= {b}.{fb} violated"
    return len(pairs)


def load_stats(ck, v, n, cache=None, golden="intbin"):
    """program + dataflow stats (dataflow logits == golden asserted).  cache: directory for the stats (.npz)."""
    prog, net, val = P.build_program(ck, v=v, golden=golden)
    sfx = "" if golden == "intbin" else "_" + golden
    path = None if cache is None else os.path.join(cache, f"{prog.run}_v{v}_n{n}{sfx}.npz")
    if path and os.path.exists(path):
        z = np.load(path)
        st, correct = {k: z[k] for k in z.files if k != "_correct"}, int(z["_correct"])
    else:
        st, correct = D.run_val(prog, net, val, n)
        if path:
            os.makedirs(cache, exist_ok=True)
            np.savez(path, _correct=correct, **st)
    return prog, net, val, st, correct


def v1_md(prog, st, correct, n, ck):
    md = [f"## {prog.run} ({ck})", "",
          f"Bit-exact: dataflow logits == IntBin logits on val[:{n}]: PASS (acc {100 * correct / n:.2f} %).", ""]
    rows, per = schedule(prog, st, 256)
    mac = sum(r["mac"] for r in rows)
    md += ["### Per pass, NL = 256 (means over images)", "",
           "| pass | PPU | tiles | chunk items | plane skip | array cyc | PPU cyc | cycles | bound | exec MAC | util |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r, p in zip(rows, prog.passes):
        bound = "PPU" if r["ppuc"] > r["arr"] else "array"
        md.append(f"| {r['name']} | {p.ppu} | {r['tiles']} | {r['items']:.1f} | "
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
    return md, (prog.run, sw, mac, top, sk)



CONFIGS = (("v1", frozenset()), ("1 only", frozenset((1,))), ("2 only", frozenset((2,))), ("3 only", frozenset((3,))),
           ("all (v1.1)", FL_ALL))
NLS11 = (128, 192, 256, 384)


def replay_check(prog, net, val, st, NL, k, nw=NW):
    """tile-granular value replay (dataflow.replay) of the v1.1 schedule at NL on val[:k]: logits == golden."""
    if (id(prog), "tiles") not in BASE:
        BASE[(id(prog), "tiles")] = tiles_of(prog)
    T, _ = BASE[(id(prog), "tiles")]
    _, _, tim = list_schedule(prog, {a: b[:k] for a, b in st.items()}, NL, nw, fl=FL_ALL, check=True)
    base = _bufbase(prog)
    xv, _ = val
    Ws = {p.name: D.PEWeights(p, "cuda") for p in prog.passes if p.k}
    for i in range(k):
        lg = D.replay(prog, xv[i:i + 1], T, base, {f: v[i] for f, v in tim.items()}, Ws=Ws)
        assert torch.equal(lg, net(xv[i:i + 1])), f"scheduled-order replay != IntBin (image {i})"
    return k


def v11_md(prog, st, correct, n, ck, st1, net=None, val=None, nrep=0):
    """v1.1 section of one checkpoint.  st1: v1 dataflow stats (v1 cycles from both must agree)."""
    md = [f"### {prog.run} ({ck})", "",
          f"Bit-exact (v1.1 program: packed stem, fused-lane block 6 where it fits): dataflow logits == IntBin logits "
          f"on val[:{n}]: PASS (acc {100 * correct / n:.2f} %).", ""]
    md += [f"* {c}" for c in prog.checks if c.startswith("v1.1")]
    for NL in NLS11:
        a = schedule(prog, st, NL)[1]
        b = schedule(prog, {k: v for k, v in st1.items()}, NL)[1]
        assert np.array_equal(a, b), "v1 count from the v1.1 dataflow stats != v1 count"
    res = {}
    for nm, fl in CONFIGS:
        for NL in NLS11:
            out = schedule(prog, st, NL, fl=fl, check=(3 in fl))
            res[nm, NL] = out
    npairs = len(BASE[(id(prog), "tiles")][1])
    md += ["", f"Schedule check (changes 3 / all, every NL, every image): {npairs} hazard pairs (RAW row-granular incl. "
           f"halo / stride / phase, WAR incl. the in-place stream, WAW; {BLK}-entry blocks) hold on the scheduled times: "
           f"every read sees exactly its program-order producer's data, so the dataflow values (logits == IntBin) are "
           f"unchanged in the scheduled order: PASS.", ""]
    if nrep:
        replay_check(prog, net, val, st, 256, nrep)
        md += [f"Value replay (dataflow.replay): val[:{nrep}] executed tile by tile in the NL-256 scheduled order (events "
               f"by time; each tile computed from snapshots of exactly its footprint rows taken at its read times, only "
               f"its own outputs written at its write time) gives logits == IntBin (torch.equal): PASS. (Sensitivity: "
               f"dropping the WAR or the drain-read RAW hazards from the scheduler makes both the hazard check and the "
               f"replay fail; compile/test_compile.py.)", ""]
    mac = sum(p.mac for p in prog.passes)
    md += ["#### Cycles / image (mean over val[:%d]) and the contribution of each change" % n, "",
           "| config | " + " | ".join(f"NL {k}" for k in NLS11) + " | util NL 256 |",
           "|---|" + "---|" * (len(NLS11) + 1)]
    for nm, _ in CONFIGS:
        md.append(f"| {nm} | " + " | ".join(f"{res[nm, k][1].mean():.1f}" for k in NLS11)
                  + f" | {mac / (SLOTS * res[nm, 256][1].mean()):.3f} |")
    rows, per = res["all (v1.1)", 256][:2]
    md += ["", "#### v1.1 per pass, NL = 256 (attributed cycles: array compute -> own pass, array idle -> pass of the "
           "binding hazard, shadow stall -> pass holding the shadow, tail -> last drain; sums to the image)", "",
           "| pass | PPU | tiles | chunk items | array cyc | PPU cyc | attributed cyc | exec MAC |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append(f"| {r['name']} | {r['ppu']} | {r['tiles']} | {r['items']:.1f} | {r['arr']:.1f} | {r['ppuc']:.0f} | "
                  f"{r['cyc']:.1f} | {r['mac']} |")
    md.append(f"| **image** | | | | {sum(r['arr'] for r in rows):.1f} | | **{per.mean():.1f}** (min {per.min()}, max "
              f"{per.max()}) | {mac} |")
    top = sorted(rows, key=lambda r: -r["cyc"])[:3]
    md += ["", "Top-3 passes (NL 256, attributed): " + ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in top), ""]
    return md, dict(run=prog.run, res=res, mac=mac, top=top, arr=sum(r["arr"] for r in rows))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--v", type=int, default=11, choices=(1, 11))
    ap.add_argument("--out", default=os.path.join(P.RESULTS, "cycles.md"))
    ap.add_argument("--cache", default=None, help="directory caching the dataflow stats")
    ap.add_argument("--nrep", type=int, default=20, help="v1.1: images replayed tile by tile in the scheduled order")
    ap.add_argument("--golden", default="p2", choices=P.GOLDENS, help="p2: write / replace the p2 section of --out; "
                    "intbin: rewrite --out (v1 + v1.1 sections, IntBin)")
    ap.add_argument("--nw", type=int, nargs="+", default=[16, 32], help="p2: wide-lane counts")
    ap.add_argument("--fc-bits", type=int, nargs="+", default=[128, 256, 512], help="p2: FC weight port widths")
    a = ap.parse_args()
    if a.golden == "p2":
        md2, s2 = [], []
        for ck in a.ckpts:
            m, sm = p2_md(ck, a.n, a.cache, a.nrep, tuple(a.nw), tuple(a.fc_bits))
            md2 += m
            s2.append(sm)
        sec = p2_section(md2, s2)
        splice(a.out, sec[0], sec)
        for s in s2:
            print(s["run"], " ".join(f"NW{nw}: " + " ".join(f"NL{k} {s['res'][nw, k][1].mean():.1f}" for k in NLS11)
                                     for nw in s["nws"]))
            print("  top:", ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in s["top"]), "| head",
                  {k: v["total"] for k, v in s["head"].items()}, "min image", s["minc"])
        print(f"wrote p2 section of {a.out}")
        return 0
    md = ["# QC18B-ACC exact cycle count (compile/cycles.py)", "",
          f"Array 16 x 8 PEs, KB 36: {SLOTS} MAC slots / cycle. Drain 1024 outputs per tile: compare units {NCMP} "
          f"(binary c1), NL fused lanes (stem, binary sc / c2), {NW} wide lanes (block 6); shadow double buffering "
          f"(stall when drain > next tile's compute); per-pass overhead {OVH} cycles; head overlapped. Plane skipping "
          f"(block 6, patch = 16 px x 9 taps x 32 ch, or 16 px x 256 ch for the 1x1 sc) measured per image on val[:{a.n}] "
          f"by the bit-exact dataflow model (logits == IntBin logits, torch.equal, asserted before counting). "
          f"Executed MAC = nonzero ternary terms x output positions. Utilisation = executed MAC / ({SLOTS} x cycles).", ""]
    summary, s11, md11 = [], [], []
    for ck in a.ckpts:
        prog, net, val, st, correct = load_stats(ck, 1, a.n, a.cache, a.golden)
        m, sm = v1_md(prog, st, correct, a.n, ck)
        md += m
        summary.append(sm)
        if a.v == 11:
            prog11, net11, val11, st11, c11 = load_stats(ck, 11, a.n, a.cache, a.golden)
            m, sm = v11_md(prog11, st11, c11, a.n, ck, st, net11, val11, a.nrep)
            md11 += m
            s11.append(sm)
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
    if a.v == 11:
        md += v11_section(md11, s11)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    hdr = "## p2 golden (IntBin2), v1.1 schedule (compile/*.py --golden p2, default)"
    old = open(a.out).read().split("\n") if os.path.exists(a.out) else []
    keep = old[old.index(hdr):] if hdr in old else []            # the p2 section survives an intbin rewrite
    with open(a.out, "w") as f:
        f.write("\n".join(md + ([""] + keep if keep else [])).rstrip("\n") + "\n")
    for run, sw, mac, top, sk in summary:
        print(run, "v1", " ".join(f"NL{k}: {v:.1f} cyc util {mac / (SLOTS * v):.3f}" for k, v in sw.items()))
        print("  top:", ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in top), "| skip", {k: round(v, 3) for k, v in sk.items()})
    for s in s11:
        for nm, _ in CONFIGS:
            print(s["run"], f"{nm:<11}", " ".join(f"NL{k}: {s['res'][nm, k][1].mean():.1f}" for k in NLS11),
                  f"util256 {s['mac'] / (SLOTS * s['res'][nm, 256][1].mean()):.3f}")
        print("  v1.1 top:", ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in s["top"]))
    print(f"wrote {a.out}")
    return 0


V11_TEXT = [
    "Changes (each selectable in cycles.CONFIGS; the program / dataflow default is --v 11, --v 1 reproduces v1):",
    "",
    "1. Fused lane v1.1 (program.lane_f): per-channel bias pre-add before the multiplier, input-ReLU mode, output "
    "clamp [0, 127] mode and a per-channel input pre-clamp x -> clamp(x, lo_c, hi_c). requant is monotone (m0 >= 0), so "
    "with the output observed only through clamp(., A_c, B_c) (u8: [0, 127]; r / c2: the int16 saturation of the sum it "
    "enters, A/B from the worst-case range of the other operand) lo_c = max{x: rq(x) <= A_c}, hi_c = min{x: rq(x) >= "
    "B_c} change no output; asserted exhaustively on every integer of every channel's worst-case domain (before the "
    "pre-clamp). A block-6 pass moves to the NL fused lanes iff every channel fits: 16-b signed input after the "
    "pre-clamp, an exact multiplier of <= 30 b in the lane's shift window s' = 17 + sel, sel < 8 (qb_lane_s8), and the "
    "lane's internal widths (18-b y, 17-b r, 19-b sum). MW needed per pass and the reason a pass stays on the wide lanes "
    "are listed per checkpoint below.",
    "2. Stem packing (dataflow.pe_stem_packed): the 36 bytes are 9 taps x 4 channel groups; in stem mode group g of "
    "cycle h carries plane 4h + g of the 8-padded image channels (same 9 tap codes in every group), the PE popcounts the "
    "4 groups separately and adds sum_g (u_g - nneg_g) << g, shifted by 4h, plane 7 (group 3 of h = 1) negative. "
    "2 cycles per stem tile instead of 8 (bit-exact, ACC_W wrap checked).",
    "3. Binary c1: b2 = acc' >= T2 by 1024 per-PE comparators at capture (no shadow, no lanes; b2 written at capture), "
    "and an event-driven list scheduler over tiles (cycles.list_schedule): array one tile at a time; shadow one per PE "
    "(a drained tile starts just in time to capture when the shadow frees, so the array is not held); fused lanes NL "
    "outputs / cycle and wide lanes 16 / cycle shared FIFO by drains and PPU-only jobs (hm in 1024-output jobs); "
    "candidates = head tile of each of the first 4 unfinished passes whose hazards are all scheduled, earliest feasible "
    "start wins, ties in program order. Hazards (cycles.tiles_of, 64-entry blocks): RAW row-granular (every input row of "
    "the tile's patch incl. halo / stride / phase, all channels, all planes, counts as written when the producing tile's "
    "drain completes; drain-time reads of s_in / r likewise), WAR (a write may start only after every earlier-ordered "
    "reader of the old value has finished reading it; this covers the in-place stream: the sc pass's r overwrites "
    "s_in rows, block-6 sc's r hi entries overwrite s6 rows that hm has not read yet, and every re-used B1 / B2 / HQ / Z "
    "row), WAW. OVH = 12 cycles only where the array idles at a pass boundary (start = data ready + 12) and once at the "
    "end of the image. Per-pass cycles in the schedule are attributed (array compute -> own pass, array idle -> pass of "
    "the binding hazard or of the shadow holder, tail -> last drain) and sum to the image cycles.",
    "",
]


V11_FINDINGS = [
    "### v1.1 findings / deviations", "",
    "1. Change 1 moves only b6.hm (both seeds): MW needed 15 (the lane keeps MW 29), input ReLU + pre-clamp [129, 32638] "
    "+ u8 clamp. b6.c1 / sc / c2 stay on the wide lanes: none has an exact multiplier inside qb_lane_s8's shift window "
    "s' in [17, 24] (they need s' up to 26-31, i.e. a 4-b sel; there MW 22-23 for c1, 30 for sc, 31 for c2), c1 / c2 "
    "(and s1's sc) need > 16-b inputs after the pre-clamp in 7-15 channels, and sc's r reaches 209 625 / 162 624 (fused "
    "lane: 17-b r, 18-b y). No moved pass uses the bias pre-add (hm has no bias); it remains needed for the stem.",
    "2. Block 6 is now ~half of the image (s0: hm 80 + c1 549 + sc 46 + c2 1160 of 3805 attributed cycles): c1 / sc / "
    "c2 drains are 3 x 8 x 64 = 1536 serial wide-lane cycles at NW 16. Next levers: NW 32, or a fused-lane mode with "
    "4-b sel and 17-b input for b6.c1.",
    "3. Change 2 hardware (not synthesized): the PE popcount split into 4 group sub-sums (9 bytes each) + a shift-add "
    "sum_g (u_g - nneg_g) << g with group 3 subtracted for plane 7, and the plane shift 4h; binary mode adds the 4 "
    "sub-sums unshifted.",
    "4. Change 3 hardware: 1024 comparators (20-b acc' vs the column's 16-b T2, sign(g) folded), B2 written at capture "
    "(1024 b per tile; binary c1 tiles take >= 2 cycles, so a 512-b port + one tile of buffering suffices). The "
    "interleaved schedule keeps two passes live (c1 of block i+1 and c2 of block i): two line-buffer contexts (2 x "
    "the ARCH line buffer) and per-tile switching of weight-code / parameter streams.",
    "5. The WAR hazards are binding, not theoretical: without them the schedule clobbers stream / B1 / B2 rows "
    "(hazard check and value replay both fail). Modelled in-place cases: binary sc r over s_in rows, block-6 sc r-hi entries "
    "over s6 rows hm has not read yet, B1 / B2 rows re-used by the next block.",
    "6. The three changes are close to additive at NL 256 (s0: -960 / -258 / -722 alone, -1952 together). With "
    "interleaving the fused lanes stop being the bottleneck above NL 256 (NL 384 gains ~70 cycles); NL 128 costs ~1180 "
    "cycles (stage-1 c2 / stem drains).",
    "",
]


# ------------------------------------------------------------------------------------------------ head (pool + FC)
FC_BITS = 128             # FC weight port (bits / cycle): FC_BITS / 8 int8 MACs per cycle
FC_LAT = 4                # FC pipeline latency (MAC tree + bias + output register)


def head_cycles(prog, nw=NW, fc_bits=FC_BITS):
    """Head of one image, overlapped with the next image (it must fit in the next image's cycles):
    pool sum: relu(s8) accumulated per channel while b7.c2 drains (512 x 20-b accumulators at the fused-lane outputs,
      no extra cycles, no S re-read: the next image's stem overwrites S);  pool requant: 512 sums on the wide lanes
      (pool_m, clamp [0, 127]; idle until the next image's block 6): ceil(512 / NW);  FC: 512 x 100 int8 MACs at
      fc_bits / 8 MACs / cycle (weights streamed from the FC macro at fc_bits / cycle, pq held in a 4-kb register) +
      int32 bias, FC_LAT pipeline.  Returns dict(pool, fc, total, mac)."""
    last = prog.passes[-1]
    C = last.cout
    W8 = prog.head["fW8"]
    nmac = fc_bits // 8
    pool = cdiv(C, nw)
    fc = cdiv(W8.shape[0] * W8.shape[1], nmac) + FC_LAT
    return dict(pool=pool, fc=fc, total=pool + fc, mac=nmac)


def p2_md(ck, n, cache, nrep, nws=(16, 32), fcs=(128, 256, 512)):
    """p2 golden section of one checkpoint: v1.1 program / dataflow / list schedule with IntBin2 parameters."""
    prog, net, val, st, correct = load_stats(ck, 11, n, cache, "p2")
    md = [f"### {prog.run} ({ck})", "",
          f"Bit-exact (p2 golden, v1.1 program, fused-lane sel window {prog.fsel} b): dataflow logits == IntBin2 logits on "
          f"val[:{n}]: PASS (acc {100 * correct / n:.2f} %).", ""]
    md += [f"* {c}" for c in prog.checks if c.startswith("v1.1") or "(p2)" in c or c.startswith("r bounds")
           or c.startswith("c2 pass")]
    res = {}
    for nw in nws:
        for NL in NLS11:
            res[nw, NL] = list_schedule(prog, st, NL, nw, fl=FL_ALL, check=True)
    npairs = len(BASE[(id(prog), "tiles")][1])
    md += ["", f"Schedule check (NW {', '.join(map(str, nws))}, every NL, every image): {npairs} hazard pairs hold on the "
           f"scheduled times: PASS.", ""]
    if nrep:
        replay_check(prog, net, val, st, 256, nrep, max(nws))
        md += [f"Value replay: val[:{nrep}] executed tile by tile in the NL-256 / NW-{max(nws)} scheduled order == "
               f"IntBin2 (torch.equal): PASS.", ""]
    mac = sum(p.mac for p in prog.passes)
    md += [f"#### Cycles / image (mean over val[:{n}], v1.1 schedule)", "",
           "| NW | " + " | ".join(f"NL {k}" for k in NLS11) + " | util NL 256 | min / max NL 256 |",
           "|---|" + "---|" * (len(NLS11) + 2)]
    for nw in nws:
        per = res[nw, 256][1]
        md.append(f"| {nw} | " + " | ".join(f"{res[nw, k][1].mean():.1f}" for k in NLS11)
                  + f" | {mac / (SLOTS * per.mean()):.3f} | {per.min()} / {per.max()} |")
    nw = max(nws)
    rows, per = res[nw, 256][:2]
    md += ["", f"#### Per pass, NL 256, NW {nw} (attributed cycles, sum to the image)", "",
           "| pass | PPU | tiles | chunk items | array cyc | PPU cyc | attributed cyc | exec MAC |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append(f"| {r['name']} | {r['ppu']} | {r['tiles']} | {r['items']:.1f} | {r['arr']:.1f} | {r['ppuc']:.0f} | "
                  f"{r['cyc']:.1f} | {r['mac']} |")
    md.append(f"| **image** | | | | {sum(r['arr'] for r in rows):.1f} | | **{per.mean():.1f}** (min {per.min()}, max "
              f"{per.max()}) | {mac} |")
    top = sorted(rows, key=lambda r: -r["cyc"])[:3]
    md += ["", "Top-3 passes (NL 256, NW %d, attributed): " % nw + ", ".join(f"{r['name']} {r['cyc']:.0f}" for r in top), ""]
    md += [f"#### Head (pool + FC {tuple(prog.head['fW8'].shape)} int8), overlapped with the next image (NW {nw}; "
           f"must be <= the image's cycles, min over val[:{n}] = {per.min()})", "",
           "| FC weight port (b / cycle) | int8 MAC / cycle | pool requant cyc | FC cyc | head cyc | fits |", "|---|---|---|---|---|---|"]
    hd = {}
    for fb in fcs:
        h = head_cycles(prog, nw, fb)
        hd[fb] = h
        md.append(f"| {fb} | {h['mac']} | {h['pool']} | {h['fc']} | {h['total']} | "
                  f"{'yes' if h['total'] <= per.min() else 'NO'} |")
    md.append("")
    return md, dict(run=prog.run, res=res, mac=mac, top=top, head=hd, nws=nws, minc=per.min())


P2_TEXT = [
    "Golden qc18bacc.golden_p2.IntBin2 (power-of-two stream ladder, results/golden_p2.md); `python3 -m "
    "qc18bacc.compile.cycles CKPT... --golden p2` writes this section (`--golden intbin` rewrites the sections above and keeps this one). "
    "Program (compile/program.py --golden p2): every IntBin2 parameter (stem_m, c2m / scm / c2h / sch, T1 / T2, block-6 "
    "and pool requants) re-exported (results/lane_export_<run>_p2.txt, lane widths results/lane_widths_<run>_p2.txt); "
    "identity-block c2: rs = relu(s_in) shifted by j = e_{k} - e_{k+1} in {0, -1} (round half up), asserted == IntBin2's "
    "idm requant on all of [0, 32767] (no second multiplier). v1.1 schedule (changes 1-3) unchanged; the block-6 fused "
    "fit uses the qb_lane_f sel window s' in [17, 32] (4 b): the p2 b6.hm multiplier needs s' = 29 (MW 22), outside "
    "qb_lane_s8's [17, 24].",
    "",
]


P2_FINDINGS = [
    "### p2 findings", "",
    "1. Bit-exact: compile/test_compile.py --golden p2 ALL PASS (v1 and v1.1 programs of E6_s0 / E6_s1: dataflow logits == "
    "IntBin2 on val[:500], schedule hazard check + tile replay, all v1 / v1.1 mutants, plus the p2 mutants: every identity "
    "block's j flipped 0 <-> -1 and the j = -1 round half up replaced by a floor shift are detected); --golden intbin ALL "
    "PASS with the unchanged v1.1 counts (3805.3 / 3753.7 at NL 256, NW 16).",
    "2. p2 lane widths (results/lane_widths_<run>_p2.txt, lane_export_<run>_p2.txt): the in-scope requants (stem, c2m, "
    "scm) need MW 28 / 27 in qb_lane_s8's window s' in [17, 24] (IntBin: 29 / 28), sel used 0..6; idm is a shift (j = 0 or "
    "-1). The E6_s0 b6.hm multiplier moved to s' = 29 (MW 22; E6_s1: s' = 23): with qb_lane_s8's 3-b sel it falls back to "
    "the wide lanes (E6_s0 NL 256 NW 32: 3710.8 instead of 3370.8 cycles / image), so qb_lane_f has a 4-b sel (s' in "
    "[17, 32], +140 um2 / lane, results/lane.md).",
    "3. Binary r under p2: idm rs <= 32767, sc r <= 15703 / 12965, so r fits 16 b; the 17-b r port / 17-b stream entry of "
    "deviation 4 (driven by the IntBin idm output 40160 / 45032) is not needed for the p2 golden (qb_lane_f keeps the "
    "specified 17-b sv port; S could be 16 b, -64 kb).",
    "4. NL 256, NW 32: 3370.8 / 3345.1 cycles / image (util 0.482 / 0.496); NW 16 equals the IntBin v1.1 count within 0.3 "
    "cycles. Block 6 still dominates (s0: b6.c2 904 + b6.c1 371 attributed of 3371).",
    "5. Head (cycles.head_cycles): pool sum of relu(s8) accumulated during the b7.c2 drain (512 x 20-b accumulators, no S "
    "re-read), pool requant 512 / NW = 16 cycles on the idle wide lanes, FC 51 200 int8 MACs. At 128 b / cycle of FC "
    "weights (16 MAC / cycle) the head takes 3220 cycles > the shortest image (3198 / 3182): it does NOT fit overlapped; "
    "256 b / cycle (32 MAC / cycle) gives 1620 cycles (2x margin), ARCH's 64 MAC / cycle 820.",
    "",
]


def p2_section(md2, s2):
    out = ["## p2 golden (IntBin2), v1.1 schedule (compile/*.py --golden p2, default)", ""] + P2_TEXT + md2
    out += ["### p2 summary", "", "| run | NW | cycles / image NL 256 | util | head cyc (FC 128 b) | head cyc (FC 256 b) |",
            "|---|---|---|---|---|---|"]
    for s in s2:
        for nw in s["nws"]:
            c = s["res"][nw, 256][1].mean()
            out.append(f"| {s['run']} | {nw} | {c:.1f} | {s['mac'] / (SLOTS * c):.3f} | {s['head'][128]['total']} | "
                       f"{s['head'][256]['total']} |")
    return out + [""] + P2_FINDINGS


def splice(path, header, lines):
    """replace the section starting at the line `header` (up to the next line starting with '## ') or append it."""
    old = open(path).read().split("\n") if os.path.exists(path) else []
    if header in old:
        i = old.index(header)
        j = next((k for k in range(i + 1, len(old)) if old[k].startswith("## ")), len(old))
        old = old[:i] + lines + old[j:]
    else:
        old = old + lines
    with open(path, "w") as f:
        f.write("\n".join(old).rstrip("\n") + "\n")


def v11_section(md11, s11):
    return (["## v1.1 (compile/*.py --v 11, default; --v 1 reproduces the v1 sections above)", ""] + V11_TEXT + md11
            + V11_FINDINGS)


if __name__ == "__main__":
    sys.exit(main())
