#!/usr/bin/env python3
"""Centroid / spread per group of the v4 crossbar-path registers (bank select, stage A, window, output registers,
write data) and of the PE rows, from locs.tcl output:  python3 locs.py <locs file>"""
import sys, re, collections
g = collections.defaultdict(list)
for l in open(sys.argv[1]):
    n, x, y = l.split(); x = float(x); y = float(y)
    m = re.match(r"u_act/g_bank_(\d+)__g_buf_(\d+)__u_ram/", n)
    if m: g[f"outreg b{int(m[1]):02d} buf{m[2]}"].append((x, y)); continue
    m = re.match(r"u_act/ar_rdata_reg_(\d+)_", n)
    if m: g[f"banksel b{int(m[1])//128:02d}"].append((x, y)); continue
    m = re.match(r"u_act/g_bank_(\d+)__wd_q_reg", n)
    if m: g[f"wdata b{int(m[1]):02d}"].append((x, y)); continue
    m = re.match(r"u_xbar/sa_reg_(\d+)_", n)
    if m: g[f"stageA s{int(m[1])//128:02d}"].append((x, y)); continue
    m = re.match(r"u_xbar/win_reg_(\d+)_", n)
    if m: g[f"window r{int(m[1])//128:02d}"].append((x, y)); continue
    m = re.match(r"u_array/g_col_(\d+)__g_row_(\d+)__u_pe/", n)
    if m: g[f"PE row{int(m[2]):02d}"].append((x, y)); continue
for k in sorted(g):
    v = g[k]; cx = sum(a for a, b in v) / len(v); cy = sum(b for a, b in v) / len(v)
    xs = sorted(a for a, b in v); ys = sorted(b for a, b in v)
    print(f"{k:22s} n {len(v):6d} centroid {cx:7.0f} {cy:7.0f}  x10-90 {xs[len(v)//10]:6.0f}-{xs[9*len(v)//10]:6.0f}  y10-90 {ys[len(v)//10]:6.0f}-{ys[9*len(v)//10]:6.0f}")
