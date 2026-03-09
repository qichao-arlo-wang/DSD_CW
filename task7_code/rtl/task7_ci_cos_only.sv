module task7_ci_cos_only #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int CORDIC_ITER_PER_CYCLE = 3
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
    localparam logic signed [FX_W-1:0] ONE_FX = $signed({{(FX_W-1){1'b0}}, 1'b1}) <<< FX_FRAC;

    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_CORDIC,
        S_OUT
    } state_t;

    state_t state;

    logic signed [CORDIC_W-1:0] cordic_angle;
    logic signed [CORDIC_W-1:0] cordic_cos;
    logic cordic_start, cordic_busy, cordic_done;

    logic signed [FX_W-1:0] cos_fx_reg;
    logic [31:0] result_fp_wire;

    logic signed [FX_W-1:0] x_fx_wire;

    function automatic logic signed [CORDIC_W-1:0] clamp_to_cordic(
        input logic signed [FX_W-1:0] in_val
    );
        logic signed [FX_W-1:0] clamped;
        begin
            if (in_val > ONE_FX) begin
                clamped = ONE_FX;
            end else if (in_val < -ONE_FX) begin
                clamped = -ONE_FX;
            end else begin
                clamped = in_val;
            end
            clamp_to_cordic = clamped[CORDIC_W-1:0];
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
        .angle_in(cordic_angle),
        .busy(cordic_busy),
        .done(cordic_done),
        .cos_out(cordic_cos)
    );

    task7_fx_to_fp32 #(
        .W(FX_W),
        .FRAC(FX_FRAC)
    ) u_out_conv (
        .fx_in(cos_fx_reg),
        .fp_out(result_fp_wire)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            result       <= '0;
            cordic_start <= 1'b0;
            cordic_angle <= '0;
            cos_fx_reg   <= '0;
        end else if (clk_en) begin
            done         <= 1'b0;
            cordic_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        cordic_angle <= clamp_to_cordic(x_fx_wire);
                        cordic_start <= 1'b1;
                        state        <= S_WAIT_CORDIC;
                    end
                end

                S_WAIT_CORDIC: begin
                    if (cordic_done) begin
                        cos_fx_reg <= {{(FX_W-CORDIC_W){cordic_cos[CORDIC_W-1]}}, cordic_cos};
                        state      <= S_OUT;
                    end
                end

                S_OUT: begin
                    result <= result_fp_wire;
                    done   <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Unused by this operation, but preserved for the standard custom-instruction interface.
    logic [31:0] datab_unused;
    logic [7:0]  n_unused;
    always_comb begin
        datab_unused = datab;
        n_unused = n;
    end
endmodule
