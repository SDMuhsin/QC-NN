#!/usr/bin/env python3
"""R9c: column-local params bank layout (opt-in RTL define QB_PRM_COL, hw/rtl/qb_seq.sv qb_prm #(COL 1)).

Bank: 9 x rf_sp 240 x 144 (macro m = bank-row bits 144 m .. 144 m + 143), one 1296-b row per cycle; a fused (f) / wide
(w) set = 4 rows (5184 / 5056 logical bits), a T2 (t) set = 1 row (1088 b).  Logical set bits (export_top2.bank):
  f  pf  : column c = bits 648 c .. 648 c + 647  (8 channel records of 81 b)
  w  pw  : column c = bits 632 c .. 632 c + 631  (8 records of 79 b)
  t  t2  : column c = bits 136 c .. 136 c + 135  (8 lanes of 17 b)
Default layout (COL 0): row r, bank bit q = logical 1296 r + q (t: q).  Column layout (COL 1): column c owns the
648-b slot c of a set (slot bit s; f s = logical - 648 c, w s = logical - 632 c, s < 632):
  s <  576 : row s // 144, macro c, bit s % 144                    (macro c under column c: local)
  s >= 576 : u = s - 576 (< 72), row u // 18, macro 8, bit 18 c + u % 18   (the 9th macro: 18 b per column per row)
  t: column c lane bits i < 136 at macro c bit i (macro 8 and bits 136..143 unused).
RTL (QB_PRM_COL): stg_f / stg_w are kept in slot order (stg[648 c + s]); landing of row r writes
stg[648 c + 144 r +: 144] <= b_q[144 c +: 144] and stg[648 c + 576 + 18 r +: 18] <= b_q[1152 + 18 c +: 18] for every c;
pf = stg_f (slot order == logical for f), pw[632 c + s] = stg_w[648 c + s], t2[136 c + i] = stg_t[144 c + i].

    python3 -I prm_col.py convert <src prog dir> <dst prog dir>     p_rows.txt of a default-layout program -> column
         layout (row consumers from the fetch lists d_ff / d_fw / d_ft); the other files are copied unchanged
    python3 -I prm_col.py analyze <out dir>                          bit maps, crossing tables, HPWL model (R9c)
"""
import os
import shutil
import sys

RW, MW, NM, NC = 1296, 144, 9, 8
NR = dict(f=4, w=4, t=1)
NB = dict(f=5184, w=5056, t=1088)
CW = dict(f=648, w=632, t=136)              # logical bits per column
SLOT, LOC, XW = 648, 576, 18                # column slot, local part (4 x 144), 9th-macro part per row (144 / 8)


def phys_of(cons, L, col):
    """logical bit L of a set of consumer cons -> (row, bank bit q)."""
    if not col:
        return (L // RW, L % RW) if cons != "t" else (0, L)
    c, s = divmod(L, CW[cons])
    if cons == "t":
        return 0, MW * c + s
    if s < LOC:
        return s // MW, MW * c + s % MW
    u = s - LOC
    return u // XW, MW * (NM - 1) + XW * c + u % XW


def column_of(cons, L):
    return L // CW[cons]


def to_rows(cons, v, col):
    """logical set value (nb bits) -> NR[cons] bank rows."""
    if not col:
        return [(v >> (RW * r)) & ((1 << RW) - 1) for r in range(NR[cons])]
    rows = [0] * NR[cons]
    for L in range(NB[cons]):
        if (v >> L) & 1:
            r, q = phys_of(cons, L, True)
            rows[r] |= 1 << q
    return rows


def from_rows(cons, rows, col):
    v = 0
    for L in range(NB[cons]):
        r, q = phys_of(cons, L, col)
        v |= ((rows[r] >> q) & 1) << L
    return v


def _check_bijective():
    for cons in "fwt":
        for col in (False, True):
            seen = set()
            for L in range(NB[cons]):
                p = phys_of(cons, L, col)
                assert 0 <= p[0] < NR[cons] and 0 <= p[1] < RW and p not in seen, (cons, col, L, p)
                seen.add(p)


def read_fl(path):
    with open(path) as fh:
        t = fh.read().split()
    n = int(t[0])
    return [int(x, 16) for x in t[1:1 + n]]


def convert(src, dst):
    _check_bijective()
    assert os.path.abspath(src) != os.path.abspath(dst)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(src):
        if f != "p_rows.txt" and os.path.isfile(os.path.join(src, f)):
            shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
    with open(os.path.join(src, "p_rows.txt")) as fh:
        rows = [int(x, 16) for x in fh.read().split()]
    kind = {}
    for cons, fn in (("f", "d_ff.txt"), ("w", "d_fw.txt"), ("t", "d_ft.txt")):
        for e in read_fl(os.path.join(src, fn)):
            base = (e >> 9) & 0xFF
            assert kind.setdefault(base, cons) == cons, (base, cons)
    out = list(rows)
    done = set()
    for base, cons in sorted(kind.items()):
        rr = list(range(base, base + NR[cons]))
        assert not done & set(rr), ("overlapping sets", base)
        done |= set(rr)
        v = from_rows(cons, [rows[r] for r in rr], False)
        assert to_rows(cons, v, False) == [rows[r] for r in rr], ("bits outside the logical set", base)
        new = to_rows(cons, v, True)
        assert from_rows(cons, new, True) == v
        for r, w in zip(rr, new):
            out[r] = w
    with open(os.path.join(dst, "p_rows.txt"), "w") as fh:
        fh.writelines(format(r, "0324x") + "\n" for r in out)
    print(f"PRM_COL convert {src} -> {dst}: {len(rows)} rows, sets f {sum(1 for k in kind.values() if k == 'f')} "
          f"w {sum(1 for k in kind.values() if k == 'w')} t {sum(1 for k in kind.values() if k == 't')}, rows "
          f"remapped {len(done)}, unreferenced {len(rows) - len(done)} (kept)", flush=True)


# ---------------------------------------------------------------------------------------------- analysis (R9c)
X0, PITCH = 860.0, 390.0
XC = [X0 + PITCH * (c + 0.5) for c in range(NC)]                       # column centres
PMW, PHG = 439.8, 10.0                                                  # rf_sp_adv 240 x 144 m2 width, gap (mplace9)
XS9 = X0 + NC * PITCH - (8 * (PMW + PHG) - PHG)                         # R9b row start (right-aligned to the east edge)
GEOM = {
    "ideal": dict(x=[XC[m] for m in range(8)] + [None], note="macro k at column k centre (task model)"),
    "r9b": dict(x=[XS9 + k * (PMW + PHG) + PMW / 2 for k in range(8)] + [10.0 + PMW / 2],
                note="R9b mplace9 x (439.8-um macros, row right-aligned; macro 8 NW corner)"),
}
M8POS = {"mid": (XC[3] + XC[4]) / 2, "east": X0 + NC * PITCH + PMW / 2, "nw": 10.0 + PMW / 2}


def consumers(col):
    """per bank bit q: {(cons, column)} over all rows of the f / w / t sets."""
    m = [set() for _ in range(RW)]
    for cons in "fwt":
        for L in range(NB[cons]):
            r, q = phys_of(cons, L, col)
            m[q].add((cons, column_of(cons, L)))
    return m


def analyze(out):
    _check_bijective()
    os.makedirs(out, exist_ok=True)
    lines = ["# R9c params bank bit map: macro m bit i (bank bit 144 m + i) -> consumers (consumer f = pf, w = pw, t = t2; column)",
             "# per macro: columns reached by its 144 Q bits (union over rows / sets); 'taps' = (Q bit, column) pairs",
             "# (= staging-slice destinations of that Q pin); other consumers of macro Q: none (common pf / pw bits come",
             "# from the pass table; the HPW write chain only drives the macro D / A pins)"]
    cm = {False: consumers(False), True: consumers(True)}
    for col in (False, True):
        lines.append(f"## layout {'COL (QB_PRM_COL)' if col else 'default'}")
        lines.append("macro | f columns | w columns | t columns | taps f / w / t | Q bits used")
        for mac in range(NM):
            qs = range(MW * mac, MW * mac + MW)
            cs = {k: sorted({c for q in qs for (kk, c) in cm[col][q] if kk == k}) for k in "fwt"}
            nt = {k: sum(1 for q in qs for (kk, c) in cm[col][q] if kk == k) for k in "fwt"}
            used = sum(1 for q in qs if cm[col][q])
            lines.append(f"{mac} | {cs['f']} | {cs['w']} | {cs['t']} | {nt['f']} / {nt['w']} / {nt['t']} | {used}")
        # bit ranges for COL: compact description
        if col:
            lines.append("COL detail: macro c<8 bit i: f row r -> col c pf[648c+144r+i]; w row r -> col c pw[632c+144r+i];"
                         " t -> col c t2[136c+i] (i<136)")
            lines.append("            macro 8 bit 18c+j: f row r -> col c pf[648c+576+18r+j]; w row r -> col c "
                         "pw[632c+576+18r+j] (18r+j<56); t unused")
    with open(os.path.join(out, "bitmap.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    # ---- crossing tables (per read: rows actually transferred; per Q pin: static connections)
    L2 = ["# R9c crossing: distance macro -> consumer column in column pitches (390 um), per geometry; static taps",
          "# (Q bit, column) and per-read traffic (bits per row read, averaged over the f / w set rows; t = its one row)",
          "# geometry ideal = macro k at column k centre (macro 8 placement given per row); r9b = R9b mplace9 x positions"]
    hp = ["# R9c params Q HPWL model (x only: span of {macro Q pin x, consumer column centres}; staging flops of column c",
          "# at its centre, as R9b's column-local pf / pw / t2 pins; y extent not modelled = same before / after).",
          "# R9b measured (longnets_gpl.txt, plain gpl): 1 296 params Q nets, 5.23 m HPWL (4.04 mm / net)"]
    for gname, g in GEOM.items():
        for m8 in (["mid", "east", "nw"] if gname == "ideal" else ["r9b"]):
            xs = list(g["x"])
            if xs[8] is None or m8 != "r9b":
                xs[8] = M8POS[m8]
            for col in (False, True):
                tag = f"{gname}/m8={m8}/{'COL' if col else 'default'}"
                hist = [0] * 9
                far = 0
                tot = 0.0
                hp9 = 0.0
                for q in range(RW):
                    mac = q // MW
                    cols = {c for (_, c) in cm[col][q]}
                    if not cols:
                        continue
                    for c in cols:
                        d = abs(xs[mac] - XC[c]) / PITCH
                        hist[min(8, int(d + 0.5))] += 1
                        far += d > 1.0
                    xx = [xs[mac]] + [XC[c] for c in cols]
                    w = max(xx) - min(xx)
                    tot += w
                    if mac == 8:
                        hp9 += w
                # per-read traffic: bits moved per row read with distance > 1 pitch, and bit*pitch
                tr = {}
                for cons in "fwt":
                    bits = farb = 0
                    bp = 0.0
                    for L in range(NB[cons]):
                        r, q = phys_of(cons, L, col)
                        d = abs(xs[q // MW] - XC[column_of(cons, L)]) / PITCH
                        bits += 1
                        farb += d > 1.0
                        bp += d
                    tr[cons] = (farb / NR[cons], bp / NR[cons] / bits * 1.0)
                L2.append(f"{tag}: taps by distance [0,1,..,7,8+ pitches] {hist}  taps > 1 pitch {far} / {sum(hist)};  "
                          f"per row read > 1 pitch: f {tr['f'][0]:.0f} w {tr['w'][0]:.0f} t {tr['t'][0]:.0f} b, mean "
                          f"distance f {tr['f'][1]:.2f} w {tr['w'][1]:.2f} t {tr['t'][1]:.2f} pitch")
                hp.append(f"{tag}: params Q nets {sum(1 for q in range(RW) if cm[col][q])}, x-HPWL {tot / 1e6:.3f} m "
                          f"(mean {tot / max(1, sum(1 for q in range(RW) if cm[col][q])):.0f} um), of which macro 8 "
                          f"{hp9 / 1e6:.3f} m")
    with open(os.path.join(out, "crossing.txt"), "w") as fh:
        fh.write("\n".join(L2) + "\n")
    with open(os.path.join(out, "hpwl.txt"), "w") as fh:
        fh.write("\n".join(hp) + "\n")
    print("\n".join(L2 + hp))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "convert":
        convert(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "analyze":
        analyze(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
