# Kit config template (copy to site.tcl, git-ignored, and fill in every <PLACEHOLDER>).
# Sourced by common/lib.tcl in DC and PrimeTime.  Corners: ss = setup signoff, tt = typical, ff = hold.
set ::QC_KIT $::env(QC_KIT)
set ::QC_CORNERS {ss tt ff}                     ;# corners sta/run_pt.sh times by default

# ---- standard-cell timing libraries (.db): file root name and operating condition per corner
set ::QC_LIBDIR <STDCELL_DB_DIR>
array set ::QC_LIB {ss <LIB_SS> tt <LIB_TT> ff <LIB_FF>}
array set ::QC_OC  {ss <OPCOND_SS> tt <OPCOND_TT> ff <OPCOND_FF>}

# ---- wire-load mode (QC_TOPO=0): area-based wire_load_selection group of the library (empty: library default;
#      check it is not a zero model, see common/lib.tcl qc_wire_load)
set ::QC_WLM_GROUP <WLM_SELECTION_GROUP>

# ---- physical data for DC topographical mode (QC_TOPO=1)
set ::QC_TF      <TECHFILE>
set ::QC_MW_REF  <MILKYWAY_REFERENCE_LIB>
set ::QC_TLU     <TLUPLUS_DIR>
set ::QC_TLU_MAP <TLUPLUS_LAYER_MAP>
array set ::QC_TLU_FILE {ss <TLU_WORST> tt <TLU_TYPICAL> ff <TLU_BEST>}

# ---- reference cells used by the generated constraints and the summary
set ::QC_NAND2    <NAND2_X1_CELL>               ;# gate-equivalent unit
set ::QC_DRV_IN   {<INPUT_DRIVER_CELL> <PIN>}   ;# driving cell of data inputs
set ::QC_DRV_CLK  {<CLOCK_DRIVER_CELL> <PIN>}   ;# driving cell of clock inputs
set ::QC_LOAD_PIN <LOAD_CELL>/<PIN>             ;# outputs see 4 x this pin's capacitance
set ::QC_DONT_USE {}                            ;# lib-cell globs DC must not use (optional)
