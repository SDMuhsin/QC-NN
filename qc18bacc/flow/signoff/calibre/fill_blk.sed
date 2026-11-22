# R55 switches of the kit dummy-metal utility (Dummy_Metal_Calibre_65nm.22c) for a BLOCK (cal.sh fill, QB55_FILL_SED):
# fill up to corners of the block extent (deck note: "for cell and macro level design, turn on dmOnCorner"); M8 / M9 are
# the chip top's layers (blocks route M2-M7, the top's straps / fill go on M8 / M9), so no block fill there.
s#^//\#DEFINE dmOnCorner#\#DEFINE dmOnCorner#
s#^\#DEFINE FILL_DM\([89]\) #//\#DEFINE FILL_DM\1 #
