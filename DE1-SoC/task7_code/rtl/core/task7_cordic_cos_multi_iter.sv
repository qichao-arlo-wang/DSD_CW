//------------------------------------------------------------------------------
// Purpose:
//   Fixed-point multi-iteration-per-cycle CORDIC cosine engine.
//
// Role In Task 7:
//   Serves as the cosine accelerator used by both Step-2 cosine-only CI and the
//   final Step-3 `f(x)` CI module.
//
// Interface Notes:
//   Rotation-mode CORDIC with start/busy/done handshake.
//   Input/output use signed fixed-point format with configurable width/fraction.
//------------------------------------------------------------------------------
module task7_cordic_cos_multi_iter #(
    parameter int W = 28,
    parameter int FRAC = 22,
    parameter int N_ITER = 18,
    parameter int ITER_PER_CYCLE = 3
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic signed [W-1:0] angle_in,
    output logic busy,
    output logic done,
    output logic signed [W-1:0] cos_out
);
    // Detailed note:
    // ITER_PER_CYCLE is the main latency/area knob:
    // larger value reduces cycles but increases per-cycle combinational work.
    // Multi-iteration-per-cycle CORDIC (rotation mode).
    // - Input/output are fixed-point signed values.
    // - angle_in is expected in [-1, 1] range (radians equivalent used by coursework flow).
    // - cos_out is scaled by 2^FRAC.
    //
    // Latency model:
    //   cycles ~= ceil(N_ITER / ITER_PER_CYCLE) + control overhead.
    // Increasing ITER_PER_CYCLE lowers latency but increases combinational depth.
    localparam int MAX_ITER = 24;
    localparam int IW = (N_ITER > 1) ? $clog2(N_ITER+1) : 1;
    localparam int BASE_FRAC = 56;

    // High-precision base constants scaled by 2^BASE_FRAC.
    // These are rounded integer representations of:
    // - K = product_i(1/sqrt(1+2^(-2i)))
    // - atan(2^-i), i=0..23
    localparam longint signed K_CONST_BASE = 64'sd43757185469210312;

    function automatic longint signed atan_base(input int idx);
        begin
            case (idx)
                0:  atan_base = 64'sd56593902016227520;
                1:  atan_base = 64'sd33409331186036028;
                2:  atan_base = 64'sd17652573055549882;
                3:  atan_base = 64'sd8960721713639278;
                4:  atan_base = 64'sd4497749271019253;
                5:  atan_base = 64'sd2251067235130761;
                6:  atan_base = 64'sd1125808294293075;
                7:  atan_base = 64'sd562938500594601;
                8:  atan_base = 64'sd281473545067998;
                9:  atan_base = 64'sd140737309398767;
                10: atan_base = 64'sd70368721808055;
                11: atan_base = 64'sd35184369292630;
                12: atan_base = 64'sd17592185694891;
                13: atan_base = 64'sd8796092978517;
                14: atan_base = 64'sd4398046505643;
                15: atan_base = 64'sd2199023254869;
                16: atan_base = 64'sd1099511627691;
                17: atan_base = 64'sd549755813877;
                18: atan_base = 64'sd274877906943;
                19: atan_base = 64'sd137438953472;
                20: atan_base = 64'sd68719476736;
                21: atan_base = 64'sd34359738368;
                22: atan_base = 64'sd17179869184;
                23: atan_base = 64'sd8589934592;
                default: atan_base = 64'sd0;
            endcase
        end
    endfunction

    // Arithmetic right-shift with round-to-nearest-even.
    function automatic longint signed rshift_round_nearest_even(
        input longint signed val,
        input int sh
    );
        longint signed abs_val;
        longint signed q;
        longint signed rem;
        longint signed half;
        begin
            if (sh <= 0) begin
                rshift_round_nearest_even = val;
            end else begin
                abs_val = (val < 0) ? -val : val;
                q = abs_val >>> sh;
                rem = abs_val - (q <<< sh);
                half = 64'sd1 <<< (sh - 1);

                if (rem > half || ((rem == half) && q[0])) begin
                    q = q + 1'b1;
                end

                rshift_round_nearest_even = (val < 0) ? -q : q;
            end
        end
    endfunction

    // Convert a BASE_FRAC fixed-point constant into target FRAC with saturation to W.
    function automatic logic signed [W-1:0] scale_from_base(input longint signed val_base);
        longint signed scaled;
        longint signed max_pos;
        longint signed min_neg;
        int sh;
        begin
            if (FRAC >= BASE_FRAC) begin
                sh = FRAC - BASE_FRAC;
                if (sh == 0) begin
                    scaled = val_base;
                end else begin
                    scaled = val_base <<< sh;
                end
            end else begin
                sh = BASE_FRAC - FRAC;
                scaled = rshift_round_nearest_even(val_base, sh);
            end

            max_pos = (64'sd1 <<< (W - 1)) - 1;
            min_neg = -(64'sd1 <<< (W - 1));

            if (scaled > max_pos) begin
                scale_from_base = max_pos[W-1:0];
            end else if (scaled < min_neg) begin
                scale_from_base = min_neg[W-1:0];
            end else begin
                scale_from_base = scaled[W-1:0];
            end
        end
    endfunction

    localparam logic signed [W-1:0] K_CONST = scale_from_base(K_CONST_BASE);
    localparam logic signed [W-1:0] ATAN_TABLE [0:MAX_ITER-1] = '{
        scale_from_base(atan_base(0)),
        scale_from_base(atan_base(1)),
        scale_from_base(atan_base(2)),
        scale_from_base(atan_base(3)),
        scale_from_base(atan_base(4)),
        scale_from_base(atan_base(5)),
        scale_from_base(atan_base(6)),
        scale_from_base(atan_base(7)),
        scale_from_base(atan_base(8)),
        scale_from_base(atan_base(9)),
        scale_from_base(atan_base(10)),
        scale_from_base(atan_base(11)),
        scale_from_base(atan_base(12)),
        scale_from_base(atan_base(13)),
        scale_from_base(atan_base(14)),
        scale_from_base(atan_base(15)),
        scale_from_base(atan_base(16)),
        scale_from_base(atan_base(17)),
        scale_from_base(atan_base(18)),
        scale_from_base(atan_base(19)),
        scale_from_base(atan_base(20)),
        scale_from_base(atan_base(21)),
        scale_from_base(atan_base(22)),
        scale_from_base(atan_base(23))
    };

    logic signed [W-1:0] x_reg, y_reg, z_reg;
    logic [IW-1:0] iter_idx;

    integer k;

    initial begin
        if (W < 3 || W > 62) begin
            $error("task7_cordic_cos_multi_iter: W must be in [3,62].");
        end
        if (FRAC < 0 || FRAC > BASE_FRAC) begin
            $error("task7_cordic_cos_multi_iter: FRAC must be in [0,%0d].", BASE_FRAC);
        end
        if (FRAC > (W - 2)) begin
            $error("task7_cordic_cos_multi_iter: require W >= FRAC + 2.");
        end
        if (N_ITER > MAX_ITER) begin
            $error("task7_cordic_cos_multi_iter: N_ITER exceeds MAX_ITER table size.");
        end
        if (ITER_PER_CYCLE < 1) begin
            $error("task7_cordic_cos_multi_iter: ITER_PER_CYCLE must be >= 1.");
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        logic signed [W-1:0] x_tmp, y_tmp, z_tmp;
        logic signed [W-1:0] x_next, y_next, z_next;
        logic [IW-1:0] idx_tmp;

        if (reset) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            cos_out  <= '0;
            x_reg    <= '0;
            y_reg    <= '0;
            z_reg    <= '0;
            iter_idx <= '0;
        end else if (clk_en) begin
            done <= 1'b0;

            if (start && !busy) begin
                // Rotation mode initialization:
                // start vector [x,y] = [K, 0], then rotate by residual z=angle.
                x_reg    <= K_CONST;
                y_reg    <= '0;
                z_reg    <= angle_in;
                iter_idx <= '0;
                busy     <= 1'b1;
            end else if (busy) begin
                x_tmp = x_reg;
                y_tmp = y_reg;
                z_tmp = z_reg;
                idx_tmp = iter_idx;

                // Execute ITER_PER_CYCLE micro-rotations in one clock.
                for (k = 0; k < ITER_PER_CYCLE; k = k + 1) begin
                    if (idx_tmp < IW'(N_ITER)) begin
                        if (z_tmp >= 0) begin
                            // Positive residual angle: rotate clockwise.
                            x_next = x_tmp - (y_tmp >>> idx_tmp);
                            y_next = y_tmp + (x_tmp >>> idx_tmp);
                            z_next = z_tmp - ATAN_TABLE[idx_tmp];
                        end else begin
                            // Negative residual angle: rotate counter-clockwise.
                            x_next = x_tmp + (y_tmp >>> idx_tmp);
                            y_next = y_tmp - (x_tmp >>> idx_tmp);
                            z_next = z_tmp + ATAN_TABLE[idx_tmp];
                        end

                        x_tmp = x_next;
                        y_tmp = y_next;
                        z_tmp = z_next;
                        idx_tmp = idx_tmp + 1'b1;
                    end
                end

                x_reg <= x_tmp;
                y_reg <= y_tmp;
                z_reg <= z_tmp;
                iter_idx <= idx_tmp;

                if (idx_tmp >= IW'(N_ITER)) begin
                    busy    <= 1'b0;
                    // done is a one-cycle pulse when final iteration batch completes.
                    done    <= 1'b1;
                    cos_out <= x_tmp;
                end
            end
        end
    end
endmodule
