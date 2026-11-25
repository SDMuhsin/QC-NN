# Kit config template (copy to site.tcl, git-ignored, and fill in every <PLACEHOLDER>).
# Sourced by common/lib.tcl in DC and PrimeTime (and the ICC2 / OpenROAD flows).
set ::QC_KIT $::env(QC_KIT)

# ---- standard-cell timing libraries (.db directory; the libraries per corner come from the corner table below)
set ::QC_LIBDIR <STDCELL_DB_DIR>

# ---- wire-load mode (QC_TOPO=0): area-based wire_load_selection group of the library (empty: library default;
#      check it is not a zero model, see common/lib.tcl qc_wire_load)
set ::QC_WLM_GROUP <WLM_SELECTION_GROUP>

# ---- physical data for DC topographical mode (QC_TOPO=1)
set ::QC_TF      <TECHFILE>
set ::QC_MW_REF  <MILKYWAY_REFERENCE_LIB>
set ::QC_TLU     <TLUPLUS_DIR>
set ::QC_TLU_MAP <TLUPLUS_LAYER_MAP>

# ---- sign-off corners: the one corner table (name, library root, operating condition, TLU+ file, ICC2 role setup / hold);
#      every tool derives QC_LIB / QC_OC / QC_TLU_FILE / QC_ROLE / QC_SIGNOFF_CORNERS from it.  Take the corners from the
#      library release note's characterization-corner table: setup at the slow process / low voltage at both temperature
#      ends (temperature inversion) x {Cworst RCworst}, hold at the fast process / high voltage at both ends x
#      {Cbest RCbest}, plus typical.  ss / tt / ff must exist (the base corners below).
set ::QC_SIGNOFF {
    ss      <LIB_WC>  <OPCOND_WC>  <TLU_CWORST>  setup
    tt      <LIB_TC>  <OPCOND_TC>  <TLU_TYPICAL> hold
    ff      <LIB_LT>  <OPCOND_LT>  <TLU_CBEST>   hold
}
set ::QC_SIGNOFF_CORNERS {}
foreach {c l oc tlu role} $::QC_SIGNOFF {
    set ::QC_LIB($c) $l; set ::QC_OC($c) $oc; set ::QC_TLU_FILE($c) $tlu; set ::QC_ROLE($c) $role
    lappend ::QC_SIGNOFF_CORNERS $c
}
# base corners (subset of the table): DC, sta/run_pt.sh default, OpenROAD blocks (block ETMs / chip top: every sign-off corner)
set ::QC_CORNERS {ss tt ff}

# ---- reference cells used by the generated constraints and the summary
set ::QC_NAND2    <NAND2_X1_CELL>               ;# gate-equivalent unit
set ::QC_DRV_IN   {<INPUT_DRIVER_CELL> <PIN>}   ;# driving cell of data inputs
set ::QC_DRV_CLK  {<CLOCK_DRIVER_CELL> <PIN>}   ;# driving cell of clock inputs
set ::QC_LOAD_PIN <LOAD_CELL>/<PIN>             ;# outputs see 4 x this pin's capacitance
set ::QC_DONT_USE {}                            ;# lib-cell globs no tool may use: DC and P&R / ECO (optional;
                                                ;# include the kit release note's dont_use table, e.g. EM high-drive cells)
set ::QC_HOLD_ONLY {}                           ;# globs of QC_DONT_USE that hold fixing alone may use (e.g. delay cells)
