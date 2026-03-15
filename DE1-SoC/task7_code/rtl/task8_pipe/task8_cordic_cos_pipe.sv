//------------------------------------------------------------------------------
// Purpose:
//   Fully pipelined fixed-point CORDIC cosine engine for Task 8 streaming use.
//
// Interface Notes:
//   - Accepts a new angle every cycle when `in_valid` is asserted.
//   - Produces one cosine result per cycle after pipeline fill.
//   - Rotation-mode CORDIC with one micro-rotation per pipeline stage.
//------------------------------------------------------------------------------
module task8_cordic_cos_pipe #(
    parameter int W = 28,
    parameter int FRAC = 22,
    parameter int N_ITER = 18
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic in_valid,
    input  logic signed [W-1:0] angle_in,
    output logic out_valid,
    output logic signed [W-1:0] cos_out
);
    localparam int MAX_ITER = 24;
    localparam int BASE_FRAC = 56;
    localparam longint signed K_CONST_BASE = 64'sd43757185469210312;

    logic signed [W-1:0] x_pipe [0:N_ITER];
    logic signed [W-1:0] y_pipe [0:N_ITER];
    logic signed [W-1:0] z_pipe [0:N_ITER];
    logic                v_pipe [0:N_ITER];

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

    function automatic logic signed [W-1:0] scale_from_base(input longint signed val_base);
        longint signed scaled;
        longint signed max_pos;
        longint signed min_neg;
        int sh;
        begin
            if (FRAC >= BASE_FRAC) begin
                sh = FRAC - BASE_FRAC;
                scaled = (sh == 0) ? val_base : (val_base <<< sh);
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

    integer i;

    initial begin
        if (N_ITER > MAX_ITER) begin
            $error("task8_cordic_cos_pipe: N_ITER exceeds table size.");
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        logic signed [W-1:0] x_next;
        logic signed [W-1:0] y_next;
        logic signed [W-1:0] z_next;
        if (reset) begin
            out_valid <= 1'b0;
            cos_out   <= '0;
            for (i = 0; i <= N_ITER; i = i + 1) begin
                x_pipe[i] <= '0;
                y_pipe[i] <= '0;
                z_pipe[i] <= '0;
                v_pipe[i] <= 1'b0;
            end
        end else if (clk_en) begin
            v_pipe[0] <= in_valid;
            if (in_valid) begin
                x_pipe[0] <= K_CONST;
                y_pipe[0] <= '0;
                z_pipe[0] <= angle_in;
            end

            for (i = 0; i < N_ITER; i = i + 1) begin
                v_pipe[i+1] <= v_pipe[i];
                if (v_pipe[i]) begin
                    /* verilator lint_off BLKSEQ */
                    if (z_pipe[i] >= 0) begin
                        x_next = x_pipe[i] - (y_pipe[i] >>> i);
                        y_next = y_pipe[i] + (x_pipe[i] >>> i);
                        z_next = z_pipe[i] - ATAN_TABLE[i];
                    end else begin
                        x_next = x_pipe[i] + (y_pipe[i] >>> i);
                        y_next = y_pipe[i] - (x_pipe[i] >>> i);
                        z_next = z_pipe[i] + ATAN_TABLE[i];
                    end
                    /* verilator lint_on BLKSEQ */
                    x_pipe[i+1] <= x_next;
                    y_pipe[i+1] <= y_next;
                    z_pipe[i+1] <= z_next;
                end
            end

            out_valid <= v_pipe[N_ITER];
            if (v_pipe[N_ITER]) begin
                cos_out <= x_pipe[N_ITER];
            end
        end
    end
endmodule
