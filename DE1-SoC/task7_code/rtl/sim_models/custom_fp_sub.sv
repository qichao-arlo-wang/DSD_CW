//------------------------------------------------------------------------------
// Purpose:
//   Simulation-only model for Intel FP subtract IP (module name compatibility).
//
// Notes:
//   - Module name matches Task 7 wrappers: custom_fp_sub.
//   - One-cycle registered output model.
//------------------------------------------------------------------------------
`include "custom_fp_utils.svh"

module custom_fp_sub (
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            q <= 32'd0;
        end else begin
            q <= task7_real_to_fp32(task7_fp32_to_real(a) - task7_fp32_to_real(b));
        end
    end
endmodule
