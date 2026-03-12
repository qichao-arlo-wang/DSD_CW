//------------------------------------------------------------------------------
// Purpose:
//   Step-2 standalone custom-instruction module for fp32 addition.
//
// Notes:
//   Uses IP-backed FP add unit (task7_fp_add_ip_unit) with start/done.
//------------------------------------------------------------------------------
module task7_ci_fp32_add #(
    parameter int ADD_LATENCY = 2
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
    logic add_busy;
    logic add_start_gated;

    always_comb add_start_gated = start && !add_busy;

    task7_fp_add_ip_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk   (clk),
        .reset (reset),
        .clk_en(clk_en),
        .start (add_start_gated),
        .a     (dataa),
        .b     (datab),
        .busy  (add_busy),
        .done  (done),
        .result(result)
    );
endmodule