// Temporary hello-world module used only for Step 0 toolchain verification.
// Will be removed once mac_unit.sv is in place.
module hello (
    input  logic clk,
    output logic out
);
    always_ff @(posedge clk) out <= ~out;
endmodule
