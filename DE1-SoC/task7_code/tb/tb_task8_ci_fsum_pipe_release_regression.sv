`timescale 1ns/1ps

module custom_fp_add(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = 3;
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
    localparam int MODEL_LATENCY = 3;
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

module tb_task8_ci_fsum_pipe_release_regression;
    localparam int MAX_FRAME_LEN = 70000;
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;
    localparam logic [7:0] OP_GET_STATUS   = 8'd3;
    localparam logic [7:0] OP_GET_ACCEPTED = 8'd4;
    localparam logic [7:0] OP_GET_FX_COUNT = 8'd5;
    localparam logic [7:0] OP_GET_REDUCED  = 8'd6;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic done;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0]  n;
    logic [31:0] result;

    logic [31:0] x_bits_mem [0:MAX_FRAME_LEN-1];

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
            clk_en = 1'b1;
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

    task automatic expect_close(
        input string tag,
        input real got,
        input real expected,
        input real tol
    );
        real diff;
        begin
            diff = got - expected;
            if (diff < 0.0) diff = -diff;
            if (diff > tol) begin
                $fatal(1, "%s got=%e expected=%e diff=%e tol=%e", tag, got, expected, diff, tol);
            end
        end
    endtask

    task automatic run_linear_case(
        input string tag,
        input int frame_len,
        input real step,
        input real tol
    );
        logic [31:0] r;
        logic [31:0] status_after;
        logic [31:0] accepted;
        logic [31:0] fx_count;
        logic [31:0] reduced;
        real x_val;
        real ref_sum;
        real final_sum;
        begin
            ref_sum = 0.0;
            for (int i = 0; i < frame_len; i = i + 1) begin
                x_val = step * i;
                x_bits_mem[i] = real_to_fp32_bits(x_val);
                ref_sum += ref_f(x_val);
            end

            ci_call(OP_INIT, frame_len[31:0], 32'd0, r);
            for (int i = 0; i < frame_len; i = i + 1) begin
                ci_call(OP_PUSH_X, x_bits_mem[i], 32'd0, r);
            end

            ci_call(OP_GET_RESULT, 32'd0, 32'd0, r);
            ci_call(OP_GET_STATUS, 32'd0, 32'd0, status_after);
            ci_call(OP_GET_ACCEPTED, 32'd0, 32'd0, accepted);
            ci_call(OP_GET_FX_COUNT, 32'd0, 32'd0, fx_count);
            ci_call(OP_GET_REDUCED, 32'd0, 32'd0, reduced);

            if (status_after != 32'h00000004) $fatal(1, "%s status_after=0x%08x", tag, status_after);
            if (accepted != frame_len) $fatal(1, "%s accepted=%0d frame_len=%0d", tag, accepted, frame_len);
            if (fx_count != frame_len) $fatal(1, "%s fx_count=%0d frame_len=%0d", tag, fx_count, frame_len);
            if (reduced != frame_len) $fatal(1, "%s reduced=%0d frame_len=%0d", tag, reduced, frame_len);

            final_sum = fp32_bits_to_real(r);
            expect_close({tag, ".sum"}, final_sum, ref_sum, tol);

            $display("[%s] PASS sum=%e ref=%e", tag, final_sum, ref_sum);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        run_linear_case("C2", 2041, (1.0/8.0), 2.0e4);
        run_linear_case("C3", 65281, (1.0/256.0), 5.0e4);

        $display("[tb_task8_ci_fsum_pipe_release_regression] PASS");
        $finish;
    end
endmodule
