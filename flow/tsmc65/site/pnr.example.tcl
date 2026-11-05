# P&R kit config for flow/tsmc65/pnr (OpenROAD).  Copy to pnr.tcl (git-ignored) and replace every <PLACEHOLDER>.
# Sourced after site.tcl, so ::QC_KIT, ::QC_CORNERS, ::QC_LIBDIR and ::QC_LIB(<corner>) are known.
# Liberty: OpenROAD reads text liberty, <QC_PNR_LIBDIR>/<QC_LIB(corner)><QC_PNR_LIBEXT> (same libraries as DC).
set ::QC_PNR_LIBDIR $::QC_LIBDIR
set ::QC_PNR_LIBEXT .lib
# technology + standard-cell LEF (metal stack must match the TLU+ / captables, here 9 metals)
set ::QC_PNR_LEF    $::QC_KIT/<TECH_CELL_LEF>
# captable per corner (RC derivation, see pnr/py/captable_rc.py)
set ::QC_PNR_CAPDIR $::QC_KIT/<CAPTABLE_DIR>
array set ::QC_PNR_CAPTABLE {ss <CWORST>.captable tt <TYPICAL>.captable ff <CBEST>.captable}
# GDS of the standard cells and the Virtuoso layer map (drawing / pin purposes) for the optional GDS merge
set ::QC_PNR_GDS    $::QC_KIT/<CELL_GDS>
set ::QC_PNR_GDSMAP $::QC_KIT/<VIRTUOSO_LAYER_MAP>
# library cells
set ::QC_PNR_SITE      core
set ::QC_PNR_PWR       VDD
set ::QC_PNR_GND       VSS
set ::QC_PNR_TIEHI     {TIEH Z}
set ::QC_PNR_TIELO     {TIEL ZN}
set ::QC_PNR_TAPCELL   {}                     ;# empty: cells are tapless (well ties inside every cell)
set ::QC_PNR_DCAP      {DCAP64 DCAP32 DCAP16 DCAP8 DCAP4}
set ::QC_PNR_FILL      {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set ::QC_PNR_DIODE     {ANTENNA I}
set ::QC_PNR_CTS_BUF   {CKBD4 CKBD8 CKBD12 CKBD16}
set ::QC_PNR_CTS_ROOT  CKBD16
set ::QC_PNR_DONT_USE  {*D0 DEL* G* LVL* ISO* CKLHQ* OD18*}
# routing / power layers
set ::QC_PNR_MIN_LAYER M2
set ::QC_PNR_MAX_LAYER M7
set ::QC_PNR_PIN_H     M3
set ::QC_PNR_PIN_V     M4
set ::QC_PNR_RAIL      M1                     ;# followpin layer of the cell rails
set ::QC_PNR_EST_SIGNAL M3                    ;# layers for pre-route RC estimates (set_wire_rc)
set ::QC_PNR_EST_CLOCK  M5
# layers whose MINIMUMCUT rules are dropped from the router's copy of the LEF (single-cut pin access, see
# pnr/py/lef_pnr.py); empty: the kit LEF is used as is
set ::QC_PNR_LEF_NO_MINCUT {M1}
