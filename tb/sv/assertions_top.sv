// SVA checker module for top.sv.
// Bound to the top module via tb/sv/bind_top.sv.
// Validated with Verilator 5.020 (make lint_sva). Not run under Icarus simulation.
//
// Assertions (8):
//   AXI A3.2.1 VALID stability — 5 properties covering every channel.
//   MAC control invariants     — done pulse width, done→busy relationship.
//
// Coverage (7):
//   AXI response types (OKAY / SLVERR on both channels).
//   MAC FSM observable events (done, busy, completion sequence).

`default_nettype none

module assertions_top (
  input logic        clk,
  input logic        rst_n,

  // AXI write channel
  input logic        s_axi_awvalid,
  input logic        s_axi_awready,
  input logic        s_axi_wvalid,
  input logic        s_axi_wready,
  input logic        s_axi_bvalid,
  input logic        s_axi_bready,
  input logic [1:0]  s_axi_bresp,

  // AXI read channel
  input logic        s_axi_arvalid,
  input logic        s_axi_arready,
  input logic        s_axi_rvalid,
  input logic        s_axi_rready,
  input logic [1:0]  s_axi_rresp,

  // Core control signals (internal nets of top, visible via bind)
  input logic        done,
  input logic        busy
);

  // -----------------------------------------------------------------------
  // AXI A3.2.1: once VALID is asserted it must not be de-asserted before
  // the handshake (VALID && READY) completes.
  // -----------------------------------------------------------------------

  property p_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axi_awvalid && !s_axi_awready) |=> s_axi_awvalid;
  endproperty
  AST_AWVALID_STABLE: assert property (p_awvalid_stable);

  property p_wvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axi_wvalid && !s_axi_wready) |=> s_axi_wvalid;
  endproperty
  AST_WVALID_STABLE: assert property (p_wvalid_stable);

  property p_bvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axi_bvalid && !s_axi_bready) |=> s_axi_bvalid;
  endproperty
  AST_BVALID_STABLE: assert property (p_bvalid_stable);

  property p_arvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axi_arvalid && !s_axi_arready) |=> s_axi_arvalid;
  endproperty
  AST_ARVALID_STABLE: assert property (p_arvalid_stable);

  property p_rvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axi_rvalid && !s_axi_rready) |=> s_axi_rvalid;
  endproperty
  AST_RVALID_STABLE: assert property (p_rvalid_stable);

  // -----------------------------------------------------------------------
  // MAC control invariants
  // -----------------------------------------------------------------------

  // done is always a single-cycle pulse (mac_array DONE state lasts 1 cycle).
  property p_done_pulse;
    @(posedge clk) disable iff (!rst_n)
    done |=> !done;
  endproperty
  AST_DONE_PULSE: assert property (p_done_pulse);

  // done is asserted only while busy (DONE state satisfies busy = state != IDLE).
  property p_done_implies_busy;
    @(posedge clk) disable iff (!rst_n)
    done |-> busy;
  endproperty
  AST_DONE_IMPLIES_BUSY: assert property (p_done_implies_busy);

  // After done, busy clears on the next cycle (DONE → IDLE transition).
  property p_busy_clears_after_done;
    @(posedge clk) disable iff (!rst_n)
    done |=> !busy;
  endproperty
  AST_BUSY_CLEARS_AFTER_DONE: assert property (p_busy_clears_after_done);

  // -----------------------------------------------------------------------
  // Functional coverage
  // -----------------------------------------------------------------------

  // AXI write response types
  COV_BRESP_OKAY:   cover property (@(posedge clk) (s_axi_bvalid && s_axi_bready && (s_axi_bresp == 2'b00)));
  COV_BRESP_SLVERR: cover property (@(posedge clk) (s_axi_bvalid && s_axi_bready && (s_axi_bresp == 2'b10)));

  // AXI read response types
  COV_RRESP_OKAY:   cover property (@(posedge clk) (s_axi_rvalid && s_axi_rready && (s_axi_rresp == 2'b00)));
  COV_RRESP_SLVERR: cover property (@(posedge clk) (s_axi_rvalid && s_axi_rready && (s_axi_rresp == 2'b10)));

  // MAC FSM observable arcs
  COV_BUSY_ASSERT:   cover property (@(posedge clk) busy);
  COV_DONE_PULSE:    cover property (@(posedge clk) done);
  COV_IDLE_REACHED:  cover property (@(posedge clk) !busy);

endmodule

`default_nettype wire
