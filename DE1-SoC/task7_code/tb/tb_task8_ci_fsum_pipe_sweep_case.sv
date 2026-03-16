`timescale 1ns/1ps

`ifndef HWISH_ADD_MODEL_LATENCY
`define HWISH_ADD_MODEL_LATENCY 3
`endif

`ifndef HWISH_MUL_MODEL_LATENCY
`define HWISH_MUL_MODEL_LATENCY 3
`endif

`ifndef HWISH_FRAME_LEN
`define HWISH_FRAME_LEN 2041
`endif

`ifndef HWISH_STEP_NUM
`define HWISH_STEP_NUM 1
`endif

`ifndef HWISH_STEP_DEN
`define HWISH_STEP_DEN 8
`endif

`ifndef HWISH_NUM_RUNS
`define HWISH_NUM_RUNS 10
`endif

`ifndef HWISH_RANDOM_MODE
`define HWISH_RANDOM_MODE 0
`endif

`ifndef HWISH_RANDOM_SEED
`define HWISH_RANDOM_SEED 334
`endif

`ifndef HWISH_RANDOM_MAX
`define HWISH_RANDOM_MAX 255.0
`endif

module custom_fp_add(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = `HWISH_ADD_MODEL_LATENCY;
    logic [31:0] pipe [0:MODEL_LATENCY-1];
    integer i;

    function automatic logic [31:0] fp_add_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r + b_r;
            fp_add_model = $shortrealtobits(y_r);
        end
    endfunction

    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            q <= 32'd0;
            for (i = 0; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= 32'd0;
            end
        end else begin
            pipe[0] <= fp_add_model(a, b);
            for (i = 1; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= pipe[i-1];
            end
            q <= pipe[MODEL_LATENCY-1];
        end
    end
endmodule

module custom_fp_mul(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = `HWISH_MUL_MODEL_LATENCY;
    logic [31:0] pipe [0:MODEL_LATENCY-1];
    integer i;

    function automatic logic [31:0] fp_mul_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r * b_r;
            fp_mul_model = $shortrealtobits(y_r);
        end
    endfunction

    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            q <= 32'd0;
            for (i = 0; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= 32'd0;
            end
        end else begin
            pipe[0] <= fp_mul_model(a, b);
            for (i = 1; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= pipe[i-1];
            end
            q <= pipe[MODEL_LATENCY-1];
        end
    end
endmodule

module tb_task8_ci_fsum_pipe_sweep_case;
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;
    localparam logic [7:0] OP_GET_STATUS   = 8'd3;
    localparam logic [7:0] OP_GET_ACCEPTED = 8'd4;
    localparam logic [7:0] OP_GET_FX_COUNT = 8'd5;
    localparam logic [7:0] OP_GET_REDUCED  = 8'd6;
    localparam int FRAME_LEN = `HWISH_FRAME_LEN;
    localparam int NUM_RUNS = `HWISH_NUM_RUNS;
    localparam int RANDOM_MODE = `HWISH_RANDOM_MODE;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic done;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic [31:0] result;

    logic [31:0] x_bits_mem [0:FRAME_LEN-1];

    task8_ci_fsum_pipe dut (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .dataa(dataa),
        .datab(datab),
        .n(n),
        .done(done),
        .result(result)
    );

    always #10 clk = ~clk;

    function automatic [31:0] real_to_fp32_bits(input real x);
        shortreal x_sr;
        begin
            x_sr = x;
            real_to_fp32_bits = $shortrealtobits(x_sr);
        end
    endfunction

    function automatic real fp32_bits_to_real(input [31:0] bits);
        bit sign_b;
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
                fp32_bits_to_real = 0.0;
            end else if (exp_raw == 0) begin
                mant_r = frac_raw / (2.0 ** 23);
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (-126));
            end else begin
                mant_r = 1.0 + (frac_raw / (2.0 ** 23));
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (exp_raw - 127));
            end
        end
    endfunction

    function automatic real ref_f(input real x);
        real t;
        begin
            t = (x - 128.0) / 128.0;
            ref_f = 0.5 * x + x * x * x * $cos(t);
        end
    endfunction

    task automatic ci_call(
        input logic [7:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        output logic [31:0] r
    );
        int timeout;
        begin
            @(posedge clk);
            n = op;
            dataa = a;
            datab = b;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 1000000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 1000000) begin
                $fatal(1, "timeout op=%0d", op);
            end
            r = result;
        end
    endtask

    initial begin
        integer i;
        integer run_idx;
        integer seed;
        logic [31:0] r;
        logic [31:0] status_after;
        logic [31:0] accepted;
        logic [31:0] fx_count;
        logic [31:0] reduced;
        real x_val;
        real ref_sum;
        real final_sum;
        real abs_err;
        real rel_err;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        seed = `HWISH_RANDOM_SEED;
        ref_sum = 0.0;
        for (i = 0; i < FRAME_LEN; i = i + 1) begin
            if (RANDOM_MODE != 0) begin
                x_val = `HWISH_RANDOM_MAX * ($itor($urandom(seed) & 32'h7fffffff) / 2147483647.0);
                seed = seed + 1;
            end else begin
                x_val = (1.0 * i * `HWISH_STEP_NUM) / `HWISH_STEP_DEN;
            end
            x_bits_mem[i] = real_to_fp32_bits(x_val);
            ref_sum = ref_sum + ref_f(x_val);
        end

        repeat (5) @(posedge clk);
        reset = 1'b0;

        final_sum = 0.0;
        for (run_idx = 0; run_idx < NUM_RUNS; run_idx = run_idx + 1) begin
            ci_call(OP_INIT, FRAME_LEN, 0, r);
            for (i = 0; i < FRAME_LEN; i = i + 1) begin
                ci_call(OP_PUSH_X, x_bits_mem[i], 0, r);
            end

            ci_call(OP_GET_RESULT, 0, 0, r);
            final_sum = fp32_bits_to_real(r);
            ci_call(OP_GET_STATUS, 0, 0, status_after);
            ci_call(OP_GET_ACCEPTED, 0, 0, accepted);
            ci_call(OP_GET_FX_COUNT, 0, 0, fx_count);
            ci_call(OP_GET_REDUCED, 0, 0, reduced);

            if (run_idx == 0) begin
                $display("RUN0 status_after=0x%08x accepted=%0d fx_count=%0d reduced=%0d len=%0d result=%e",
                         status_after, accepted, fx_count, reduced, FRAME_LEN, final_sum);
            end
        end

        abs_err = (final_sum > ref_sum) ? (final_sum - ref_sum) : (ref_sum - final_sum);
        rel_err = (ref_sum != 0.0) ? (abs_err / ((ref_sum >= 0.0) ? ref_sum : -ref_sum)) : 0.0;
        $display("FINAL F_hw=%e F_ref=%e abs_err=%e rel_err=%e", final_sum, ref_sum, abs_err, rel_err);
        $finish;
    end
endmodule
