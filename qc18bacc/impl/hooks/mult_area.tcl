# variant (d): datapath generator optimised for area
if {[catch {set_dp_smartgen_options -optimize_for area} e]} { puts "QBS_HOOK_ERR $e" } else { puts "QBS_HOOK optimize_for area" }
