# R38: the hub DEF has no VDD / VSS PINS (its PG pins exist only in the abstract LEF), so the layout PG nets carry no
# port text.  Name them by a point on a hub M4 PG stripe (DEF SPECIALNETS: VDD x 1770400, VSS x 1790400, y 49120-260020
# in 2000-dbu units = um 885.2 / 895.2, 24.56-130.01); text layer 134 = M4.  Use after lvs_hub.sed.
/^LVS ISOLATE SHORTS YES/a\
LAYOUT TEXT "VDD" 885.2 60.0 134 qb_hub\
LAYOUT TEXT "VSS" 895.2 60.0 134 qb_hub
