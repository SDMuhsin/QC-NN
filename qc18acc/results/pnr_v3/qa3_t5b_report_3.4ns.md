clock 3.4 ns (294 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 344.72 (187.43 / 127.97 / 29.32) |
| **+dat total mW** | **388.60** |
| **uJ / inference (+dat)** | **107.60** (PT only 95.45) |
| leakage share (+dat) | 7.5 % |
| CTS clock-tree cells (n = 13754) mW | 53.10 = 13.7 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 91.50 = 23.5 % |
| all ICGs (CKLNQD, n = 1363) mW | 4.46 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 36.82 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 162.85 | 162.85 | 6.01 |
| u_ppu | 45.33 | 45.33 | 1.38 |
| u_drain | 4.98 | 4.98 | 0.31 |
| u_head | 0.68 | 0.68 | 0.21 |
| u_xbar | 7.68 | 7.68 | 0.30 |
| u_agu | 1.09 | 1.09 | 0.03 |
| u_seq | 0.92 | 0.92 | 0.07 |
| u_host | 0.38 | 0.38 | 0.07 |
| activation macros | 12.87 | 42.15 | 6.07 |
| weight macros | 10.39 | 24.51 | 6.89 |
| param macros | 2.21 | 2.69 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 4.31 | 4.31 | 0.97 |
| u_wmem wrapper logic | 0.97 | 0.97 | 0.06 |
| u_pmem wrapper logic | 0.07 | 0.07 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 53.10 | 53.10 | 1.20 |
| top-level glue | 36.82 | 36.82 | 3.53 |
| **total** | 344.72 | 388.60 | 29.32 |

SAIF annotation: nets from activity file 369946 (87.31 %); line: Nets             369946(87.31%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        2822(0.67%)     0(0.00%)        50964(12.03%)   0(0.00%)      423732
