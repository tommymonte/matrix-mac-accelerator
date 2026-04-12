// Shared Q8.8 fixed-point types for the matrix-MAC accelerator.
package types_pkg;
  parameter int Q_FRAC = 8;
  typedef logic signed [(2*Q_FRAC)-1:0] q8_8_t;
  typedef logic signed [(4*Q_FRAC)-1:0] mac_acc_t;
endpackage
