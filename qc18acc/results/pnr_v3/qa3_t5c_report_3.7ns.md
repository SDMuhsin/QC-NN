clock 3.7 ns (270 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 320.66 (172.35 / 118.99 / 29.32) |
| **+dat total mW** | **360.98** |
| **uJ / inference (+dat)** | **108.77** (PT only 96.62) |
| leakage share (+dat) | 8.1 % |
| CTS clock-tree cells (n = 13746) mW | 48.93 = 13.6 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 84.10 = 23.3 % |
| all ICGs (CKLNQD, n = 1363) mW | 4.10 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 34.36 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 150.63 | 150.63 | 6.01 |
| u_ppu | 41.77 | 41.77 | 1.38 |
| u_drain | 4.61 | 4.61 | 0.31 |
| u_head | 0.65 | 0.65 | 0.21 |
| u_xbar | 7.71 | 7.71 | 0.30 |
| u_agu | 1.01 | 1.01 | 0.03 |
| u_seq | 0.85 | 0.85 | 0.07 |
| u_host | 0.35 | 0.35 | 0.07 |
| activation macros | 12.33 | 39.23 | 6.07 |
| weight macros | 10.11 | 23.09 | 6.89 |
| param macros | 2.21 | 2.65 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 4.12 | 4.12 | 0.97 |
| u_wmem wrapper logic | 0.90 | 0.90 | 0.06 |
| u_pmem wrapper logic | 0.06 | 0.06 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 48.93 | 48.93 | 1.20 |
| top-level glue | 34.36 | 34.36 | 3.53 |
| **total** | 320.66 | 360.98 | 29.32 |

SAIF annotation: nets from activity file 369946 (87.30 %); line: Nets             369946(87.30%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        2822(0.67%)     0(0.00%)        51017(12.04%)   0(0.00%)      423785
