//------------------------------------------------------------------------------
// Purpose:
//   Step-2 standalone custom-instruction module for fp32 subtraction.
//
// Notes:
//   Uses IP-backed FP subtract unit (task7_fp_sub_ip_unit) with start/done.
//------------------------------------------------------------------------------
module task7_ci_fp32_sub #(
    parameter int SUB_LATENCY = 3
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
    logic sub_busy;
    logic sub_start_gated;

    always_comb sub_start_gated = start && !sub_busy;

    task7_fp_sub_ip_unit #(
        .LATENCY(SUB_LATENCY)
    ) u_sub (
        .clk   (clk),
        .reset (reset),
        .clk_en(clk_en),
        .start (sub_start_gated),
        .a     (dataa),
        .b     (datab),
        .busy  (sub_busy),
        .done  (done),
        .result(result)
    );
endmodule
