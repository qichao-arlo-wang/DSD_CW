//------------------------------------------------------------------------------
// Purpose:
//   Task 8 custom-instruction block targeting outer-function throughput.
//
// Role In Task 8:
//   This unit accepts two fp32 inputs (x1, x2) and an operation code, computes
//   f(x) = 0.5*x + x^3*cos((x-128)/128) using Task 7 single-f(x) cores, and
//   optionally updates/returns an internal running sum.
//
// Interface Notes:
//   - Nios II CI-style start/done handshake.
//   - dataa/datab carry x1/x2.
//   - n selects operation:
//       0: pair accumulate    -> sum += f(x1)+f(x2), result=sum
//       1: reset sum          -> sum=0, result=0
//       2: read sum           -> result=sum
//       3: single A accumulate-> sum += f(x1), result=sum
//       4: single B accumulate-> sum += f(x2), result=sum
//       5: pair only          -> result=f(x1)+f(x2), sum unchanged
//       6: single A only      -> result=f(x1), sum unchanged
//       7: single B only      -> result=f(x2), sum unchanged
//
// Design Notes:
//   - Two Task7 f(x) cores are instantiated to process x1 and x2 concurrently.
//   - One shared fp32 adder IP unit is reused for pair-sum and accumulation.
//------------------------------------------------------------------------------
module task8_ci_f2_accum #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int CORDIC_ITER_PER_CYCLE = 3,
    parameter int MUL_LATENCY = 3,
    parameter int ADD_LATENCY = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_en,
    input  logic        start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    input  logic [7:0]  n,
    output logic        done,
    output logic [31:0] result
);
    localparam logic [7:0] OP_PAIR_ACCUM = 8'd0;
    localparam logic [7:0] OP_RESET_SUM = 8'd1;
    localparam logic [7:0] OP_READ_SUM = 8'd2;
    localparam logic [7:0] OP_SINGLE_A_ACCUM = 8'd3;
    localparam logic [7:0] OP_SINGLE_B_ACCUM = 8'd4;
    localparam logic [7:0] OP_PAIR_ONLY = 8'd5;
    localparam logic [7:0] OP_SINGLE_A_ONLY = 8'd6;
    localparam logic [7:0] OP_SINGLE_B_ONLY = 8'd7;

    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_SINGLE,
        S_WAIT_PAIR,
        S_WAIT_PAIR_ADD,
        S_WAIT_ACCUM_ADD,
        S_OUT
    } state_t;

    state_t state;

    logic [31:0] sum_reg;
    logic [31:0] fx_a_reg;
    logic [31:0] fx_b_reg;

    logic op_accumulate;
    logic op_single_sel_a;

    logic got_a;
    logic got_b;

    logic start_fx_a;
    logic start_fx_b;
    logic done_fx_a;
    logic done_fx_b;
    logic [31:0] result_fx_a;
    logic [31:0] result_fx_b;

    logic add_start;
    logic add_busy;
    logic add_done;
    logic [31:0] add_a;
    logic [31:0] add_b;
    logic [31:0] add_result;

    task7_ci_f_single #(
        .FX_W(FX_W),
        .FX_FRAC(FX_FRAC),
        .CORDIC_W(CORDIC_W),
        .CORDIC_FRAC(CORDIC_FRAC),
        .CORDIC_ITER(CORDIC_ITER),
        .CORDIC_ITER_PER_CYCLE(CORDIC_ITER_PER_CYCLE),
        .MUL_LATENCY(MUL_LATENCY),
        .ADD_LATENCY(ADD_LATENCY)
    ) u_fx_a (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_fx_a),
        .dataa(dataa),
        .datab(32'd0),
        .n(8'd0),
        .done(done_fx_a),
        .result(result_fx_a)
    );

    task7_ci_f_single #(
        .FX_W(FX_W),
        .FX_FRAC(FX_FRAC),
        .CORDIC_W(CORDIC_W),
        .CORDIC_FRAC(CORDIC_FRAC),
        .CORDIC_ITER(CORDIC_ITER),
        .CORDIC_ITER_PER_CYCLE(CORDIC_ITER_PER_CYCLE),
        .MUL_LATENCY(MUL_LATENCY),
        .ADD_LATENCY(ADD_LATENCY)
    ) u_fx_b (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_fx_b),
        .dataa(datab),
        .datab(32'd0),
        .n(8'd0),
        .done(done_fx_b),
        .result(result_fx_b)
    );

    task7_fp_add_ip_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(add_start),
        .a(add_a),
        .b(add_b),
        .busy(add_busy),
        .done(add_done),
        .result(add_result)
    );

    always_ff @(posedge clk or posedge reset) begin
        logic pair_ready_now;
        logic [31:0] pair_a_now;
        logic [31:0] pair_b_now;
        logic single_ready_now;
        logic [31:0] single_value_now;
        if (reset) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            result         <= 32'd0;
            sum_reg        <= 32'd0;
            fx_a_reg       <= 32'd0;
            fx_b_reg       <= 32'd0;
            op_accumulate  <= 1'b0;
            op_single_sel_a <= 1'b1;
            got_a          <= 1'b0;
            got_b          <= 1'b0;
            start_fx_a     <= 1'b0;
            start_fx_b     <= 1'b0;
            add_start      <= 1'b0;
            add_a          <= 32'd0;
            add_b          <= 32'd0;
        end else if (clk_en) begin
            done       <= 1'b0;
            start_fx_a <= 1'b0;
            start_fx_b <= 1'b0;
            add_start  <= 1'b0;

            pair_ready_now = 1'b0;
            pair_a_now = fx_a_reg;
            pair_b_now = fx_b_reg;
            single_ready_now = 1'b0;
            single_value_now = 32'd0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        case (n)
                            OP_RESET_SUM: begin
                                sum_reg <= 32'd0;
                                result  <= 32'd0;
                                state   <= S_OUT;
                            end

                            OP_READ_SUM: begin
                                result <= sum_reg;
                                state  <= S_OUT;
                            end

                            OP_SINGLE_A_ACCUM: begin
                                op_accumulate   <= 1'b1;
                                op_single_sel_a <= 1'b1;
                                start_fx_a      <= 1'b1;
                                state           <= S_WAIT_SINGLE;
                            end

                            OP_SINGLE_B_ACCUM: begin
                                op_accumulate   <= 1'b1;
                                op_single_sel_a <= 1'b0;
                                start_fx_b      <= 1'b1;
                                state           <= S_WAIT_SINGLE;
                            end

                            OP_SINGLE_A_ONLY: begin
                                op_accumulate   <= 1'b0;
                                op_single_sel_a <= 1'b1;
                                start_fx_a      <= 1'b1;
                                state           <= S_WAIT_SINGLE;
                            end

                            OP_SINGLE_B_ONLY: begin
                                op_accumulate   <= 1'b0;
                                op_single_sel_a <= 1'b0;
                                start_fx_b      <= 1'b1;
                                state           <= S_WAIT_SINGLE;
                            end

                            OP_PAIR_ONLY: begin
                                op_accumulate <= 1'b0;
                                got_a         <= 1'b0;
                                got_b         <= 1'b0;
                                start_fx_a    <= 1'b1;
                                start_fx_b    <= 1'b1;
                                state         <= S_WAIT_PAIR;
                            end

                            OP_PAIR_ACCUM: begin
                                op_accumulate <= 1'b1;
                                got_a         <= 1'b0;
                                got_b         <= 1'b0;
                                start_fx_a    <= 1'b1;
                                start_fx_b    <= 1'b1;
                                state         <= S_WAIT_PAIR;
                            end

                            default: begin
                                // Unknown opcodes fall back to "read sum" for safety.
                                result <= sum_reg;
                                state  <= S_OUT;
                            end
                        endcase
                    end
                end

                S_WAIT_SINGLE: begin
                    if (op_single_sel_a && done_fx_a) begin
                        single_ready_now = 1'b1;
                        single_value_now = result_fx_a;
                    end else if (!op_single_sel_a && done_fx_b) begin
                        single_ready_now = 1'b1;
                        single_value_now = result_fx_b;
                    end

                    if (single_ready_now) begin
                        if (op_accumulate) begin
                            add_a     <= sum_reg;
                            add_b     <= single_value_now;
                            add_start <= 1'b1;
                            state     <= S_WAIT_ACCUM_ADD;
                        end else begin
                            result <= single_value_now;
                            state  <= S_OUT;
                        end
                    end
                end

                S_WAIT_PAIR: begin
                    if (done_fx_a) begin
                        fx_a_reg <= result_fx_a;
                        got_a    <= 1'b1;
                    end
                    if (done_fx_b) begin
                        fx_b_reg <= result_fx_b;
                        got_b    <= 1'b1;
                    end

                    pair_a_now = done_fx_a ? result_fx_a : fx_a_reg;
                    pair_b_now = done_fx_b ? result_fx_b : fx_b_reg;
                    pair_ready_now = (got_a || done_fx_a) && (got_b || done_fx_b);

                    if (pair_ready_now && !add_busy) begin
                        add_a     <= pair_a_now;
                        add_b     <= pair_b_now;
                        add_start <= 1'b1;
                        state     <= S_WAIT_PAIR_ADD;
                    end
                end

                S_WAIT_PAIR_ADD: begin
                    if (add_done) begin
                        if (op_accumulate) begin
                            add_a     <= sum_reg;
                            add_b     <= add_result;
                            add_start <= 1'b1;
                            state     <= S_WAIT_ACCUM_ADD;
                        end else begin
                            result <= add_result;
                            state  <= S_OUT;
                        end
                    end
                end

                S_WAIT_ACCUM_ADD: begin
                    if (add_done) begin
                        sum_reg <= add_result;
                        result  <= add_result;
                        state   <= S_OUT;
                    end
                end

                S_OUT: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
