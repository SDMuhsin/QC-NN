"""Supply-aware cycle model of QC18B-ACC (activation supply = qb_act, results/r2.md): the v1.1 list scheduler
(compile/cycles.list_schedule) with every array tile's compute time stretched by the activation supply.

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.supply CKPT [CKPT ...] [--n 100] [--cache DIR] [--out MD]

Model (per image, inside the list scheduler, hook cycles.list_schedule(..., sup=Supply(...))):
* qb_act contexts (ctx = 1: pass-level command, as built; 2: two contexts, c1 / c2 interleave).  A context owns one
  array pass from its first tile to its last; a new pass may take a context only after the context's previous pass
  issued its last item + TAIL (done pulse) + 1 (start).  The scheduler offers tiles of at most ctx array passes.
* Binary maps (as built): virtual rows of the pass (qb_act vl: top pad row, map rows, bottom pad row for 3x3 passes
  that are not whole-map tiles; 1x1 stride-2 odd rows are skipped in 1 cycle), loaded in order through ONE map read
  port shared by all contexts, LINE = 512 b per line, 4 lines per row, `width` b / cycle (pad rows cost the same as
  read rows: one LB quarter write per line).  Row v of a context can be loaded only when it fits the 8-slot line buffer
  (v < vb + 8, vb = window base of the context's segment being issued; the slot frees when the last segment with
  vb <= v - 8 has issued its last item), after its data is written (RAW ready of the tile from the scheduler), after
  the context started the pass, and after the port finished the previous load (port served in array-tile commit
  order).  A row is usable LAT = 3 cycles after its last line left the port (m_ra reg -> macro -> rdq -> LB).
* Items: a binary tile issues its items one per cycle once its whole window (vb .. vb + K) is loaded (qb_act S_BIN);
  later channel tiles of the same pixel tile reuse the window.  int8 (block 6, as built): per (channel tile, plane)
  segment, window = the plane's R rows (HQ 8, Z 4, K = R), S_WAIT -> S_FLAG -> items (only nonzero chunks) -> one
  empty S_ITER cycle; one S_CTEND cycle per channel tile (carries the zero item of an empty channel tile).
* Block 6 from S (options B..E): HQ / Z stored slice-major ((plane, chunk) contiguous) in the stream buffer S, read at
  S_W b / cycle (own port, no conflict assumed), writer-side (plane, chunk) zero flags: only words holding an executed
  slice are read (c1: slice 2048 b = 1 word; c2: slice 512 b, 4 chunks per word; sc: decimated even-pixel copy, 4096 b
  = 2 words; sc_full=True: the whole plane, 8 words), re-read per channel tile, items back to back (no flag / empty
  cycles), the 16-kb line buffer holds at most 8 words not yet consumed.
* Array tile duration = (last item issue) - (scheduler start); array items and drain occupancy (shadow / lanes) stay
  the scheduler's.  So tile cycles = max(items, drain, supply) as the scheduler composes them.
"""
import argparse
import os

import numpy as np
import torch

from . import cycles as Cy
from . import dataflow as D
from . import program as P

LAT, TAIL = 3, 4           # row usable LAT cycles after its last line left the port; done = last issue + 3 + ACT_PIPE
ROWL = 4                   # 512-b lines per map row (2048 b)


# ------------------------------------------------------------------------------------------------ block-6 masks
def b6_masks(prog, net, val, n, cache=None, bs=100, dev="cuda"):
    """executed (plane, chunk) items of every int8 array pass: {pass: [n, 8, nchunk] bool} (tiles_px = 1 in block 6),
    from the dataflow buffers before each pass (same skip rule as dataflow.pe_array; totals asserted == its items)."""
    path = None if cache is None else os.path.join(cache, f"{prog.run}_v11_n{n}_p2_b6mask.npz")
    if path and os.path.exists(path):
        z = np.load(path)
        return {k: z[k] for k in z.files}
    xv, _ = val
    Ws = {p.name: D.PEWeights(p, dev) for p in prog.passes if p.k}
    out = {}
    with torch.no_grad():
        for i in range(0, n, bs):
            xb = xv[i:min(i + bs, n)]
            bf = D.Bufs(len(xb), dev)
            D.load_image(prog, bf, xb, dev)
            st = {}
            for p in prog.passes:
                if p.k and p.inb == 8 and p.kind != "stem":
                    assert p.tiles_px == 1
                    Li = p.Hin * p.Win
                    m = []
                    for b in range(8):
                        a = D.nchw(bf.read(p.src, Li, p.cin, plane=b), p.Hin, p.Win).float()
                        pt = D.patches(a, p)                                       # [N, L, nchunk, 288]
                        m.append(pt.reshape(pt.shape[0], -1, p.nchunk, pt.shape[-1]).any(-1).any(1))
                    out.setdefault(p.name, []).append(torch.stack(m, 1).cpu().numpy())
                D.do_pass(prog, p, bf, Ws, dev, st)
            lg = D.head(prog, bf, dev)
            assert torch.equal(lg, net(xb)), "dataflow != golden"
            for k in out:
                assert np.array_equal(out[k][-1].sum((1, 2)), st[k][:, 0]), f"{k}: mask total != dataflow items"
    out = {k: np.concatenate(v) for k, v in out.items()}
    if path:
        os.makedirs(cache, exist_ok=True)
        np.savez(path, **out)
    return out


def load(ck, n, cache):
    prog, net, val, st, correct = Cy.load_stats(ck, 11, n, cache, "p2")
    return prog, net, val, st, correct, b6_masks(prog, net, val, n, cache)


# ------------------------------------------------------------------------------------------------ geometry
def bin_geom(p):
    """binary / stem pass as qb_act loads it: (vtot, padL, cost class per virtual row, windows [(vb, vend)] per
    pixel tile).  cost class: 'row' (4 lines, read or pad), 'skip' (odd row of a 1x1 stride-2 pass, 1 cycle)."""
    whole = p.tiles_px == 1
    padL = p.pad if (p.k == 3 and not whole) else 0
    even = p.k == 1 and p.stride == 2
    vtot = p.Hin + 2 * padL
    kind = ["skip" if (even and (v - padL) % 2) else "row" for v in range(vtot)]
    win = []
    for tp in range(p.tiles_px):
        if whole:
            win.append((0, vtot))
            continue
        oys = sorted({x // p.Wout for x in range(tp * P.ROWS, (tp + 1) * P.ROWS)})
        if p.k == 3:
            vs = [oy * p.stride + dy - p.pad + padL for oy in oys for dy in range(3)]
        else:
            vs = [oy * p.stride for oy in oys]
        win.append((min(vs), max(vs) + 1 + (1 if even else 0)))
    return vtot, padL, kind, win


S_SLICE = {"wc1": 2048, "wc2": 512, "wsc": 4096}       # bits of one (plane, chunk) slice (sc: decimated copy)


class Supply:
    """supply hook for cycles.list_schedule (see the module doc).  width: binary-map port b / cycle; b6: 'maps' (as
    built, through the map port, per-plane LB windows) or 'S' (slice-major in S at s_w b / cycle); ctx: contexts."""

    def __init__(self, prog, masks, width=512, b6="maps", ctx=1, s_w=2048, sc_full=False):
        self.prog, self.masks, self.width, self.b6, self.ctx, self.s_w = prog, masks, width, b6, ctx, s_w
        self.sc_full = sc_full
        self.m = width // 512                                      # lines / cycle
        self.geo = {pi: bin_geom(p) for pi, p in enumerate(prog.passes) if p.k and not (p.inb == 8 and p.kind != "stem")}
        self.final = {}

    # list_schedule interface
    def varies(self, d):
        p = self.prog.passes[d["pi"]]
        return bool(d["arr"] and p.inb == 8 and p.kind != "stem")

    def new(self, T, nt):
        self.nt = nt
        return _State(self.ctx, len(self.prog.passes))

    def dur(self, S, T, t, s, C, img, ra):
        d = T[t]
        pi = d["pi"]
        p = self.prog.passes[pi]
        cx = S.context(pi, self.nt[pi])
        start = s
        if pi in self.geo:
            ce = self._bin(S, cx, pi, d, s, ra, C)
        elif self.b6 == "maps":
            ce = self._b6_maps(S, cx, p, d, s, ra, self.masks[p.name][img])
        else:
            ce = self._b6_s(S, cx, p, d, s, ra, self.masks[p.name][img])
        cx["left"] -= 1
        cx["last"] = ce
        if cx["left"] == 0:
            cx["free"] = ce + TAIL + 1                             # done pulse (last issue + 5); start next cycle
        ps = S.ps[pi]
        ps["first"] = start if ps["first"] is None else ps["first"]
        ps["end"] = ce
        ps["extra"] += (ce - s) - C
        self.final[img] = S
        return ce - s

    def probe(self, S, T, t, ra):
        """supply-ready time of tile t's window if it were next (no state change, port contention ignored); used by
        the scheduler to pick among candidate tiles.  Block-6 tiles: 0 (no preference)."""
        d = T[t]
        pi = d["pi"]
        if pi not in self.geo:
            return 0
        cx = next((c for c in S.ctx if c["pi"] == pi), None)
        if cx is None:
            c = min((c for c in S.ctx if c["left"] == 0), key=lambda c: c["free"])
            cx = dict(start=c["free"] + 1, vl=0, rdy=0, ld=0, segs=[])
        vtot, padL, kind, win = self.geo[pi]
        vend = win[d["tp"]][1]
        if cx["vl"] >= vend:
            return cx["rdy"]
        cost = sum(1 if kind[v] == "skip" else -(-ROWL // self.m) for v in range(cx["vl"], vend))
        return max(cx["ld"], ra, cx["start"], self._avail(cx, cx["vl"])) + cost + LAT

    # loads ------------------------------------------------------------------------------------------------
    def _avail(self, cx, v):
        a = 0
        for vb, end in cx["segs"]:
            if vb <= v - 8:
                a = end
            else:
                break
        return a

    def _load_rows(self, S, cx, upto, kind, ra, port, pi):
        """load virtual rows cx['vl'] .. upto - 1 through the map port; returns the ready time of row upto - 1."""
        while cx["vl"] < upto:
            v = cx["vl"]
            cost = 1 if kind(v) == "skip" else -(-ROWL // self.m)
            st = S.grab(port, max(cx["ld"], self._avail(cx, v), ra, cx["start"]), cost)
            cx["ld"] = st + cost
            cx["rdy"] = cx["ld"] + LAT
            S.ps[pi]["bits"] += 0 if kind(v) == "skip" else ROWL * 512
            cx["vl"] += 1
        return cx["rdy"]

    def _bin(self, S, cx, pi, d, s, ra, C):
        vtot, padL, kind, win = self.geo[pi]
        vb, vend = win[d["tp"]]
        rdy = self._load_rows(S, cx, vend, lambda v: kind[v], ra, "map", pi)
        first = max(s, rdy)
        ce = first + C
        if not cx["segs"] or cx["segs"][-1][0] != vb:
            cx["segs"].append((vb, ce))
        else:
            cx["segs"][-1] = (vb, ce)
        return ce

    def _b6_maps(self, S, cx, p, d, s, ra, mk):
        """as built: per (channel tile, plane) segment the plane's R rows, S_WAIT / S_FLAG / items / empty, S_CTEND."""
        R = p.Hin
        even = p.kind == "wsc"
        cur = s
        for pl in range(8):
            vb = (d["cg"] * 8 + pl) * R
            rdy = self._load_rows(S, cx, vb + R, lambda v: "skip" if (even and (v % R) % 2) else "row", ra, "map",
                                  self.prog.passes.index(p))
            first = max(cur + 1, rdy) + 2                         # vb == vbp one cycle after a shift
            cur = first + int(mk[pl].sum()) + 1
            cx["segs"].append((vb, cur))
        return cur + 1

    def _b6_s(self, S, cx, p, d, s, ra, mk):
        """block-6 maps slice-major in S: read only words holding executed slices, items back to back."""
        pi = self.prog.passes.index(p)
        W = self.s_w
        sl = S_SLICE[p.kind]
        items = [(pl, g) for pl in range(8) for g in range(p.nchunk) if mk[pl, g]]
        if not items:
            return max(s, cx["start"]) + 1
        if p.kind == "wsc":
            nw = (p.Hin * p.Win * p.cin // W) if self.sc_full else -(-sl // W)
            words = lambda it: [(it[0], k) for k in range(nw)]
        else:
            per = max(1, W // sl)
            nwi = max(1, sl // W)
            words = lambda it: [(it[0], it[1] // per, k) for k in range(nwi)]
        cap = 16384 // W                                           # LB words in flight (16 kb)
        lastuse = {}
        for k, it in enumerate(items):
            for w in words(it):
                lastuse[w] = k
        cur = s
        got, idx = {}, {}
        for k, it in enumerate(items):
            for w in words(it):
                if w in got:
                    continue
                rel = cx["rel"][-cap] if len(cx["rel"]) >= cap else 0
                rel = cur if rel is None else rel
                st = S.grab("S", max(cx["ld"], rel, ra, cx["start"]), 1)
                cx["ld"] = st + 1
                got[w] = cx["ld"] + LAT
                S.ps[pi]["bits"] += W
                idx[w] = len(cx["rel"])
                cx["rel"].append(None)
            first = max(cur, max(got[w] for w in words(it)))
            cur = first + 1
            for w in words(it):
                if lastuse[w] == k:
                    cx["rel"][idx[w]] = cur
        return cur


class _State:
    def __init__(self, nctx, npass):
        self.port = {"map": [], "S": []}                        # busy intervals [a, b) of each read port
        self.ctx = [dict(pi=None, left=0, free=0, last=0) for _ in range(nctx)]
        self.ps = [dict(first=None, end=None, extra=0, bits=0) for _ in range(npass)]

    def copy(self):
        import copy
        return copy.deepcopy(self)

    def grab(self, port, lo, cost):
        """earliest start >= lo of a free gap of cost cycles on the port (loads of different contexts may fill gaps,
        loads of one context stay in order through cx['ld']); keeps only the recent intervals."""
        iv = self.port[port]
        t = lo
        k = 0
        while k < len(iv) and iv[k][1] <= t:
            k += 1
        while k < len(iv) and iv[k][0] < t + cost:
            t = max(t, iv[k][1])
            k += 1
        iv.insert(k, (t, t + cost))
        if len(iv) > 4096:
            del iv[:2048]
        return t

    def context(self, pi, ntiles):
        for c in self.ctx:
            if c["pi"] == pi:
                return c
        c = min((c for c in self.ctx if c["left"] == 0), key=lambda c: c["free"])
        c.update(pi=pi, left=ntiles, start=c["free"] + 1, vl=0, rdy=0, ld=0, segs=[], rel=[])
        return c


def standalone(prog, st, sup, img):
    """every array pass alone (cold qb_act, start at cycle 0, no core back-pressure), as the R2 bench runs it:
    {pass: cycles from start to done}."""
    key = (id(prog), "tiles")
    if key not in Cy.BASE:
        Cy.BASE[key] = Cy.tiles_of(prog)
    T, _ = Cy.BASE[key]
    out = {}
    for pi, p in enumerate(prog.passes):
        ts = [t for t, d in enumerate(T) if d["pi"] == pi]
        if not T[ts[0]]["arr"]:
            continue
        C = Cy.tile_items(p, st[p.name], Cy.FL_ALL)[img]
        S = sup.new(T, [len([t for t, d in enumerate(T) if d["pi"] == q]) for q in range(len(prog.passes))])
        s = 0
        for k, t in enumerate(ts):
            s += sup.dur(S, T, t, s, int(C[k]), img, 0)
        out[p.name] = s + TAIL
    return out


NL, NWD = 256, 32
CONFIGS = (  # name, ctx (None = v1.2 list scheduler as is), Supply kwargs (None = free supply), mechanism
    ("v1.2", None, None, "cycles.py as is: free supply, up to WIN = 4 passes interleaved"),
    ("A0", 1, None, "one context (pass-serial array), free supply"),
    ("A", 1, dict(width=512, b6="maps", ctx=1), "as built: 512-b map port, one context, b6 per-plane LB windows"),
    ("B", 1, dict(width=512, b6="S", ctx=1), "A + b6 slice-major in S at 2048 b/cycle, executed slices only"),
    ("C0", 2, None, "two contexts, free supply"),
    ("C", 2, dict(width=512, b6="S", ctx=2), "B + two contexts sharing the 512-b map port"),
    ("D", 1, dict(width=1024, b6="S", ctx=1), "B with a 1024-b map port"),
    ("E", 2, dict(width=1024, b6="S", ctx=2), "C with a 1024-b map port"),
    ("B-scfull", 1, dict(width=512, b6="S", ctx=1, sc_full=True), "B, b6.sc from the full HQ plane (no decimated copy)"),
)


def run(prog, st, mk, ctx, kw):
    sup = None if kw is None else Supply(prog, mk, **kw)
    rows, per, _ = Cy.list_schedule(prog, st, NL, NWD, ctx=ctx, sup=sup, check=True)
    return rows, per, sup


def evaluate(ck, n, cache):
    prog, net, val, st, correct, mk = load(ck, n, cache)
    res = {}
    for name, ctx, kw, _ in CONFIGS:
        res[name] = run(prog, st, mk, ctx, kw)
        print(f"{prog.run} {name}: {res[name][1].mean():.1f} cycles / image", flush=True)
    sa = [standalone(prog, st, Supply(prog, mk, 512, "maps", 1), i) for i in (0, 1)]
    return prog, st, mk, res, sa


R2_TB = os.path.join(os.path.dirname(__file__), "..", "results", "r2_tb.txt")


def r2_measured():
    """{img: {pass: cycles}} of the passing R2 bench runs (results/r2_tb.txt, the first two image blocks)."""
    out, cur = [], {}
    for line in open(R2_TB):
        w = line.split()
        if line.startswith("QB_ACT pass"):
            cur[w[3]] = int(w[w.index("cycles") + 1])
        elif line.startswith("QB_ACT_TB"):
            out.append(cur)
            cur = {}
            if len(out) == 2:
                break
    return out


def report(out, n, runs):
    md = ["# Supply-aware cycle model (compile/supply.py)", "",
          "Labels: [M] measured (RTL simulation), [Mod] modelled.  Golden p2, v1.1 program, NL 256, NW 32, "
          f"val[:{n}] (never the test set), GPU 0.  Every config runs the v1.1 list scheduler (compile/cycles.py) with "
          "its hazard check on the scheduled times (PASS for every config / image).", ""]
    md += ["## Method", ""] + [l for l in (__doc__.split("Model (per image")[1]).splitlines()[1:] if l.strip()] + [""]
    prog0, st0, mk0, res0, sa0 = runs[0]
    md += ["## Agreement with R2 (qb_act RTL, standalone passes, E6_s0 val 0 / 1)", "",
           "Model `standalone()` = config A's supply model run pass by pass from a cold qb_act, as the R2 bench does.", "",
           "| pass | R2 img0 [M] | model img0 [Mod] | R2 img1 [M] | model img1 [Mod] |", "|---|---|---|---|---|"]
    r2 = r2_measured()
    for k in sa0[0]:
        md.append(f"| {k} | {r2[0][k]} | {sa0[0][k]} | {r2[1][k]} | {sa0[1][k]} |")
    md.append(f"| **sum of 20 passes** | {sum(r2[0].values())} | {sum(sa0[0].values())} | {sum(r2[1].values())} | "
              f"{sum(sa0[1].values())} |")
    nd = sum(r2[i][k] != sa0[i][k] for i in (0, 1) for k in sa0[0])
    md += ["", f"Passes that differ from the RTL: {nd} of 40 (cycle-exact on both images).", ""]
    md += ["## Cycles / image [Mod] (mean over val[:%d]; min / max)" % n, "",
           "| config | mechanism | " + " | ".join(r[0].run for r in runs) + " | delta vs v1.2 (" + runs[0][0].run + ") |",
           "|---|---|" + "---|" * (len(runs) + 1)]
    for name, ctx, kw, mech in CONFIGS:
        cells = [f"{r[3][name][1].mean():.1f} ({r[3][name][1].min()} / {r[3][name][1].max()})" for r in runs]
        d = res0[name][1].mean() - res0["v1.2"][1].mean()
        md.append(f"| {name} | {mech} | " + " | ".join(cells) + f" | {d:+.1f} |")
    for prog, st, mk, res, sa in runs:
        names = [c[0] for c in CONFIGS]
        md += ["", f"### Per pass, {prog.run} (attributed cycles [Mod]; supply stall = sum over tiles of "
               "(supply-stretched - item) cycles, mean)", "",
               "| pass | items | " + " | ".join(names) + " | stall A | stall B | stall C | stall D | stall E |",
               "|---|---|" + "---|" * (len(names) + 5)]
        for pi, p in enumerate(prog.passes):
            row = [p.name, f"{res['v1.2'][0][pi]['arr']:.1f}"]
            row += [f"{res[nm][0][pi]['cyc']:.1f}" for nm in names]
            for nm in "ABCDE":
                sup = res[nm][2]
                row.append(f"{np.mean([sup.final[i].ps[pi]['extra'] for i in sup.final]):.1f}")
            md.append("| " + " | ".join(row) + " |")
        md.append("| **image** | | " + " | ".join(f"**{res[nm][1].mean():.1f}**" for nm in names) + " | | | | | |")
        # S read demand of block 6 in B..E
        md += ["", f"S read demand of the block-6 passes, {prog.run} (b / cycle over the pass's span = first array "
               "start .. last item; mean over images) [Mod]; the S read port runs at 2048 b / cycle while streaming", "",
               "| pass | bits read / image | B | C | D | E |", "|---|---|---|---|---|---|"]
        for pi, p in enumerate(prog.passes):
            if p.inb == 8 and p.kind != "stem":
                cells = []
                for nm in "BCDE":
                    sup = res[nm][2]
                    v = [sup.final[i].ps[pi]["bits"] / max(1, sup.final[i].ps[pi]["end"] - sup.final[i].ps[pi]["first"])
                         for i in sup.final]
                    cells.append(f"{np.mean(v):.0f}")
                bits = np.mean([res["B"][2].final[i].ps[pi]["bits"] for i in res["B"][2].final])
                md.append(f"| {p.name} | {bits:.0f} | " + " | ".join(cells) + " |")
    with open(out, "w") as f:
        f.write("\n".join(md) + "\n")
    return md


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", default=None)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "results", "supply.md"))
    a = ap.parse_args()
    runs = [evaluate(ck, a.n, a.cache) for ck in a.ckpts]
    report(a.out, a.n, runs)


if __name__ == "__main__" and not os.environ.get("SUPPLY_COLLECT"):
    main()

if __name__ == "__main__" and os.environ.get("SUPPLY_COLLECT"):
    import sys
    for ck in sys.argv[1:]:
        prog, net, val, st, correct, mk = load(ck, 100, os.environ["SUPPLY_COLLECT"])
        print(prog.run, {k: (v.shape, v.sum((1, 2))[:2]) for k, v in mk.items()}, flush=True)
