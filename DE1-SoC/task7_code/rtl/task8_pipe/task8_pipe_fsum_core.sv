//------------------------------------------------------------------------------
// Purpose:
//   Fully pipelined Task 8 reduction core without MM/DMA wrapper.
//
// Interface Contract:
//   - `start` begins a new frame of `len` fp32 samples.
//   - While `busy`, the core accepts one fp32 sample per cycle on
//     `in_valid/in_data`.
//   - After all samples are reduced, `done` pulses and `result` holds F(X).
//
// Design Summary:
//   - x^2 / x^3 / term / final f(x) addition use multi-lane round-robin fp32
//     stages to sustain one input per cycle.
//   - cosine uses a fully pipelined CORDIC engine.
//   - final reduction uses interleaved partial sums.
//------------------------------------------------------------------------------
module task8_pipe_fsum_core #(
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
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] len,
    input  logic in_valid,
    input  logic [31:0] in_data,
    output logic in_ready,
    output logic busy,
    output logic done,
    output logic [31:0] result,
    output logic [31:0] accepted_count,
    output logic [31:0] fx_count,
    output logic [31:0] reduced_count,
    output logic error
);
    localparam logic signed [FX_W-1:0] CONST_128 =
        $signed({{(FX_W-8){1'b0}}, 8'd128}) <<< FX_FRAC;
    localparam logic signed [FX_W-1:0] ONE_ANGLE =
        $signed({{(FX_W-1){1'b0}}, 1'b1}) <<< FX_FRAC;
    localparam int FIFO_PTR_W = (X3_FIFO_DEPTH <= 1) ? 1 : $clog2(X3_FIFO_DEPTH);
    localparam logic [FIFO_PTR_W:0] X3_FIFO_DEPTH_W = X3_FIFO_DEPTH[FIFO_PTR_W:0];

    typedef enum logic [1:0] {
        S_IDLE,
        S_RUN,
        S_WAIT_DONE,
        S_ZERO_DONE
    } state_t;

    state_t state;
    logic [31:0] frame_len;

    logic signed [FX_W-1:0] x_fx_wire;
    logic signed [CORDIC_W-1:0] angle_cordic_wire;
    logic signed [CORDIC_W-1:0] angle_cordic_reg;
    logic [31:0] half_x_wire;

    logic        cordic_in_valid;
    logic        cos_valid;
    logic signed [CORDIC_W-1:0] cos_fx;
    logic [31:0] cos_fp;

    logic        x2_valid;
    logic [31:0] x2_value;
    logic [63:0] x2_side;
    logic        x2_error;

    logic        x3_valid;
    logic [31:0] x3_value;
    logic [31:0] x3_side;
    logic        x3_error;

    logic [63:0] x3_fifo_mem [0:X3_FIFO_DEPTH-1];
    logic [FIFO_PTR_W-1:0] x3_wr_ptr;
    logic [FIFO_PTR_W-1:0] x3_rd_ptr;
    logic [FIFO_PTR_W:0]   x3_count;
    logic [63:0] x3_head;
    logic        x3_push;
    logic        x3_pop;

    logic        term_valid;
    logic [31:0] term_value;
    logic [31:0] term_side;
    logic        term_error;

    logic        fx_valid;
    logic [31:0] fx_value;
    logic [0:0]  fx_side_unused;
    logic        fx_error;

    logic        acc_start;
    logic [31:0] acc_total_len;
    logic        acc_done;
    logic [31:0] acc_sum;
    logic [31:0] acc_reduced;
    logic        acc_error;

    function automatic logic signed [CORDIC_W-1:0] angle_to_cordic(
        input logic signed [FX_W-1:0] x_in
    );
        logic signed [FX_W-1:0] angle_fx;
        logic signed [CORDIC_W-1:0] clamped;
        begin
            angle_fx = (x_in - CONST_128) >>> 7;
            if (angle_fx > ONE_ANGLE) begin
                clamped = ONE_ANGLE[CORDIC_W-1:0];
            end else if (angle_fx < -ONE_ANGLE) begin
                clamped = -$signed(ONE_ANGLE[CORDIC_W-1:0]);
            end else begin
                clamped = angle_fx[CORDIC_W-1:0];
            end
            angle_to_cordic = clamped;
        end
    endfunction

    function automatic [31:0] fp32_mul_half(input logic [31:0] x);
        logic sign;
        logic [7:0] exp;
        logic [22:0] frac;
        logic [23:0] mant24;
        logic [23:0] half24;
        logic [22:0] frac_half;
        begin
            sign = x[31];
            exp  = x[30:23];
            frac = x[22:0];

            if ((exp == 8'hFF) || ((exp == 8'd0) && (frac == 23'd0))) begin
                fp32_mul_half = x;
            end else if (exp > 8'd1) begin
                fp32_mul_half = {sign, exp - 8'd1, frac};
            end else if (exp == 8'd1) begin
                mant24 = {1'b1, frac};
                half24 = {1'b0, mant24[23:1]};
                if (mant24[0] && half24[0]) begin
                    half24 = half24 + 1'b1;
                end
                if (half24[23]) begin
                    fp32_mul_half = {sign, 8'd1, 23'd0};
                end else begin
                    fp32_mul_half = {sign, 8'd0, half24[22:0]};
                end
            end else begin
                frac_half = {1'b0, frac[22:1]};
                if (frac[0] && frac_half[0]) begin
                    frac_half = frac_half + 1'b1;
                end
                fp32_mul_half = {sign, 8'd0, frac_half};
            end
        end
    endfunction

    task7_fp32_to_fx #(
        .W(FX_W),
        .FRAC(FX_FRAC)
    ) u_in_conv (
        .fp_in(in_data),
        .fx_out(x_fx_wire)
    );

    assign angle_cordic_wire = angle_to_cordic(x_fx_wire);
    assign half_x_wire = fp32_mul_half(in_data);

    task8_cordic_cos_pipe #(
        .W(CORDIC_W),
        .FRAC(CORDIC_FRAC),
        .N_ITER(CORDIC_ITER)
    ) u_cordic_pipe (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .in_valid(cordic_in_valid),
        .angle_in(angle_cordic_reg),
        .out_valid(cos_valid),
        .cos_out(cos_fx)
    );

    task7_fx_to_fp32 #(
        .W(FX_W),
        .FRAC(FX_FRAC)
    ) u_cos_to_fp (
        .fx_in({{(FX_W-CORDIC_W){cos_fx[CORDIC_W-1]}}, cos_fx}),
        .fp_out(cos_fp)
    );

    task8_fp_mul_rr_stage #(
        .LATENCY(MUL_LATENCY),
        .LANES(MUL_LANES),
        .SIDE_W(64)
    ) u_x2_stage (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .in_valid((state == S_RUN) && in_valid && in_ready),
        .in_a(in_data),
        .in_b(in_data),
        .in_side({half_x_wire, in_data}),
        .out_valid(x2_valid),
        .out_result(x2_value),
        .out_side(x2_side),
        .error(x2_error)
    );

    task8_fp_mul_rr_stage #(
        .LATENCY(MUL_LATENCY),
        .LANES(MUL_LANES),
        .SIDE_W(32)
    ) u_x3_stage (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .in_valid(x2_valid),
        .in_a(x2_value),
        .in_b(x2_side[31:0]),
        .in_side(x2_side[63:32]),
        .out_valid(x3_valid),
        .out_result(x3_value),
        .out_side(x3_side),
        .error(x3_error)
    );

    assign x3_head = x3_fifo_mem[x3_rd_ptr];
    assign x3_push = x3_valid;
    assign x3_pop  = cos_valid && (x3_count != 0);

    task8_fp_mul_rr_stage #(
        .LATENCY(MUL_LATENCY),
        .LANES(MUL_LANES),
        .SIDE_W(32)
    ) u_term_stage (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .in_valid(x3_pop),
        .in_a(x3_head[63:32]),
        .in_b(cos_fp),
        .in_side(x3_head[31:0]),
        .out_valid(term_valid),
        .out_result(term_value),
        .out_side(term_side),
        .error(term_error)
    );

    task8_fp_add_rr_stage #(
        .LATENCY(ADD_LATENCY),
        .LANES(ADD_LANES),
        .SIDE_W(1)
    ) u_fx_stage (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .in_valid(term_valid),
        .in_a(term_value),
        .in_b(term_side),
        .in_side(1'b0),
        .out_valid(fx_valid),
        .out_result(fx_value),
        .out_side(fx_side_unused),
        .error(fx_error)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    task8_fp_accum_interleaved #(
        .ADD_LATENCY(ADD_LATENCY),
        .ACC_LANES(ADD_LANES)
    ) u_acc (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(acc_start),
        .total_len(acc_total_len),
        .in_valid(fx_valid),
        .in_data(fx_value),
        .busy(),
        .done(acc_done),
        .sum_out(acc_sum),
        .accepted_count(),
        .reduced_count(acc_reduced),
        .error(acc_error)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    assign acc_start = (state == S_IDLE) && start;
    assign acc_total_len = acc_start ? len : frame_len;

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            result         <= 32'd0;
            in_ready       <= 1'b0;
            frame_len      <= 32'd0;
            cordic_in_valid <= 1'b0;
            angle_cordic_reg <= '0;
            accepted_count <= 32'd0;
            fx_count       <= 32'd0;
            reduced_count  <= 32'd0;
            error          <= 1'b0;
            x3_wr_ptr      <= '0;
            x3_rd_ptr      <= '0;
            x3_count       <= '0;
            for (i = 0; i < X3_FIFO_DEPTH; i = i + 1) begin
                x3_fifo_mem[i] <= 64'd0;
            end
        end else if (clk_en) begin
            done         <= 1'b0;
            reduced_count <= acc_reduced;

            if (x2_error || x3_error || term_error || fx_error || acc_error) begin
                error <= 1'b1;
            end
            if (cos_valid && (x3_count == 0)) begin
                error <= 1'b1;
            end
            if (x3_push && (x3_count == X3_FIFO_DEPTH_W) && !x3_pop) begin
                error <= 1'b1;
            end

            if (x3_push && (!x3_pop || (x3_count != 0))) begin
                if (x3_count < X3_FIFO_DEPTH_W) begin
                    x3_fifo_mem[x3_wr_ptr] <= {x3_value, x3_side};
                    x3_wr_ptr <= (x3_wr_ptr == FIFO_PTR_W'(X3_FIFO_DEPTH - 1)) ? '0 : (x3_wr_ptr + FIFO_PTR_W'(1));
                end
            end
            if (x3_pop) begin
                x3_rd_ptr <= (x3_rd_ptr == FIFO_PTR_W'(X3_FIFO_DEPTH - 1)) ? '0 : (x3_rd_ptr + FIFO_PTR_W'(1));
            end
            case ({x3_push, x3_pop})
                2'b10: if (x3_count < X3_FIFO_DEPTH_W) x3_count <= x3_count + 1'b1;
                2'b01: if (x3_count != 0) x3_count <= x3_count - 1'b1;
                default: begin end
            endcase

            if (fx_valid) begin
                fx_count <= fx_count + 32'd1;
            end

            cordic_in_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    in_ready <= 1'b0;
                    busy     <= 1'b0;
                    if (start) begin
                        frame_len      <= len;
                        accepted_count <= 32'd0;
                        fx_count       <= 32'd0;
                        reduced_count  <= 32'd0;
                        result         <= 32'd0;
                        error          <= 1'b0;
                        x3_wr_ptr      <= '0;
                        x3_rd_ptr      <= '0;
                        x3_count       <= '0;
                        if (len == 32'd0) begin
                            in_ready <= 1'b0;
                            busy     <= 1'b0;
                            state    <= S_ZERO_DONE;
                        end else begin
                            in_ready <= 1'b1;
                            busy     <= 1'b1;
                            state    <= S_RUN;
                        end
                    end
                end

                S_RUN: begin
                    in_ready <= (accepted_count < frame_len);
                    busy     <= 1'b1;
                    if (in_valid && in_ready) begin
                        accepted_count <= accepted_count + 32'd1;
                        angle_cordic_reg <= angle_cordic_wire;
                        cordic_in_valid <= 1'b1;
                        if ((accepted_count + 32'd1) >= frame_len) begin
                            in_ready <= 1'b0;
                            state    <= S_WAIT_DONE;
                        end
                    end
                end

                S_WAIT_DONE: begin
                    in_ready <= 1'b0;
                    busy     <= 1'b1;
                    if (acc_done) begin
                        result <= acc_sum;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= S_IDLE;
                    end
                end

                S_ZERO_DONE: begin
                    in_ready <= 1'b0;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    state    <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
