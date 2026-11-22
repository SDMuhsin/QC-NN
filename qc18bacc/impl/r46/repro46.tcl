# R46 minimal repro of the repair_antennas crash mechanism (results/r46.md), no design data: kit tech LEF only.
# One net, one dbWire built exactly as grt::RepairAntennas::addWireTerms builds it for a global-route wire on M1 that
# ends on an M1 pin while the min routing layer is M2: newPath(M1) + addTechVia(default via of M2 = VIA23_1cut).
# dbWireEncoder::addTechVia finds the current layer (M1) is neither the via's top nor bottom layer; its ZASSERT is
# compiled out, so it encodes TECH_VIA with via id 0.  Decoding that id gives a via without a bbox, and
# any shape walk of the wire (odb::orderWires in repair_antennas / check_antennas, dbWire::getLength here) dereferences the null bbox -> SIGSEGV in odb::_dbBox::isOct.
# R46_CASE bad [default] | good (via VIA12_1cut, whose bottom layer is M1: legal encoding, no crash).
# Usage: R46_LEF=<tech lef> openroad -exit repro46.tcl
read_lef $::env(R46_LEF)
set db [ord::get_db]; set tech [$db getTech]
set chip [odb::dbChip_create $db]
set block [odb::dbBlock_create $chip top]
$block setDieArea [odb::Rect x 0 0 20000 20000]
set net [odb::dbNet_create $block n1]
set case [expr {[info exists ::env(R46_CASE)] ? $::env(R46_CASE) : "bad"}]
set via [$tech findVia [expr {$case eq "good" ? "VIA12_1cut" : "VIA23_1cut"}]]
set wire [odb::dbWire_create $net]
set enc [odb::dbWireEncoder]
$enc begin $wire
$enc newPath [$tech findLayer M1] ROUTED
$enc addPoint 1000 1000
$enc addPoint 5000 1000
$enc addTechVia $via
$enc end
set dec [odb::dbWireDecoder]
$dec begin $wire
for {set op [$dec next]} {$op != 12} {set op [$dec next]} {
    if {$op == 7} { set v [$dec getTechVia]
        set nm [expr {[catch {$v getName} e] ? "<getName fails: $e>" : $e}]
        puts "R46_REPRO case $case encoded via [$via getName] -> decoded TECH_VIA $v name $nm bbox [$v getBBox]" }
}
set ops {}; for {set k 0} {$k < [$wire length]} {incr k} { lappend ops [format "%d:0x%02x/%d" $k [$wire getOpcode $k] [$wire getData $k]] }
puts "R46_REPRO case $case raw ops (index:opcode/operand; the tech-via operand is the via id) $ops"
puts "R46_REPRO case $case wire shape walk (dbWire::getLength -> dbWireShapeItr, as orderWires walks it) ..."
puts "R46_REPRO case $case survived, length [$wire getLength]"
