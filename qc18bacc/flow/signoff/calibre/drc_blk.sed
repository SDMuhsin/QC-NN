# R38 opt-in DRC deck switches for a BLOCK run (impl/r36/cal36.sh QB36_DRC_SED="-f drc_blk.sed"):
# no chip-corner / seal-ring rules (FULL_CHIP off), GP process on, all results kept.
s#^\#DEFINE FULL_CHIP#//\#DEFINE FULL_CHIP#
s#^//\#DEFINE GP #\#DEFINE GP #
s#^DRC MAXIMUM RESULTS 1000#DRC MAXIMUM RESULTS ALL#
# R77: OD.DN.1 / PO.DN.1 (OD and poly density over the layout extent, after the kit dummy OD / PO fill, cal.sh odpo) on a
# BLOCK.  The kit deck guards them with FULL_CHIP (off above); they move under QB_BLK_DN, the rest of those FULL_CHIP
# sections (DOD.EN.2 chip-edge enclosure) stays off.
s#^//\#DEFINE FULL_CHIP.*#&\n\#DEFINE QB_BLK_DN        // OD.DN.1 / PO.DN.1 on the block extent#
s#^// OD.DN.1 is checked by#\#ENDIF\n\#IFDEF QB_BLK_DN\n&#
s#^//PO.DN.1 is checked by#\#ENDIF\n\#IFDEF QB_BLK_DN\n&#
