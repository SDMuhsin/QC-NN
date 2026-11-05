# Overlay for snitch_cluster's target/snitch_cluster/Makefile, loaded with
#   make -f Makefile -f $(QCNN_SIM)/mk/overlay.mk ...
# Adapts the upstream flow (written for Verilator 4.110) to Verilator 5.x
# without touching the upstream sources.

# Verilator 5 parses SVA and rejects `until_with` in snitch_lsu.sv;
# upstream already disables assertions for Verilator (COMMON_CELLS_ASSERTS_OFF),
# this also covers the generic common_cells `ASSERT macros.
VLT_FLAGS += -DASSERTS_OFF
# The testbench has no timing constructs that need the V5 scheduler.
VLT_FLAGS += --no-timing
VLT_FLAGS += -Wno-MULTIDRIVEN -Wno-PINMISSING -Wno-SELRANGE
# Verilator 5 runtime needs the threads support object as well.
VLT_COBJ  += $(VLT_BUILDDIR)/vlt/verilated_threads.o
# (prerequisites of the upstream link rule were expanded before this file, so
#  add the extra object as a prerequisite explicitly)
$(BIN_DIR)/$(TARGET).vlt: $(VLT_BUILDDIR)/vlt/verilated_threads.o
