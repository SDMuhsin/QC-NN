viol_r5dB_tt_p2.0.txt: 579 violating endpoints
| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough (act -> act_o, IO) | 283 | -0.016 | `act[3365]` -> `act_o[3365]` | 2 (1) | 0.00 / 0.05 / 0.04 | 0.031 |
| s_rd / south in -> fused u_rin (IO) | 238 | -0.080 | `s_rd[309]` -> `u_core/g_fq_2__g_fc_0__g_fi_2__u_lf/u_rin/q_reg_43_/D` | 23 (4) | 1.09 / 0.23 / 0.09 | 0.101 |
| PE shadow -> fused lane u_rin | 32 | -0.043 | `u_core/g_r_2__g_c_0__u_pe/u_shd/shd_reg_60_/CP` -> `u_core/g_fq_2__g_fc_0__g_fi_3__u_lf/u_rin/q_reg_43_/D` | 27 (7) | 1.19 / 0.30 / 0.27 | 0.248 |
| wide lane stages | 11 | -0.013 | `u_core/g_wq_0__g_wc_0__u_lw/x0_reg_8_/CP` -> `u_core/g_wq_0__g_wc_0__u_lw/p1_reg_42_/D` | 24 (2) | 1.68 / 0.06 / 0.01 | 0.052 |
| south in -> other (IO) | 10 | -0.126 | `s_rd[424]` -> `u_core/g_fq_3__g_fc_0__g_fi_0__u_lf/u_rlate/q_reg_53_/D` | 21 (6) | 1.03 / 0.30 / 0.06 | 0.150 |
| north in (cd / ctl / t2, IO) | 4 | -0.083 | `cd[72]` -> `u_core/g_col_0__nw_reg_7_/D` | 21 (2) | 1.16 / 0.03 / 0.02 | 0.046 |
| BR -> PE popcount / S1 | 1 | -0.008 | `u_core/g_col_0__g_grp_7__u_br/c_q_reg_333_/CP` -> `u_core/g_r_14__g_c_0__u_pe/g_pop2_u_pop/u_q_reg_8_/D` | 18 (4) | 1.55 / 0.26 / 0.02 | 0.064 |
viol_r5dB_ss_p3.0.txt: 1592 violating endpoints
| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough (act -> act_o, IO) | 839 | -0.045 | `act[3365]` -> `act_o[3365]` | 2 (1) | 0.00 / 0.09 / 0.03 | 0.034 |
| s_rd / south in -> fused u_rin (IO) | 386 | -0.317 | `s_rd[37]` -> `u_core/g_fq_0__g_fc_0__g_fi_2__u_lf/u_rin/q_reg_36_/D` | 22 (3) | 2.10 / 0.19 / 0.07 | 0.089 |
| PE internal (S1 -> S2 acc) | 150 | -0.163 | `u_core/g_r_14__g_c_0__u_pe/g_pop2_nnw_p_reg_0_/CP` -> `u_core/g_r_14__g_c_0__u_pe/g_pop2_u_acc/acc_reg_136_/D` | 24 (4) | 2.65 / 0.32 / 0.02 | 0.097 |
| wide lane stages | 84 | -0.300 | `u_core/g_wq_0__g_wc_0__u_lw/x0_reg_8_/CP` -> `u_core/g_wq_0__g_wc_0__u_lw/p1_reg_42_/D` | 24 (2) | 2.93 / 0.10 / 0.01 | 0.057 |
| BR -> PE popcount / S1 | 58 | -0.344 | `u_core/g_col_0__g_grp_7__u_br/c_q_reg_333_/CP` -> `u_core/g_r_14__g_c_0__u_pe/g_pop2_u_pop/u_q_reg_8_/D` | 18 (4) | 2.77 / 0.45 / 0.02 | 0.075 |
| fused lane stages | 32 | -0.137 | `u_core/g_fq_0__g_fc_0__g_fi_1__u_lf/u_rlate/q_reg_3_/CP` -> `u_core/g_fq_0__g_fc_0__g_fi_1__u_lf/g_fin2_u_rmid/q_reg_35_/D` | 25 (3) | 2.51 / 0.33 / 0.02 | 0.065 |
| south in -> other (IO) | 19 | -0.334 | `s_rd[424]` -> `u_core/g_fq_3__g_fc_0__g_fi_0__u_lf/u_rlate/q_reg_53_/D` | 21 (6) | 1.72 / 0.53 / 0.06 | 0.174 |
| PE shadow -> fused lane u_rin | 16 | -0.102 | `u_core/g_r_1__g_c_0__u_pe/u_shd/shd_reg_61_/CP` -> `u_core/g_fq_1__g_fc_0__g_fi_3__u_lf/u_rin/q_reg_33_/D` | 27 (7) | 1.92 / 0.58 / 0.29 | 0.290 |
| north in (cd / ctl / t2, IO) | 8 | -0.302 | `cd[73]` -> `u_core/g_col_0__nw_reg_7_/D` | 20 (0) | 2.09 / 0.00 / 0.01 | 0.054 |
