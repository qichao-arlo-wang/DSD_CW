module task7_ci_fp32_addsub #(
    parameter int ADD_LATENCY = 1
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
    logic [31:0] b_eff;
    logic add_busy;

    // n[0] = 0 -> add, n[0] = 1 -> subtract
    always_comb begin
        b_eff = datab;
        if (n[0]) begin
            b_eff[31] = ~datab[31];
        end
    end

    task7_fp32_add_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .a(dataa),
        .b(b_eff),
        .busy(add_busy),
        .done(done),
        .result(result)
    );
endmodule
