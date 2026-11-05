// Smoke-test package: operand / accumulator types.
`include "mac8_pkg.svh"
package mac8_pkg;
  typedef logic signed [7:0]              op_t;
  typedef logic signed [`MAC8_ACC_W-1:0] acc_t;
endpackage
