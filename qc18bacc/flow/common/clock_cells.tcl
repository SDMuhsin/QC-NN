# Clock-tree lib-cell globs (R75), sourced by flow/icc2/common.tcl and signoff/pt/drv_eco.tcl after site/pnr.tcl: the CTS
# buffers QC_PNR_CTS_BUF, the CKND* inverters and the CKLNQD* clock gates.  ICC2 CTS uses only these (icc2/cts.tcl), and
# so does the sign-off ECO in the clock network (drv_eco.tcl qb_eco_drc: r75 eco 1 without the restriction sized a
# clock inverter to INVD8 [M]).
proc qb_clock_cells {} { return [concat $::QC_PNR_CTS_BUF {CKND* CKLNQD*}] }
