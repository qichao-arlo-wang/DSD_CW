//------------------------------------------------------------------------------
// Purpose:
//   Task 8 memory-mapped accelerator front-end for DMA-fed reduction:
//     F(X) = sum_i f(x_i),
//     f(x) = 0.5*x + x^3*cos((x-128)/128)
//
// Interface Summary:
//   - Avalon-MM control/status slave (CSR).
//   - Avalon-ST sink for streaming fp32 samples from DMA.
//   - Optional interrupt output when run is completed.
//
// Design Intent:
//   - Remove per-sample custom-instruction software overhead.
//   - Keep arithmetic core reuse from Task 7 (single-f(x) + fp add unit).
//   - Functional baseline first; throughput can be improved with deeper pipelining.
//------------------------------------------------------------------------------
module task8_mm_fsum_accel #(
    parameter int FX_W = 40,
    parameter int FX_FRAC = 22,
    parameter int CORDIC_W = 28,
    parameter int CORDIC_FRAC = 22,
    parameter int CORDIC_ITER = 18,
    parameter int CORDIC_ITER_PER_CYCLE = 3,
    parameter int MUL_LATENCY = 3,
    parameter int ADD_LATENCY = 3,
    parameter int ADDR_W = 4
) (
    input  logic                  clk,
    input  logic                  reset,

    // Avalon-MM CSR slave.
    input  logic [ADDR_W-1:0]     avs_address,
    input  logic                  avs_write,
    input  logic [31:0]           avs_writedata,
    input  logic                  avs_read,
    output logic [31:0]           avs_readdata,
    output logic                  avs_waitrequest,

    // Avalon-ST sink (DMA source feeds this stream).
    input  logic                  in_valid,
    output logic                  in_ready,
    input  logic [31:0]           in_data,

    // Optional interrupt line.
    output logic                  irq
);
    localparam logic [ADDR_W-1:0] ADDR_CTRL         = 4'd0;
    localparam logic [ADDR_W-1:0] ADDR_STATUS       = 4'd1;
    localparam logic [ADDR_W-1:0] ADDR_LEN          = 4'd2;
    localparam logic [ADDR_W-1:0] ADDR_RESULT       = 4'd3;
    localparam logic [ADDR_W-1:0] ADDR_CYCLES       = 4'd4;
    localparam logic [ADDR_W-1:0] ADDR_ACCEPTED     = 4'd5;
    localparam logic [ADDR_W-1:0] ADDR_PROCESSED    = 4'd6;
    localparam logic [ADDR_W-1:0] ADDR_VERSION      = 4'd7;

    localparam logic [31:0] VERSION_WORD = 32'h5438_4D4D; // "T8MM"

    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_SAMPLE,
        S_LAUNCH_FX,
        S_WAIT_FX,
        S_LAUNCH_ADD,
        S_WAIT_ADD,
        S_DONE
    } state_t;

    state_t state;

    logic        busy_reg;
    logic        done_reg;
    logic        err_reg;
    logic        irq_en_reg;

    logic [31:0] len_reg;
    logic [31:0] sum_reg;
    logic [31:0] cycles_reg;
    logic [31:0] accepted_reg;
    logic [31:0] processed_reg;

    logic [31:0] x_reg;
    logic [31:0] fx_reg;

    logic start_cmd;
    logic clear_cmd;
    logic irq_en_wr;

    logic start_fx;
    logic done_fx;
    logic [31:0] result_fx;

    logic start_add;
    logic add_done;
    logic [31:0] add_result;
    /* verilator lint_off UNUSEDSIGNAL */
    logic add_busy_unused;
    /* verilator lint_on UNUSEDSIGNAL */

    assign start_cmd = avs_write && (avs_address == ADDR_CTRL) && avs_writedata[0];
    assign clear_cmd = avs_write && (avs_address == ADDR_CTRL) && avs_writedata[1];
    assign irq_en_wr = avs_write && (avs_address == ADDR_CTRL);

    // Waitrequest is permanently deasserted in this simple CSR slave.
    assign avs_waitrequest = 1'b0;
    assign irq = done_reg && irq_en_reg;

    assign in_ready = (state == S_WAIT_SAMPLE) && busy_reg && (accepted_reg < len_reg);

    // One-cycle launch pulses for child units.
    assign start_fx = (state == S_LAUNCH_FX);
    assign start_add = (state == S_LAUNCH_ADD);

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
        .clk_en(1'b1),
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
        .clk_en(1'b1),
        .start(start_add),
        .a(sum_reg),
        .b(fx_reg),
        .busy(add_busy_unused),
        .done(add_done),
        .result(add_result)
    );

    // CSR reads are purely combinational.
    always_comb begin
        avs_readdata = 32'd0;
        if (avs_read) begin
            unique case (avs_address)
                ADDR_CTRL: begin
                    avs_readdata = {29'd0, irq_en_reg, 1'b0, 1'b0};
                end
                ADDR_STATUS: begin
                    avs_readdata = {29'd0, err_reg, done_reg, busy_reg};
                end
                ADDR_LEN: begin
                    avs_readdata = len_reg;
                end
                ADDR_RESULT: begin
                    avs_readdata = sum_reg;
                end
                ADDR_CYCLES: begin
                    avs_readdata = cycles_reg;
                end
                ADDR_ACCEPTED: begin
                    avs_readdata = accepted_reg;
                end
                ADDR_PROCESSED: begin
                    avs_readdata = processed_reg;
                end
                ADDR_VERSION: begin
                    avs_readdata = VERSION_WORD;
                end
                default: begin
                    avs_readdata = 32'd0;
                end
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= S_IDLE;
            busy_reg      <= 1'b0;
            done_reg      <= 1'b0;
            err_reg       <= 1'b0;
            irq_en_reg    <= 1'b0;
            len_reg       <= 32'd0;
            sum_reg       <= 32'd0;
            cycles_reg    <= 32'd0;
            accepted_reg  <= 32'd0;
            processed_reg <= 32'd0;
            x_reg         <= 32'd0;
            fx_reg        <= 32'd0;
        end else begin
            // Sticky writeable control bit.
            if (irq_en_wr) begin
                irq_en_reg <= avs_writedata[2];
            end

            // LEN is software-programmed before START.
            if (avs_write && (avs_address == ADDR_LEN)) begin
                len_reg <= avs_writedata;
            end

            // Clear command is allowed both idle and busy.
            if (clear_cmd) begin
                sum_reg       <= 32'd0;
                cycles_reg    <= 32'd0;
                accepted_reg  <= 32'd0;
                processed_reg <= 32'd0;
                done_reg      <= 1'b0;
                err_reg       <= 1'b0;
                if (!busy_reg) begin
                    state <= S_IDLE;
                end
            end

            if (busy_reg) begin
                cycles_reg <= cycles_reg + 32'd1;
            end

            case (state)
                S_IDLE: begin
                    if (start_cmd) begin
                        done_reg      <= 1'b0;
                        err_reg       <= 1'b0;
                        cycles_reg    <= 32'd0;
                        accepted_reg  <= 32'd0;
                        processed_reg <= 32'd0;
                        if (len_reg == 32'd0) begin
                            busy_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state    <= S_DONE;
                        end else begin
                            busy_reg <= 1'b1;
                            state    <= S_WAIT_SAMPLE;
                        end
                    end
                end

                S_WAIT_SAMPLE: begin
                    if (start_cmd) begin
                        // Software protocol violation: start while already running.
                        err_reg <= 1'b1;
                    end

                    if (in_valid && in_ready) begin
                        x_reg         <= in_data;
                        accepted_reg  <= accepted_reg + 32'd1;
                        state         <= S_LAUNCH_FX;
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
                        sum_reg       <= add_result;
                        processed_reg <= processed_reg + 32'd1;

                        if ((processed_reg + 32'd1) >= len_reg) begin
                            busy_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state    <= S_DONE;
                        end else begin
                            state <= S_WAIT_SAMPLE;
                        end
                    end
                end

                S_DONE: begin
                    if (start_cmd) begin
                        done_reg      <= 1'b0;
                        err_reg       <= 1'b0;
                        cycles_reg    <= 32'd0;
                        accepted_reg  <= 32'd0;
                        processed_reg <= 32'd0;
                        if (len_reg == 32'd0) begin
                            busy_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state    <= S_DONE;
                        end else begin
                            busy_reg <= 1'b1;
                            state    <= S_WAIT_SAMPLE;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
