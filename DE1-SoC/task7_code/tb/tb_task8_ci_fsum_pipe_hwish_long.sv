`timescale 1ns/1ps

`ifndef HWISH_ADD_MODEL_LATENCY
`define HWISH_ADD_MODEL_LATENCY 3
`endif

`ifndef HWISH_MUL_MODEL_LATENCY
`define HWISH_MUL_MODEL_LATENCY 3
`endif

`ifndef HWISH_FRAME_LEN
`define HWISH_FRAME_LEN 128
`endif

`ifndef HWISH_STEP_NUM
`define HWISH_STEP_NUM 1
`endif

`ifndef HWISH_STEP_DEN
`define HWISH_STEP_DEN 1
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

module tb_task8_ci_fsum_pipe_hwish_long;
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;
    localparam logic [7:0] OP_GET_ACCEPTED = 8'd4;

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

    function automatic [31:0] int_to_fp32_bits(input int unsigned val);
        int msb;
        int unsigned rem;
        logic [22:0] mant;
        begin
            if (val == 0) begin
                int_to_fp32_bits = 32'd0;
            end else begin
                msb = 31;
                while ((msb > 0) && (val[msb] == 1'b0)) msb = msb - 1;
                rem = val - (1 << msb);
                if (msb >= 23) mant = 23'(rem >> (msb - 23));
                else mant = 23'(rem << (23 - msb));
                int_to_fp32_bits = {1'b0, (8'd127 + msb[7:0]), mant[22:0]};
            end
        end
    endfunction

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
            while ((done !== 1'b1) && (timeout < 100000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                $fatal(1, "timeout op=%0d", op);
            end
            r = result;
        end
    endtask

    initial begin
        integer i;
        int frame_len;
        logic [31:0] r;
        real ref_sum;
        real got_sum;
        real abs_err;
        real tol;

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

        ci_call(OP_INIT, frame_len, 0, r);
        for (i = 0; i < frame_len; i = i + 1) begin
            real x_val;
            x_val = (1.0 * i * `HWISH_STEP_NUM) / `HWISH_STEP_DEN;
            ref_sum = ref_sum + ref_f(x_val);
            if ((`HWISH_STEP_DEN == 1) && (`HWISH_STEP_NUM == 1)) begin
                ci_call(OP_PUSH_X, int_to_fp32_bits(i), 0, r);
            end else begin
                ci_call(OP_PUSH_X, real_to_fp32_bits(x_val), 0, r);
            end
        end

        ci_call(OP_GET_ACCEPTED, 0, 0, r);
        if (r != frame_len) begin
            $fatal(1, "accepted mismatch got=%0d expect=%0d", r, frame_len);
        end

        ci_call(OP_GET_RESULT, 0, 0, r);
        got_sum = fp32_bits_to_real(r);
        abs_err = (got_sum > ref_sum) ? (got_sum - ref_sum) : (ref_sum - got_sum);
        tol = 100.0 + 1.0e-6 * ((ref_sum >= 0.0) ? ref_sum : -ref_sum);
        if (abs_err > tol) begin
            $fatal(1, "long hwish mismatch got=%f ref=%f abs_err=%e tol=%e", got_sum, ref_sum, abs_err, tol);
        end

        $display("[tb_task8_ci_fsum_pipe_hwish_long] PASS got=%f ref=%f abs_err=%e tol=%e", got_sum, ref_sum, abs_err, tol);
        $finish;
    end
endmodule
