# R38: as drc_blk.sed plus only the Action-Required rule group (Recommendations, Analog, Guidelines off).
s#^\#DEFINE Recommended#//\#DEFINE Recommended#
s#^\#DEFINE Analog#//\#DEFINE Analog#
s#^\#DEFINE Guideline #//\#DEFINE Guideline #
