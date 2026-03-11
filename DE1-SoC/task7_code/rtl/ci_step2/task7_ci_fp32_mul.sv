//------------------------------------------------------------------------------
// Purpose:
//   Step-2 standalone custom-instruction module for fp32 multiplication.
//
// Role In Task 7:
//   Exposes the shared fp32 multiplier as an independent CI block for Step-2
//   validation and benchmarking before final Step-3 fusion.
//
// Interface Notes:
//   Uses Nios II CI-style start/done handshake.
//   Computes `result = dataa * datab` in IEEE-754 single precision.
//------------------------------------------------------------------------------
module task7_ci_fp32_mul #(
    parameter int MUL_LATENCY = 2
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    output logic done,
    output logic [31:0] result
);
    logic mul_busy;
    logic mul_start_gated;

    always_comb mul_start_gated = start && !mul_busy;

    task7_fp32_mul_unit #(
        .LATENCY(MUL_LATENCY)
    ) u_mul (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(mul_start_gated),
        .a(dataa),
        .b(datab),
        .busy(mul_busy),
        .done(done),
        .result(result)
    );
endmodule

