// qb_chip R4b tech build: as qb_chip_tech.f (R4) + the R4b hooks: retimed sequencer qb_seq_rt (QB_SEQ_RT, descriptor
// macros, stored load-permission age 10 b), qb_prm fetch lists sized to the program (160 / 32 / 112 of 256; s0 / s1
// use 156 / 24 / 106), S read rotation as a log rotator (QB_TOP_SROT), head FC tree in two stages (QB_HEAD_HP).
// Paths relative to this file.  Top: qb_chip.
+define+QB_TECH+QB_SEQ_NT=640+QB_SEQ_NLT=320+QB_SEQ_DSCM=1+QB_SEQ_RT=1+QB_SEQ_LSW=10+QB_PRM_NFF=160+QB_PRM_NFW=32+QB_PRM_NFT=112+QB_TOP_SROT=1+QB_HEAD_HP=1+QB_TOP_WBR=1
../rtl/qb_lane_f.sv
../rtl/qb_dec.sv
../rtl/qb_core.sv
../rtl/qb_act_net.sv
../rtl/qb_act.sv
../rtl/qb_act2_net.sv
../rtl/qb_act2.sv
../rtl/qb_seq.sv
../rtl/qb_seq_rt.sv
../rtl/qb_top.sv
../rtl/qb_head.sv
../rtl/qb_chip.sv
qb_mem_tech.sv
