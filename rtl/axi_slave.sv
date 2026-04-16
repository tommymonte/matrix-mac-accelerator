`default_nettype none

// AXI4-Lite slave for the 4×4 Q8.8 MAC accelerator.
//
// Register map (byte-addressed, 32-bit words)
// -------------------------------------------
//   0x00  CTRL   (RW)  bit0 = start (write-1-to-pulse, self-clearing)
//                      bit1 = soft_reset (write-1-to-pulse, self-clearing)
//   0x04  STATUS (RO)  bit0 = busy
//                      bit1 = done  (sticky; cleared by writing 1 to STATUS.done,
//                                    or implicitly when a new start is accepted)
//   0x10..0x4C  A[0..15]  (RW)  matrix A, row-major  (only low 16 bits used, Q8.8)
//   0x50..0x8C  B[0..15]  (RW)  matrix B, row-major
//   0x90..0xCC  C[0..15]  (RO)  matrix C, row-major  (32-bit accumulators)
//
//   Any other address → AXI response SLVERR.
//   Write to RO region (C) → SLVERR, register file unchanged.
//
// AXI4-Lite conformance
// ---------------------
//   - Data width 32, address width 8 (covers 0x00..0xCC).
//   - Write transactions require both AW and W to be valid before the slave
//     accepts. The handshake uses a two-state FSM per direction.
//   - VALID asserted by the slave remains high until READY is observed
//     (AXI rule A3.2.1).
//   - Read response RRESP and write response BRESP use 2'b00 (OKAY) or 2'b10
//     (SLVERR). DECERR is not used.

module axi_slave
  import types_pkg::*;
#(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // ---- AXI4-Lite ----
  // Write address
  input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [2:0]              s_axi_awprot,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                    s_axi_awvalid,
  output logic                    s_axi_awready,
  // Write data
  input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                    s_axi_wvalid,
  output logic                    s_axi_wready,
  // Write response
  output logic [1:0]              s_axi_bresp,
  output logic                    s_axi_bvalid,
  input  logic                    s_axi_bready,
  // Read address
  input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [2:0]              s_axi_arprot,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                    s_axi_arvalid,
  output logic                    s_axi_arready,
  // Read data
  output logic [DATA_WIDTH-1:0]   s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  output logic                    s_axi_rvalid,
  input  logic                    s_axi_rready,

  // ---- Core-facing ports (wired to mac_array in Step 4) ----
  output logic                    start_pulse,
  output logic                    soft_reset,
  input  logic                    busy,
  input  logic                    done,          // one-cycle pulse from mac_array
  output logic [255:0]            a_flat,        // 16 × q8_8_t
  output logic [255:0]            b_flat,        // 16 × q8_8_t
  input  logic [511:0]            c_flat         // 16 × mac_acc_t  (RO)
);

  // -------------------------------------------------------------------------
  // AXI response codes
  // -------------------------------------------------------------------------
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  // -------------------------------------------------------------------------
  // Register storage
  // -------------------------------------------------------------------------
  // Matrices live as 16 × 32-bit registers each so that 32-bit AXI writes map
  // 1:1 even though only the low 16 bits are meaningful (sign-extended on read
  // via stored value). Unpacking to flat buses happens combinationally.
  logic [31:0] reg_a [0:15];
  logic [31:0] reg_b [0:15];

  logic status_done_q;   // sticky done

  // -------------------------------------------------------------------------
  // Address decode helpers
  // -------------------------------------------------------------------------
  // Word-aligned check: low 2 bits of address must be 00.
  // Accepted address ranges: 0x00, 0x04, 0x10..0x4C, 0x50..0x8C, 0x90..0xCC.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic is_aligned(input logic [ADDR_WIDTH-1:0] a);
    return a[1:0] == 2'b00;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic logic is_ctrl  (input logic [ADDR_WIDTH-1:0] a); return a == 8'h00; endfunction
  function automatic logic is_status(input logic [ADDR_WIDTH-1:0] a); return a == 8'h04; endfunction
  function automatic logic is_a_reg (input logic [ADDR_WIDTH-1:0] a); return (a >= 8'h10) && (a <= 8'h4C); endfunction
  function automatic logic is_b_reg (input logic [ADDR_WIDTH-1:0] a); return (a >= 8'h50) && (a <= 8'h8C); endfunction
  function automatic logic is_c_reg (input logic [ADDR_WIDTH-1:0] a); return (a >= 8'h90) && (a <= 8'hCC); endfunction

  function automatic logic write_ok(input logic [ADDR_WIDTH-1:0] a);
    return is_aligned(a) && (is_ctrl(a) || is_status(a) || is_a_reg(a) || is_b_reg(a));
  endfunction

  function automatic logic read_ok(input logic [ADDR_WIDTH-1:0] a);
    return is_aligned(a) && (is_ctrl(a) || is_status(a) || is_a_reg(a) || is_b_reg(a) || is_c_reg(a));
  endfunction

  // Matrix index from byte address within a region (4-byte stride).
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [3:0] idx_from(input logic [ADDR_WIDTH-1:0] a,
                                          input logic [ADDR_WIDTH-1:0] base);
    logic [ADDR_WIDTH-1:0] diff;
    diff = (a - base) >> 2;
    return diff[3:0];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // -------------------------------------------------------------------------
  // Write channel FSM
  // -------------------------------------------------------------------------
  // States:
  //   W_IDLE  : awready = wready = 1. Wait for both AWVALID and WVALID.
  //             On simultaneous handshake, latch addr/data and go to W_RESP.
  //   W_RESP  : bvalid = 1 with captured bresp. Wait for bready, return to IDLE.
  typedef enum logic [0:0] { W_IDLE, W_RESP } w_state_t;
  w_state_t                    w_state_q, w_state_d;
  logic [1:0]                  bresp_q;

  logic aw_hs, w_hs;
  assign aw_hs = s_axi_awvalid && s_axi_awready;
  assign w_hs  = s_axi_wvalid  && s_axi_wready;

  // Combinational next-state / handshake drives
  always_comb begin
    w_state_d     = w_state_q;
    s_axi_awready = 1'b0;
    s_axi_wready  = 1'b0;
    s_axi_bvalid  = 1'b0;
    s_axi_bresp   = bresp_q;

    case (w_state_q)
      W_IDLE: begin
        // Accept AW and W together (atomic) to keep FSM minimal.
        s_axi_awready = s_axi_awvalid && s_axi_wvalid;
        s_axi_wready  = s_axi_awvalid && s_axi_wvalid;
        if (aw_hs && w_hs) w_state_d = W_RESP;
      end
      W_RESP: begin
        s_axi_bvalid = 1'b1;
        if (s_axi_bready) w_state_d = W_IDLE;
      end
      default: w_state_d = W_IDLE;
    endcase
  end

  // -------------------------------------------------------------------------
  // Read channel FSM
  // -------------------------------------------------------------------------
  typedef enum logic [0:0] { R_IDLE, R_RESP } r_state_t;
  r_state_t                    r_state_q, r_state_d;
  logic [DATA_WIDTH-1:0]       rdata_q;
  logic [1:0]                  rresp_q;

  logic ar_hs;
  assign ar_hs = s_axi_arvalid && s_axi_arready;

  always_comb begin
    r_state_d     = r_state_q;
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    s_axi_rdata   = rdata_q;
    s_axi_rresp   = rresp_q;

    case (r_state_q)
      R_IDLE: begin
        s_axi_arready = 1'b1;
        if (ar_hs) r_state_d = R_RESP;
      end
      R_RESP: begin
        s_axi_rvalid = 1'b1;
        if (s_axi_rready) r_state_d = R_IDLE;
      end
      default: r_state_d = R_IDLE;
    endcase
  end

  // -------------------------------------------------------------------------
  // Sequential: state, register file, CTRL pulses, sticky done
  // -------------------------------------------------------------------------
  logic                       write_commit;       // this cycle accepts a write
  logic [ADDR_WIDTH-1:0]      wcommit_addr;
  logic [DATA_WIDTH-1:0]      wcommit_data;
  logic                       wcommit_ok;

  assign write_commit  = (w_state_q == W_IDLE) && aw_hs && w_hs;
  assign wcommit_addr  = s_axi_awaddr;
  assign wcommit_data  = s_axi_wdata;
  assign wcommit_ok    = write_ok(wcommit_addr);

  // STATUS read value
  logic [DATA_WIDTH-1:0] status_word;
  assign status_word = {30'b0, status_done_q, busy};

  // Read data MUX for C region
  logic [DATA_WIDTH-1:0] c_word;
  logic [3:0]            c_idx;
  assign c_idx  = idx_from(s_axi_araddr, 8'h90);
  assign c_word = c_flat[32*c_idx +: 32];

  // Read data MUX for A/B
  logic [3:0] a_idx, b_idx;
  assign a_idx = idx_from(s_axi_araddr, 8'h10);
  assign b_idx = idx_from(s_axi_araddr, 8'h50);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_state_q     <= W_IDLE;
      r_state_q     <= R_IDLE;
      bresp_q       <= RESP_OKAY;
      rdata_q       <= '0;
      rresp_q       <= RESP_OKAY;
      start_pulse   <= 1'b0;
      soft_reset    <= 1'b0;
      status_done_q <= 1'b0;
      for (int i = 0; i < 16; i++) begin
        reg_a[i] <= 32'd0;
        reg_b[i] <= 32'd0;
      end
    end else begin
      w_state_q   <= w_state_d;
      r_state_q   <= r_state_d;

      // CTRL pulses default low each cycle (1-cycle pulse behavior)
      start_pulse <= 1'b0;
      soft_reset  <= 1'b0;

      // Sticky done latch: set on mac_array done pulse
      if (done) status_done_q <= 1'b1;

      // ---- Write commit ----
      if (write_commit) begin
        if (!wcommit_ok) begin
          bresp_q <= RESP_SLVERR;
        end else begin
          bresp_q <= RESP_OKAY;
          if (is_ctrl(wcommit_addr)) begin
            start_pulse <= wcommit_data[0];
            soft_reset  <= wcommit_data[1];
            // Starting a new run clears the sticky done flag.
            if (wcommit_data[0]) status_done_q <= 1'b0;
          end else if (is_status(wcommit_addr)) begin
            // Write-1-to-clear on STATUS.done (bit 1). busy is RO.
            if (wcommit_data[1]) status_done_q <= 1'b0;
          end else if (is_a_reg(wcommit_addr)) begin
            reg_a[idx_from(wcommit_addr, 8'h10)] <= wcommit_data;
          end else if (is_b_reg(wcommit_addr)) begin
            reg_b[idx_from(wcommit_addr, 8'h50)] <= wcommit_data;
          end
        end
      end

      // ---- Read commit ----
      if ((r_state_q == R_IDLE) && ar_hs) begin
        if (!read_ok(s_axi_araddr)) begin
          rdata_q <= 32'hDEAD_BEEF;
          rresp_q <= RESP_SLVERR;
        end else begin
          rresp_q <= RESP_OKAY;
          if      (is_ctrl  (s_axi_araddr)) rdata_q <= 32'd0;          // CTRL self-clears
          else if (is_status(s_axi_araddr)) rdata_q <= status_word;
          else if (is_a_reg (s_axi_araddr)) rdata_q <= reg_a[a_idx];
          else if (is_b_reg (s_axi_araddr)) rdata_q <= reg_b[b_idx];
          else if (is_c_reg (s_axi_araddr)) rdata_q <= c_word;
          else                              rdata_q <= 32'h0;
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Unpack register files to flat output buses (low 16 bits = Q8.8 operand)
  // -------------------------------------------------------------------------
  genvar gi;
  generate
    for (gi = 0; gi < 16; gi++) begin : g_flat
      assign a_flat[16*gi +: 16] = reg_a[gi][15:0];
      assign b_flat[16*gi +: 16] = reg_b[gi][15:0];
    end
  endgenerate

endmodule

`default_nettype wire
