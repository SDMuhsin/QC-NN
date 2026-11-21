# R45: impl/r38/reroute38.tcl (full re-route of a block copy) with impl/r45/lef57db45.tcl applied to the loaded tech
# right before its global_route (so DRT sees min-step + EOL spacing).  Run via impl/r29/or29.sh <tag> rr45.tcl <log>;
# env R45_RR38 = path of reroute38.tcl, R45_FIXTCL = path of lef57db45.tcl (R45_NOFIX 1: plain reroute38 = control).
rename global_route r45_global_route_orig
proc global_route {args} {
    if {![info exists ::env(R45_NOFIX)] || !$::env(R45_NOFIX)} { source $::env(R45_FIXTCL) }
    uplevel 1 [list r45_global_route_orig {*}$args]
}
source $::env(R45_RR38)
