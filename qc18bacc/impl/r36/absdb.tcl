# R36: exact abstract LEF of a block db (stand-alone, no run dir): R36_ODB -> R36_LEF (write_abstract_lef -bloat_factor 0).
read_db $::env(R36_ODB)
write_abstract_lef -bloat_factor 0 $::env(R36_LEF)
puts "R36_ABSDB [ord::get_db_block] -> $::env(R36_LEF)"
exit
