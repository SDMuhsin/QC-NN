# R9c: column-local params bank (opt-in RTL `QB_PRM_COL=1` + compile `--prm-col`; defaults unchanged)
[M] sim, [S] Yosys, [Mod] geometric model, [R] reasoning.  Tables `results/r9c/{bitmap,crossing,hpwl,tb,yosys}.txt`.
**Measured map (before) [R, `bitmap.txt`]:** row r, bank bit q = set bit 1296 r + q, so fused row r feeds cols 2r / 2r+1
(648 b each) and wide (632-b) rows straddle columns.  Macros 0-3 feed f/w cols {0,2,4,6}, 5-8 feed {1,3,5,7}, macro 4 all 8;
T2 macro m -> cols m, m+1.  6 072 (Q bit, column) taps; 3 648 > 1 pitch (macro k at col k) -> 846 b of each f row read and
804 of each w row cross > 1 pitch.  No other macro-Q consumer (common bits come from the pass table).
**Layout (COL) [R, `compile/prm_col.py`]:** column c owns a 648-b slot; slot bits 0-575 = macro c (row s/144), 576-647 =
macro 8 bits 18c..18c+17 (row u/18).  T2: col c lanes in macro c bits 0-135; macro 8 unused on T2 rows.  Each macro c<8 now
feeds only column c (f / w / t); **the 9th macro is the only cross traffic: 144 Q nets, 18 b to each column per f/w row read**.
**RTL (`qb_seq.sv` qb_prm #(COL), `qb_top.sv` define):** stg_f / stg_w kept in slot order; landing of row r writes
stg[648c+144r +: 144] <= b_q[144c +: 144] and stg[648c+576+18r +: 18] <= b_q[1152+18c +: 18]; pf = stg_f unchanged,
pw[632c+s] = stg_w[648c+s], t2[136c+i] = stg_t[144c+i].  The prm logic does not mix columns (pf 2:1 mux is per bit), so no
restructuring is needed: the staging already splits into per-column slices (R7g: 2 064 flops each) fed by 144 + 18 Q bits
+ the 9 broadcast control bits.  **Cost: +0 flops (24 867 both, [S]); same 13 landing enables; Yosys comb -18 k cells**
(artefact of COL 0's variable part-select, not a saving to claim).  Fetch lists / arbiter / HPW write chain untouched.
**Compile:** `export_top3.py --prm-col` or `prm_col.py convert prog progc` (asserted lossless): same 14 prog files (E6_s0).
**Verification [M] (`tb.txt`), full set = R8d new + QB_ACT_S2M, s0 val 60 61 0 1 2, s1 val 13 55 7 42 91:** COL 10/10 PASS,
100/100 logits, 600/600 tiles cycle-exact, err 0; full logs == COL 0 logs == R8d new logs line for line; logits files
identical; torch.equal 10/10.  Plain build == R8d plain logs.  Mutant `QBP_MUT_COL` (macro-8 share of row r lands in
row r^1): 10/10 FAIL, torch.equal 0/10.  Negative controls (COL RTL on default rows, COL 0 RTL on column rows): 20/20 FAIL.
**Wire model [Mod] (`hpwl.txt`, x span macro pin -> consumer col centres, x0 860, pitch 390, y not modelled):**
macro k at col k + macro 8 mid-array: **3.08 -> 0.11 m (-96 %)**; same, macro 8 at R9b NW corner: 3.25 -> 0.32 m;
R9b mplace9 x (439.8-um macros right-aligned, macro k at -443+60k um from col k): 3.32 -> 0.59 m (-82 %, 0.32 m macro 8).
R9b measured 5.23 m for these 1 296 nets (incl. y).  East-west trunk in the band: 1 296 b at every column cut -> <= 72 b
(macro 8 mid) or 144 b (NW).  Next [R]: place macro 8 mid-row; for full locality the row needs macros <= 380 um wide.
