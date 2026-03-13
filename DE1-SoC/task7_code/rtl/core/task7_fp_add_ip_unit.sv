//------------------------------------------------------------------------------
// Purpose:
//   FP add execution unit for Task 7 control FSMs.
//
// Notes:
// - Default path is synthesis/IP-compatible (safe for Quartus Analysis & Synthesis).
// - Define TASK7_FORCE_SIM only for pure RTL simulation without external FP IP.
//------------------------------------------------------------------------------
module task7_fp_add_ip_unit #(
    parameter int LATENCY = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_en,
    input  logic        start,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    localparam int EFF_LATENCY = (LATENCY < 1) ? 1 : LATENCY;
    localparam int CNT_W = (EFF_LATENCY <= 1) ? 1 : $clog2(EFF_LATENCY);
    localparam logic [CNT_W-1:0] CNT_INIT = CNT_W'(EFF_LATENCY - 1);

    logic [CNT_W-1:0] cnt;

`ifndef TASK7_FORCE_SIM
`define TASK7_USE_SYNTH_IMPL
`endif

`ifdef TASK7_USE_SYNTH_IMPL
    logic [31:0] a_reg;
    logic [31:0] b_reg;
    logic [31:0] ip_result;

    custom_fp_add u_ip (
        .clk   (clk),
        .areset(reset),
        .a     (a_reg),
        .b     (b_reg),
        .q     (ip_result)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 32'd0;
            cnt    <= '0;
            a_reg  <= 32'd0;
            b_reg  <= 32'd0;
        end else if (clk_en) begin
            done <= 1'b0;

            if (start && !busy) begin
                a_reg <= a;
                b_reg <= b;
                busy  <= 1'b1;
                cnt   <= CNT_INIT;
            end else if (busy) begin
                if (cnt == 0) begin
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    result <= ip_result;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
`else
    logic [31:0] pending_result;

    function automatic logic [31:0] fp_add_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r + b_r;
            fp_add_model = $shortrealtobits(y_r);
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy           <= 1'b0;
            done           <= 1'b0;
            result         <= 32'd0;
            pending_result <= 32'd0;
            cnt            <= '0;
        end else if (clk_en) begin
            done <= 1'b0;

            if (start && !busy) begin
                busy           <= 1'b1;
                cnt            <= CNT_INIT;
                pending_result <= fp_add_model(a, b);
            end else if (busy) begin
                if (cnt == 0) begin
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    result <= pending_result;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
`endif

`ifdef TASK7_USE_SYNTH_IMPL
`undef TASK7_USE_SYNTH_IMPL
`endif
endmodule
