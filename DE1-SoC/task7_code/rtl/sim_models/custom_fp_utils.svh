//------------------------------------------------------------------------------
// Purpose:
//   Utility functions for simulation-only fp32 arithmetic models.
//
// Notes:
//   - These helpers are intended for Verilator/RTL simulation fallback only.
//   - They implement basic IEEE-754 single conversions with simple rounding.
//   - Sufficient for coursework functional validation, not a bit-exact FP IP
//     replacement across all corner cases.
//------------------------------------------------------------------------------
`ifndef TASK7_SIM_FP_UTILS_SVH
`define TASK7_SIM_FP_UTILS_SVH

function automatic real task7_fp32_to_real(input logic [31:0] bits);
    logic sign_b;
    int exp_raw;
    int frac_raw;
    real sign_r;
    real mant_r;
    begin
        sign_b = bits[31];
        exp_raw = int'(bits[30:23]);
        frac_raw = int'(bits[22:0]);
        sign_r = sign_b ? -1.0 : 1.0;

        if ((exp_raw == 0) && (frac_raw == 0)) begin
            task7_fp32_to_real = 0.0;
        end else if (exp_raw == 0) begin
            mant_r = frac_raw / (2.0 ** 23);
            task7_fp32_to_real = sign_r * mant_r * (2.0 ** (-126));
        end else if (exp_raw == 255) begin
            task7_fp32_to_real = sign_b ? -1.0e300 : 1.0e300;
        end else begin
            mant_r = 1.0 + (frac_raw / (2.0 ** 23));
            task7_fp32_to_real = sign_r * mant_r * (2.0 ** (exp_raw - 127));
        end
    end
endfunction

function automatic logic [31:0] task7_real_to_fp32(input real x_in);
    real x;
    logic sign_b;
    int exp_unb;
    int exp_raw;
    real scaled;
    real frac_real;
    int frac_int;
    begin
        if (x_in == 0.0) begin
            task7_real_to_fp32 = 32'd0;
        end else begin
            sign_b = (x_in < 0.0);
            x = sign_b ? -x_in : x_in;

            // Handle overflow as infinity.
            if (x >= (2.0 ** 128)) begin
                task7_real_to_fp32 = {sign_b, 8'hFF, 23'd0};
            end else begin
                exp_unb = int'($floor($ln(x) / $ln(2.0)));

                if (exp_unb < -126) begin
                    // Subnormal: value = frac * 2^-149
                    frac_real = x * (2.0 ** 149);
                    frac_int = int'($rtoi(frac_real + 0.5));
                    if (frac_int > ((1 << 23) - 1)) begin
                        frac_int = (1 << 23) - 1;
                    end
                    task7_real_to_fp32 = {sign_b, 8'd0, frac_int[22:0]};
                end else begin
                    // Normal: x = (1 + frac/2^23) * 2^exp_unb
                    scaled = x / (2.0 ** exp_unb);
                    frac_real = (scaled - 1.0) * (2.0 ** 23);
                    frac_int = int'($rtoi(frac_real + 0.5));

                    // Round overflow in mantissa.
                    if (frac_int >= (1 << 23)) begin
                        frac_int = 0;
                        exp_unb = exp_unb + 1;
                    end

                    exp_raw = exp_unb + 127;
                    if (exp_raw >= 255) begin
                        task7_real_to_fp32 = {sign_b, 8'hFF, 23'd0};
                    end else begin
                        task7_real_to_fp32 = {sign_b, exp_raw[7:0], frac_int[22:0]};
                    end
                end
            end
        end
    end
endfunction

`endif
