//------------------------------------------------------------------------------
// Purpose:
//   Stateful Task-8 custom instruction front-end for the streaming pipeline
//   reduction core.
//
// Interface Summary:
//   This wrapper keeps the fully pipelined datapath of Task 8 inside hardware,
//   while exposing a Nios-II custom-instruction control protocol through `n`.
//
// Opcode map (`n`):
//   0: INIT        dataa = frame length, clears previous status and starts frame.
//   1: PUSH_X      dataa = fp32 sample x, accepted only while core reports ready.
//   2: GET_RESULT  blocks until the current frame completes, then returns F(X).
//   3: GET_STATUS  immediate status word:
//                    bit0 busy, bit1 in_ready, bit2 frame_done_latched,
//                    bit3 core_error_latched, bit4 protocol_error_latched.
//   4: GET_ACCEPTED  immediate accepted sample count.
//   5: GET_FX_COUNT  immediate number of produced f(x) samples.
//   6: GET_REDUCED   immediate reduction count.
//
// Notes:
//   - `datab` is kept for CI compatibility and is not used by this wrapper.
//   - `GET_RESULT` is the only blocking operation; all others respond quickly.
//   - Protocol misuse (for example PUSH without INIT) sets a sticky protocol
//     error flag that is cleared by the next INIT.
//------------------------------------------------------------------------------
module task8_ci_fsum_pipe #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int MUL_LATENCY = 3,
    parameter int ADD_LATENCY = 3,
    parameter int MUL_LANES = MUL_LATENCY + 3,
    parameter int ADD_LANES = ADD_LATENCY + 3,
    parameter int X3_FIFO_DEPTH = 32
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
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;
    localparam logic [7:0] OP_GET_STATUS   = 8'd3;
    localparam logic [7:0] OP_GET_ACCEPTED = 8'd4;
    localparam logic [7:0] OP_GET_FX_COUNT = 8'd5;
    localparam logic [7:0] OP_GET_REDUCED  = 8'd6;

    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_FRAME_DONE,
        S_RESPOND
    } state_t;

    state_t state;

    logic        start_q;
    logic        start_evt;
    logic [31:0] cmd_result;

    logic        core_start;
    logic [31:0] core_len;
    logic        core_in_valid;
    logic [31:0] core_in_data;
    logic        core_in_ready;
    logic        core_busy;
    logic        core_done;
    logic [31:0] core_result;
    logic [31:0] core_accepted_count;
    logic [31:0] core_fx_count;
    logic [31:0] core_reduced_count;
    logic        core_error;

    logic        frame_done_latched;
    logic [31:0] frame_result_latched;
    logic        core_error_latched;
    logic        protocol_error_latched;

    function automatic [31:0] status_word(
        input logic busy_i,
        input logic ready_i,
        input logic frame_done_i,
        input logic core_err_i,
        input logic protocol_err_i
    );
        begin
            status_word = 32'd0;
            status_word[0] = busy_i;
            status_word[1] = ready_i;
            status_word[2] = frame_done_i;
            status_word[3] = core_err_i;
            status_word[4] = protocol_err_i;
        end
    endfunction

    assign start_evt = start & ~start_q;

    task8_pipe_fsum_core #(
        .FX_W(FX_W),
        .FX_FRAC(FX_FRAC),
        .CORDIC_W(CORDIC_W),
        .CORDIC_FRAC(CORDIC_FRAC),
        .CORDIC_ITER(CORDIC_ITER),
        .MUL_LATENCY(MUL_LATENCY),
        .ADD_LATENCY(ADD_LATENCY),
        .MUL_LANES(MUL_LANES),
        .ADD_LANES(ADD_LANES),
        .X3_FIFO_DEPTH(X3_FIFO_DEPTH)
    ) u_core (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(core_start),
        .len(core_len),
        .in_valid(core_in_valid),
        .in_data(core_in_data),
        .in_ready(core_in_ready),
        .busy(core_busy),
        .done(core_done),
        .result(core_result),
        .accepted_count(core_accepted_count),
        .fx_count(core_fx_count),
        .reduced_count(core_reduced_count),
        .error(core_error)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state                  <= S_IDLE;
            start_q                <= 1'b0;
            done                   <= 1'b0;
            result                 <= 32'd0;
            cmd_result             <= 32'd0;
            core_start             <= 1'b0;
            core_len               <= 32'd0;
            core_in_valid          <= 1'b0;
            core_in_data           <= 32'd0;
            frame_done_latched     <= 1'b0;
            frame_result_latched   <= 32'd0;
            core_error_latched     <= 1'b0;
            protocol_error_latched <= 1'b0;
        end else if (clk_en) begin
            start_q       <= start;
            done          <= 1'b0;
            core_start    <= 1'b0;
            core_in_valid <= 1'b0;

            if (core_done) begin
                frame_done_latched   <= 1'b1;
                frame_result_latched <= core_result;
            end
            if (core_error) begin
                core_error_latched <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    if (start_evt) begin
                        unique case (n)
                            OP_INIT: begin
                                if (core_busy) begin
                                    protocol_error_latched <= 1'b1;
                                    cmd_result             <= status_word(core_busy,
                                                                           core_in_ready,
                                                                           frame_done_latched,
                                                                           core_error_latched,
                                                                           1'b1);
                                end else begin
                                    core_len               <= dataa;
                                    core_start             <= 1'b1;
                                    frame_done_latched     <= 1'b0;
                                    frame_result_latched   <= 32'd0;
                                    core_error_latched     <= 1'b0;
                                    protocol_error_latched <= 1'b0;
                                    cmd_result             <= 32'd0;
                                end
                                state <= S_RESPOND;
                            end

                            OP_PUSH_X: begin
                                if (core_busy && core_in_ready) begin
                                    core_in_data  <= dataa;
                                    core_in_valid <= 1'b1;
                                    cmd_result    <= 32'd0;
                                end else begin
                                    protocol_error_latched <= 1'b1;
                                    cmd_result             <= status_word(core_busy,
                                                                           core_in_ready,
                                                                           frame_done_latched,
                                                                           core_error_latched,
                                                                           1'b1);
                                end
                                state <= S_RESPOND;
                            end

                            OP_GET_RESULT: begin
                                if (frame_done_latched) begin
                                    cmd_result <= frame_result_latched;
                                    state      <= S_RESPOND;
                                end else if (core_busy) begin
                                    state <= S_WAIT_FRAME_DONE;
                                end else begin
                                    protocol_error_latched <= 1'b1;
                                    cmd_result             <= 32'd0;
                                    state                  <= S_RESPOND;
                                end
                            end

                            OP_GET_STATUS: begin
                                cmd_result <= status_word(core_busy,
                                                          core_in_ready,
                                                          frame_done_latched,
                                                          core_error_latched,
                                                          protocol_error_latched);
                                state <= S_RESPOND;
                            end

                            OP_GET_ACCEPTED: begin
                                cmd_result <= core_accepted_count;
                                state      <= S_RESPOND;
                            end

                            OP_GET_FX_COUNT: begin
                                cmd_result <= core_fx_count;
                                state      <= S_RESPOND;
                            end

                            OP_GET_REDUCED: begin
                                cmd_result <= core_reduced_count;
                                state      <= S_RESPOND;
                            end

                            default: begin
                                protocol_error_latched <= 1'b1;
                                cmd_result             <= 32'hBAD0_00FF;
                                state                  <= S_RESPOND;
                            end
                        endcase
                    end
                end

                S_WAIT_FRAME_DONE: begin
                    if (frame_done_latched) begin
                        cmd_result <= frame_result_latched;
                        state      <= S_RESPOND;
                    end
                end

                S_RESPOND: begin
                    done   <= 1'b1;
                    result <= cmd_result;
                    state  <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    /* verilator lint_off UNUSED */
    logic [31:0] datab_unused;
    always_comb begin
        datab_unused = datab;
    end
    /* verilator lint_on UNUSED */
endmodule
