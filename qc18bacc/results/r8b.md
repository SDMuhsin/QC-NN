# R8b: act-supply S1 routing demand cut in RTL (opt-in `QB_ACT_S1M`, default off = R7c RTL)
**[Mod]** `impl/r8b/model.py`, **[M]** RTL sim, **[S]** DC / OpenROAD (OR est.) on tau4; data `results/r8b/{model,tb,dc,grt}.txt`.
**Result: `QB_ACT_S1M=1` (context pre-mux + flat S1) at B4: GRT 105.1 -> 87.9 % (V 135 -> 97 %, M2 155 -> 105 %), overflow
-54 %, DC -7.0 %, fmax unchanged, 0 cycles, bit/cycle-exact.** The QB_IO_LAT 0.55 fix alone: R7c 115.1 -> 105.1 %.
**Model [Mod].** Base S1 = AND-OR over lb0 and lb1: 2 488 group terms (79 616 bit inputs); each LB bit feeds 1-8 S1 gates.
Two causes dominate: (i) every term exists once per context; (ii) the chunk select S1 (s, x) <- group g W + x at W <= 16.
W8 / W16 / W4 = 62 % of candidates (span 28 / 24 / 30 of 64 groups), int8 14 %; 1-D model y WL -5.6 % (a), -11.8 % (a + b).
**RTL** (`gen_act2.py` -> `qb_act2_net.sv`; `qb_act2.sv` S1 instance only, R8a regions untouched):
* `qba2_pm`: m = s1c ? lb1 : lb0 per bit, s1c = registered `is_v[1]` (DC merges it with the dsc ctx flop; regs 56 857 in all).
* `=1` `qba2_s1m`: one flat AND-OR over m, sel = sel1a | sel1b. `=2` `qba2_s1s`: 3x3 chunk select as a shifter by g W
  (stages 32 / 16 / 8 / 4, output-trimmed); 1x1 / int8 terms flat. The generator asserts both equal qba2_s1 for all 39 lines.
  Mutant `QBA2_MUT_S1M`: stage 16 takes the stage-32 select.
**Verification [M]** (chip bench QBT_TECH=2 + FW128 + HPW144 + RSH=1; s0 val 60 61 0 1 2, s1 val 13 55 7 42 91):
* S1M=1 and =2: 10/10 PASS, 600/600 tiles cycle-exact, err 0; logs equal R7e's RSH=1 logs line for line; logits files identical.
  torch.equal 10/10. Default and S1M=1 + R8a CTXR + LDR builds PASS. Mutant: 10/10 FAIL (100 logit and 40 tile-cycle mismatches per image), torch.equal 0/10.
**DC / P&R [S]** (R7c recipe, B4 820 x 2420, IO_LAT 0.55, GRT probe on post-CTS-repair db; base = R7c netlist from its B4 place):
| | DC um2 | S1 + pre-mux | pre-route tt / ss MHz | post-CTS um2 (util) | GRT total / V / M2 | overflow | WL m |
|---|---|---|---|---|---|---|---|
| base | 910 476 | 237 231 | 601.9 / 384.9 | 1 257 152 (0.644) | 105.1 / 135.2 / 155.0 % | 5.32 M | 51.1 |
| S1M=1 | 847 045 | 205 406 | 602.9 / 386.3 | 1 104 352 (0.566) | **87.9 / 96.9 / 105.0 %** | 2.43 M | 44.7 |
| S1M=2 | 829 787 | 185 497 | 603.1 / 385.5 | 1 076 167 (0.552) | 91.2 / 100.6 / 111.5 % | 2.99 M | 46.1 |
* fmax: still the ctx `ival -> nav` path (R8a); the S1 class is unchanged (ss 406.0 / 408.6 / 407.7). =2 is smaller but routes
  worse: S1 V refs 0.90 -> 0.74 M, LB + pre-mux 1.37 -> 1.90 M (its 32 / 16 butterflies pair groups 16-32 apart), so use =1.
* Top V class is now S2 (25 %, pixel-to-row); GRT WNS = unrepaired DRV on S1 -> S2 nets. **Next [E]:** =1 needs ~2.26 mm2 at
  85 % V (base 3.15); restructure S2, re-probe a narrower die. Repro `impl/r8b/run.sh syn|pnr|rt|grt`; bench as r7g.md §5 + `QB_ACT_S1M`.
