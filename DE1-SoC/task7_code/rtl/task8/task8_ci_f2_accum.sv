//------------------------------------------------------------------------------
// Purpose:
//   Stateless Task-8 custom instruction for software-managed accumulation.
//
// Interface Contract (matches hello_world.c mode-4):
//   dataa = acc_in, datab = x
//   result = acc_in + f(x), where
//     f(x) = 0.5*x + x^3*cos((x-128)/128)
//
// Notes:
//   - No internal running-sum register is kept in hardware.
//   - Each call is independent; software performs run-level reset via acc=0.
//------------------------------------------------------------------------------
module task8_ci_f2_accum #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int CORDIC_ITER_PER_CYCLE = 3,
    parameter int MUL_LATENCY = 3,
    parameter int ADD_LATENCY = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_en,
    input  logic        start,
    input  logic [31:0] dataa,   // acc_in
    input  logic [31:0] datab,   // x
    output logic        done,
    output logic [31:0] result
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_LAUNCH_FX,
        S_WAIT_FX,
        S_LAUNCH_ADD,
        S_WAIT_ADD,
        S_OUT
    } state_t;

    state_t state;

    logic [31:0] acc_reg;
    logic [31:0] x_reg;
    logic [31:0] fx_reg;
    logic        start_q;
    logic        start_evt;

    logic start_fx;
    logic done_fx;
    logic [31:0] result_fx;

    logic start_add;
    logic add_done;
    logic [31:0] add_result;
    /* verilator lint_off UNUSEDSIGNAL */
    logic add_busy_unused;
    /* verilator lint_on UNUSEDSIGNAL */

    assign start_fx = (state == S_LAUNCH_FX);
    assign start_add = (state == S_LAUNCH_ADD);
    assign start_evt = start & ~start_q;

    task7_ci_f_single #(
        .FX_W(FX_W),
        .FX_FRAC(FX_FRAC),
        .CORDIC_W(CORDIC_W),
        .CORDIC_FRAC(CORDIC_FRAC),
        .CORDIC_ITER(CORDIC_ITER),
        .CORDIC_ITER_PER_CYCLE(CORDIC_ITER_PER_CYCLE),
        .MUL_LATENCY(MUL_LATENCY),
        .ADD_LATENCY(ADD_LATENCY)
    ) u_fx (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_fx),
        .dataa(x_reg),
        .datab(32'd0),
        .n(8'd0),
        .done(done_fx),
        .result(result_fx)
    );

    task7_fp_add_ip_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_add),
        .a(acc_reg),
        .b(fx_reg),
        .busy(add_busy_unused),
        .done(add_done),
        .result(add_result)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= S_IDLE;
            done    <= 1'b0;
            result  <= 32'd0;
            acc_reg <= 32'd0;
            x_reg   <= 32'd0;
            fx_reg  <= 32'd0;
            start_q <= 1'b0;
        end else if (clk_en) begin
            start_q <= start;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_evt) begin
                        acc_reg <= dataa;
                        x_reg   <= datab;
                        state   <= S_LAUNCH_FX;
                    end
                end

                S_LAUNCH_FX: begin
                    state <= S_WAIT_FX;
                end

                S_WAIT_FX: begin
                    if (done_fx) begin
                        fx_reg <= result_fx;
                        state  <= S_LAUNCH_ADD;
                    end
                end

                S_LAUNCH_ADD: begin
                    state <= S_WAIT_ADD;
                end

                S_WAIT_ADD: begin
                    if (add_done) begin
                        result <= add_result;
                        state  <= S_OUT;
                    end
                end

                S_OUT: begin
                    done  <= 1'b1;
                    if (start_evt) begin
                        acc_reg <= dataa;
                        x_reg   <= datab;
                        state   <= S_LAUNCH_FX;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
