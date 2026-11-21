# R38 (read-only on the db): DEF + power-pin Verilog of a db into R38's own dir, for Calibre A/B tests.
#   QB38_DB=<odb> QB38_OUT=<dir> QB38_TOP=<name> openroad -no_init -exit dbexport.tcl
read_db $::env(QB38_DB)
file mkdir $::env(QB38_OUT)
write_def $::env(QB38_OUT)/$::env(QB38_TOP).def
write_verilog -include_pwr_gnd $::env(QB38_OUT)/$::env(QB38_TOP)_pg.v
puts "DBEXPORT done"
