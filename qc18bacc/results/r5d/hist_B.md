viol_B_tt_p2.0.txt: 418 violating endpoints
| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough (act -> act_o, IO) | 344 | -0.029 | `act[1891]` -> `act_o[1891]` | 2 (1) | 0.00 / 0.05 / 0.04 | 0.039 |
| s_rd / south in -> fused u_rin (IO) | 40 | -0.101 | `s_rd[102]` -> `u_core/g_fq_0__g_fc_0__g_fi_6__u_lf/u_rin/q_reg_43_/D` | 24 (4) | 1.18 / 0.14 / 0.07 | 0.112 |
| dec -> BR nnw_q (cdr -> u_br) | 28 | -0.164 | `u_core/cdr_reg_79_/CP` -> `u_core/g_col_0__g_grp_1__u_br/nnw_q_reg_8_/D` | 24 (5) | 1.48 / 0.27 / 0.15 | 0.173 |
| wide lane stages | 5 | -0.126 | `u_core/g_wq_0__g_wc_0__u_lw/sh1_reg_1_/CP` -> `u_core/g_wq_0__g_wc_0__u_lw/y2_reg_0_/D` | 31 (6) | 1.35 / 0.39 / 0.11 | 0.197 |
| PE shadow -> fused lane u_rin | 1 | -0.011 | `u_core/g_r_1__g_c_0__u_pe/u_shd/shd_reg_45_/CP` -> `u_core/g_fq_1__g_fc_0__g_fi_2__u_lf/u_rin/q_reg_33_/D` | 25 (5) | 1.29 / 0.16 / 0.25 | 0.255 |
viol_B_ss_p3.0.txt: 1465 violating endpoints
| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough (act -> act_o, IO) | 1245 | -0.064 | `act[1891]` -> `act_o[1891]` | 2 (1) | 0.00 / 0.10 / 0.04 | 0.043 |
| s_rd / south in -> fused u_rin (IO) | 77 | -0.377 | `s_rd[102]` -> `u_core/g_fq_0__g_fc_0__g_fi_6__u_lf/u_rin/q_reg_43_/D` | 24 (4) | 2.05 / 0.27 / 0.07 | 0.133 |
| dec -> BR nnw_q (cdr -> u_br) | 52 | -0.454 | `u_core/cdr_reg_79_/CP` -> `u_core/g_col_0__g_grp_1__u_br/nnw_q_reg_8_/D` | 24 (5) | 2.54 / 0.47 / 0.16 | 0.205 |
| wide lane stages | 49 | -0.454 | `u_core/g_wq_0__g_wc_0__u_lw/sh1_reg_1_/CP` -> `u_core/g_wq_0__g_wc_0__u_lw/y2_reg_18_/D` | 29 (4) | 2.50 / 0.59 / 0.01 | 0.056 |
| BR -> PE popcount / S1 | 17 | -0.361 | `u_core/g_col_0__g_grp_7__u_br/c_q_reg_228_/CP` -> `u_core/g_r_14__g_c_0__u_pe/g_pop2_u_pop/u_q_reg_153_/D` | 15 (4) | 2.44 / 0.65 / 0.02 | 0.094 |
| PE internal (S1 -> S2 acc) | 14 | -0.080 | `u_core/g_r_2__g_c_0__u_pe/ctl_p_reg_3_/CP` -> `u_core/g_r_2__g_c_0__u_pe/g_pop2_u_acc/acc_reg_158_/D` | 24 (6) | 2.30 / 0.54 / 0.01 | 0.058 |
| fused lane stages | 9 | -0.111 | `u_core/g_fq_3__g_fc_0__g_fi_3__u_lf/u_rlate/q_reg_2_/CP` -> `u_core/g_fq_3__g_fc_0__g_fi_3__u_lf/g_fin2_u_rmid/q_reg_36_/D` | 29 (6) | 2.25 / 0.53 / 0.02 | 0.077 |
| south in -> other (IO) | 2 | -0.145 | `s_rd[407]` -> `u_core/g_fq_2__g_fc_0__g_fi_7__u_lf/u_rlate/q_reg_53_/D` | 20 (4) | 1.62 / 0.44 / 0.03 | 0.098 |
