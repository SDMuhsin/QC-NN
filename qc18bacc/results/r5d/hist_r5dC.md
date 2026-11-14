viol_r5dC_tt_p2.0.txt: 161 violating endpoints
| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough (act -> act_o, IO) | 69 | -0.017 | `act[3365]` -> `act_o[3365]` | 2 (1) | 0.00 / 0.05 / 0.04 | 0.032 |
| s_rd / south in -> fused u_rin (IO) | 63 | -0.079 | `s_rd[54]` -> `u_core/g_fq_0__g_fc_0__g_fi_3__u_lf/u_rin/q_reg_43_/D` | 24 (5) | 0.99 / 0.22 / 0.16 | 0.168 |
| south in -> other (IO) | 10 | -0.046 | `s_rd[169]` -> `u_core/g_fq_1__g_fc_0__g_fi_1__u_lf/u_rlate/q_reg_53_/D` | 21 (5) | 1.02 / 0.26 / 0.05 | 0.159 |
| BR -> PE popcount / S1 | 10 | -0.059 | `u_core/g_col_0__g_grp_6__u_br/c_q_reg_93_/CP` -> `u_core/g_r_13__g_c_0__u_pe/g_pop2_u_pop/u_q_reg_48_/D` | 15 (4) | 1.45 / 0.34 / 0.01 | 0.082 |
| other | 8 | -0.053 | `u_core/fs_q_reg/CP` -> `u_core/g_fq_1__g_fc_0__g_fi_3__u_lf/u_rin/q_reg_43_/D` | 27 (7) | 1.14 / 0.39 / 0.25 | 0.169 |
| north in (cd / ctl / t2, IO) | 1 | -0.070 | `cd[108]` -> `u_core/g_col_0__nw_reg_8_/D` | 18 (1) | 1.09 / 0.02 / 0.04 | 0.050 |
