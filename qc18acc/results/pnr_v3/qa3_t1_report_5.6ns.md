clock 5.6 ns (179 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 234.25 (121.90 / 82.82 / 29.53) |
| **+dat total mW** | **260.90** |
| **uJ / inference (+dat)** | **118.99** (PT only 106.83) |
| leakage share (+dat) | 11.3 % |
| CTS clock-tree cells (n = 13418) mW | 40.54 = 15.5 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 64.00 = 24.5 % |
| all ICGs (CKLNQD, n = 1363) mW | 2.73 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 25.39 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 103.88 | 103.88 | 6.14 |
| u_ppu | 28.91 | 28.91 | 1.42 |
| u_drain | 3.33 | 3.33 | 0.32 |
| u_head | 0.54 | 0.54 | 0.22 |
| u_xbar | 4.63 | 4.63 | 0.29 |
| u_agu | 0.76 | 0.76 | 0.03 |
| u_seq | 0.63 | 0.63 | 0.08 |
| u_host | 0.27 | 0.27 | 0.08 |
| activation macros | 10.24 | 28.00 | 6.07 |
| weight macros | 8.96 | 17.56 | 6.89 |
| param macros | 2.18 | 2.47 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 3.26 | 3.26 | 0.97 |
| u_wmem wrapper logic | 0.62 | 0.62 | 0.07 |
| u_pmem wrapper logic | 0.05 | 0.05 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 40.54 | 40.54 | 1.32 |
| top-level glue | 25.39 | 25.39 | 3.43 |
| **total** | 234.25 | 260.90 | 29.53 |

SAIF annotation: nets from activity file 371303 (87.10 %); line: Nets             371303(87.10%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        1465(0.34%)     1(0.00%)        53549(12.56%)   0(0.00%)      426318
