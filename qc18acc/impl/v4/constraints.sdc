# Constraints of QC18-ACC v4 (QA_V=4 in impl/run.sh): the shared constraints.sdc (QA_SDC_BASE) plus the v4 hold rule
# (ARCH.md v4 addendum "Hold"): every input pin of the weight / param macros (A, D, CEN, WEN; driven directly by the
# qa_bankmem4 input flops, which also launch the host write data) gets a minimum delay of QA_MACRO_MIN ns (default
# 0.4) from its launching flop, so synthesis builds the hold margin that the post-route hold ECO needs against a late
# macro clock (v3 routed: -0.39 / -0.46 ns tt at the weight-macro D pins, results/pnr_v3.md).
source $::env(QA_SDC_BASE)
set qa_min [qc_env QA_MACRO_MIN 0.4]
set qa_wp [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name=~qa_wgt_* || ref_name=~qa_par_*)"]
if {[sizeof_collection $qa_wp] && $qa_min > 0} {
    set qa_pins [get_pins -quiet -of_objects $qa_wp -filter "direction==in"]
    set qa_pins [filter_collection $qa_pins "lib_pin_name=~A* || lib_pin_name=~D* || lib_pin_name==CEN || lib_pin_name=~WEN*"]
    set_min_delay $qa_min -to $qa_pins
    puts "QA_MACRO_MIN $qa_min ns on [sizeof_collection $qa_pins] weight / param macro input pins"
}
