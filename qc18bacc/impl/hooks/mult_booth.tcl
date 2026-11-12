# variant (d): force Booth (radix-4) partial-product encoding for the datapath multipliers
if {[catch {set_dp_smartgen_options -booth_encoding true} e]} { puts "QBS_HOOK_ERR $e" } else { puts "QBS_HOOK booth_encoding true" }
