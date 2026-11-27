# R55 switches of the kit dummy-metal utility (Dummy_Metal_Calibre_65nm.22c) for a BLOCK (cal.sh fill, QB55_FILL_SED):
# fill up to corners of the block extent (deck note: "for cell and macro level design, turn on dmOnCorner"); M8 / M9 are
# the chip top's layers (blocks route M2-M7, the top's straps / fill go on M8 / M9), so no block fill there.
# R99: the fill extent is the chip window xLB / yLB / xRT / yRT = the block's DEF DIEAREA (set by the caller, common/block.sh
# blk_fill_label die_window.sed, as odpo_blk.sed), not the drawn extent of the layout ([M] rgr: y 4.76 .. 124.04 of 130 um).
# The results in the deck copy (signoff/calibre/cal.sh cal_deck, R109):
#@expect ^#DEFINE dmOnCorner\b
#@expect ^#DEFINE ChipWindowUsed\b
#@absent ^#DEFINE FILL_DM[89]\b
#@expect ^//#DEFINE FILL_DM8\b
#@expect ^//#DEFINE FILL_DM9\b
s#^//\#DEFINE dmOnCorner#\#DEFINE dmOnCorner#
s#^//\#DEFINE ChipWindowUsed#\#DEFINE ChipWindowUsed#
s#^\#DEFINE FILL_DM\([89]\) #//\#DEFINE FILL_DM\1 #
