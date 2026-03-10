//------------------------------------------------------------------------------
// Purpose:
//   IEEE-754 single-precision to signed fixed-point converter.
//
// Role In Task 7:
//   Converts fp32 input values from CI interface into fixed-point values for
//   the CORDIC cosine core and fixed-point internal operations.
//
// Interface Notes:
//   Combinational converter with saturation handling for NaN/Inf/out-of-range
//   cases, parameterized by output width `W` and fractional bits `FRAC`.
//------------------------------------------------------------------------------
module task7_fp32_to_fx #(
    parameter int W = 64,
    parameter int FRAC = 34
) (
    input  logic [31:0] fp_in,
    output logic signed [W-1:0] fx_out
);
    // IEEE-754 single -> signed fixed-point Q( W-FRAC ).FRAC converter.
    //
    // Behavior policy:
    // - NaN / +/-Inf: saturate to fixed-point max/min.
    // - Normal/subnormal finite values: convert with truncation-by-shift.
    // - Out-of-range finite values: saturate.
    // - Signed zero: maps to zero.
    localparam int MAG_W = W + 64;
    localparam logic signed [W-1:0] FX_MAX = {1'b0, {(W-1){1'b1}}};
    localparam logic signed [W-1:0] FX_MIN = {1'b1, {(W-1){1'b0}}};

    logic sign;
    logic [7:0] exp_raw;
    logic [22:0] frac_raw;

    integer exp_unbiased;
    integer shift_amt;

    logic [23:0] mantissa;
    logic signed [MAG_W-1:0] mag_ext;
    logic signed [MAG_W-1:0] signed_ext;
    logic signed [MAG_W-1:0] fx_max_ext;
    logic signed [MAG_W-1:0] fx_min_ext;

    always_comb begin
        sign       = fp_in[31];
        exp_raw    = fp_in[30:23];
        frac_raw   = fp_in[22:0];
        mantissa   = 24'd0;
        exp_unbiased = 0;
        shift_amt  = 0;
        mag_ext    = '0;
        signed_ext = '0;
        fx_max_ext = {{(MAG_W-W){FX_MAX[W-1]}}, FX_MAX};
        fx_min_ext = {{(MAG_W-W){FX_MIN[W-1]}}, FX_MIN};

        if ((exp_raw == 8'd0) && (frac_raw == 23'd0)) begin
            // Signed zero maps to fixed zero.
            fx_out = '0;
        end else if (exp_raw == 8'hFF) begin
            // Infinity/NaN are saturated.
            fx_out = sign ? FX_MIN : FX_MAX;
        end else begin
            if (exp_raw == 8'd0) begin
                // Subnormal number.
                mantissa     = {1'b0, frac_raw};
                exp_unbiased = -126;
            end else begin
                // Normalized number.
                mantissa     = {1'b1, frac_raw};
                exp_unbiased = $signed({24'd0, exp_raw}) - 32'sd127;
            end

            // Convert exponent from fp32 binary point (after 23 frac bits)
            // to target fixed-point binary point (FRAC frac bits).
            shift_amt = exp_unbiased - 23 + FRAC;

            if (shift_amt >= 0) begin
                // Left-shift for larger-magnitude results.
                if (shift_amt >= (MAG_W - 24)) begin
                    mag_ext = fx_max_ext;
                end else begin
                    mag_ext = $signed({{(MAG_W-24){1'b0}}, mantissa}) <<< shift_amt;
                end
            end else begin
                // Right-shift for smaller-magnitude results.
                if ((-shift_amt) >= 24) begin
                    mag_ext = '0;
                end else begin
                    mag_ext = $signed({{(MAG_W-24){1'b0}}, mantissa}) >>> (-shift_amt);
                end
            end

            signed_ext = sign ? -mag_ext : mag_ext;

            // Final saturation to output width.
            if (signed_ext > fx_max_ext) begin
                fx_out = FX_MAX;
            end else if (signed_ext < fx_min_ext) begin
                fx_out = FX_MIN;
            end else begin
                fx_out = signed_ext[W-1:0];
            end
        end
    end
endmodule
