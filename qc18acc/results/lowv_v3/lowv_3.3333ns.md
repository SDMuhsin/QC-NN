clock 3.3333 ns (300 MHz), SDF SAIF image 0 (81438 cycles, 271.5 us / inference)
k_leak (logic leakage 0.8 V / 1.0 V) = 0.440

| quantity | 1.0 V (tcbn65gplustc_ccs) | 0.8 V (tcbn65gplustc0d8_ccs) | ratio |
|---|---|---|---|
| logic internal mW | 121.98 | 75.24 | 0.617 |
| logic switching mW | 59.86 | 37.15 | 0.621 |
| logic leakage mW | 6.04 | 2.66 | 0.440 |
| logic total mW (PT) | 187.88 | 115.04 | 0.612 |
| macro dynamic mW (datatable + output nets) | 54.43 | 34.83 | 0.640 |
| macro leakage mW | 15.15 | 6.66 | 0.440 |
| **total mW (+dat)** | 257.46 | 156.53 | 0.608 |
| leakage mW (logic + macro) | 21.19 | 9.32 | 0.440 |
| **uJ / inference** | 69.89 | 42.49 | 0.608 |
| leakage share % | 8.2 | 6.0 | |
| pJ / dense-equivalent MAC | 0.1258 | 0.0765 | |

bound with macro leakage x 0.8 (no DIBL reduction): 161.99 mW, 43.97 uJ / inference, leakage share 9.1 %

per block at the low voltage (PT logic; macros modelled as above) mW:
  u_array 82.58 (ref 134.57);  u_ppu 24.29 (ref 39.75);  u_drain 1.05 (ref 1.77);  u_head 0.35 (ref 0.63);  u_xbar 3.28 (ref 5.38);  u_agu 0.66 (ref 1.08);  u_seq 0.62 (ref 1.04);  u_host 0.22 (ref 0.37);
