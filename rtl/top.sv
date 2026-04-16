`default_nettype none

// Top-level: wires axi_slave to mac_array.
// soft_reset (CTRL.bit1 pulse) extends rst_n to mac_array only; axi_slave keeps
// its register state so the AXI master can read STATUS after a soft reset.

module top
  import types_pkg::*;
#(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input  logic                      clk,
  input  logic                      rst_n,

  input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr,
  input  logic [2:0]                s_axi_awprot,
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,
  input  logic [DATA_WIDTH-1:0]     s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0]   s_axi_wstrb,
  input  logic                      s_axi_wvalid,
  output logic                      s_axi_wready,
  output logic [1:0]                s_axi_bresp,
  output logic                      s_axi_bvalid,
  input  logic                      s_axi_bready,
  input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
  input  logic [2:0]                s_axi_arprot,
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,
  output logic [DATA_WIDTH-1:0]     s_axi_rdata,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready
);

  logic        start_pulse, soft_reset;
  logic        busy, done;
  logic [255:0] a_flat, b_flat;
  logic [511:0] c_flat;

  // soft_reset pulses mac_array's reset without disturbing axi_slave registers.
  logic rst_n_core;
  assign rst_n_core = rst_n & ~soft_reset;

  axi_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) u_axi (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awprot   (s_axi_awprot),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awready  (s_axi_awready),
    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wready   (s_axi_wready),
    .s_axi_bresp    (s_axi_bresp),
    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bready   (s_axi_bready),
    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arprot   (s_axi_arprot),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_arready  (s_axi_arready),
    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rready   (s_axi_rready),
    .start_pulse    (start_pulse),
    .soft_reset     (soft_reset),
    .busy           (busy),
    .done           (done),
    .a_flat         (a_flat),
    .b_flat         (b_flat),
    .c_flat         (c_flat)
  );

  mac_array u_mac (
    .clk    (clk),
    .rst_n  (rst_n_core),
    .start  (start_pulse),
    .done   (done),
    .busy   (busy),
    .a_flat (a_flat),
    .b_flat (b_flat),
    .c_flat (c_flat)
  );

endmodule

`default_nettype wire
