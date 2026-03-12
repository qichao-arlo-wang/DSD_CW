//------------------------------------------------------------------------------
// Purpose:
//   Step-2 standalone custom-instruction module for fp32 multiplication.
//
// Notes:
//   Uses IP-backed FP multiply unit (task7_fp_mul_ip_unit) with start/done.
//------------------------------------------------------------------------------
module task7_ci_fp32_mul #(
    parameter int MUL_LATENCY = 2
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_en,
    input  logic        start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    output logic        done,
    output logic [31:0] result
);
    logic mul_busy;
    logic mul_start_gated;

    always_comb mul_start_gated = start && !mul_busy;

    task7_fp_mul_ip_unit #(
        .LATENCY(MUL_LATENCY)
    ) u_mul (
        .clk   (clk),
        .reset (reset),
        .clk_en(clk_en),
        .start (mul_start_gated),
        .a     (dataa),
        .b     (datab),
        .busy  (mul_busy),
        .done  (done),
        .result(result)
    );
endmodule
