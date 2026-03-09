module task7_ci_f_single #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int CORDIC_ITER_PER_CYCLE = 3,
    parameter int MUL_LATENCY = 2,
    parameter int ADD_LATENCY = 1
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] dataa,
    input  logic [31:0] datab,
    input  logic [7:0] n,
    output logic done,
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
        S_WAIT_ADD,
        S_OUT
    } state_t;

    state_t state;

    logic [31:0] x_fp_reg;
    logic [31:0] x3_fp_reg;
    logic [31:0] half_x_fp_reg;
    logic [31:0] cos_fp_reg;

    logic cos_ready;

    logic signed [FX_W-1:0] x_fx_wire;
    logic signed [CORDIC_W-1:0] angle_cordic_reg;
    logic signed [CORDIC_W-1:0] cordic_cos;
    logic cordic_start, cordic_busy, cordic_done;

    logic signed [FX_W-1:0] cos_fx_wire;
    logic [31:0] cos_fp_wire;

    logic mul_start, mul_busy, mul_done;
    logic [31:0] mul_a, mul_b, mul_result;

    logic add_start, add_busy, add_done;
    logic [31:0] add_a, add_b, add_result;

    function automatic logic signed [CORDIC_W-1:0] angle_to_cordic(
        input logic signed [FX_W-1:0] x_in
    );
        logic signed [FX_W-1:0] angle_fx;
        logic signed [FX_W-1:0] clamped;
        begin
            // angle = (x - 128) / 128
            angle_fx = (x_in - CONST_128) >>> 7;

            // Keep CORDIC argument inside the analysed interval [-1, 1].
            if (angle_fx > ONE_ANGLE) begin
                clamped = ONE_ANGLE;
            end else if (angle_fx < -ONE_ANGLE) begin
                clamped = -ONE_ANGLE;
            end else begin
                clamped = angle_fx;
            end

            angle_to_cordic = clamped[CORDIC_W-1:0];
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
                // Normal -> subnormal transition with round-to-nearest-even.
                mant24 = {1'b1, frac};
                half24 = {1'b0, mant24[23:1]};
                if (mant24[0] && half24[0]) begin
                    half24 = half24 + 1'b1;
                end
                if (half24[23]) begin
                    // Rounded up to min normal.
                    fp32_mul_half = {sign, 8'd1, 23'd0};
                end else begin
                    fp32_mul_half = {sign, 8'd0, half24[22:0]};
                end
            end else begin
                // Subnormal -> smaller subnormal with round-to-nearest-even.
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
        .fp_in(dataa),
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
        .angle_in(angle_cordic_reg),
        .busy(cordic_busy),
        .done(cordic_done),
        .cos_out(cordic_cos)
    );

    assign cos_fx_wire = {{(FX_W-CORDIC_W){cordic_cos[CORDIC_W-1]}}, cordic_cos};

    task7_fx_to_fp32 #(
        .W(FX_W),
        .FRAC(FX_FRAC)
    ) u_cos_fp (
        .fx_in(cos_fx_wire),
        .fp_out(cos_fp_wire)
    );

    task7_fp32_mul_unit #(
        .LATENCY(MUL_LATENCY)
    ) u_mul (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(mul_start),
        .a(mul_a),
        .b(mul_b),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_result)
    );

    task7_fp32_add_unit #(
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
        if (reset) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            result         <= '0;

            x_fp_reg       <= '0;
            x3_fp_reg      <= '0;
            half_x_fp_reg  <= '0;
            cos_fp_reg     <= '0;

            cos_ready      <= 1'b0;

            angle_cordic_reg <= '0;
            cordic_start   <= 1'b0;

            mul_start      <= 1'b0;
            mul_a          <= '0;
            mul_b          <= '0;

            add_start      <= 1'b0;
            add_a          <= '0;
            add_b          <= '0;
        end else if (clk_en) begin
            done         <= 1'b0;
            cordic_start <= 1'b0;
            mul_start    <= 1'b0;
            add_start    <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        x_fp_reg         <= dataa;
                        half_x_fp_reg    <= fp32_mul_half(dataa);
                        angle_cordic_reg <= angle_to_cordic(x_fx_wire);
                        cos_ready        <= 1'b0;

                        // Start x^2 and cos() in parallel.
                        mul_a     <= dataa;
                        mul_b     <= dataa;
                        mul_start <= 1'b1;

                        cordic_start <= 1'b1;
                        state <= S_WAIT_X2;
                    end
                end

                S_WAIT_X2: begin
                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;
                    end

                    if (mul_done) begin
                        // x^3 = x^2 * x
                        mul_a      <= mul_result;
                        mul_b      <= x_fp_reg;
                        mul_start  <= 1'b1;
                        state      <= S_WAIT_X3;
                    end
                end

                S_WAIT_X3: begin
                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;
                    end

                    if (mul_done) begin
                        x3_fp_reg <= mul_result;

                        if (cos_ready || cordic_done) begin
                            mul_a <= mul_result;
                            mul_b <= cordic_done ? cos_fp_wire : cos_fp_reg;
                            mul_start <= 1'b1;
                            state <= S_WAIT_TERM;
                        end else begin
                            state <= S_WAIT_COS;
                        end
                    end
                end

                S_WAIT_COS: begin
                    if (cordic_done) begin
                        cos_fp_reg <= cos_fp_wire;
                        cos_ready  <= 1'b1;

                        mul_a      <= x3_fp_reg;
                        mul_b      <= cos_fp_wire;
                        mul_start  <= 1'b1;
                        state      <= S_WAIT_TERM;
                    end
                end

                S_WAIT_TERM: begin
                    if (mul_done) begin
                        // f(x) = 0.5*x + x^3*cos(...)
                        add_a     <= half_x_fp_reg;
                        add_b     <= mul_result;
                        add_start <= 1'b1;
                        state     <= S_WAIT_ADD;
                    end
                end

                S_WAIT_ADD: begin
                    if (add_done) begin
                        result <= add_result;
                        state <= S_OUT;
                    end
                end

                S_OUT: begin
                    done   <= 1'b1;
                    state  <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // Unused, but kept for a standard custom-instruction component signature.
    logic [31:0] datab_unused;
    logic [7:0]  n_unused;
    always_comb begin
        datab_unused = datab;
        n_unused = n;
    end
endmodule
