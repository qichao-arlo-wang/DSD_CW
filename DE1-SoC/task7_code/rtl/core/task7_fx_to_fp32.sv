//------------------------------------------------------------------------------
// Purpose:
//   Signed fixed-point to IEEE-754 single-precision converter.
//
// Role In Task 7:
//   Converts fixed-point outputs (for example CORDIC cosine results) back to
//   fp32 format required by CI result ports and fp32 arithmetic units.
//
// Interface Notes:
//   Combinational converter with normalization and rounding path, plus explicit
//   overflow handling to +/-Inf for out-of-range magnitudes.
//------------------------------------------------------------------------------
module task7_fx_to_fp32 #(
    parameter int W = 64,
    parameter int FRAC = 34
) (
    input  logic signed [W-1:0] fx_in,
    output logic [31:0] fp_out
);
    // Signed fixed-point -> IEEE-754 single converter.
    //
    // Behavior policy:
    // - Exact zero -> fp32 zero.
    // - Out-of-range magnitude -> +/-Inf.
    // - Very small values below normal range -> flush to zero in this design.
    //   (subnormal output path is intentionally omitted for current Task-7 range)
    logic sign;
    logic [W-1:0] abs_val;
    logic [23:0] shifted_abs;

    integer msb_idx;
    integer exp_unbiased;
    integer exp_raw;
    integer shift_amt;

    logic [24:0] mant24_ext;
    logic [22:0] mantissa;
    logic round_bit;
    logic sticky_bits;

    function automatic logic [23:0] low24(input logic [W-1:0] v);
        logic [23:0] tmp;
        begin
            tmp = '0;
            for (int j = 0; j < 24; j = j + 1) begin
                if (j < W) begin
                    tmp[j] = v[j];
                end
            end
            low24 = tmp;
        end
    endfunction

    always_comb begin
        // Defaults keep the block purely combinational.
        fp_out       = 32'd0;
        sign         = fx_in[W-1];
        abs_val      = sign ? $unsigned(-fx_in) : $unsigned(fx_in);
        shifted_abs  = '0;
        msb_idx      = 0;
        exp_unbiased = 0;
        exp_raw      = 0;
        shift_amt    = 0;
        mant24_ext   = '0;
        mantissa     = '0;
        round_bit    = 1'b0;
        sticky_bits  = 1'b0;

        if (fx_in != '0) begin
            // Locate the highest set bit of |fx_in| without break statements.
            for (int bit_idx = 0; bit_idx < W; bit_idx = bit_idx + 1) begin
                if (abs_val[bit_idx]) begin
                    msb_idx = bit_idx;
                end
            end

            exp_unbiased = msb_idx - FRAC;
            exp_raw = exp_unbiased + 127;

            if (exp_raw >= 255) begin
                // Overflow: map to infinity.
                fp_out = {sign, 8'hFF, 23'd0};
            end else if (exp_raw <= 0) begin
                // Underflow: flush to zero (subnormal path not required for this task range).
                fp_out = {sign, 8'd0, 23'd0};
            end else begin
                if (msb_idx >= 23) begin
                    // Shift right to obtain 1.xxx... mantissa window.
                    shift_amt = msb_idx - 23;
                    shifted_abs = 24'($unsigned(abs_val) >> shift_amt);
                    mant24_ext = {1'b0, shifted_abs};

                    if (shift_amt > 0) begin
                        // Guard variable index access for synthesis tools.
                        if ((shift_amt - 1) < W) begin
                            round_bit = abs_val[shift_amt-1];
                        end else begin
                            round_bit = 1'b0;
                        end

                        sticky_bits = 1'b0;
                        for (int sticky_idx = 0; sticky_idx < W; sticky_idx = sticky_idx + 1) begin
                            if (sticky_idx < (shift_amt - 1)) begin
                                sticky_bits = sticky_bits | abs_val[sticky_idx];
                            end
                        end

                        // Round to nearest even.
                        if (round_bit && (sticky_bits || mant24_ext[0])) begin
                            mant24_ext = mant24_ext + 1'b1;
                        end
                    end

                    // Handle carry after rounding.
                    if (mant24_ext[24]) begin
                        mant24_ext = mant24_ext >> 1;
                        exp_raw = exp_raw + 1;
                    end
                end else begin
                    // Shift left when magnitude fits fully below mantissa MSB.
                    shift_amt  = 23 - msb_idx;
                    mant24_ext = {1'b0, low24(abs_val)} << shift_amt;
                end

                if (exp_raw >= 255) begin
                    fp_out = {sign, 8'hFF, 23'd0};
                end else begin
                    // Pack sign | exponent | fraction.
                    mantissa = mant24_ext[22:0];
                    fp_out = {sign, exp_raw[7:0], mantissa};
                end
            end
        end
    end
endmodule
