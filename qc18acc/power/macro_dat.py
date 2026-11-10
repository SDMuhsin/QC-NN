#!/usr/bin/env python3
"""Macro dynamic power from the ARM ASCII datatables (run on the build host; the .dat stays there).

    macro_dat.py <QC_MC_OUT> <pt_macros.txt> [corner=tt_1p0v_25c] [escale=1] > pt_macro_dat.txt

escale (lowv.sh): factor on the access energies, e.g. (0.8 / 1.0)^2 = 0.64 for a MODELLED 0.8 V point (the
compilers have no 0.8 V characterisation; CV^2 scaling of the 1.0 V datatable energies).

The macro .lib files (sram_sp_adv / rf_sp_adv, flow/tsmc65/sram/mc_gen.sh) have every CLK internal_power table at 0,
so PrimeTime only sees the pin energies (A, D, CEN, WEN, Q) and misses the access energy.  The datatable gives the
supply current per MHz for a read (icc_c_r<ema> + icc_p_r<ema>), a write (..._w<ema>) and a deselected clock
(CEN = 1: icc_c_desel + icc_p_desel), core + periphery, in mA/MHz: E [pJ] = icc x V x 1000.  With the SAIF
activity of each instance (pt_power.tcl: CLK toggle rate, P(CEN = 1), P(WEN = 1); CEN / WEN change only at clock
edges, WEN = 0 only together with CEN = 0 and only during writes) per analysed cycle:
  accesses = 1 - P(CEN = 1),  writes = 1 - P(WEN = 1),  reads = accesses - writes,
  deselected clocks = CLK rising edges - accesses   (v1: ungated CLK, 1 edge per cycle; v2: CLK gated by a CKLNQD
                                                     enabled by ~CEN, edges = accesses, so ~0)
  P = f_clk x (reads E_read + writes E_write + desel E_desel),   EMA = 000 (index 0, qa_sram_tech.sv).
(Same numbers as the v1 formula, which counted per CLK edge, when the clock is ungated.)
Output: one line per macro type (design names and derived numbers only) and the totals.
QA_DAT_WRITES="<ref>:<writes per analysed cycle, all instances>[,...]" (v4, power.sh): the v4 WEN pins are driven by
flops that hold their value between accesses, so P(WEN = 0) is not the write rate there; for these types the writes
are the given count and reads = accesses (from CEN, reloaded every cycle) - writes.
"""
import collections
import sys

mc, act = sys.argv[1], sys.argv[2]
corner = sys.argv[3] if len(sys.argv) > 3 else "tt_1p0v_25c"
escale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0


def dat(ref):
    rows = {}
    with open(f"{mc}/{ref}/{ref}.dat") as f:
        for line in f:
            w = line.split()
            if not w or w[0].startswith("#"):
                continue
            if w[0] == "name":
                col = w.index(corner)
            else:
                rows[w[0]] = w
    g = lambda k: float(rows[k][col])
    v = g("volt")
    e = lambda k: (g(f"icc_c_{k}") + g(f"icc_p_{k}")) * v * 1000.0 * escale  # pJ per clock edge
    return dict(read=e("r0"), write=e("w0"), desel=e("desel"), leak_mw=(g("icc_c_standby") + g("icc_p_standby")) * v)


acc = collections.OrderedDict()
period = None
with open(act) as f:
    for line in f:
        if line.startswith("#"):
            period = float(line.split("period_ns")[1].split(")")[0])
            continue
        inst, ref, tr, cen1, wen1 = line.split()
        a = acc.setdefault(ref, dict(n=0, cyc=0.0, r=0.0, w=0.0, d=0.0))
        e = float(tr) / 2.0 * period                          # CLK rising edges per analysed cycle (1 = ungated)
        pon = 1.0 - float(cen1)                               # accesses per cycle
        pw = min(pon, 1.0 - float(wen1))                      # writes per cycle
        a["n"] += 1
        a["cyc"] += e
        a["r"] += (pon - pw) / period                         # per ns
        a["w"] += pw / period
        a["d"] += max(0.0, e - pon) / period
import os
for kv in filter(None, os.environ.get("QA_DAT_WRITES", "").split(",")):
    ref, w = kv.split(":")
    if ref in acc:
        a = acc[ref]
        tot = a["r"] + a["w"]
        a["w"] = float(w) / period
        a["r"] = tot - a["w"]
        print(f"# {ref}: writes per cycle from QA_DAT_WRITES = {float(w):.4f} (WEN-based estimate overridden)")
print(f"# macro datatable model, corner {corner}, escale {escale}, period_ns {period}: per type n, reads / writes / deselected clocks "
      f"per cycle (sum over instances), E_read / E_write / E_desel pJ, P_read / P_write / P_desel / P_dyn W, datatable standby leakage W")
tot = 0.0
for ref, a in acc.items():
    d = dat(ref)
    pr, pw, pd = (a[k] * 1e9 * d[e] * 1e-12 for k, e in (("r", "read"), ("w", "write"), ("d", "desel")))
    tot += pr + pw + pd
    print(f"datmacro:{ref} n {a['n']} clk_per_cycle {a['cyc'] / a['n']:.4f} reads_pc {a['r'] * period:.4f} "
          f"writes_pc {a['w'] * period:.4f} desel_pc {a['d'] * period:.4f} E_read {d['read']:.2f} E_write {d['write']:.2f} "
          f"E_desel {d['desel']:.2f} P_read {pr:.6e} P_write {pw:.6e} P_desel {pd:.6e} P_dyn {pr + pw + pd:.6e} "
          f"leak_dat {d['leak_mw'] * 1e-3 * a['n']:.6e}")
print(f"datmacro:total P_dyn {tot:.6e}")
