// Binds assertions_top into the top module scope so the SVA checker can
// observe all ports and internal nets of top without modifying RTL.

bind top assertions_top u_assert (
  .clk            (clk),
  .rst_n          (rst_n),
  .s_axi_awvalid  (s_axi_awvalid),
  .s_axi_awready  (s_axi_awready),
  .s_axi_wvalid   (s_axi_wvalid),
  .s_axi_wready   (s_axi_wready),
  .s_axi_bvalid   (s_axi_bvalid),
  .s_axi_bready   (s_axi_bready),
  .s_axi_bresp    (s_axi_bresp),
  .s_axi_arvalid  (s_axi_arvalid),
  .s_axi_arready  (s_axi_arready),
  .s_axi_rvalid   (s_axi_rvalid),
  .s_axi_rready   (s_axi_rready),
  .s_axi_rresp    (s_axi_rresp),
  .done           (done),
  .busy           (busy)
);
