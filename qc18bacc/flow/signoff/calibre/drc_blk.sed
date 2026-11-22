# R38 opt-in DRC deck switches for a BLOCK run (impl/r36/cal36.sh QB36_DRC_SED="-f drc_blk.sed"):
# no chip-corner / seal-ring rules (FULL_CHIP off), GP process on, all results kept.
s#^\#DEFINE FULL_CHIP#//\#DEFINE FULL_CHIP#
s#^//\#DEFINE GP #\#DEFINE GP #
s#^DRC MAXIMUM RESULTS 1000#DRC MAXIMUM RESULTS ALL#
