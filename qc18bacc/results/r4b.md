# R4b: sequencer retime, non-core area cuts, chip DC with the macro-clock constraints

Labels: **[S]** synthesis / STA, **[M]** simulation, **[Mod]** cycle model, **[E]** estimate.  Tools as R4 (DC
W-2024.09-SP2 topographical tt 1.65 ns, PT Q-2019.12, Verilator 5.050).  Summaries in `results/r4b/`; netlists and
full reports stay on tau (`/tmp/ckp908/qc18bacc/build/syn/r4b_*` on usask / tau5).

**Cycle cost of everything below: 0** [M]: every change is cycle-exact; the image interval stays the static-order model
+ 1 (s0 val 0/1/2: 3 748 / 3 788 / 3 812; s1 val 7/42/88: 3 732 / 3 796 / 3 700, = R4), head latency +1 638 (= R4).
No `compile/` hook was needed; `test_compile --n 100` ALL PASS, unchanged.

**Result (chip run d = the repo RTL; DC topographical tt 1.65 ns with `impl/r4/constraints.sdc` in DC, PT on the DC
parasitics) [S]:**
* fmax **601.0 MHz tt / 375.8 MHz ss** pre-route.  R4: 169.7 / 104.6.  Every path class is at the 1.65 ns target at tt
  (section 3).
* Logic **7.879 mm2**, R4 8.050 (-0.171).
  * Non-core 2.188, R4 2.416 (-0.228).
  * The core grew +0.057: DC now closes it at 600 MHz instead of 400-480.
* Macros 7.248, unchanged.  Chip **15.127 mm2** pre-route, R4 15.298.
* Flops 337 779, R4 350 681.
* Run b (sequencer v2, otherwise identical) gives 600.8 / 378.2 MHz and 7.858 mm2: the same within DC noise.

## 1. Sequencer retime: `hw/rtl/qb_seq_rt.sv` (new module, qb_top define `QB_SEQ_RT`, default 0)

Same ports, program and cycle behaviour as R3b `qb_seq` (DSCM = 1).  R4's chains were combinational lookups over the
640-entry stamp table and 320-entry load-permission table plus same-cycle arithmetic.  Each is now computed one cycle
ahead from registered state:

| R4 chain (pre-route tt) | R4b structure |
|---|---|
| load permission: `lptr` -> lt read -> epos multiply -> compare -> 2nd lt read -> stamp lookup + add + compare -> `l_ok` (170 MHz) | per context a 3-entry window of lt in registers (`lt[lptr..lptr+2]`, refill `lt[lptr+3]`), readiness and positions of the next window precomputed (int8 position products from registered popcounts), next pass's first 3 entries prefetched (one lt read / cycle); `l_ok` = compare vs. the loader position + 3 gates |
| token: descriptor macro Q -> end phase -> `s_fire` -> `tgo` (239 MHz) | descriptor ports = 4-entry prefetch **shift** FIFOs (end port: sequential chain; head and 2nd entry are registers); token RAW readiness (`sv && now >= stamp + lat`, and `+ OVH`) registered one cycle ahead; `now + C` precomputed; both outcomes (predecessor commits / does not commit this cycle) evaluated in parallel, the commit's cap / de as parallel compares, selected by `p_arr` |
| end phase: macro Q -> rw lookup -> max chain -> de (277 MHz) | registered head, rw stamp looked up one cycle ahead (head or 2nd entry), this cycle's commit bypassed; ds / de = max of 4 by pairwise compares; stamp writes registered (pending write visible to lookups) |
| pass start: `now == 0` -> `p_fire` -> lookup address | `p_fire` registered (from the previous cycle's go / done / pp; asserted equal to the R3b formula every cycle) |

**Exactness.**
* The registered readiness ignores a dependency committed in the previous cycle.  It cannot be ready yet:
  * drained / PPU producers have de >= commit + 4;
  * pecmp producers have de = ce, and every RAW latency of the program is >= 11 (ras and lt: 11..21).
  * So this needs commit - ce <= 9 for pecmp tiles.  Measured [Mod]: max lag 0 on val[:100] of both seeds
    (`static_seq` emulation).  The RTL asserts it.
* The int8 counts (C, executed S words) come from flag popcounts through a register (2 cycles old at use).  Exact while
  the block-6 flags are final 2 cycles before use.
* Both points are checked behaviourally: in simulation qb_top runs the R3b `qb_seq` **in lockstep** on the same inputs
  (`QBT_NOLOCK` disables it).  Any difference in p_fire / p_pi / tgo / l_ok / l_seq / capture / PPU-job outputs sets
  err.  **0 differences** on all bench images.

**Standalone DC** [S] (`impl/r4b/seq_rt.f`, `impl/r4b/seq.sdc`: inputs 0.3 ns from registers, outputs 0.6 ns into
qb_act2 / qb_top; NT 640, NLT 320; macros 2 x 0.118 mm2 included in the totals):

| version | total mm2 | worst reg -> reg | worst path |
|---|---|---|---|
| R4 qb_seq (DSCM 1, r4.md) | 0.737 | 5.6 ns in chip (170 MHz) | lptr -> ... -> qb_act2 lcnt |
| v1 (window, FIFOs, registered readiness) | 0.788 | 1.82 ns | now -> nowp -> lookup compare -> RdA |
| v2 (+ shift FIFOs, x <= now+1-d, max4, S0/S1 token) | 0.782 | 1.58 ns | now -> p_fire -> lookup address -> RdA |
| v3 (+ local now+1, raw stamps + latency at the compare) | 0.782 | 1.66 ns | same (p_fire) |
| v4 (+ registered p_fire) = repo RTL, chip run d | 0.781 | 1.60 ns (chip: 602 MHz) | lookup -> compare -> RdA / RdB |

The standalone IO model is pessimistic: comb in -> out paths take 0.9 of 1.4 ns.  In the chip the sequencer closes at
602 / 604 MHz tt (runs d / b, section 3).  Area: the window, prefetch and one-cycle-ahead lookups cost +0.045 mm2 over R4's
qb_seq standalone.  They need 10 stamp read ports instead of 6.  In the chip the sequencer is +0.095 (section 3).

## 2. Area audit of the non-core logic and cuts

**Audit [S]** (R4 netlist; register groups in `results/r4b/reg_audit.txt`): flops / comb mm2.
* qb_top glue: 0.166 / 0.496.  Flops: act distribution 4 608 b 0.035, S read output register 4 096 b 0.029, S write
  data 4 096 b 0.028, pass table 0.018, code output register 0.017, b2 FIFO 0.014.
* qb_seq: 0.191 / 0.241.  Flops: lt 13 440 b 0.092, stamps 10 240 b 0.070.
* qb_prm: 0.256 / 0.089.  Flops: fetch lists 19 168 b 0.131, fused staging 2 x 5 184 b 0.071, wide 0.035, T2 0.009.
* qb_act2: 0.378 / 0.418.  Flops: line buffers 32 768 b 0.234, S1 0.042, S2 / act pipe 2 x 0.032, sdq 0.017.
* qb_head: pq 0.025.

The glue comb was the largest unknown.  The write-back request logic alone, synthesized standalone, has about 0.30 mm2
of comb (`qb_wb_x`, 0.378 mm2 incl. its I/O registers).

**Cuts** (all behaviour-preserving, 0 cycles; defines default off, set by `hw/tech/qb_chip_tech_r4b.f`):

| cut | how | mm2 [S] | cycles |
|---|---|---|---|
| S write requests (`QB_TOP_WBR`) | HQ / HQD / Z words are a fixed 16-lane permutation rotated by the tile position -> log rotators; stream / b6.c2 pixels -> per-lane-group AND-OR selects; HQD / Z / c2 data replicated under the bit mask instead of position muxes; flags ORed before the rotation | -0.195 standalone (0.378 -> 0.183; the old block also held the map writes) | 0 |
| S read rotation for qb_act2 (`QB_TOP_SROT`) | indexed 32:1 mux per bit -> group mux + 4-stage log rotator | -0.089 standalone (0.167 -> 0.078), slack +0.23 -> +0.32 ns; with WBR: **glue -0.221 chip** (0.661 -> 0.440) | 0 |
| qb_prm fetch lists (`QB_PRM_NFF/NFW/NFT`) | 3 x 256 entries -> 160 / 32 / 112 (programs: 156 / 24 / 106; host write beyond = error) | **-0.112 chip** (0.344 -> 0.232, -11 572 flops) | 0 |
| lt age field (`QB_SEQ_LSW` 10) | stored l_seq 16 -> 10 b (programs < 1 024; host write check) | (in seq) | 0 |
| head FC tree (`QB_HEAD_HP`, timing) | pq chunk selected one stage early (pq stable while the FC runs), tree in 2 x 16 products, 3-input accumulate | ~+0.002 | 0 (latency unchanged) |

Checked and **not cut**:
* **fused params double buffer.** Single-buffered is late on every image (R3b mutant PRM1).  The wide and T2 buffers
  are already single.
* **act pipe / distribution registers** (2 x 4 608 b).  They are pipeline stages of D = 2 + AP + DIST.  Removing one
  changes the cycle model and the timing.
* **stamp table.** Only 397 of 616 tiles are ever referenced.  A compiler-assigned stamp slot would shrink it, but needs
  a program-format change (open).
* **duplicated flops.** The flag sets (200 b in qb_top and qb_act2) are too small to matter.  DC merges the popcount
  registers.

## 3. Chip DC re-run (constraints in DC) and pre-route STA

Two whole-chip runs:
* **d** (tau5): the repo RTL, `qb_seq_rt` v4.  2 h 07 min, 15.2 GB.  Primary.
* **b** (usask): `qb_seq_rt` v2, otherwise identical.  2 h 14 min.

File list `hw/tech/qb_chip_tech_r4b.f`; constraints `impl/r4/constraints.sdc`, now applied in DC as well.  The DC
compiles close at **WNS +0.000 ns (d) / -0.0007 ns (b)**, against -369.5 ns in R4.  Summaries: `results/r4b/{area,dc,
pt_tt,pt_ss}_{d,b}.txt`.

**Area by block** [S] (logic mm2, macros excluded):

| block | R4 | R4b d | delta | (b) | regs R4 -> R4b |
|---|---|---|---|---|---|
| core (PE / fused / wide / banks / dec+BR / other) | 5.634 | 5.691 (3.241 / 1.618 / 0.304 / 0.105 / 0.305 / 0.118) | +0.057 | 5.683 | 205 799 -> 205 799 |
| act supply (qb_act2) | 0.796 | 0.790 | -0.006 | 0.786 | 52 152 -> 52 152 |
| sequencer | 0.432 | 0.527 | **+0.095** | 0.525 | 26 347 -> 25 314 |
| params path (qb_prm) | 0.344 | 0.232 | **-0.112** | 0.233 | 35 916 -> 24 344 |
| head | 0.175 | 0.194 | +0.019 | 0.192 | 7 322 -> 7 566 |
| qb_top glue | 0.661 | 0.440 | **-0.221** | 0.434 | |
| macro wrappers + chip glue | 0.008 | 0.006 | -0.002 | 0.006 | |
| **logic** | **8.050** | **7.879** | **-0.171** | 7.858 | 350 681 -> 337 779 |
| non-core logic | 2.416 | 2.188 | **-0.228** | 2.175 | |
| macros (119) | 7.248 | 7.248 | 0 | | |
| **chip pre-route** | **15.298** | **15.127** | **-0.171** | 15.106 | |

Per cut, chip level:
* glue -0.221: S write requests (WBR) + S read rotator (SROT).  Standalone -0.195 and -0.089; the chip delta also
  includes timing-driven resizing at 600 MHz.
* params path -0.112: fetch-list sizing (-11 572 flops).
* sequencer +0.095: retime structure, against +0.045 standalone; the rest is timing upsizing.  The 10-b age saves 1 920
  flops.
* head +0.019: HP stage + upsizing.

**PT pre-route fmax per path class** [S] (worst path whose endpoint is in the class; setup uncertainty 0.25 ns
included, as in R4).  Run d; b in brackets.

| class | R4 tt | **R4b tt** | **R4b ss** | worst path (d, tt) |
|---|---|---|---|---|
| **chip** | 169.7 | **601.0** (600.8) | **375.8** (378.2) | tt: fused lane `u_rin` -> 16 x 27 multiplier -> `u_rp1` (1.40 ns); ss: qb_top slice-flag queue `fp_hq` -> `fp_z` |
| core fused lanes / other | 401.9 / 397.4 | 601.0 / 601.0 | 382.9 / 377.6 | same (other at ss: PE popcount -> accumulator) |
| core wide lanes | 476.3 | 601.6 | 378.9 | wide lane shift -> y2 |
| core decoders + BR | 418.0 | 602.4 | 384.6 | code port reg -> BR nnw |
| core PE compare | 669.8 | 672.7 | 430.5 | acc -> b2 |
| act supply | 169.7 | 603.3 | 383.2 | ctx `ival` -> `rcnt` |
| sequencer | 276.9 | 602.2 (604.3) | 380.9 | `npr` -> RAW readiness (`rokO`) |
| token (through `tgo` / `d_eot`) | 239.4 / 311.6 | 605.8 / 618.4 | 390.5 / 402.9 | end FIFO head -> qb_act2 `sel1b`; `dsc` -> start FIFO |
| params path | 405.7 | 601.6 | 387.7 | `rfree` -> bank address |
| head | 313.9 | 602.0 | 380.0 | pool requant lane |
| PE popcount / acc, macro boundaries | met | met (not in the worst 200 000) | met | |

**Critical path (tt):** inside qb_core, a fused lane's multiplier stage (input register `u_rin` -> 16 x 27 CSA tree +
carry chain -> `u_rp1`).  It is 1.40 ns of logic + 0.25 ns uncertainty = 601 MHz.  Every class now sits at the
synthesis target, so 1.65 ns sets the limit; no single structure does.  The R4 hypothesis holds: the core classes
return from 400-480 to the slice's 600 MHz once DC sees the macro-clock false paths.

ss is the same tt-compiled netlist at the ss corner, 0.63 x tt, as in the slice runs.  Its worst path is qb_top's flag
queue.  R4's `top_glue` class never matches: its regex expects the endpoint name without the pin, so glue paths show as
"chip" only.  Hold: tt -0.043 ns on 81 endpoints, pre-CTS.


## 4. Verification [M]

| bench | build | result |
|---|---|---|
| `run_tb_chip.sh` + `export_top3.py --check` | R4b tech RTL (`QBT_TECH=2`, macro pin models, seq v4 and v2): E6_s0 val 0/1/2, E6_s1 val 7/42/88 streamed | logits torch.equal PASS 6/6, 600/600 tiles cycle-exact per image, err 0, lockstep 0 differences |
| same | non-tech R4b defines; default build (R4 behaviour); R4 tech build (`QBT_TECH=1`) | PASS |
| `run_tb_top.sh` R3a (img0) / R3b (s0 img0) | default and with all R4b defines | PASS (633 664 checks, final S, 600 tiles cycle-exact) |
| `run_tb_core.sh` img0 / img1 | | PASS 3 644 / 3 684 |
| `run_tb_act2.sh` img0 | | PASS 600 / 600 tiles |
| `compile/test_compile.py --n 100` | both seeds | ALL PASS |

**Mutants** (lockstep off, `QBT_NOLOCK`):
* RTB, token RAW readiness dropped: **caught**.  40 tiles off-cycle per image, logits wrong, err.
* RTL, load-permission window refilled one entry short: **caught**.  Deadlock, timeout.
* WBQ, HQD rotation without the ct term (write-back): **caught** on R3a top, 27 113 errors.
* QBH_MUT_FCK under HP: **caught**, logits wrong.
* RTW, drain-read stamp bypass dropped: **not distinguishable**, even against the lockstep reference.  On these 6 images
  the bypassed stamp (38 distance-1 drain dependencies in the program) never changes an event time.  The bypass is kept
  for exactness.

## 5. Open items / deviations

1. **Two chip runs.**  Run d is the repo RTL (sequencer v4); run b is sequencer v2.  The two sequencer versions are
   cycle-identical and pass the same benches.  Their chip numbers agree within DC noise.
2. **Sequencer floor.**  Standalone, the remaining sequencer path is one 640:1 stamp lookup + compare + window select
   (1.6 ns with the pessimistic IO model).  Next step if routing makes it critical: a 2-stage lookup.  The raw stamps of
   a 4-entry window are registered, and readiness is computed from them one cycle later.  This is exact under the same
   lag argument (lag <= 8), at about 6 more lookup ports.
3. **Further area candidates (not done).**
   * Stamp slots: only 397 of 616 tiles are referenced, and that needs a program-format change.
   * qb_act2 line buffers as pointer-addressed slots instead of a 1/2/4 shift: about 0.2 mm2 of shift muxes [E], but
     the S1 select semantics change.
   * pq in a small macro.
   * Fix the `top_glue` class regex in `impl/r4/pt_class.tcl`: endpoints are pins.
4. **The `rw` stamp bypass is unexercised on the bench images.**  Mutant RTW is equivalent here.  It is kept for
   exactness.
5. **Deleted on tau (own runs from this session only):** tau5 `build/syn/r4b_chip_a`, a superseded partial seq-v1 run;
   tau5 `build/syn/r4b_chip_c`, a seq-v3 run replaced by d.  Nothing else was deleted.

## 6. Files

* New:
  * `hw/rtl/qb_seq_rt.sv`;
  * `hw/tech/qb_chip_tech_r4b.f`;
  * `impl/r4b/` (`reg_audit.tcl`, `seq_rt.f`, `seq.sdc`, `sdc_chk.sdc`, `exp/`: rotation / write-back / SDC micro
    experiments);
  * `results/r4b/`.
* Hooks, default off:
  * `qb_top.sv`: `QB_SEQ_RT` (+ lockstep), `QB_SEQ_LSW`, `QB_TOP_SROT`, `QB_TOP_WBR`, `QB_PRM_*`;
  * `qb_seq.sv` (qb_prm `NFF/NFW/NFT`);
  * `qb_head.sv` (`HP`);
  * `qb_chip.sv` (`QB_HEAD_HP`);
  * `hw/tb/run_tb_chip.sh` (`QBT_TECH=2`, `qb_seq_rt.sv` in the file list);
  * `hw/tb/run_tb_top.sh` (file list).
* `impl/r4/constraints.sdc` is now used by DC as well: `QB_SDC`.  Its `lib_pin_name` filter resolves in DC (checked:
  `impl/r4b/sdc_chk.sdc`, 2 / 2 clock pins of an rf_2p).
