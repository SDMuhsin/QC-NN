# variant (d): non-Booth (AND-array) partial products for the datapath multipliers
if {[catch {set_dp_smartgen_options -booth_encoding false} e]} { puts "QBS_HOOK_ERR $e" } else { puts "QBS_HOOK booth_encoding false" }
