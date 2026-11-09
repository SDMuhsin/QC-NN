#!/usr/bin/env python3
"""Macro dynamic power from the ARM ASCII datatables (run on the build host; the .dat stays there).

    macro_dat.py <QC_MC_OUT> <pt_macros.txt> [corner=tt_1p0v_25c] > pt_macro_dat.txt

The macro .lib files (sram_sp_adv / rf_sp_adv, flow/tsmc65/sram/mc_gen.sh) have every CLK internal_power table at 0,
so PrimeTime only sees the pin energies (A, D, CEN, WEN, Q) and misses the access energy.  The datatable gives the
supply current per MHz for a read (icc_c_r<ema> + icc_p_r<ema>), a write (..._w<ema>) and a deselected clock
(CEN = 1: icc_c_desel + icc_p_desel), core + periphery, in mA/MHz: E [pJ] = icc x V x 1000.  With the SAIF
activity of each instance (pt_power.tcl: CLK toggle rate, P(CEN = 1), P(WEN = 1); WEN = 0 only together with
CEN = 0 in this design, and only during writes) the clock edges split into reads, writes and deselected cycles:
  P = f_clk x (p_read E_read + p_write E_write + p_desel E_desel),   EMA = 000 (index 0, qa_sram_tech.sv).
Output: one line per macro type (design names and derived numbers only) and the totals.
"""
import collections
import sys

mc, act = sys.argv[1], sys.argv[2]
corner = sys.argv[3] if len(sys.argv) > 3 else "tt_1p0v_25c"


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
    e = lambda k: (g(f"icc_c_{k}") + g(f"icc_p_{k}")) * v * 1000.0          # pJ per clock edge
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
        f = float(tr) / 2.0                                   # clock edges per ns
        pon = 1.0 - float(cen1)
        pw = min(pon, 1.0 - float(wen1))
        a["n"] += 1
        a["cyc"] += f * period                                # clock edges per analysed cycle (1 = every cycle)
        a["r"] += f * (pon - pw)                              # per ns
        a["w"] += f * pw
        a["d"] += f * (1.0 - pon)
print(f"# macro datatable model, corner {corner}, period_ns {period}: per type n, reads / writes / deselected clocks "
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
