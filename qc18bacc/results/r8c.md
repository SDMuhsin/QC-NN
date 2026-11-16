# R8c: act-supply S2 routing demand cut in RTL (opt-in `QB_ACT_S2M` on `QB_ACT_S1M=1`; defaults unchanged)
**[Mod]** `impl/r8c/model.py`, **[M]** RTL sim, **[S]** DC / OpenROAD (OR est.) on tau4; data `results/r8c/{model,tb,dc,grt}.txt`.
**Result: B4 (820 x 2420, IO_LAT 0.55) GRT 87.9 -> 70.1 % (V 96.9 -> 75.2 %, M2 105.0 -> 81.9 %), overflow -54 %, WL -19 %, post-CTS
cells -5.1 %, DC -2.2 % (-2 048 flops), fmax unchanged, 0 cycles, bit/cycle-exact.** Die 720 x 2420: V 91.2 % -> [E] 85 % V at ~760 um (~1.84 mm2; R8b `=1` ~2.26).
**Mechanism [Mod].** The R2 S1 register (slot, x) is shared by all 11 cfgs, but its act row depends on the cfg: stride 1 row ~ x (mod 16 / 8 / 4,
several output rows at W <= 8), stride 2 row x / 2, 1x1 gathers x mod 16 / 8 / 4. 139 of 192 S1 groups feed rows spanning 1-15 (mean 5.4
rows ~ 640 um); stride 1 + 2 in one register adds 2.6 rows (104 groups), 1x1 + stride 2 adds 1.7 (88).
**Candidates (ranked).** (1) row-homed S1: re-index S1 by act row with a cfg-qualified select -> S2 local (model y-WL -8.6 %, S2 5.5 -> 1.7
bit-m, pre-mux -> S1 5.2 -> 6.8). (2) S1 layout reorder alone: cfgs sharing select lines (0/1/2, 4/5) must share register contents, so the
stride-1 / 2 conflict stays. (3) merge S1 o S2 (LB -> act AND-OR + delay reg): 7 259 group terms vs 2 177 (3.3x), rejected.
(4) move the S1 reg / stage S2: moving the register is (3); an extra stage costs a cycle and keeps the span.
**RTL (1)** (`hw/tb/gen_act2_s2m.py`, called by `gen_act2.py` -> `qb_act2_net.sv` modules `qba2_s1r` / `qba2_s2r`; `qb_act2.sv`: only the
S1/S2 instance block, R8a regions untouched). Each (cfg, R2 S1 value) is split into act-row clusters of <= 3 rows, each on a register homed
at row h (consumers in h +- 1), 8 per row = **128 registers (was 192)**, greedily packed for shared LB terms. S1 term condition = OR of
sel[l] & sel2[c] (sel2 = the registered cfg of the same item; plain sel[l] where all cfgs that raise l agree): 1 470 S1 / 531 S2 terms
(was 1 244 / 933; S2 fan-in <= 7). The generator checks act(u) == qba_s2 o qba2_s1m for every reachable (cfg, line) pair; the RTL
`$error`s (QBA2_S2M_ERR) on any other pair in simulation. Mutant `QBA2_MUT_S2M`: cfg 4, row 5 unit 4 reads unit 3's register.
**Verification [M]** (chip bench QBT_TECH=2 + FW128 + HPW144 + RSH=1; s0 val 60 61 0 1 2, s1 val 13 55 7 42 91): S2M 10/10 PASS, 600/600
tiles cycle-exact, err 0, no QBA2_S2M_ERR; logs equal R8b's S1M=1 logs line for line, logits files identical, torch.equal 10/10.
S2M + R8a CTXR + LDR and the default build: 3/3 PASS each. Mutant: 10/10 FAIL (100 logit, 0-40 tile-cycle mismatches/image), torch.equal 0/10.
**DC / P&R [S]** (vs R8b `=1`): DC 847 045 -> 828 477 um2 (regs 56 857 -> 54 809; S1 + S2 231 k both; pre-mux 59 -> 38 k, buf/inv +13 k).
Pre-route tt / ss 602.9 / 386.3 -> 602.4 / 384.9 MHz (worst = ctx sequencer in both, R8a); S1 class 620 -> 616 tt (sel2 AND), S2 615 -> 624.
Pre-repair DRV nets 14 019 -> 10 062 (S2 4 892 -> 1 112); post-CTS setup WNS -0.60 -> -0.21 ns. GRT V refs (M): S2 1.35 -> 0.12, S1 0.90 ->
1.14 (the pixel -> row distance moves to pre-mux -> S1), LB 0.99 -> 0.98. GRT WNS -5.57 = unrepaired line-buffer DRV (not S1 / S2).
**Next [E]:** top V classes now S1 34 % and LB 30 %; the LB -> S1 pixel fan-out is inherent to the cfg mix. Repro `impl/r8c/run.sh syn|pnr|rt|grt`.
