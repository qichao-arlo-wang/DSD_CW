//------------------------------------------------------------------------------
// Purpose:
//   Optional signed fixed-point saturating multiplier with handshake latency.
//
// Role In Task 7:
//   Auxiliary module for fixed-point design-space exploration; not used in the
//   main Step-3 CI datapath that uses shared fp32 multiply/add units.
//
// Interface Notes:
//   Start/busy/done protocol with configurable latency, fixed-point rescaling
//   by `FRAC`, and signed saturation on overflow.
//------------------------------------------------------------------------------
module task7_fx_mul_unit #(
    parameter int W = 64,
    parameter int FRAC = 34,
    parameter int LATENCY = 2
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic signed [W-1:0] a,
    input  logic signed [W-1:0] b,
    output logic busy,
    output logic done,
    output logic signed [W-1:0] result
);
    localparam int CW = (LATENCY > 1) ? $clog2(LATENCY) : 1;
    localparam logic signed [W-1:0] FX_MAX = {1'b0, {(W-1){1'b1}}};
    localparam logic signed [W-1:0] FX_MIN = {1'b1, {(W-1){1'b0}}};

    logic signed [W-1:0] a_reg, b_reg;
    logic [CW-1:0] cnt;

    function automatic logic signed [W-1:0] fx_mul_sat(
        input logic signed [W-1:0] lhs,
        input logic signed [W-1:0] rhs
    );
        logic signed [(2*W)-1:0] prod;
        logic signed [(2*W)-1:0] prod_round;
        logic signed [(2*W)-1:0] shifted;
        logic signed [(2*W)-1:0] max_ext;
        logic signed [(2*W)-1:0] min_ext;
        logic signed [(2*W)-1:0] round_const;
        begin
            prod = lhs * rhs;
            round_const = '0;

            if (FRAC > 0) begin
                round_const[FRAC-1] = 1'b1;
                if (prod >= 0) begin
                    prod_round = prod + round_const;
                end else begin
                    prod_round = prod - round_const;
                end
            end else begin
                prod_round = prod;
            end

            shifted = prod_round >>> FRAC;
            max_ext = {{W{FX_MAX[W-1]}}, FX_MAX};
            min_ext = {{W{FX_MIN[W-1]}}, FX_MIN};

            if (shifted > max_ext) begin
                fx_mul_sat = FX_MAX;
            end else if (shifted < min_ext) begin
                fx_mul_sat = FX_MIN;
            end else begin
                fx_mul_sat = shifted[W-1:0];
            end
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= '0;
            a_reg  <= '0;
            b_reg  <= '0;
            cnt    <= '0;
        end else if (clk_en) begin
            done <= 1'b0;

            if (start && !busy) begin
                a_reg <= a;
                b_reg <= b;
                busy  <= 1'b1;
                if (LATENCY <= 1) begin
                    cnt <= '0;
                end else begin
                    cnt <= CW'(LATENCY - 1);
                end
            end else if (busy) begin
                if (cnt == '0) begin
                    result <= fx_mul_sat(a_reg, b_reg);
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
endmodule
