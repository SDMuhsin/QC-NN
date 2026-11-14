# QC_POST_HOOK of impl/r4/run.sh: write the RTL -> gate SAIF name map for PrimeTime PX (QB_SAIF_MAP=1).
if {[qc_env QB_SAIF_MAP 0]} {
    saif_map -type ptpx -essential -write_map $::env(QC_OUT)/saif_map.ptpx
    puts "QB_SAIF_MAP written"
}
