# R38: SRAM macros (no layout in the kit, abstracts only) excluded from DRC; use after drc_blk.sed
/^DRC MAXIMUM RESULTS/a\
EXCLUDE CELL qb_s_256x128m1 qb_b_128x128m1 qb_i_128x128m1 qb_p_240x144m2 qb_f_3232x128m8
