# PRE_PLACE_TCL of impl/r20/act.cfg: impl/r19/place.tcl (band seed around gpl + r13 place.tcl) with the band of the R20
# QB_ACT_S1T replicas added to qb19_band_of (DC names): s1t_c_reg_<k>_ -> band k / 4, selt_reg_<b>__<i>_,
# sel2t_reg_<b>__<i>_, */shqt_reg_<b>__<i>_ -> band b.
source $::QB19_DIR/place.tcl
if {[info commands qb19_band_of_r19] eq ""} { rename qb19_band_of qb19_band_of_r19 }
proc qb19_band_of {n pj} {
    if {[regexp {s1t_c_reg_(\d+)_} $n -> k]} { return [expr {$k / 4}] }
    if {[regexp {(?:selt|sel2t|shqt)_reg_(\d+)__\d+_} $n -> b]} { return $b }
    return [qb19_band_of_r19 $n $pj]
}
