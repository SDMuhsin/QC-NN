// Placeholder for the Infineon S27KS0641 HyperRAM model (download no longer available from
// infineon.com without login). Our tests run from the memory island and never touch HyperRAM;
// this stub only satisfies chimera's testbench. Bus pins are left floating (high-Z).
module s27ks0641 #(
  parameter UserPreload   = 0,
  parameter mem_file_name = "none",
  parameter TimingModel   = "S27KS0641DPBHI020"
) (
  inout wire DQ7, DQ6, DQ5, DQ4, DQ3, DQ2, DQ1, DQ0,
  inout wire RWDS,
  input wire CSNeg, CK, CKNeg, RESETNeg
);
endmodule
