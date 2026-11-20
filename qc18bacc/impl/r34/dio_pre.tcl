# R34 dio hook (impl/r29/dio29.tcl R29_PDN, via impl/r31/run31.sh R31_PDN; results/r34.md): the two antenna fixes in one
# pass: impl/r29/pdn29.tcl (macro M4 straps trimmed off the signal pins, R29) then impl/r31/buf31.tcl (BUFFD2 at every
# macro input on a net with pin HPWL > R31_BHPWL [300] um, R31).  (Paths from QC_FLOW: [info script] is relative here.)
set _r34i [file normalize $::env(QC_FLOW)/../../qc18bacc/impl]
source $_r34i/r29/pdn29.tcl
source $_r34i/r31/buf31.tcl
