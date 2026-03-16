//------------------------------------------------------------------------------
// Purpose:
//   FP multiply execution unit for Task 7/8 control logic.
//
// Design note:
//   The vendor FP IP samples registered operands and updates `q` on a clock
//   edge. Another always_ff block cannot safely consume that new `q` value on
//   the same edge, so this wrapper waits an extra cycle, captures `q`, then
//   asserts `done` one cycle later.
//------------------------------------------------------------------------------
module task7_fp_mul_ip_unit #(
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
    localparam int WAIT_CYCLES = EFF_LATENCY + 1;
    localparam int CNT_W = (WAIT_CYCLES <= 1) ? 1 : $clog2(WAIT_CYCLES + 1);

    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT,
        S_CAPTURE,
        S_OUT
    } state_t;

    state_t state;
    logic [CNT_W-1:0] cnt;
    logic [31:0] a_reg;
    logic [31:0] b_reg;
    logic [31:0] capture_value;
    logic        op_clk_en;

`ifndef TASK7_FORCE_SIM
`define TASK7_USE_SYNTH_IMPL
`endif

`ifdef TASK7_USE_SYNTH_IMPL
    logic [31:0] ip_result;

    custom_fp_mul u_ip (
        .clk   (clk),
        .areset(reset),
        .a     (a_reg),
        .b     (b_reg),
        .q     (ip_result)
    );

    always_comb begin
        capture_value = ip_result;
    end
`else
    logic [31:0] pending_result;

    function automatic logic [31:0] fp_mul_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r * b_r;
            fp_mul_model = $shortrealtobits(y_r);
        end
    endfunction

    always_comb begin
        capture_value = pending_result;
    end
`endif

    assign op_clk_en = clk_en || (state != S_IDLE);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state  <= S_IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 32'd0;
            cnt    <= '0;
            a_reg  <= 32'd0;
            b_reg  <= 32'd0;
`ifndef TASK7_FORCE_SIM
`else
            pending_result <= 32'd0;
`endif
        end else if (op_clk_en) begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start && clk_en) begin
                        a_reg <= a;
                        b_reg <= b;
`ifndef TASK7_FORCE_SIM
`else
                        pending_result <= fp_mul_model(a, b);
`endif
                        cnt   <= CNT_W'(WAIT_CYCLES - 1);
                        busy  <= 1'b1;
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    busy <= 1'b1;
                    if (cnt == 0) begin
                        state <= S_CAPTURE;
                    end else begin
                        cnt <= cnt - CNT_W'(1);
                    end
                end

                S_CAPTURE: begin
                    busy   <= 1'b1;
                    result <= capture_value;
                    state  <= S_OUT;
                end

                S_OUT: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

`ifdef TASK7_USE_SYNTH_IMPL
`undef TASK7_USE_SYNTH_IMPL
`endif
endmodule
