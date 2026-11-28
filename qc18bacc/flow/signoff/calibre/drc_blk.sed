# R38 opt-in DRC deck switches for a BLOCK run (impl/r36/cal36.sh QB36_DRC_SED="-f drc_blk.sed"):
# no chip-corner / seal-ring rules (FULL_CHIP off), GP process on.  (All results are kept: the kit deck's DRC MAXIMUM
# RESULTS ALL, which cal.sh no longer caps and cal_result requires for drc and ant, R113.)
# The results in the deck copy (signoff/calibre/cal.sh cal_deck, R109; the QB_ rule: signoff/verdict.py drc_qb_rules):
#@absent ^#DEFINE FULL_CHIP\b
#@expect ^//#DEFINE FULL_CHIP\b
#@expect ^#DEFINE GP\b
#@expect ^#DEFINE QB_BLK_DN\b
#@expect ^#IFDEF QB_BLK_DN$
#@expect ^DRC UNSELECT CHECK M8\.DN\.1$
#@expect ^DRC UNSELECT CHECK M9\.DN\.1$
s#^\#DEFINE FULL_CHIP#//\#DEFINE FULL_CHIP#
s#^//\#DEFINE GP #\#DEFINE GP #
# R77: OD.DN.1 / PO.DN.1 (OD and poly density over the layout extent, after the kit dummy OD / PO fill, cal.sh odpo) on a
# BLOCK.  The kit deck guards them with FULL_CHIP (off above); they move under QB_BLK_DN, the rest of those FULL_CHIP
# sections (DOD.EN.2 chip-edge enclosure) stays off.
s#^//\#DEFINE FULL_CHIP.*#&\n\#DEFINE QB_BLK_DN        // OD.DN.1 / PO.DN.1 on the block extent#
s#^// OD.DN.1 is checked by#\#ENDIF\n\#IFDEF QB_BLK_DN\n&#
s#^//PO.DN.1 is checked by#\#ENDIF\n\#IFDEF QB_BLK_DN\n&#
# R82 (PI decision): M8.DN.1 / M9.DN.1 (Metal8 / Metal9 local density over the layout extent) are chip-level density rules;
# the block has no M8 / M9 metal (column: routing to M7), so on a block they flag the empty window, not the design.  These two
# rules ONLY are unselected on a block (M8.DN.1.1 / M9.DN.1.1 and every other rule stay); the chip top MUST check them
# (the chip top deck).  The exclusion holds only while the block has no M8 / M9 at all: rule QB_BLK.M8M9.0 flags every
# M8 / M9 shape of every datatype this deck maps (drawn, dummy, not-use).  R84: the rule is appended at the END of the deck
# (outside every #IFDEF; its LAYER inputs are defined at depth 0), so no deck switch can drop it; cal.sh fails the drc run on
# any QB_* rule with results AND on any QB_* rule of the deck without a RULECHECK line in the summary report.
s#^DRC MAXIMUM RESULTS ALL#&\nDRC UNSELECT CHECK M8.DN.1\nDRC UNSELECT CHECK M9.DN.1#
$a\
QB_M8ANY = ((M8_OLD OR M8_NEW) OR (DUM8_OLD OR DUM8_NEW)) OR (NOUSEM8_OLD OR NOTUSEM8)\
QB_M9ANY = ((M9_OLD OR M9_NEW) OR (DUM9_OLD OR DUM9_NEW)) OR (NOUSEM9_OLD OR NOTUSEM9)\
QB_BLK.M8M9.0 { @ QB block gate: no M8 / M9 shape (M8.DN.1 / M9.DN.1 unselected on a block, checked at the chip top)\
  QB_M8ANY OR QB_M9ANY\
}
