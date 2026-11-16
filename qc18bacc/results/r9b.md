# R9b: south hub as a hard block (netlist partition + standalone OpenROAD P&R), tau6 -- placement only, no route
[S] tool output, [R] reasoning.  Scripts `impl/r9b/` (run.sh dump|part|ports|sdc|equiv|fp|pnr|dr), tables `results/r9b/`.
Netlist **r8d_rpg** (tau6 `build/r9b_d`); the same flow on r8a_rp (`build/r9b`, `*_r8a_rp.txt`) gives the same boundary.
**Partition [S], no RTL change:** cuts.py groups (`--head-south --split-w`) -> `part.py`: hub = group S (S 32, B 8, params 9, FC,
IMG 4, prm, head, write-back / rotator / S- and map-read glue, host image / params stages) + comb rotator ends cuts.py homed
in qb_act2 (20.6 k) + pass table + chip head-config regs + u_core DC buffers on south pins; ICGs follow their flops.  DC
`dc_part.tcl` (no compile): `ungroup u_top`, flatten u_core, `group` -> u_hub = qb_hub (202 k cells, 0.841 mm2 std +
4.04 mm2 macros); 30 broadcast outputs split per column (+75 ports / BUFFD4); `const.py` ties DC's 1'b0 hier-pin literals.
**Equivalence [S] (`equiv.txt`):** tau Formality is 2019.12 (cannot read DC 2024 ddc / svf) -> pin-level structural check of both
OpenROAD-linked flat netlists: 577 338 = 577 338 instances, 0 master mismatches, 641 171 / 641 171 nets with identical
(instance, pin) terminal sets after merging the 75 split buffers, 4 604 constant pins equal -> same graph.
**Boundary [S] (`boundary_bus.txt`, `pins_per_um.txt`): 27 852 ports (6 658 in / 21 194 out), all on the north edge.**
| bus | bits | hub-side registered |
|---|---|---|
| to columns pf / pw / s_rd / w_r / ctrl | 5 224 / 5 080 / 4 147 / 608 / 56 | 0 / 99.5 / 0 / 0 / 43 % |
| from columns f_y / b2 / w_y / f_b / w_b | 4 096 / 1 024 / 608 / 256 / 32 | 100 / 100 / 100 / 0 / 0 % |
| to column north pins over the array (t2, rst_n) | 1 093 | t2 100 % |
| act supply out (s_q 2 048, m_q 512 ..) / in | 2 652 / 18 | 0.5 / 0 % (act block registers) |
| sequencer + top glue out / in; host in; chip IO out | 2 276 / 496; 112; 41 | 84 / 79; 90; 98 % |
Per column 2 640 pins straight under its south pins (same x / layer) = 6.77 /um + 137 M8 pins (t2: 3.1-mm top wire over the
array); west strip x 12-848 (under the act block) 5 625 = 6.73 /um; edge 6.98 /um.  Budget (`sdc.py`) from the column
budgets (not raw ETM arrivals: f_y / b2 ~0.9-ns insertion delay excluded, per PI): col in 0.27 P, out 0.20 P, act out 0.30 P.
**P&R [S] (`place_runs.txt`): die 3990 (array + west strip) x H, R8 south-band macros, period 1.85 ns.**
- H 1 551.2 (6.19 mm2): DRV repair 0.841 -> 1.599 mm2 std (53 k buffers, 81 k resized; 71.9 k slew / 15.8 k long-wire
  violations), util 0.92 -> GPL-0302, does not fit.  H 1 700.6 (6.79 mm2 = R8's band, no height gain): run e DPL-0036 on
  924 clumped cells (u_top glue comb, f_y regs, head fyi); run f (TD / RD off, DPL window 500 um) legal: **std 1.711 mm2 =
  2.03x DC**, 65 k buffers, stopped in CTS at the box.  **No GRT / DR / DRC / routed fmax; peak RSS 2.9 GB (placement).**
**Mechanism [S] (`longnets_gpl.txt`, plain gpl, H 1 700.6): 23.9 k nets > 400 um, 31.7 m HPWL:** glue comb (rotators /
write-back / gather) 11.9 m; S macro Q 4 091 nets 5.3 m (S Q feeds both its column's s_rd and the act port at the far
west); params Q 1 296 nets 5.2 m (4.0 mm each, [R] params banks fan out to pf / pw of all 8 columns); f_y regs 1.7 m; B Q
1.5 m.  [R] The repair doubling comes from array-wide horizontal traffic inside the hub, which a boundary cannot remove.
Next [R]: params bank per column, S-read registered per column with the act port mid-array, then GRT.
