clock 3.9 ns (256 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 212.12 (115.59 / 70.04 / 26.48) |
| **+dat total mW** | **229.02** |
| **uJ / inference (+dat)** | **142.89** (PT only 132.35) |
| leakage share (+dat) | 11.6 % |
| CTS clock-tree cells (n = 7036) mW | 33.98 = 14.8 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 67.10 = 29.3 % |
| all ICGs (CKLNQD, n = 1230) mW | 3.33 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 19.35 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 97.31 | 97.31 | 4.12 |
| u_ppu | 26.41 | 26.41 | 0.89 |
| u_drain | 3.42 | 3.42 | 0.39 |
| u_head | 0.56 | 0.56 | 0.19 |
| u_xbar | 2.94 | 2.94 | 0.12 |
| u_agu | 0.98 | 0.98 | 0.03 |
| u_seq | 0.81 | 0.81 | 0.07 |
| u_host | 0.36 | 0.36 | 0.07 |
| activation macros | 11.88 | 23.08 | 8.07 |
| weight macros | 9.13 | 14.61 | 6.89 |
| param macros | 2.17 | 2.38 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 2.11 | 2.11 | 0.47 |
| u_wmem wrapper logic | 0.62 | 0.62 | 0.08 |
| u_pmem wrapper logic | 0.05 | 0.05 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 33.98 | 33.98 | 0.84 |
| top-level glue | 19.35 | 19.35 | 2.04 |
| **total** | 212.12 | 229.02 | 26.48 |

SAIF annotation: nets from activity file 268938 (90.20 %); line: Nets             268938(90.20%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        1464(0.49%)     0(0.00%)        27752(9.31%)    0(0.00%)      298154
