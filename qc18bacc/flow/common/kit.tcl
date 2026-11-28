# Kit files the flow reads by a path it derives from the site facts (sourced after flow/tsmc65 common/lib.tcl, i.e.
# site.tcl): one proc per file, used by its reader and by common/env.sh qb_kit_files (the role table of the kit files'
# provenance, R117; round-17 finding: the antenna rule file was read by ICC2 and in no record).
# qb_antenna_rule_file: the Milkyway antenna rule file of the tech file's metal stack, <QC_MW>/clf/antennaRule_n65_<n>lm.tcl
# (<n>lm from the tech file's name; icc2/common.tcl qb_antenna_rules); error when the name has no <n>lm
proc qb_antenna_rule_file {} {
    set nm [regexp -inline {[0-9]+lm} [file tail $::QC_TF]]
    if {$nm eq ""} { error "qb_antenna_rule_file: no <n>lm metal stack in the tech file name [file tail $::QC_TF]" }
    return $::QC_MW/clf/antennaRule_n65_$nm.tcl
}
