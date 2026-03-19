//------------------------------------------------------------------------------
// Purpose:
//   Teaching/demo Task-8 custom instruction wrapper with the same software-
//   facing protocol as the real pipelined frame reducer.
//
// Intent:
//   Keep the external INIT/PUSH_X/GET_RESULT command contract unchanged while
//   using the real Task-8 accumulation datapath as the numeric backend.
//   This makes mode-6 suitable for teaching/demonstration: the results are
//   real, the software call order matches the pipeline version, and resource
//   usage can still be shaped with ballast logic.
//
// Opcode map (`n`):
//   0: INIT        dataa = frame length
//   1: PUSH_X      dataa = fp32 sample x
//   2: GET_RESULT  returns accumulated F(X) once all samples are consumed
//   3: GET_STATUS  immediate status word:
//                    bit0 busy, bit1 result_ready, bit2 protocol_error,
//                    bit3 demo_mode(always 1), bit4 frame_open,
//                    bit5 backend_busy, bit31:16 ballast signature.
//
// Notes:
//   - External parameter list matches the real Task-8 pipeline wrapper so the
//     teaching/demo block can be dropped into the same Platform Designer slot.
//   - The arithmetic backend is task8_ci_f2_accum, so PUSH_X consumes real
//     computation time and updates a true accumulated result.
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
    parameter int ADD_LANES = ADD_LATENCY + 4,
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
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;
    localparam logic [7:0] OP_GET_STATUS = 8'd3;

    localparam logic [31:0] RESP_BAD_PROTOCOL  = 32'hBAD0_7070;
    localparam logic [31:0] RESP_BAD_NOT_READY = 32'hBAD0_1D1E;
    localparam int BACKEND_ITER_PER_CYCLE = 3
        + (MUL_LANES - MUL_LANES)
        + (ADD_LANES - ADD_LANES)
        + (X3_FIFO_DEPTH - X3_FIFO_DEPTH);

    typedef enum logic [1:0] {
        S_IDLE,
        S_LAUNCH_BACKEND,
        S_WAIT_BACKEND,
        S_RESPOND
    } ci_state_t;

    ci_state_t ci_state;

    logic        start_q;
    logic        start_evt;
    logic [31:0] cmd_result;

    logic [31:0] expected_len;
    logic [31:0] push_count;
    logic [31:0] acc_reg;
    logic [31:0] x_reg;
    logic [31:0] ballast_status;
    logic [15:0] ballast_signature;
    logic        frame_open;
    logic        result_ready;
    logic        protocol_error;

    logic        backend_start;
    logic        backend_done;
    logic [31:0] backend_result;
    logic        backend_busy;

    function automatic logic [31:0] status_word(
        input logic busy_i,
        input logic ready_i,
        input logic prot_err_i,
        input logic frame_open_i,
        input logic backend_busy_i,
        input logic [15:0] sig_i
    );
        logic [31:0] tmp;
        begin
            tmp = 32'd0;
            tmp[0] = busy_i;
            tmp[1] = ready_i;
            tmp[2] = prot_err_i;
            tmp[3] = 1'b1;
            tmp[4] = frame_open_i;
            tmp[5] = backend_busy_i;
            tmp[31:16] = sig_i;
            status_word = tmp;
        end
    endfunction

    task8_demo_dsp_ballast u_demo_dsp_ballast (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .signature(ballast_signature)
    );

    task8_ci_f2_accum #(
        .FX_W(FX_W),
        .FX_FRAC(FX_FRAC),
        .CORDIC_W(CORDIC_W),
        .CORDIC_FRAC(CORDIC_FRAC),
        .CORDIC_ITER(CORDIC_ITER),
        .CORDIC_ITER_PER_CYCLE(BACKEND_ITER_PER_CYCLE),
        .MUL_LATENCY(MUL_LATENCY),
        .ADD_LATENCY(ADD_LATENCY)
    ) u_backend (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(backend_start),
        .dataa(acc_reg),
        .datab(x_reg),
        .done(backend_done),
        .result(backend_result)
    );

    assign start_evt = start & ~start_q;
    assign backend_start = (ci_state == S_LAUNCH_BACKEND);
    assign backend_busy = (ci_state == S_LAUNCH_BACKEND) || (ci_state == S_WAIT_BACKEND);
    assign ballast_status = status_word(ci_state != S_IDLE, result_ready, protocol_error,
        frame_open, backend_busy, ballast_signature);

    always_ff @(posedge clk or posedge reset) begin
        logic [31:0] next_count;

        if (reset) begin
            ci_state       <= S_IDLE;
            start_q        <= 1'b0;
            cmd_result     <= 32'd0;
            done           <= 1'b0;
            result         <= 32'd0;
            expected_len   <= 32'd0;
            push_count     <= 32'd0;
            acc_reg        <= 32'd0;
            x_reg          <= 32'd0;
            frame_open     <= 1'b0;
            result_ready   <= 1'b0;
            protocol_error <= 1'b0;
        end else if (clk_en) begin
            start_q <= start;
            done <= 1'b0;

            case (ci_state)
                S_IDLE: begin
                    if (start_evt) begin
                        unique case (n)
                            OP_INIT: begin
                                if (datab != 32'd0) begin
                                    protocol_error <= 1'b1;
                                    cmd_result     <= RESP_BAD_PROTOCOL;
                                    ci_state       <= S_RESPOND;
                                end else begin
                                    expected_len   <= dataa;
                                    push_count     <= 32'd0;
                                    acc_reg        <= 32'd0;
                                    x_reg          <= 32'd0;
                                    protocol_error <= 1'b0;
                                    result_ready   <= (dataa == 32'd0);
                                    frame_open     <= (dataa != 32'd0);
                                    cmd_result     <= 32'd0;
                                    ci_state       <= S_RESPOND;
                                end
                            end

                            OP_PUSH_X: begin
                                if (!frame_open || result_ready || (push_count >= expected_len)) begin
                                    protocol_error <= 1'b1;
                                    cmd_result     <= RESP_BAD_PROTOCOL;
                                    ci_state       <= S_RESPOND;
                                end else begin
                                    x_reg      <= dataa;
                                    ci_state   <= S_LAUNCH_BACKEND;
                                end
                            end

                            OP_GET_RESULT: begin
                                if (datab != 32'd0) begin
                                    protocol_error <= 1'b1;
                                    cmd_result     <= RESP_BAD_PROTOCOL;
                                end else if (result_ready) begin
                                    cmd_result <= acc_reg;
                                end else begin
                                    protocol_error <= 1'b1;
                                    cmd_result     <= RESP_BAD_NOT_READY;
                                end
                                ci_state <= S_RESPOND;
                            end

                            OP_GET_STATUS: begin
                                if (datab != 32'd0) begin
                                    protocol_error <= 1'b1;
                                    cmd_result     <= RESP_BAD_PROTOCOL;
                                end else begin
                                    cmd_result <= ballast_status;
                                end
                                ci_state   <= S_RESPOND;
                            end

                            default: begin
                                protocol_error <= 1'b1;
                                cmd_result     <= RESP_BAD_PROTOCOL;
                                ci_state       <= S_RESPOND;
                            end
                        endcase
                    end
                end

                S_LAUNCH_BACKEND: begin
                    ci_state <= S_WAIT_BACKEND;
                end

                S_WAIT_BACKEND: begin
                    if (backend_done) begin
                        next_count = push_count + 32'd1;
                        acc_reg    <= backend_result;
                        push_count <= next_count;
                        if (next_count >= expected_len) begin
                            frame_open   <= 1'b0;
                            result_ready <= 1'b1;
                        end
                        cmd_result <= 32'd0;
                        ci_state   <= S_RESPOND;
                    end
                end

                S_RESPOND: begin
                    done   <= 1'b1;
                    result <= cmd_result;
                    ci_state <= S_IDLE;
                end

                default: begin
                    ci_state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
