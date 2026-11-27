# Case-sensitive LVS of a block (LAYOUT / SOURCE CASE YES after the kit deck's LVS ISOLATE SHORTS YES); the results in the
# deck copy (signoff/calibre/cal.sh cal_deck, R109):
#@expect ^LAYOUT CASE YES$
#@expect ^SOURCE CASE YES$
#@absent ^(LAYOUT|SOURCE) CASE NO\b
/^LVS ISOLATE SHORTS YES/a\
LAYOUT CASE YES\
SOURCE CASE YES
