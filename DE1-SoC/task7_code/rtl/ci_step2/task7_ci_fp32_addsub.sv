//------------------------------------------------------------------------------
// Purpose:
//   Step-2 standalone custom-instruction module for fp32 add/sub arithmetic.
//
// Role In Task 7:
//   Wraps the shared fp32 adder unit so software can call add/sub as an
//   independent accelerator before full Step-3 integration.
//
// Interface Notes:
//   Uses Nios II CI-style start/done handshake.
//   `n = 0` selects add, `n = 1` selects subtract.
//------------------------------------------------------------------------------
module task7_ci_fp32_addsub #(
    parameter int ADD_LATENCY = 1
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    input  logic        n,
    output logic done,
    output logic [31:0] result
);
    logic [31:0] b_eff;
    logic add_busy;
    logic add_start_gated;

    // n = 0 -> add, n = 1 -> subtract
    always_comb begin
        b_eff = datab;
        if (n) begin
            b_eff[31] = ~datab[31];
        end
        add_start_gated = start && !add_busy;
    end

    task7_fp32_add_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(add_start_gated),
        .a(dataa),
        .b(b_eff),
        .busy(add_busy),
        .done(done),
        .result(result)
    );
endmodule


