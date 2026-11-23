# Sign-off ECO of the routed block (R56, results/r56.md): the PrimeTime change list of signoff/pt/drv_eco.tcl
# (<run>/out/eco/pt_eco.tcl, icc2tcl: size_cell / insert_buffer) on block label route -> eco.  New cells without a PT
# location are placed (place_eco_cells), then every changed cell is legalised on free sites (filler / decap cells under
# it removed), ECO-routed (route_eco, routing options of route.tcl), the emptied sites refilled (decap then FILL, as
# route.tcl), check_routes / check_lvs.  No optimisation here: the change list is the whole ECO.
source [file dirname [info script]]/common.tcl
qb_open route eco
qb_route_setup
set chg $::R/out/eco/pt_eco.tcl
set n0 [sizeof_collection [get_flat_cells]]
source $chg
set fill {}; foreach c [concat $::QC_PNR_DCAP $::QC_PNR_FILL] { lappend fill */$c }
set fill [get_lib_cells $fill]
set up [get_flat_cells -quiet -filter "physical_status==unplaced"]
qb_line "eco [file tail $chg]: cells $n0 -> [sizeof_collection [get_flat_cells]], unplaced [sizeof_collection $up]"
if {[sizeof_collection $up]} { place_eco_cells -cells $up -remove_filler_references $fill }
place_eco_cells -eco_changed_cells -legalize_only -remove_filler_references $fill
redirect -variable lg { check_legality }
qb_line "eco check_legality: [regsub -all {\s+} [join [lrange [regexp -all -inline -line {^.*(?:[Vv]iolat|succeeded|failed).*$} $lg] 0 2] { | }] { }]"
route_eco -utilize_dangling_wires true
qb_fillers
qb_route_checks eco
qb_qor eco
qb_done eco
