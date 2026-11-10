clock 3.5 ns (286 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 233.33 (128.80 / 78.05 / 26.48) |
| **+dat total mW** | **252.16** |
| **uJ / inference (+dat)** | **141.19** (PT only 130.65) |
| leakage share (+dat) | 10.5 % |
| CTS clock-tree cells (n = 7036) mW | 37.76 = 15.0 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 74.60 = 29.6 % |
| all ICGs (CKLNQD, n = 1230) mW | 3.71 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 21.33 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 107.96 | 107.96 | 4.12 |
| u_ppu | 29.32 | 29.32 | 0.89 |
| u_drain | 3.76 | 3.76 | 0.39 |
| u_head | 0.60 | 0.60 | 0.19 |
| u_xbar | 3.26 | 3.26 | 0.12 |
| u_agu | 1.09 | 1.09 | 0.03 |
| u_seq | 0.89 | 0.89 | 0.07 |
| u_host | 0.39 | 0.39 | 0.07 |
| activation macros | 12.31 | 24.80 | 8.07 |
| weight macros | 9.39 | 15.49 | 6.89 |
| param macros | 2.18 | 2.41 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 2.30 | 2.30 | 0.47 |
| u_wmem wrapper logic | 0.68 | 0.68 | 0.08 |
| u_pmem wrapper logic | 0.05 | 0.05 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 37.76 | 37.76 | 0.84 |
| top-level glue | 21.33 | 21.33 | 2.04 |
| **total** | 233.33 | 252.16 | 26.48 |

SAIF annotation: nets from activity file 268938 (90.20 %); line: Nets             268938(90.20%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        1464(0.49%)     0(0.00%)        27752(9.31%)    0(0.00%)      298154
