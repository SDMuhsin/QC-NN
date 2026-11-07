| core (standalone, DC 4.2 ns ss, WLM) | total um2 (kGE) | array | 64 tiles (per tile) | row x / butterflies + decoder | control + input cut | regs | fmax ss / tt (all paths) | fmax ss / tt (reg2reg) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| dense | 622928 (432.6), x1.00 | 593568 | 590908 (9233) | 0 | 29360 | 4598 | 238 / 335 MHz | 238 / 369 MHz |
| ternary | 168367 (116.9), x0.27 | 145710 | 137736 (2152) | 0 | 22657 | 3806 | 238 / 332 MHz | 238 / 367 MHz |
| qc | 164368 (114.1), x0.26 | 142668 | 125580 (1962) | 16615 | 21700 | 3678 | 238 / 333 MHz | 238 / 369 MHz |

| core, DC at 2.0 ns ss (fmax runs) | total um2 (kGE) | DC ss WNS | fmax ss (DC) | fmax ss / tt (PT, all paths) | DC worst path |
|---|---:|---:|---:|---:|---|
| dense | 748602 (519.9) | -0.943 | 340 MHz | 340 / 519 MHz | AblGemm_dense_dataCut2/out_r_1_d_reg_6_/CP -> gemm_array/g/mesh/mesh_7_3/accumulation_reg_reg_23_/D |
| ternary | 280152 (194.6) | -0.207 | 453 MHz | 454 / 633 MHz | N_reg_8_/CP -> cstate_reg/D |
| qc | 260235 (180.7) | -0.155 | 464 MHz | 465 / 640 MHz | N_reg_18_/CP -> cstate_reg/D |

| conv1, PT PX tt 2.8 ns, SAIF sdf, WLM | GLS vs model | busy cyc | total mW | leak mW | array mW | tiles mW | clock net mW | regs mW | comb mW | conv1 energy nJ | pJ / dense MAC | vs dense base |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dense, dense ResNet-8 conv1 | PASS (bad 0) | 4866 | 209.00 | 3.599 | 192.94 | 190.06 | 21.30 | 12.70 | 174.90 | 2848 | 1.207 | x1.00 |
| dense, s2 conv1 (int8 ternary) | PASS (bad 0) | 4866 | 205.30 | 3.610 | 189.70 | 186.98 | 21.30 | 11.90 | 172.10 | 2797 | 1.186 | x0.98 |
| ternary, s2 conv1 | PASS (bad 0) | 4866 | 73.60 | 0.910 | 66.28 | 65.05 | 17.90 | 6.01 | 49.80 | 1003 | 0.425 | x0.35 |
| QC, s2 conv1 | PASS (bad 0) | 4866 | 81.10 | 0.874 | 74.56 | 70.54 | 17.30 | 6.05 | 57.70 | 1105 | 0.468 | x0.39 |

| conv1, PT PX tt 2.8 ns, SAIF zd, WLM | GLS vs model | busy cyc | total mW | leak mW | array mW | tiles mW | clock net mW | regs mW | comb mW | conv1 energy nJ | pJ / dense MAC | vs dense base |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dense, dense ResNet-8 conv1 | PASS (bad 0) | 4866 | 150.30 | 3.601 | 134.29 | 131.40 | 21.30 | 10.40 | 118.60 | 2048 | 0.868 | x1.00 |
| dense, s2 conv1 (int8 ternary) | PASS (bad 0) | 4866 | 151.60 | 3.612 | 136.04 | 133.31 | 21.30 | 9.31 | 121.00 | 2066 | 0.875 | x1.01 |
| ternary, s2 conv1 | PASS (bad 0) | 4866 | 55.60 | 0.911 | 48.24 | 47.00 | 17.80 | 3.91 | 33.80 | 758 | 0.321 | x0.37 |
| QC, s2 conv1 | PASS (bad 0) | 4866 | 56.80 | 0.874 | 50.28 | 46.27 | 17.30 | 3.61 | 35.90 | 774 | 0.328 | x0.38 |

| conv1, PT PX tt 2.8 ns, SAIF sdf, zero wire load | GLS vs model | busy cyc | total mW | leak mW | array mW | tiles mW | clock net mW | regs mW | comb mW | conv1 energy nJ | pJ / dense MAC | vs dense base |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dense, dense ResNet-8 conv1 | PASS (bad 0) | 4866 | 171.70 | 3.599 | 160.32 | 159.54 | 19.70 | 7.68 | 144.30 | 2339 | 0.992 | x1.00 |
| dense, s2 conv1 (int8 ternary) | PASS (bad 0) | 4866 | 169.30 | 3.610 | 158.07 | 157.32 | 19.70 | 7.36 | 142.20 | 2307 | 0.978 | x0.99 |
| ternary, s2 conv1 | PASS (bad 0) | 4866 | 63.20 | 0.910 | 56.71 | 56.01 | 16.60 | 5.29 | 41.30 | 861 | 0.365 | x0.37 |
| QC, s2 conv1 | PASS (bad 0) | 4866 | 68.10 | 0.874 | 62.21 | 59.55 | 16.10 | 5.44 | 46.50 | 928 | 0.393 | x0.40 |

| conv1, PT PX tt 2.8 ns, SAIF zd, zero wire load | GLS vs model | busy cyc | total mW | leak mW | array mW | tiles mW | clock net mW | regs mW | comb mW | conv1 energy nJ | pJ / dense MAC | vs dense base |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dense, dense ResNet-8 conv1 | PASS (bad 0) | 4866 | 121.40 | 3.601 | 109.99 | 109.20 | 19.70 | 5.36 | 96.30 | 1654 | 0.701 | x1.00 |
| dense, s2 conv1 (int8 ternary) | PASS (bad 0) | 4866 | 122.90 | 3.612 | 111.73 | 110.98 | 19.70 | 4.75 | 98.40 | 1674 | 0.710 | x1.01 |
| ternary, s2 conv1 | PASS (bad 0) | 4866 | 47.90 | 0.911 | 41.39 | 40.69 | 16.60 | 3.21 | 28.10 | 653 | 0.277 | x0.39 |
| QC, s2 conv1 | PASS (bad 0) | 4866 | 47.80 | 0.874 | 41.90 | 39.28 | 16.10 | 3.04 | 28.60 | 651 | 0.276 | x0.39 |

