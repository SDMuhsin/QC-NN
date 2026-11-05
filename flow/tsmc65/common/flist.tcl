# Flat file-list reader (the format of `bender script flist`, VCS -f files):
#   one token per source file; +incdir+<d>[+<d>...]; +define+<N>[=<V>][+...]; -f / -F <nested.f>;
#   // and # comments; $VAR / ${VAR} expanded from the environment.
#   Relative paths are taken relative to the directory of the .f file that names them.
#   Other options (-v, -y, +libext+, ...) are skipped with a warning.
# In a tool:  qc_flist <a.f> [<b.f> ...]  ->  dict with keys files, incdirs, defines (lists, in order, unique).
# Standalone: tclsh flist.tcl <a.f> ...    prints the same as one flat .f with absolute paths (for VCS).

proc qc_flist_expand {s} {
    regsub -all {\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?} $s {$::env(\1)} s
    return [subst -nocommands -nobackslashes $s]
}
proc qc_flist_path {dir p} {
    set p [qc_flist_expand $p]
    if {[file pathtype $p] ne "absolute"} { set p [file join $dir $p] }
    return [file normalize $p]
}
proc qc_flist_read {f dvar} {
    upvar $dvar d
    set f [file normalize $f]
    set dir [file dirname $f]
    set fh [open $f]; set text [read $fh]; close $fh
    set toks {}
    foreach line [split $text "\n"] {
        regsub {//.*$} $line {} line
        regsub {^\s*#.*$} $line {} line
        lappend toks {*}[regexp -all -inline {\S+} $line]
    }
    for {set i 0} {$i < [llength $toks]} {incr i} {
        set t [lindex $toks $i]
        if {[string match +incdir+* $t]} {
            foreach x [lrange [split $t +] 2 end] { if {$x ne ""} { lappend d(incdirs) [qc_flist_path $dir $x] } }
        } elseif {[string match +define+* $t]} {
            foreach x [lrange [split $t +] 2 end] { if {$x ne ""} { lappend d(defines) [qc_flist_expand $x] } }
        } elseif {$t eq "-f" || $t eq "-F"} {
            incr i; qc_flist_read [qc_flist_path $dir [lindex $toks $i]] d
        } elseif {[string match {[-+]*} $t]} {
            puts stderr "qc_flist: $f: skipping option $t"
            if {$t in {-v -y}} { incr i }
        } else {
            lappend d(files) [qc_flist_path $dir $t]
        }
    }
}
proc qc_flist {args} {
    array set d {files {} incdirs {} defines {}}
    foreach f $args { qc_flist_read $f d }
    return [dict create files [qc_flist_uniq $d(files)] \
                        incdirs [qc_flist_uniq $d(incdirs)] defines [qc_flist_uniq $d(defines)]]
}
proc qc_flist_uniq {l} {
    set out {}; set seen [dict create]
    foreach x $l { if {![dict exists $seen $x]} { dict set seen $x 1; lappend out $x } }
    return $out
}

if {[info exists argv0] && [file tail $argv0] eq "flist.tcl"} {
    set d [qc_flist {*}$argv]
    foreach x [dict get $d incdirs] { puts "+incdir+$x" }
    foreach x [dict get $d defines] { puts "+define+$x" }
    foreach x [dict get $d files]   { puts $x }
}
