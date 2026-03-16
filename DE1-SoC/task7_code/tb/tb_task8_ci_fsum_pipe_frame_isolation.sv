`timescale 1ns/1ps

`define HWISH_ADD_MODEL_LATENCY 3
`define HWISH_MUL_MODEL_LATENCY 3

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

module tb_task8_ci_fsum_pipe_frame_isolation;
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;

    logic clk, reset, clk_en, start, done;
    logic [31:0] dataa, datab, result;
    logic [7:0] n;

    task8_ci_fsum_pipe dut (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .n(n), .done(done), .result(result)
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

    task automatic assert_frame_quiescent(input string tag);
        begin
            if (!dut.u_core.pipeline_drained) begin
                $fatal(1, "[%s] pipeline_drained=0 after GET_RESULT", tag);
            end
            if (!dut.u_core.x2_stage_empty ||
                !dut.u_core.x3_stage_empty ||
                !dut.u_core.term_stage_empty ||
                !dut.u_core.fx_stage_empty) begin
                $fatal(1, "[%s] stage empty flags not all high", tag);
            end
            if ((dut.u_core.x3_count != 0) ||
                (dut.u_core.cos_issue_count != 0) ||
                (dut.u_core.cos_count != 0)) begin
                $fatal(1, "[%s] fifo counts not empty x3=%0d cos_issue=%0d cos=%0d",
                       tag,
                       dut.u_core.x3_count,
                       dut.u_core.cos_issue_count,
                       dut.u_core.cos_count);
            end
            if (dut.u_core.x2_valid ||
                dut.u_core.x3_valid ||
                dut.u_core.cos_valid ||
                dut.u_core.term_valid ||
                dut.u_core.fx_valid) begin
                $fatal(1, "[%s] valid pulse still active after GET_RESULT", tag);
            end
        end
    endtask

    task automatic run_linear_frame(
        input string tag,
        input integer frame_len,
        input real step
    );
        integer i;
        logic [31:0] r;
        real ref_sum;
        real got_sum;
        real abs_err;
        real tol;
        real x_val;
        begin
            ref_sum = 0.0;
            ci_call(OP_INIT, frame_len, 0, r);
            for (i = 0; i < frame_len; i = i + 1) begin
                x_val = i * step;
                ref_sum = ref_sum + ref_f(x_val);
                ci_call(OP_PUSH_X, real_to_fp32_bits(x_val), 0, r);
            end
            ci_call(OP_GET_RESULT, 0, 0, r);
            got_sum = fp32_bits_to_real(r);
            abs_err = (got_sum > ref_sum) ? (got_sum - ref_sum) : (ref_sum - got_sum);
            tol = 100.0 + 1.0e-5 * ((ref_sum >= 0.0) ? ref_sum : -ref_sum);
            if (abs_err > tol) begin
                $fatal(1, "[%s] got=%f ref=%f abs_err=%e tol=%e", tag, got_sum, ref_sum, abs_err, tol);
            end
            assert_frame_quiescent(tag);
            $display("[tb_task8_ci_fsum_pipe_frame_isolation] %s PASS got=%f ref=%f abs_err=%e",
                     tag, got_sum, ref_sum, abs_err);
        end
    endtask

    task automatic run_random_frame(
        input string tag,
        input integer frame_len,
        input integer seed_base
    );
        integer i;
        integer seed;
        logic [31:0] r;
        real ref_sum;
        real got_sum;
        real abs_err;
        real tol;
        real x_val;
        begin
            seed = seed_base;
            ref_sum = 0.0;
            ci_call(OP_INIT, frame_len, 0, r);
            for (i = 0; i < frame_len; i = i + 1) begin
                x_val = 255.0 * ($itor($urandom(seed) & 32'h7fffffff) / 2147483647.0);
                ref_sum = ref_sum + ref_f(x_val);
                ci_call(OP_PUSH_X, real_to_fp32_bits(x_val), 0, r);
                seed = seed + 1;
            end
            ci_call(OP_GET_RESULT, 0, 0, r);
            got_sum = fp32_bits_to_real(r);
            abs_err = (got_sum > ref_sum) ? (got_sum - ref_sum) : (ref_sum - got_sum);
            tol = 100.0 + 1.0e-5 * ((ref_sum >= 0.0) ? ref_sum : -ref_sum);
            if (abs_err > tol) begin
                $fatal(1, "[%s] got=%f ref=%f abs_err=%e tol=%e", tag, got_sum, ref_sum, abs_err, tol);
            end
            assert_frame_quiescent(tag);
            $display("[tb_task8_ci_fsum_pipe_frame_isolation] %s PASS got=%f ref=%f abs_err=%e",
                     tag, got_sum, ref_sum, abs_err);
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

        repeat (5) @(posedge clk);
        reset = 1'b0;

        run_linear_frame("linear_a", 2041, 0.125);
        run_linear_frame("linear_b", 257, 1.0 / 256.0);
        run_random_frame("random_c", 233, 334);
        run_linear_frame("linear_d", 2041, 0.125);

        $display("[tb_task8_ci_fsum_pipe_frame_isolation] PASS");
        $finish;
    end
endmodule
