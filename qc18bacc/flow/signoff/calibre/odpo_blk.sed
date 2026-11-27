# R77 switches of the kit dummy OD / PO utility (CLN65GP autofill_OD_PO = TN65CLDR001C2_V2.2B/Dummy_OD_PO_Calibre_65nm.22b) for a
# BLOCK (cal.sh odpo, QB77_ODPO_SED; the chip window xLB / yLB / xRT / yRT = the block's DEF DIEAREA, set by the caller,
# blocks/col/run.sh fill).  Kit (deck header and 3_UserGuide.txt section 5): "For cell and macro level design, please turn on
# "dmOnCorner" to insert dummy on corner"; cell-level note 1: "Cell boundary: turn on option "ChipWindowUsed" to define cell
# boundary or use whole layout extent" (UseprBoundary is no option here: every standard cell carries the prBoundary layer
# 108;0, R77 [M] 0 dummies).  No TCD patterns (FILL_TCD_PATTERN: drawn OD / PO / PP / NP + TCDDMY test structures for the
# chip, declared at tape-out; a block adds none).  Dummies keep 0.6 um to the window edge (dod2Chip, DOD.EN.2 / DPO.EN.1).
# The results in the deck copy (signoff/calibre/cal.sh cal_deck, R109):
#@expect ^#DEFINE ChipWindowUsed\b
#@expect ^#DEFINE dmOnCorner\b
#@absent ^#DEFINE FILL_TCD_PATTERN\b
#@expect ^//#DEFINE FILL_TCD_PATTERN\b
s#^//\#DEFINE ChipWindowUsed#\#DEFINE ChipWindowUsed#
s#^//\#DEFINE dmOnCorner#\#DEFINE dmOnCorner#
s#^\#DEFINE FILL_TCD_PATTERN#//\#DEFINE FILL_TCD_PATTERN#
