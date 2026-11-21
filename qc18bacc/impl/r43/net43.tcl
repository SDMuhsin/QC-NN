# R43 probe: terminals (inst master/pin, dont_touch) of the nets in R43_NETS on db R43_DB [grt] (read_db only).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
read_db $::OUT/db/[qc_env R43_DB grt].odb
set b [ord::get_db_block]
foreach nn [qc_env R43_NETS ""] {
    set n [$b findNet $nn]; if {$n eq "NULL"} { puts "R43_NET $nn missing"; continue }
    puts "R43_NET $nn dont_touch [$n isDoNotTouch] bterms [llength [$n getBTerms]]"
    foreach t [$n getITerms] { set i [$t getInst]; puts "R43_TERM $nn [$i getName] [[$i getMaster] getName]/[[$t getMTerm] getName] io [$t getIoType] inst_dt [$i isDoNotTouch] status [$i getPlacementStatus]" }
}
