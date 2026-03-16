`timescale 1ns/1ps

`define HWISH_MODEL_LATENCY 3
`define HWISH_FRAME_LEN 2041
`define HWISH_STEP_NUM 1
`define HWISH_STEP_DEN 8

module custom_fp_add(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = `HWISH_MODEL_LATENCY;
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
    localparam int MODEL_LATENCY = `HWISH_MODEL_LATENCY;
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

module tb_task8_ci_fsum_pipe_clk_en_glitch;
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic done;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic [31:0] result;

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

    task automatic ci_call_glitch(
        input logic [7:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        output logic [31:0] r
    );
        int timeout;
        begin
            @(posedge clk);
            clk_en = 1'b1;
            n = op;
            dataa = a;
            datab = b;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            timeout = 0;
            while ((done !== 1'b1) && (timeout < 100000)) begin
                clk_en = timeout[0] ? 1'b0 : 1'b1;
                @(posedge clk);
                timeout = timeout + 1;
            end
            clk_en = 1'b1;
            if (timeout >= 100000) begin
                $fatal(1, "timeout op=%0d", op);
            end
            r = result;
        end
    endtask

    initial begin
        integer i;
        logic [31:0] r;
        int frame_len;
        real ref_sum;
        real got_sum;
        real x_val;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;
        repeat (5) @(posedge clk);
        reset = 1'b0;

        frame_len = `HWISH_FRAME_LEN;
        ref_sum = 0.0;

        ci_call_glitch(OP_INIT, frame_len, 0, r);
        for (i = 0; i < frame_len; i = i + 1) begin
            x_val = (1.0 * i * `HWISH_STEP_NUM) / `HWISH_STEP_DEN;
            ref_sum = ref_sum + ref_f(x_val);
            ci_call_glitch(OP_PUSH_X, real_to_fp32_bits(x_val), 0, r);
        end
        ci_call_glitch(OP_GET_RESULT, 0, 0, r);
        got_sum = fp32_bits_to_real(r);

        $display("[tb_task8_ci_fsum_pipe_clk_en_glitch] got=%f ref=%f rel=%e", got_sum, ref_sum, (ref_sum != 0.0) ? ((got_sum-ref_sum)/ref_sum) : 0.0);
        $finish;
    end
endmodule
