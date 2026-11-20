# R33: where do the data buffers of the gated-clock subtree come from? per db: does each instance exist, its master, the
# net it drives and the driver chain up to a non-buffer
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
qc_read_liberty
foreach db $::env(R33_DBS) {
  read_db $::OUT/db/$db.odb
  set blk [ord::get_db_block]
  foreach n {wire6 max_length12 wire11 wire10 u_top_g_wbc_hoy_reg_0_} {
    set i [$blk findInst $n]
    if {$i eq "NULL"} { puts "R33K $db $n absent"; continue }
    set ci [lindex [lmap it [$i getITerms] {expr {[$it isInputSignal] || [[$it getMTerm] getSigType] eq "CLOCK" ? $it : [continue]}}] 0]
    set desc ""
    foreach it [$i getITerms] { set nn [$it getNet]; if {$nn eq "NULL"} continue; append desc " [[$it getMTerm] getName]=[$nn getName]([$nn getSigType])" }
    puts "R33K $db $n [[$i getMaster] getName] $desc"
  }
  [ord::get_db] clear
}
exit
