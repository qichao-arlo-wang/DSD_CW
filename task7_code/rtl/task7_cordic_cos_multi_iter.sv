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
    localparam int MAX_ITER = 24;
    localparam int IW = (N_ITER > 1) ? $clog2(N_ITER+1) : 1;

    // The constants below are precomputed for FRAC = 22.
    // If FRAC is changed, regenerate this table.
    localparam logic signed [W-1:0] K_CONST = $signed(28'sd2547003);
    localparam logic signed [W-1:0] ATAN_TABLE [0:MAX_ITER-1] = '{
        $signed(28'sd3294199),
        $signed(28'sd1944679),
        $signed(28'sd1027515),
        $signed(28'sd521583),
        $signed(28'sd261803),
        $signed(28'sd131029),
        $signed(28'sd65531),
        $signed(28'sd32767),
        $signed(28'sd16384),
        $signed(28'sd8192),
        $signed(28'sd4096),
        $signed(28'sd2048),
        $signed(28'sd1024),
        $signed(28'sd512),
        $signed(28'sd256),
        $signed(28'sd128),
        $signed(28'sd64),
        $signed(28'sd32),
        $signed(28'sd16),
        $signed(28'sd8),
        $signed(28'sd4),
        $signed(28'sd2),
        $signed(28'sd1),
        $signed(28'sd0)
    };

    logic signed [W-1:0] x_reg, y_reg, z_reg;
    logic [IW-1:0] iter_idx;

    integer k;

    initial begin
        if (FRAC != 22) begin
            $error("task7_cordic_cos_multi_iter: FRAC must be 22 with this constant table.");
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
                // Rotation mode CORDIC for cosine: start from [K, 0, angle].
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

                for (k = 0; k < ITER_PER_CYCLE; k = k + 1) begin
                    if (idx_tmp < IW'(N_ITER)) begin
                        if (z_tmp >= 0) begin
                            x_next = x_tmp - (y_tmp >>> idx_tmp);
                            y_next = y_tmp + (x_tmp >>> idx_tmp);
                            z_next = z_tmp - ATAN_TABLE[idx_tmp];
                        end else begin
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
                    done    <= 1'b1;
                    cos_out <= x_tmp;
                end
            end
        end
    end
endmodule
