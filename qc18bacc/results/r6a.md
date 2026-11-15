# R6a: host-port share of the R5b top-level long nets, physical groups and their cuts, narrow host port

Labels: **[M]** simulation, **[S]** tool / static (OpenROAD database of R5b run v, DC), **[E]** estimate.  Tools as
R5b (DC W-2024.09-SP2 topographical, OpenROAD 2.0-12381, Verilator 5.050).  Host tau6, build tree
`/tmp/ckp908/qc18bacc/build` (`r6a/`, `syn/r6a_hpw144`, `r6a_gen144`); text summaries in `results/r6a/`.

**Answer.**
- **H1 (host port dominates the long nets / repair buffers): mostly refuted [S].**  In the placed R5b run v,
  `h_data` (2 104 connected bits) owns **26 028 of 191 340 repair buffers (13.6 %, 0.26 mm2 of buffer trees)** but
  only **1 397 of 51 122 nets > 1 mm (2.7 %)** (1 296 of 16 622 > 2 mm, 7.8 %).  All host inputs together: 14.1 % /
  2.8 %.  The long nets are the params path to the blocks (prm staging -> `pf` / `pw` / `t2`, 22 %), the glue to the
  blocks (`s_rd`, `cd`, 14 %), the act supply's own scattered logic (14 %), `f_y` / `w_y` to the head / write-back
  (12 %), the act distribution (6.5 %) and the S macros -> act supply S read (5.8 %).  Loading is not throughput-critical (section 3:
  the image is loaded in 512 cycles inside a >= 3 300-cycle window).
- **H2 (groups with narrow registered cuts): partly [S].**  Group std-cell areas (DC basis): **W 1.52 mm2** (act
  supply 0.94 + sequencer / pass table 0.58) + 0.24 mm2 macros, **S 0.73 mm2** + 4.04 mm2 macros (with the head),
  **N 0.03 mm2** + 2.67 mm2 macros.  Every group <-> group cut is narrow (<= 640 b) or quasi-static except **two wide
  cuts that are unregistered at the act supply's input: S macros -> act supply (4 096 b macro Q -> S-read rotator) and
  B / IMG maps -> act supply (1 536 b Q -> 512-b map mux)**; group <-> block cuts are wide by construction (south 16 056
  + 6 019 b, west act 4 608 b, north cd 2 304 b + t2 1 088 b) and partly combinational within the blocks' R5a IO
  budgets.  Ambiguous assignments: head (W in R5b -> **S**: its pool reads 4 352 b of `f_y` from the south edge),
  slice-flag queues (-> S), pass table (read by every group), `t2` (params, south, but pinned on the block's north
  edge).
- **Floorplan [E]:** W strip 835 x 3 110, N band 3 520 x 850, S band 3 955 x 1 410 around the 3 120 x 3 110 array:
  **die ~3 955 x 5 370 = 21.2 mm2** vs the 20.7 budget (+0.5); **~20.6 mm2** if the sequencer part of W moves into the
  north-west corner left by the 3 520-um weight band.
- **Narrow host port (define `QB_HPW`, default off): HPW = 144**, one macro word per write, registered daisy chains.
  **Image interval delta 0 [M]** (3 836 / 3 748 = R5e).  Image load 128 -> 512 cycles, finished >= 2 962 cycles
  before the running image ends; program load 5 318 -> 16 387 cycles (once per network).  Bit-exact [M]: E6_s1 val
  13 / 55 and E6_s0 val 0 / 1 torch.equal, 600 / 600 tiles cycle-exact, err 0; mutant `QBT_MUT_HPW` caught.
- **DC logic-area delta of the narrow port [S]: +0.029 mm2** (+2 051 flops; R5b top recipe, blocks as ETMs, same
  host as the R5b baseline); the raw total is -0.201 mm2 only because DC's act-chain buffering artefact in the
  `u_core` wrapper (0.233 mm2, removed in P&R anyway) disappeared.  The P&R-side saving it targets is the 26 028
  repair buffers / 0.26 mm2 on h_data (section 1) [S, not re-run].

## 1. H1: which nets carry the repair buffers and the long wires

`impl/r6a/net_trace.tcl` on `pnr/r5b_v/db/place.odb` (after both DRV repairs and detailed placement): every buffer /
inverter is attributed to its root net (driver = a non-buffer cell or a chip input), with the placed HPWL of the
root driver + leaf sinks.  Repair buffers = instances named by OpenROAD rsz (`wire`, `fanout`, `max_length`,
`load_slew`, `max_cap`): 191 340 (R5b: 121 384 + 68 123 [S]).  `impl/r6a/trace_sum.py` groups the roots by driver
hierarchy -> leaf groups (`results/r6a/h1_trace_v.txt`).

| class (root driver -> leaf sinks) [S] | roots | rsz buffers | share | nets > 1 mm | share | > 2 mm |
|---|---|---|---|---|---|---|
| **host `h_data` (chip IO -> weight / params / IMG / FC / descriptor macros)** | 2 104 | **26 028** | **13.6 %** | **1 397** | **2.7 %** | 1 296 |
| other host inputs (`h_addr`, `h_sel`, `h_go`; `rst_n` 369) | 17 | 521 | 0.3 % | 17 | | 17 |
| qb_top glue internal (write-back, delay lines, rotators) | 15 051 | 30 174 | 15.8 % | 4 144 | 8.1 % | 1 100 |
| sequencer internal | 8 702 | 29 660 | 15.5 % | 2 784 | 5.4 % | 1 133 |
| act supply internal (S1 stage 22 453, line buffers 10 589, other 10 495) | 60 675 | 43 537 | 22.8 % | 7 059 | 13.8 % | 2 059 |
| params macros -> qb_prm staging | 1 296 | 13 139 | 6.9 % | 1 296 | 2.5 % | 1 296 |
| qb_prm staging -> blocks (`pf`, `pw`, `t2`) | 11 328 | 6 212 | 3.2 % | **11 328** | **22.2 %** | 598 |
| glue -> blocks (`s_rd`, `cd`, `w_r`, ctl) | 7 363 | 3 415 | 1.8 % | 7 363 | 14.4 % | 3 172 |
| blocks `f_y` / `w_y` -> head + write-back | 6 018 | 14 126 | 7.4 % | 6 018 | 11.8 % | 4 475 |
| S macros -> glue (act-supply S read, write-back read) | 3 996 | 6 745 | 3.5 % | 2 956 | 5.8 % | 528 |
| act distribution -> column 0 `act` | 3 958 | 1 417 | 0.7 % | 3 320 | 6.5 % | 64 |
| maps -> glue | 773 | 3 604 | 1.9 % | 772 | 1.5 % | 257 |
| **total** (listed roots) | 132 788 | **191 340** | | **51 122** | | 16 622 |

Most h_data bits have 3-5 leaf sinks (weight macro lanes x 3 deep, a params macro, an IMG macro); 13 bits fan out to
665 sinks (the descriptor / config bits).  **Verdict [S]:** h_data is the largest single chip-wide bus by repair
buffers but a small share of the long wires; the long-wire count comes from the params -> block, glue -> block and
`f_y` buses (all on the south edge) and from placement scattering the act supply / sequencer / glue internals
(> 1 mm nets inside one RTL module: ~14 k).  Removing the host broadcast removes ~14 % of the repair buffers, not
the long-wire problem; grouping (section 2) addresses the rest.

## 2. H2: groups, cuts, areas, floorplan

**Method [S].**  `impl/r6a/net_dump.tcl` dumps the run-v netlist (DC netlist + rsz buffers) with block-pin edges;
`impl/r6a/cuts.py` collapses the rsz buffer trees, assigns groups and lists every net crossing a group / block
boundary.  Seeds: RTL hierarchy (`u_act`, `g_dist`, `u_seq`, qb_chip glue -> W; `u_prm`, `u_head` -> S), macros by
type (qb_w -> N; qb_s / qb_b / qb_i / qb_p / qb_f -> S; qb_d -> W), the 8 blocks, and every qb_top glue register by
its RTL role (`cuts.py` `NAMED`: cd_r / weight address / item-control pipeline -> N; rq_r, S and map write registers,
b2 FIFO, write-back delay lines / jobs, slice-flag queues -> S; pass table, time base -> W).  The glue's
combinational cells (and unnamed registers) take the majority group of the cells they drive (logic sits with its
destination registers), else of their drivers.  "Registered" = driven by a flop / macro / block output (source),
captured only by flops / macros / block inputs (destination).  Tables: `results/r6a/cuts_headS.txt` (proposal),
`cuts_headW.txt` (head in W, as R5b), `cuts_headS_splitW.txt` (W split into WA = act supply and W = sequencer).

**Group areas.**  Std cells: DC areas of `results/r5b/dc_top.txt` per hierarchy; the qb_top glue (0.481 mm2 DC)
split by the placed-cell shares of `cuts.py` (scale 0.481 / 0.678 placed); the 0.233 mm2 of DC act-chain buffers in
the `u_core` wrapper are dropped (abutted blocks, R5b `remove_buffers`).

| group | content | std cells mm2 [S] | macros mm2 [S] |
|---|---|---|---|
| **WA** (west, south part) | act supply qb_act2 0.835 + act distribution + its glue (pass-table field muxes) | **0.94** | - |
| **W** (west, north part) | sequencer 0.545, pass table / time base / context glue, qb_chip glue 0.015 | **0.58** | 2 descriptor 0.236 |
| **S** (south band) | qb_prm 0.234, head 0.163, write-back + S read / write registers + rotators + b2 FIFO + map writes + flag queues 0.331 | **0.73** | 32 S 2.497, 9 params 0.536, 8 B 0.406, FC 0.466, 4 IMG 0.135 = **4.04** |
| **N** (north band) | cd_r 2 304 b, weight-row address, item-control pipeline | **0.03** | 48 W **2.671** |
| blocks | 8 x qb_col_blk (fixed) | | 8 x 1.213 = 9.703 |
| total | | 2.27 (+0.23 dropped) | 6.95 |

**Cut table (proposal: head in S, W split) [S].**  bits; src / dst = registered at source / destination; edge = block
edge of the pins.

| cut | bus | bits | src reg | dst reg | note |
|---|---|---|---|---|---|
| IO -> N / S / W | host `h_data` + address (wide port) | 2 320 / 1 314 / 113 | port | macro | replaced by the 144-b narrow port (section 3) |
| N -> BLK (north) | `cd` codes from cd_r | 2 304 | yes | block (0.30 P budget) | 8 columns, 288 b each |
| N -> BLK (north) | `ctl` (item control pipeline) | 8 | yes | block | |
| **S -> BLK (north)** | **`t2` from qb_prm T2 staging** | **1 088** | yes | block | **crosses the array height (3.1 mm); flag** |
| S -> BLK (south) | `pf` from qb_prm fused staging (double-buffer select) | 5 184 | **no** (mux) | block (0.20 P) | **wide, comb at the top side; needs prm staging at the south edge** |
| S -> BLK (south) | `pw` from qb_prm wide staging | 5 056 | yes | block | |
| S -> BLK (south) | `s_rd` (rq_r -> lane rotation) | 4 096 | **no** (rotator) | block (0.20 P) | **wide, comb; rotator at the south edge** |
| S -> BLK (south) | `w_r`, `f_src`, PPU controls | 608 + 13 | no | block | |
| BLK (south) -> S | `f_y` 4 096, `b2` 1 024, `w_y` 608, `f_b` 256, `w_b` 32, valids 3 | 6 019 | yes (block regs, 0.25 P out) | no (write-back rotators, head pool) | comb at the destination; S logic at the south edge |
| BLK (south) -> W | `f_y` bits / valids read by W logic | 45 | yes | no | 4 105 b if the head stays in W |
| WA -> BLK (west) | `act` (column 0, then block to block) | 4 608 | yes (g_dist) | block (0.55 P) | WA must abut the array's west edge |
| **S -> WA** | **S macros Q -> act-supply S-read rotator -> qb_act2** | **4 096** | macro | **no** | **wide AND unregistered at the act supply; flag** |
| **S -> WA** | **B / IMG macros Q -> map mux (`m_q` 512 b) -> qb_act2** | **1 536** | macro | **no** | **wide AND unregistered; flag** |
| S -> WA / W | write-back / flag state -> act supply / sequencer (`fs_*` flags 200 b to the sequencer) | 245 + 602 | 209 + 405 | no | narrow |
| W -> WA | pass-table fields -> act-supply context config | 960 | yes | no | quasi-static (pt changes only at program load); narrows to ~2 x 40 b if the pt read mux sits in W |
| W -> N | pass-table fields -> weight-row address | 527 | yes | no | quasi-static; narrows to w_row 10 b + 2 b |
| W -> S | pass-table fields -> write-back address; sequencer / chip -> head, prm | 473 + 136 | 487 total | 52 | quasi-static / narrow |
| WA -> N / S / W | act-supply item outputs (`d_vld` ... to ictl, map read address to maps) | 16 / 32 / 38 | partly | partly | narrow |
| S -> IO | logits | 41 | yes | port | |

**Flags.**
1. **Wide and unregistered:** S -> WA S read (4 096 b of macro Q through the rotator to qb_act2's S1 registers) and
   maps -> WA (1 536 b Q, 512 b after the mux).  Today both are one cycle macro clk->Q (0.7-0.9 ns tt) + wire +
   rotator / mux; across a group boundary that only closes if WA abuts the S band (WA in the south-west corner of the
   W strip) or the rotator / mux moves into S with a register on its 2 048 + 512-b output (+1 cycle of S / map read
   latency: a compile-model change, not done).
2. **Wide, combinational at the top side by design:** `pf` 5 184 and `s_rd` 4 096 (+ `w_r` 608) into the block south
   edge within the R5a 0.20 P input budget, and `f_y` / `w_y` / `b2` out of it into the write-back within 0.25 P: the S
   group's staging registers / rotators must sit against the block's south edge (they are S-group logic; the cut is
   fine only if S is one block abutting the array, or these registers move into a per-column south slice).
3. **`t2` (1 088 b) is pinned on the block's north edge but sourced from the params bank in S**: 3.1 mm across the
   array.  Either a T2 staging copy in N (fed from the bank: more bank bandwidth or a copy of the T2 rows) or a block
   re-pin of `t2` to the south edge (block re-P&R).
4. **Ambiguous assignments:** (a) head: W in R5b; its pool reads 4 352 b of `f_y` from the south edge and the FC
   macro moves with it -> S (BLK -> W cut 4 105 -> 45 b; S macros 4.04 mm2 instead of 3.58).  (b) slice-flag queues
   (`fp_*` / `fs_*`, 400 flops): set from zero detects of `f_y` (S), read by the sequencer (W) -> S, 200-b registered
   cut.  (c) pass table (2 656 flops): read by WA (960 b of fields), N (527), S (473); static during an image, so
   any placement works if each reader's field mux sits next to the table, or it is replicated per group (~0.02 mm2
   each [E]).  (d) `ictl` (item control, 24 flops) -> N with the codes (it feeds the north `ctl` pins).
5. N has only 0.03 mm2 of logic: it needs no hard block (top-level registers in the macro channels, or eight per-column
   slices).

**Floorplan proposal [E]** (blocks fixed 8 x 390 x 3 110; std-cell utilisation 0.65 in the group blocks; macros +10 %
for halos / channels; macro shapes as R5b):

```
 y 5370 +-----------+-------------------------------------------------+
        | (W-seq in |  N: 48 qb_w, 8 slots x 6 rows (440 x 127),      |   850
        |  corner)  |     cd_r / ictl in the channels, 3 520 wide       |
   4520 +-----------+-------------------------------------------------+
        | W: seq +  |                                                 |
        | 2 desc    |  8 x qb_col_blk abutted, 3 120 x 3 110           |
        | 835x1375  |  act west (col 0), cd / ctl / t2 north,         |  3 110
        |-----------|  pf / pw / s_rd / f_y / b2 south                |
        | WA: act   |                                                 |
        | supply    |                                                 |
        | 835x1735  |                                                 |
   1410 +-----------+-------------------------------------------------+
        | FC (R90)  | S: 4 rows x 8 qb_s (one column of 4 per block), |  1 410
        | IMG x4    | B row, params row, prm staging / rotators /     |
        | head      | write-back against the block south edge         |
      0 +-----------+-------------------------------------------------+
        0          835                                              3955
```

| group | area need [E] | shape um | mm2 |
|---|---|---|---|
| W strip (WA 0.94 / 0.65 + W 0.58 / 0.65 + desc 0.26) | 2.60 | 835 x 3 110 | 2.60 |
| N band (2.671 x 1.1 + 0.04) | 2.98 | 3 520 x 850 (in a 3 955-wide band) | 3.36 |
| S band (4.04 x 1.1 + 0.73 / 0.65) | 5.57 | 3 955 x 1 410 | 5.58 |
| array | 9.70 | 3 120 x 3 110 | 9.70 |
| **die** | | **3 955 x 5 370** | **21.2** (vs 20.7: +0.5) |

The 3 520-um weight band leaves a 435 x 850 um (0.37 mm2) corner: putting W-seq there narrows the W strip to ~715 um
and gives **~3 835 x 5 370 = 20.6 mm2 [E]**.  Each group is in the size range OpenROAD handled for the column block
(1.21 mm2 block, routed): WA ~1.45 mm2 / 0.94 mm2 std cells, W ~1.15 mm2, S 5.6 mm2 with 54 macros but 0.73 mm2 of
std cells (the open risk: 54 macros in one block; S splits per column only if the write-back rotators, which permute
across lanes, are split).  vs R5b run v (placed, 23.97 mm2): the difference is mostly the 2.13 mm2 of repair buffers
and 2.68 mm2 of halos / empty rows that the group shapes are meant to avoid; none of these numbers is a P&R result.

## 3. Narrow host port (`QB_HPW`, opt-in)

**How the image is loaded today** (`tb_qb_chip.sv`, `qb_chip.sv`): IMG is single-buffered; the host loads image
i + 1 (128 lines x 512 b, one line per cycle) as soon as `st_img_free` rises (the running image's stem has ended,
+275 cycles after its go), and gives `h_go` in the first `st_idle` cycle.  The load overlaps the previous image;
the interval is set by the engine (static model + 1), not by the port.

**Design (HPW = 144 = the weight / params macro word).**  `qb_chip` define `QB_HPW` (undefined = unchanged wide
port).  Ports: `h_data[HPW-1:0]` + `h_lane[4:0]`; one macro word per write: weights h_sel 0 lane 0..15 (144 b),
params h_sel 1 lane 0..8 (144 b), IMG h_sel 2 lane 0..3 (128 b), every other select one write as before (<= 128 b;
FW 128 required).  Distribution, all registered (`qb_chip.sv`, `qb_top.sv` / `qb_seq.sv` parameter `HPW`):
* IO register stage in qb_chip for h_we / h_sel / h_addr / h_lane / h_data (`h_go` is not delayed);
* weights: a daisy chain of 8 stages {valid, lane, row, 144 b} along the weight-macro row, stage s writes lanes 2s /
  2s + 1 (the R5b slot order), so each stage drives 6 macros next to it;
* params: a 3-stage chain in qb_prm, stage s writes bank macros 3s .. 3s + 2;
* IMG: one register stage next to the 4 IMG macros; descriptors / head / FC: the IO register.
A write lands <= 10 cycles after it is given; `h_go` within 10 cycles of a write sets `err` (the bench waits 10
cycles before image 0); an IMG write landing in a stem IMG-read cycle sets `err`.  Chip IOs: 5 260 -> 220.

**Cycles [M]** (E6_s1 program; `results/r6a/tb.txt`):

| load | wide port writes | HPW 144 writes |
|---|---|---|
| weights 611 rows | 611 | 9 776 (x 16) |
| params 238 rows | 238 | 2 142 (x 9) |
| descriptors / lists / counts / head config | 1 244 | 1 244 |
| FC 3 225 rows (128 b) | 3 225 | 3 225 |
| **program (once per network)** | **5 318** | **16 387** |
| **image (per image)** | **128** | **512**, done at go + 786 of the previous image, >= 2 962 cycles before its end |
| **image interval** | 3 836 / 3 748 (s1 13 / s0 0) | **3 836 / 3 748: delta 0** |

**Verification [M]** (R4b tech build `QBT_TECH=2`, `QB_HEAD_FW=128`, ARM pin models):

| build | images | result |
|---|---|---|
| `+QB_HPW=144` | E6_s1 val 13 / 55 | PASS: logits torch.equal (`export_top3.py --check`), 600 / 600 tiles cycle-exact, intervals 3 836 (= R5e), err 0, FC overlap slack 406 (= R5e) |
| `+QB_HPW=144` | E6_s0 val 0 / 1 | PASS, torch.equal, interval 3 748 (= R5e), slack 430 |
| `+QB_HPW=144 +QBT_MUT_HPW` (weight-lane decode ignores the lane LSB: both lanes of a chain stage written) | E6_s1 val 13 / 55 | **caught**: 100 / 100 logits wrong per image, 40 tiles off-cycle, err set |
| default (no `QB_HPW`), tech and behavioural | E6_s1 val 13 / 55 | PASS, intervals 3 836, = R5e |
| `run_tb_top.sh` R3a (qb_top default) | img0 | PASS (633 664 checks, 600 tiles cycle-exact) |

## 4. DC logic area of the narrow port

`impl/r6a/syn.sh 144` = the R5b top DC (`impl/r5b/run.sh syn`: R4b recipe, 1.65 ns tt topographical, R5e head
FW 128, the 8 column blocks as R5d ETMs, `impl/r5b/dc_hook.tcl`) + `QB_HPW=144`; 49.5 min on tau6, the same host,
recipe and block views as the R5b baseline `syn/r5b_top` (`results/r5b/dc_top.txt`).  `results/r6a/dc_hpw144.txt`.

| logic mm2 [S] | R5b top (wide port) | HPW 144 | delta |
|---|---|---|---|
| act supply / sequencer / qb_prm / head | 0.835 / 0.545 / 0.234 / 0.163 | 0.831 / 0.547 / 0.239 / 0.166 | -0.004 / +0.003 / **+0.005** / +0.003 |
| qb_top glue (incl. weight chain, IMG stage) | 0.481 | 0.499 | **+0.018** |
| macro wrappers (per-lane host address muxes) / qb_chip glue | 0.006 / 0.015 | 0.011 / 0.014 | +0.005 / -0.001 |
| `u_core` wrapper (DC act-chain buffers between the block ETMs) | 0.233 | 0.003 | -0.230 (artefact, see below) |
| **logic total** | **2.511** | **2.310** | **-0.201** |
| **logic total without the u_core artefact** | **2.278** | **2.307** | **+0.029** |
| registers | 131 609 | 133 660 | **+2 051** (expected 2 052: chain 8 x 159 + 3 x 157 + IMG 138 + IO 171) |
| WNS / violating endpoints (ideal clock, block ETMs) | -6.94 / 44 761 | -5.22 / 45 391 | same classes (act chain to column 7) |

* **Narrow-port cost: +0.029 mm2 of logic [S]** (2 051 flops of the chains / IO register + per-lane address muxes,
  +1.3 % of the top logic).  The -0.230 mm2 in the `u_core` wrapper is the R5b section 2 / 5.3 artefact: DC
  topographical buffers the act chain between the black-box blocks (CKBD12 per hop) depending on its own die and
  pin placement, which changes when 5 189 input pins disappear; P&R removes these buffers anyway (`remove_buffers`,
  R5b run u / v).  It is not a saving of the narrow port.
* DC does not buffer the 5 189-fanout input port (qb_chip glue 0.015 in both), so the narrow port's benefit is not
  visible in DC: it is the P&R repair on h_data measured in section 1 (26 028 buffers, 0.26 mm2 of buffer trees,
  1 397 nets > 1 mm) [S], which the registered 144-b chains (each stage drives <= 6 macros next to it) replace.
* Macros unchanged (104, 6.948 mm2).

## 5. Files

* RTL (defaults unchanged): `hw/rtl/qb_chip.sv` (define `QB_HPW`, parameter `HPW`, IO register, `h_lane`,
  in-flight check), `hw/rtl/qb_top.sv` (parameter `HPW`: weight daisy chain, IMG stage, IMG write/read check, mutant
  `QBT_MUT_HPW`), `hw/rtl/qb_seq.sv` (qb_prm parameter `HPW`: bank chain).
* Bench: `hw/tb/tb_qb_chip.sv` (under `QB_HPW`: lane-split writes, 128-b image streaming, 10-cycle wait, load-cycle
  report).  `export_top3.py` unchanged (the bench splits the exported wide rows).
* Flow: `impl/r5b/run.sh` (`QB_GEN`, `QB_DEFS_EXTRA`, default unchanged); new `impl/r6a/`: `net_trace.tcl`,
  `trace_sum.py`, `net_dump.tcl`, `cuts.py`, `syn.sh`.
* Results: `results/r6a/` (`h1_trace_v.txt`, `area_groups_*.txt`, `cuts_*.txt`, `tb.txt`, `dc_*.txt`).

```bash
# tau6, from /tmp/ckp908/qc18bacc/repo, QC_BUILD=/tmp/ckp908/qc18bacc/build
QB_RUN=$QC_BUILD/pnr/r5b_v QB_OUT=trace_v.txt openroad -exit qc18bacc/impl/r6a/net_trace.tcl; python3 -I qc18bacc/impl/r6a/trace_sum.py trace_v.txt --long 45
QB_RUN=$QC_BUILD/pnr/r5b_v QB_OUT=dump_v.txt openroad -exit qc18bacc/impl/r6a/net_dump.tcl
python3 -I qc18bacc/impl/r6a/cuts.py dump_v.txt cvsw --head-south --split-w      # also: no flag (head W), --head-south
qc18bacc/impl/r6a/syn.sh 144                                                      # DC -> syn/r6a_hpw144
# local
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top3.py /tmp/root/qc18b/exc200/E6_s1/best.pt OUT --cache CACHE --images 13 55 --fc 128
QB_TB_WORK=W QBT_TAG=_n144 QBT_TECH=2 QBT_DEFS="+define+QB_HEAD_FW=128+QB_HPW=144" qc18bacc/hw/tb/run_tb_chip.sh build
QB_TB_WORK=W QBT_TAG=_n144 qc18bacc/hw/tb/run_tb_chip.sh run OUT/prog OUT/img13 OUT/img55   # then copy logits_rtl_n144.txt -> logits_rtl.txt, --check
```

Nothing deleted on tau.  New on tau6: `build/r6a/` (trace / dump text, 145 MB), `build/r6a_gen144`,
`build/syn/r6a_hpw144`.
