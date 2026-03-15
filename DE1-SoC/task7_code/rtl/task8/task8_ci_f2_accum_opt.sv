//------------------------------------------------------------------------------
// Purpose:
//   Improved Task-8 custom instruction for software-managed accumulation.
//
// Interface Contract:
//   dataa = acc_in, datab = x
//   result = acc_in + f(x), where
//     f(x) = 0.5*x + x^3*cos((x-128)/128)
//
// Optimization Strategy:
//   Flatten the Task-8 datapath instead of wrapping Task-7 Step-3 and then
//   appending another adder stage. The block now overlaps three independent
//   activities at the beginning of each call:
//     1) x^2 path (first FP multiply)
//     2) CORDIC cosine evaluation
//     3) acc_in + 0.5*x partial sum
//   This hides one FP add latency inside the existing critical path and reduces
//   per-call latency compared with the previous "task7_ci_f_single + final add"
//   structure, while still keeping only one FP multiplier, one FP adder, and
//   one CORDIC instance.
//
// Notes:
//   - The block is still stateless across calls: software owns the running sum.
//   - Throughput is improved relative to Step-3, but this is still a blocking
//     multicycle custom instruction from the Nios point of view.
//------------------------------------------------------------------------------
module task8_ci_f2_accum_opt #(
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
    input  logic [31:0] dataa,   // acc_in
    input  logic [31:0] datab,   // x
    output logic        done,
    output logic [31:0] result
);
    localparam logic signed [FX_W-1:0] CONST_128 = $signed({{(FX_W-8){1'b0}}, 8'd128}) <<< FX_FRAC;
    localparam logic signed [FX_W-1:0] ONE_ANGLE = $signed({{(FX_W-1){1'b0}}, 1'b1}) <<< FX_FRAC;

    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_X2,
        S_WAIT_X3,
        S_WAIT_COS,
        S_WAIT_TERM,
        S_WAIT_PSUM,
        S_WAIT_FINAL
    } state_t;

    state_t state;

    logic [31:0] x_reg;
    logic [31:0] x3_reg;
    logic [31:0] term_reg;
    logic [31:0] partial_sum_reg;
    logic [31:0] cos_fp_reg;

    logic partial_ready;
    logic cos_ready;

    logic start_q;
    logic start_evt;

    logic mul_start;
    logic mul_start_r;
    logic mul_busy;
    logic mul_done;
    logic [31:0] mul_a;
    logic [31:0] mul_b;
    logic [31:0] mul_result;

    logic add_start;
    logic add_start_r;
    logic add_busy;
    logic add_done;
    logic [31:0] add_a;
    logic [31:0] add_b;
    logic [31:0] add_result;

    logic cordic_start;
    logic cordic_start_r;
    logic cordic_busy;
    logic cordic_done;
    logic signed [CORDIC_W-1:0] angle_cordic_reg;
    logic signed [CORDIC_W-1:0] cordic_cos;

    logic signed [FX_W-1:0] x_fx_wire;
    logic signed [FX_W-1:0] cos_fx_wire;
    logic [31:0] cos_fp_wire;
    logic launch_initial;
    logic [31:0] mul_a_in;
    logic [31:0] mul_b_in;
    logic [31:0] add_a_in;
    logic [31:0] add_b_in;
    logic signed [CORDIC_W-1:0] angle_cordic_in;

    assign start_evt = start & ~start_q;
    assign cos_fx_wire = {{(FX_W-CORDIC_W){cordic_cos[CORDIC_W-1]}}, cordic_cos};
    assign launch_initial = (state == S_IDLE) && start_evt && !mul_busy && !add_busy && !cordic_busy;
    assign mul_start = mul_start_r | launch_initial;
    assign add_start = add_start_r | launch_initial;
    assign cordic_start = cordic_start_r | launch_initial;
    assign mul_a_in = launch_initial ? datab : mul_a;
    assign mul_b_in = launch_initial ? datab : mul_b;
    assign add_a_in = launch_initial ? dataa : add_a;
    assign add_b_in = launch_initial ? fp32_mul_half(datab) : add_b;
    assign angle_cordic_in = launch_initial ? angle_to_cordic(x_fx_wire) : angle_cordic_reg;

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
        .fp_in(datab),
        .fx_out(x_fx_wire)
    );

    task7_cordic_cos_multi_iter #(
        .W(CORDIC_W),
        .FRAC(CORDIC_FRAC),
        .N_ITER(CORDIC_ITER),
        .ITER_PER_CYCLE(CORDIC_ITER_PER_CYCLE)
    ) u_cordic (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(cordic_start),
        .angle_in(angle_cordic_in),
        .busy(cordic_busy),
        .done(cordic_done),
        .cos_out(cordic_cos)
    );

    task7_fx_to_fp32 #(
        .W(FX_W),
        .FRAC(FX_FRAC)
    ) u_cos_fp (
        .fx_in(cos_fx_wire),
        .fp_out(cos_fp_wire)
    );

    task7_fp_mul_ip_unit #(
        .LATENCY(MUL_LATENCY)
    ) u_mul (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(mul_start),
        .a(mul_a_in),
        .b(mul_b_in),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_result)
    );

    task7_fp_add_ip_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(add_start),
        .a(add_a_in),
        .b(add_b_in),
        .busy(add_busy),
        .done(add_done),
        .result(add_result)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state           <= S_IDLE;
            done            <= 1'b0;
            result          <= 32'd0;

            x_reg           <= 32'd0;
            x3_reg          <= 32'd0;
            term_reg        <= 32'd0;
            partial_sum_reg <= 32'd0;
            cos_fp_reg      <= 32'd0;

            partial_ready   <= 1'b0;
            cos_ready       <= 1'b0;
            start_q         <= 1'b0;

            mul_start_r     <= 1'b0;
            mul_a           <= 32'd0;
            mul_b           <= 32'd0;

            add_start_r     <= 1'b0;
            add_a           <= 32'd0;
            add_b           <= 32'd0;

            cordic_start_r  <= 1'b0;
            angle_cordic_reg <= '0;
        end else if (clk_en) begin
            start_q      <= start;
            done         <= 1'b0;
            mul_start_r    <= 1'b0;
            add_start_r    <= 1'b0;
            cordic_start_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (launch_initial) begin
                        x_reg           <= datab;
                        partial_ready   <= 1'b0;
                        cos_ready       <= 1'b0;
                        angle_cordic_reg <= angle_to_cordic(x_fx_wire);

                        mul_a        <= datab;
                        mul_b        <= datab;

                        add_a        <= dataa;
                        add_b        <= fp32_mul_half(datab);

                        state        <= S_WAIT_X2;
                    end
                end

                S_WAIT_X2: begin
                    if (add_done) begin
                        partial_sum_reg <= add_result;
                        partial_ready   <= 1'b1;
                    end

                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;
                    end

                    if (mul_done) begin
                        mul_a     <= mul_result;
                        mul_b     <= x_reg;
                        mul_start_r <= 1'b1;
                        state     <= S_WAIT_X3;
                    end
                end

                S_WAIT_X3: begin
                    if (add_done) begin
                        partial_sum_reg <= add_result;
                        partial_ready   <= 1'b1;
                    end

                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;
                    end

                    if (mul_done) begin
                        x3_reg <= mul_result;

                        if (cos_ready || cordic_done) begin
                            mul_a     <= mul_result;
                            mul_b     <= cordic_done ? cos_fp_wire : cos_fp_reg;
                            mul_start_r <= 1'b1;
                            state     <= S_WAIT_TERM;
                        end else begin
                            state <= S_WAIT_COS;
                        end
                    end
                end

                S_WAIT_COS: begin
                    if (add_done) begin
                        partial_sum_reg <= add_result;
                        partial_ready   <= 1'b1;
                    end

                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;
                        mul_a      <= x3_reg;
                        mul_b      <= cos_fp_wire;
                        mul_start_r  <= 1'b1;
                        state      <= S_WAIT_TERM;
                    end
                end

                S_WAIT_TERM: begin
                    if (add_done) begin
                        partial_sum_reg <= add_result;
                        partial_ready   <= 1'b1;
                    end

                    if (mul_done) begin
                        if (partial_ready || add_done) begin
                            add_a     <= partial_ready ? partial_sum_reg : add_result;
                            add_b     <= mul_result;
                            add_start_r <= 1'b1;
                            state     <= S_WAIT_FINAL;
                        end else begin
                            term_reg <= mul_result;
                            state    <= S_WAIT_PSUM;
                        end
                    end
                end

                S_WAIT_PSUM: begin
                    if (add_done) begin
                        add_a     <= add_result;
                        add_b     <= term_reg;
                        add_start_r <= 1'b1;
                        state     <= S_WAIT_FINAL;
                    end
                end

                S_WAIT_FINAL: begin
                    if (add_done) begin
                        result <= add_result;
                        done   <= 1'b1;
                        state  <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
