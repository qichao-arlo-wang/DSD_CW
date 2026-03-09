module task7_ci_fp32_mul #(
    parameter int MUL_LATENCY = 2
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    input  logic [7:0] n,
    output logic done,
    output logic [31:0] result
);
    logic mul_busy;

    task7_fp32_mul_unit #(
        .LATENCY(MUL_LATENCY)
    ) u_mul (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .a(dataa),
        .b(datab),
        .busy(mul_busy),
        .done(done),
        .result(result)
    );

    logic [7:0] n_unused;
    always_comb n_unused = n;
endmodule
