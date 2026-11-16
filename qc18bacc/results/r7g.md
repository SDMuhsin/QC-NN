# R7g: column-sliced head pool (opt-in RTL `QB_HEAD_PCOL`, default 0 = R7e RTL) + params-staging split analysis

**[M]** RTL sim, **[S]** Yosys, **[R]** reading the RTL; data `results/r7g/{tb,yosys,prm}.txt`.
**Result A: exact [M]; per column 512 head wires -> 76 out + 7 in; Yosys -33 cells (flops identical) [S].**
**Result B: per-column split of the prm staging is bit / cycle exact possible (proposal, `prm.txt`) [R].**
## 1. RTL A (`hw/rtl/qb_head.sv` parameter `PCOL`, `hw/rtl/qb_chip.sv` define `QB_HEAD_PCOL` -> `.PCOL`)
* New module `qb_hpcol #(NQ, C)` (end of qb_head.sv), instances `g_pcol[c].u_pc`, c = 0..7.  Slice c takes only
  column c's f_y lanes 64 q + 8 c + i (4 px x 8 ch x 16 b = 512 b) and holds s4 / tacc / hold of channels 8 c .. 8 c + 7
  (same enables, no reset, updates only out of reset, `QBH_MUT_RELU` mirrored).
* Select: lane i reads channel NQ rq_j + i, in column rq_j / 2 (NQ 4).  Each slice drives `po` = its 4 x 19 b
  hold[4 (rq_j % 2) + i] when rq_j / 2 == C, else 0; the lanes take the OR of the 8 `po` (`pc_q`).  Exactly one slice
  matches for every rq_j, so the lane input equals hold[NQ rq_j + i] for all inputs (incl. rq_v = 0).
* Control stays in qb_head: tap, rq_v / rq_j / hct, rq_ovr, err, busy unchanged; slices get tap, k0 = (f_k == 0),
  k3 = (f_k == 3), rq_j.  PCOL 0: the original s4 / tacc / hold code (names unchanged) behind constant `!PCOL` guards.
* Mutant `QBH_MUT_PCOL`: slice picks the wrong half of its channels (rq_j % 2 inverted).

## 2. Verification [M] (Verilator 5.050, QBT_TECH=2 + QB_HEAD_FW=128 + QB_HPW=144 + QB_TOP_RSH=1; R7d vectors)
| build | s0 val 60 61 0 1 2 | s1 val 13 55 7 42 91 |
|---|---|---|
| PCOL=1 | PASS: 100/100 logits, 600/600 tiles cycle-exact, err 0 (5/5); `--check` torch.equal 5/5 | PASS; 5/5 |
| PCOL=1 + `QBH_MUT_PCOL` | FAIL: 100/100 logit mismatches per image (tiles still cycle-exact); torch.equal 0/5 | FAIL; 0/5 |
| default (plain) | - | val 13 / 55 PASS, err 0 |
PCOL=1 bench logs == R7e RSH=1 logs line for line (s0 and s1, paths / walltime stripped); s1 logits files identical.
## 3. Wires / area
| per column (8 columns) | before (PCOL 0) | after (PCOL 1) |
|---|---|---|
| f_y bits that must leave the column for the head | 512 (4 px x 8 ch x 16 b; 4 096 total to the SW corner) | 0 (slice next to the column) |
| slice -> head (lane candidates) | - | 76 (NQ x 19 b; 608 total) |
| head -> slice (control) | - | 7 (tap, k0, k3, rq_j[3:0]) |
Yosys generic, qb_head FW 128 with the FC macro black-boxed (`impl/r7g/syn.sh`): PCOL 0 64 409 cells, PCOL 1 64 376
(-33; MUX 4 221 -> 4 065, flops 6 939 both: same registers).  The 16:1 x 76-b hold select becomes 8 x (2:1 + AND) + OR.
Cheaper option: daisy-chained OR (76 b per column boundary).  f_y still feeds qb_top's write-back rotators (R7e).
## 4. Task B (params staging, details `results/r7g/prm.txt`) [R]
* Shared: fetch lists (flf 160 / flw 32 / flt 112 x 25 b = 7 600 flops, incl. R7b's flt 2 800), arbiter, counters,
  p1 / p2 pipeline, tags / valids, HPW write chain: column-agnostic, belong next to the 9 macros.
* Per bit: staging stg_f[2] (2 x 5184), stg_w (5184), stg_t (1296) = 16 576 flops, enable-loaded from b_q (1 296 b /
  cycle).  Column block c reads pf[648 c +: 648] + 5, pw[632 c +: 632] + 3, t2[136 c +: 136] = 1 424 b (11 392 total).
* Per cycle macros -> columns: one 1296-b row; fused row r -> cols 2r / 2r+1 (one half each), wide (79-b records)
  rows straddle cols 2/4/6, t2 row -> all 8.  b_q taps per column 648-880 b (sum 6 072).
* Split (exact): 8 slices with column c's staging bits (2 064 flops) + pf 2:1 mux, fed by their b_q taps + 9 broadcast
  control bits (p2_v, p2_c, p2_r, p2_b, ruse[0][0]) + 8 pass-table bits; 11 392 pin wires become local, the band
  carries a 1296-b trunk.  Optional: 81-b wide records (64 x 81 = stg_w) align wide rows with fused (taps <= 784).

## 5. Commands (local; work dir /tmp/root/qc18bacc/r7g, vectors v/ = copies of r7d/{s0,s1})
`QB_TB_WORK=W QBT_TAG=_pc QBT_TECH=2 QBT_DEFS="+define+QB_HEAD_FW=128+QB_HPW=144+QB_TOP_RSH=1+QB_HEAD_PCOL=1"
hw/tb/run_tb_chip.sh build` (mutant: append `+QBH_MUT_PCOL`, tag _pcm); `run v/s0/prog v/s0/img60 ...`; copy
`img<i>/logits_rtl_pc.txt` -> `chk_pc/<s>/img<i>/logits_rtl.txt`, then `CUDA_VISIBLE_DEVICES=0 python3
hw/tb/export_top3.py /tmp/root/qc18b/exc200/E6_<s>/best.pt chk_pc/<s> --cache /tmp/root/qc18bacc/exp2/cache --images
... --fc 128 --check`.  Yosys: `impl/r7g/syn.sh h0 0`, `impl/r7g/syn.sh h1 1` (logs in cwd).
