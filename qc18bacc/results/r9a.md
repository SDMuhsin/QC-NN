# R9a: act supply qb_act2_blk (S1M=1 + S2M + R8a act set) as a hard block, tau3 -- partial: routed, NOT DRC-clean, fmax far below target
**[S]** DC / OpenROAD / PT, [OR est.] OpenROAD STA.  Flow `impl/r9a/` (run.sh syn|pins|pnr|rt|post|abs), data `results/r9a/{dc,pnr,pt,pins}.txt`.
**Result:** die **900 x 1970 um = 1.773 mm2** (top = array top, yoff 1140), DC 0.819 -> P&R 1.085 mm2 cells (util 0.622).  Routed only to DR
iteration 0: **2 205 122 markers** (shorts M2 1.03 M); antenna 0 / 0; **DR peak 18.75 GB (RSS 19.8 GB), fits 30 GB**, 65 min / iteration at
16 threads -> DRC 0 needs ~8+ more iterations (> 8 h; R5a column: 300 k -> 9 k in 7).  PT on that route: **344.3 / 251.4 MHz tt / ss** (target 520).
**Root causes fixed:**
* DRV bloat: DC left 36 900 max-tran nets because compile_ultra -spg's re-placement + area recovery deleted the DRV-fix buffers after the DRV
  pass (R8c dc.log: cost 77 k -> 205 k).  `compile_final_drc_fix all` + DC limits = P&R limits (0.30 ns / fo 32) + P&R die context:
  **230 DRV nets left** (819 k um2, -1.1 % vs R8c).  P&R still repairs 12.5 k nets (+21.7 %, R7c +27 %): long S1 / lb / sdq nets of the real placement.
* East-edge legalisation: the 4 608 act flops (`g_pipe_1 q_reg`, they drive the pins directly) are placed legally at their pins before gpl
  (`place.tcl`, gap 0.6, depth 56 um, max dy 5.7 um), FIRM in gpl: **no DPL-0036** in place / CTS (R7c 94-398 cells), DPL window 200 um.
* IO latency 0.55: act clk->pin 0.72-0.82 ns tt; hold to column -0.064 (budget-limited, no buffer chains).
**Floorplans (pnr.txt):** F1 780 x 2420 (1.888) post-CTS -0.772 ns @2.0 / 14 856 ep vs **F2 900 x 1970 (1.773) -0.486 / 1 809** -> F2 (shorter =
less vertical lb / S1 spread).  F2 GRT at adjust 0.25: 59 % total but 283 k overflow (S1 36 %, repair buf 31 %, pre-mux 15 % of V) and the flow GRT
did not converge in 2 h; with 20 iterations it got worse (576 k) and left missing routes -> GRT antenna repair SIGSEGV.  Adjust 0.05: 313 overflow
-> the 2.2 M DR markers: the S1 / pre-mux pin density is real, the 0.25 derate was hiding it.
**Fmax limiters (new, structural, not P&R knobs):** (1) `dsc_reg[21]` = s1c (R8b merged) drives the context pre-mux select of all 16 k lb bits:
a block-wide 0.2-0.5 pF buffer tree before S1 (routed tt worst, -0.905 @2.0).  (2) lb write enables: ev2.row - vb -> slot decode -> ~20 repeaters ->
lb ICG E (post-CTS worst, -0.218 @2.0).  repair_timing at 1.85 ns oscillated on (2) for > 1.5 h (stopped; repair at 2.0: 8 min).
**Next [E]:** RTL, cycle-neutral: replicate s1c per lb region (dont-merge, ~16 copies) and register the decoded lb slot enables (wsl from ev1)
replicated per region; then P&R with -routability_driven + cell padding on S1 / pre-mux, GR adjust ~0.15, and >= 8 DR iterations (~9 h at 65 min).
**Abstracts (tau3 `/tmp/ckp908/qc18bacc/build/r9a_blk/r9a_f2j/`):** LEF (SIZE = die), ring LEF, ETM tt/ss/ff (.lib + .db), routed netlist; iteration-0
route: floorplan / pins / timing shape only.  Pins: east 4 608 act (4 608 / 4 608 match column 0), south 2 581 (S 2 048 + map 512 + read port), north 185.
Repro: `run.sh syn; run.sh pins; QB9_DW=900 QB9_DH=1970 QC_PNR_TO=cts run.sh pnr r9a_f2`; route step from cts with cts.sdc period 2.0 -> r9a_f2r;
`QB9_GR_ADJ=0.05 QB9_GR_ITER=10 QB9_ANT=0 QB_DR_ITER=0 run.sh rt r9a_f2r r9a_f2j; run.sh post r9a_f2j; run.sh abs r9a_f2j`.
