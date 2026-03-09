module task7_fp32_mul_unit #(
    parameter int LATENCY = 2
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
    localparam int CW = (LATENCY > 1) ? $clog2(LATENCY) : 1;

    logic [31:0] a_reg, b_reg;
    logic [CW-1:0] cnt;

    function automatic [31:0] fp32_mul(input logic [31:0] lhs, input logic [31:0] rhs);
        logic sign_a, sign_b, sign_r;
        logic [7:0] exp_a, exp_b;
        logic [22:0] frac_a, frac_b;
        logic [23:0] mant_a, mant_b;
        logic [47:0] prod;
        logic [47:0] prod_n;
        logic [23:0] mant24;
        logic [24:0] mant25;
        logic guard_b, round_b, sticky_b;
        integer exp_eff_a, exp_eff_b;
        integer exp_r;
        integer sh, j, k;
        logic is_zero_a, is_zero_b;
        logic is_inf_a, is_inf_b;
        logic is_nan_a, is_nan_b;
        logic [24:0] sub_sig;
        logic [24:0] sub_shifted;
        logic [23:0] sub_frac;
        logic round_sub, sticky_sub;
        begin
            sign_a = lhs[31];
            sign_b = rhs[31];
            exp_a  = lhs[30:23];
            exp_b  = rhs[30:23];
            frac_a = lhs[22:0];
            frac_b = rhs[22:0];
            sign_r = sign_a ^ sign_b;

            is_zero_a = (exp_a == 8'd0) && (frac_a == 23'd0);
            is_zero_b = (exp_b == 8'd0) && (frac_b == 23'd0);
            is_inf_a  = (exp_a == 8'hFF) && (frac_a == 23'd0);
            is_inf_b  = (exp_b == 8'hFF) && (frac_b == 23'd0);
            is_nan_a  = (exp_a == 8'hFF) && (frac_a != 23'd0);
            is_nan_b  = (exp_b == 8'hFF) && (frac_b != 23'd0);

            if (is_nan_a || is_nan_b || ((is_inf_a || is_inf_b) && (is_zero_a || is_zero_b))) begin
                fp32_mul = 32'h7FC00000; // qNaN
            end else if (is_inf_a || is_inf_b) begin
                fp32_mul = {sign_r, 8'hFF, 23'd0};
            end else if (is_zero_a || is_zero_b) begin
                fp32_mul = {sign_r, 31'd0};
            end else begin
                if (exp_a == 8'd0) begin
                    mant_a = {1'b0, frac_a};
                    exp_eff_a = 1;
                end else begin
                    mant_a = {1'b1, frac_a};
                    exp_eff_a = {24'd0, exp_a};
                end

                if (exp_b == 8'd0) begin
                    mant_b = {1'b0, frac_b};
                    exp_eff_b = 1;
                end else begin
                    mant_b = {1'b1, frac_b};
                    exp_eff_b = {24'd0, exp_b};
                end

                prod = mant_a * mant_b;
                prod_n = prod;
                exp_r = exp_eff_a + exp_eff_b - 127;

                if (prod_n == 48'd0) begin
                    fp32_mul = {sign_r, 31'd0};
                end else begin
                    if (!prod_n[47]) begin
                        for (k = 0; k < 47; k = k + 1) begin
                            if (!prod_n[46]) begin
                                prod_n = prod_n << 1;
                                exp_r = exp_r - 1;
                            end
                        end
                    end

                    if (prod_n[47]) begin
                        mant24   = prod_n[47:24];
                        guard_b  = prod_n[23];
                        round_b  = prod_n[22];
                        sticky_b = |prod_n[21:0];
                        exp_r    = exp_r + 1;
                    end else begin
                        mant24   = prod_n[46:23];
                        guard_b  = prod_n[22];
                        round_b  = prod_n[21];
                        sticky_b = |prod_n[20:0];
                    end

                    if (guard_b && (round_b || sticky_b || mant24[0])) begin
                        mant25 = {1'b0, mant24} + 25'd1;
                        if (mant25[24]) begin
                            mant24 = 24'h800000;
                            exp_r = exp_r + 1;
                        end else begin
                            mant24 = mant25[23:0];
                        end
                    end

                    if (exp_r >= 255) begin
                        fp32_mul = {sign_r, 8'hFF, 23'd0};
                    end else if (exp_r <= 0) begin
                        // Subnormal/underflow path.
                        sh = 1 - exp_r;
                        if (sh > 24) begin
                            fp32_mul = {sign_r, 31'd0};
                        end else begin
                            sub_sig = {1'b0, mant24};
                            sub_shifted = sub_sig >> sh;
                            sub_frac = sub_shifted[23:0];
                            round_sub = 1'b0;
                            sticky_sub = 1'b0;

                            if (sh > 0) begin
                                round_sub = sub_sig[sh-1];
                                for (j = 0; j < sh-1; j = j + 1) begin
                                    sticky_sub = sticky_sub | sub_sig[j];
                                end
                            end

                            if (round_sub && (sticky_sub || sub_frac[0])) begin
                                sub_frac = sub_frac + 1'b1;
                            end

                            if (sub_frac[23]) begin
                                // Rounded to min normal.
                                fp32_mul = {sign_r, 8'd1, 23'd0};
                            end else begin
                                fp32_mul = {sign_r, 8'd0, sub_frac[22:0]};
                            end
                        end
                    end else begin
                        fp32_mul = {sign_r, exp_r[7:0], mant24[22:0]};
                    end
                end
            end
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 32'd0;
            a_reg  <= 32'd0;
            b_reg  <= 32'd0;
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
                    result <= fp32_mul(a_reg, b_reg);
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
endmodule
