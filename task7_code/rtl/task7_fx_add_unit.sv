module task7_fx_add_unit #(
    parameter int W = 64,
    parameter int LATENCY = 1
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

    function automatic logic signed [W-1:0] fx_add_sat(
        input logic signed [W-1:0] lhs,
        input logic signed [W-1:0] rhs
    );
        logic signed [W:0] sum_ext;
        begin
            sum_ext = $signed({lhs[W-1], lhs}) + $signed({rhs[W-1], rhs});
            if (sum_ext > $signed({FX_MAX[W-1], FX_MAX})) begin
                fx_add_sat = FX_MAX;
            end else if (sum_ext < $signed({FX_MIN[W-1], FX_MIN})) begin
                fx_add_sat = FX_MIN;
            end else begin
                fx_add_sat = sum_ext[W-1:0];
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
                    result <= fx_add_sat(a_reg, b_reg);
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
endmodule
