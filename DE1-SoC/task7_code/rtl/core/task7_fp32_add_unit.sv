//------------------------------------------------------------------------------
// Purpose:
//   Shared fp32 add unit with deterministic handshake latency.
//
// Role In Task 7:
//   Provides floating-point addition support to Step-2 add/sub CI and Step-3
//   final `f(x)` CI scheduling logic.
//
// Interface Notes:
//   Behavioral IEEE-754 single-precision adder model with start/busy/done
//   protocol, suitable for integration and verification in this coursework.
//------------------------------------------------------------------------------
module task7_fp32_add_unit #(
    parameter int LATENCY = 1
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
    // Detailed note:
    // This is a compact behavioral fp32 adder for coursework integration/tests.
    // It models key IEEE-754 semantics used by the task (specials + RNE rounding).
    localparam int CW = (LATENCY > 1) ? $clog2(LATENCY) : 1;

    logic [31:0] a_reg, b_reg;
    logic [CW-1:0] cnt;

    // Right-shift with sticky-bit generation (used for exponent alignment).
    // Example: when shifting out bits during mantissa alignment, any discarded
    // non-zero bit must be remembered via sticky=1 for correct IEEE rounding.
    function automatic [26:0] shr_sticky_27(input logic [26:0] in_v, input integer sh);
        logic [26:0] out_v;
        integer j;
        logic sticky_acc;
        begin
            if (sh <= 0) begin
                out_v = in_v;
            end else if (sh >= 27) begin
                out_v = 27'd0;
                out_v[0] = |in_v;
            end else begin
                out_v = in_v >> sh;
                sticky_acc = 1'b0;
                for (j = 0; (j < sh) && (j < 27); j = j + 1) begin
                    sticky_acc = sticky_acc | in_v[j];
                end
                out_v[0] = out_v[0] | sticky_acc;
            end
            shr_sticky_27 = out_v;
        end
    endfunction

    function automatic [31:0] fp32_add(input logic [31:0] lhs, input logic [31:0] rhs);
        logic sign_a, sign_b, sign_r;
        logic [7:0] exp_a, exp_b;
        logic [22:0] frac_a, frac_b;
        logic [23:0] mant_a, mant_b;
        logic [23:0] mant24;
        logic [24:0] mant25;
        logic [26:0] ma, mb;
        logic [27:0] mr;
        logic guard_b, round_b, sticky_b;
        logic is_zero_a, is_zero_b;
        logic is_inf_a, is_inf_b;
        logic is_nan_a, is_nan_b;
        integer exp_eff_a, exp_eff_b;
        integer exp_r;
        integer diff;
        integer i;
        logic [23:0] mant_big, mant_sml;
        logic sign_big, sign_sml;
        integer exp_big_eff, exp_sml_eff;
        logic zero_after_sub;
        begin
            // 1) Classify operands and handle IEEE-754 special cases first.
            // This keeps the arithmetic core focused on finite non-zero cases.
            sign_a = lhs[31];
            sign_b = rhs[31];
            exp_a  = lhs[30:23];
            exp_b  = rhs[30:23];
            frac_a = lhs[22:0];
            frac_b = rhs[22:0];

            is_zero_a = (exp_a == 8'd0) && (frac_a == 23'd0);
            is_zero_b = (exp_b == 8'd0) && (frac_b == 23'd0);
            is_inf_a  = (exp_a == 8'hFF) && (frac_a == 23'd0);
            is_inf_b  = (exp_b == 8'hFF) && (frac_b == 23'd0);
            is_nan_a  = (exp_a == 8'hFF) && (frac_a != 23'd0);
            is_nan_b  = (exp_b == 8'hFF) && (frac_b != 23'd0);

            if (is_nan_a || is_nan_b || (is_inf_a && is_inf_b && (sign_a != sign_b))) begin
                fp32_add = 32'h7FC00000;
            end else if (is_inf_a) begin
                fp32_add = {sign_a, 8'hFF, 23'd0};
            end else if (is_inf_b) begin
                fp32_add = {sign_b, 8'hFF, 23'd0};
            end else if (is_zero_a && is_zero_b) begin
                fp32_add = 32'd0;
            end else begin
                // 2) Decode mantissas and effective exponents.
                //    - Normal:   value = 1.frac * 2^(exp-127)
                //    - Subnormal:value = 0.frac * 2^(-126)
                // For alignment math, subnormal is treated with effective exp = 1.
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

                // 3) Align smaller operand to the larger exponent and combine magnitudes.
                // We always subtract/add "small" from/to "big" to avoid negative
                // intermediate magnitudes after opposite-sign operation.
                // Select operand with larger magnitude as "big".
                if ((exp_eff_a > exp_eff_b) || ((exp_eff_a == exp_eff_b) && (mant_a >= mant_b))) begin
                    exp_big_eff = exp_eff_a;
                    mant_big    = mant_a;
                    sign_big    = sign_a;

                    mant_sml    = mant_b;
                    sign_sml    = sign_b;
                    exp_sml_eff = exp_eff_b;
                end else begin
                    exp_big_eff = exp_eff_b;
                    mant_big    = mant_b;
                    sign_big    = sign_b;

                    mant_sml    = mant_a;
                    sign_sml    = sign_a;
                    exp_sml_eff = exp_eff_a;
                end

                diff = exp_big_eff - exp_sml_eff;
                ma = {mant_big, 3'b000};
                mb = shr_sticky_27({mant_sml, 3'b000}, diff);

                exp_r = exp_big_eff;
                zero_after_sub = 1'b0;

                if (sign_big == sign_sml) begin
                    // Same-sign: pure addition of aligned mantissas.
                    mr = {1'b0, ma} + {1'b0, mb};
                    sign_r = sign_big;

                    if (mr[27]) begin
                        sticky_b = mr[0];
                        mr = mr >> 1;
                        mr[0] = mr[0] | sticky_b;
                        exp_r = exp_r + 1;
                    end
                end else begin
                    // Opposite-sign: magnitude subtraction (big - small).
                    mr = {1'b0, ma} - {1'b0, mb};
                    sign_r = sign_big;

                    if (mr[26:0] == 27'd0) begin
                        zero_after_sub = 1'b1;
                    end

                    if (!zero_after_sub) begin
                        // Renormalize left after subtraction until hidden bit reaches bit[26].
                        // Bound by 27 steps because mantissa+GRS width is 27.
                        for (i = 0; i < 27; i = i + 1) begin
                            if ((mr[26] == 1'b0) && (exp_r > 1)) begin
                                mr = mr << 1;
                                exp_r = exp_r - 1;
                            end
                        end
                    end
                end

                // 4) Normalize, round (nearest-even), then repack to fp32.
                // Mantissa format at this point:
                //   mr[26:3] = 24-bit significand candidate
                //   mr[2]    = guard
                //   mr[1]    = round
                //   mr[0]    = sticky
                if (zero_after_sub) begin
                    fp32_add = 32'd0;
                end else begin
                    guard_b  = mr[2];
                    round_b  = mr[1];
                    sticky_b = mr[0];
                    mant24   = mr[26:3];

                    if (guard_b && (round_b || sticky_b || mant24[0])) begin
                        // IEEE round-to-nearest-even:
                        // - round up on >0.5 ulp
                        // - on exactly 0.5 ulp, round to even LSB
                        mant25 = {1'b0, mant24} + 25'd1;
                        if (mant25[24]) begin
                            mant24 = 24'h800000;
                            exp_r = exp_r + 1;
                        end else begin
                            mant24 = mant25[23:0];
                        end
                    end

                    if (exp_r >= 255) begin
                        // Overflow after rounding.
                        fp32_add = {sign_r, 8'hFF, 23'd0};
                    end else if (mant24 == 24'd0) begin
                        // Exact cancellation to zero.
                        fp32_add = 32'd0;
                    end else if ((exp_r == 1) && (mant24[23] == 1'b0)) begin
                        // Effective exponent is -126 but significand has no hidden 1:
                        // this must be encoded as a subnormal number.
                        fp32_add = {sign_r, 8'd0, mant24[22:0]};
                    end else begin
                        // Standard normalized fp32 packing.
                        fp32_add = {sign_r, exp_r[7:0], mant24[22:0]};
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
                // Capture inputs at start; arithmetic result is produced after LATENCY cycles.
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
                    result <= fp32_add(a_reg, b_reg);
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end
endmodule

