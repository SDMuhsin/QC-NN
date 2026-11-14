// R4 variant: program descriptors as flop arrays (QB_SEQ_DSCM 0), the macro-vs-flops comparison run r4_chip.
// qb_chip with the TSMC 65 nm macros (R4): define QB_TECH (qb_top.sv hook) + hw/tech/qb_mem_tech.sv; descriptors in 2
// sram_sp 624 x 80 macros (QB_SEQ_DSCM, qb_seq.sv); flop tables of
// qb_seq sized to the network program (616 tiles, 286 load-permission entries; R3b default 1024 / 1024).
// Paths relative to this file.  Top: qb_chip.
+define+QB_TECH+QB_SEQ_NT=640+QB_SEQ_NLT=320
../../hw/rtl/qb_lane_f.sv
../../hw/rtl/qb_dec.sv
../../hw/rtl/qb_core.sv
../../hw/rtl/qb_act_net.sv
../../hw/rtl/qb_act.sv
../../hw/rtl/qb_act2_net.sv
../../hw/rtl/qb_act2.sv
../../hw/rtl/qb_seq.sv
../../hw/rtl/qb_top.sv
../../hw/rtl/qb_head.sv
../../hw/rtl/qb_chip.sv
../../hw/tech/qb_mem_tech.sv
