`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   End-to-end regression for the teaching/demo Task-8 wrapper.
//
// Coverage:
//   - same software-visible protocol as the real pipelined Task-8 CI:
//       INIT(len) -> PUSH_X repeated len times -> GET_RESULT
//   - numeric result comes from the real task8_ci_f2_accum backend
//   - zero-length frame handling
//   - repeated GET_RESULT returns the same latched accumulated result
//------------------------------------------------------------------------------
module tb_task8_ci_demo_replay;
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;
    localparam logic [7:0] OP_GET_STATUS = 8'd3;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
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
                while ((msb > 0) && (val[msb] == 1'b0)) begin
                    msb = msb - 1;
                end
                rem = val - (1 << msb);
                if (msb >= 23) begin
                    mant = 23'(rem >> (msb - 23));
                end else begin
                    mant = 23'(rem << (23 - msb));
                end
                int_to_fp32_bits = {1'b0, (8'd127 + msb[7:0]), mant[22:0]};
            end
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

            if (exp_raw == 0 && frac_raw == 0) begin
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

    task automatic check_close(
        input string tag,
        input real got,
        input real expected
    );
        real abs_err;
        real tol;
        begin
            abs_err = (got > expected) ? (got - expected) : (expected - got);
            tol = 5e-2 + 5e-5 * ((expected >= 0.0) ? expected : -expected);
            $display("%s got=%f expected=%f abs_err=%e tol=%e", tag, got, expected, abs_err, tol);
            if (abs_err > tol) begin
                $fatal(1, "%s mismatch", tag);
            end
        end
    endtask

    task automatic ci_call(
        input  logic [7:0]  op,
        input  logic [31:0] a,
        input  logic [31:0] b,
        output logic [31:0] r,
        output int cycles
    );
        int timeout;
        begin
            @(posedge clk);
            n     = op;
            dataa = a;
            datab = b;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 50000)) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end
            if (timeout >= 50000) begin
                $fatal(1, "Timeout waiting for done (op=%0d)", op);
            end
            r = result;
        end
    endtask

    task automatic run_frame(
        input int unsigned x_seq[],
        input int len,
        output logic [31:0] got_bits,
        output real got_real,
        output real ref_real
    );
        logic [31:0] r;
        int cycles;
        begin
            ref_real = 0.0;
            ci_call(OP_INIT, len, 32'd0, r, cycles);
            if (r != 32'd0) begin
                $fatal(1, "INIT should acknowledge with zero");
            end

            for (int i = 0; i < len; i++) begin
                ref_real += ref_f(x_seq[i]);
                ci_call(OP_PUSH_X, int_to_fp32_bits(x_seq[i]), 32'd0, r, cycles);
                if (r != 32'd0) begin
                    $fatal(1, "PUSH_X returned non-zero response at i=%0d", i);
                end
                if (cycles < 10) begin
                    $fatal(1, "PUSH_X completed too quickly; backend did not behave as multicycle");
                end
            end

            ci_call(OP_GET_RESULT, 32'd0, 32'd0, got_bits, cycles);
            got_real = fp32_bits_to_real(got_bits);
        end
    endtask

    initial begin
        logic [31:0] r;
        logic [31:0] got_bits;
        logic [31:0] got_bits_repeat;
        int cycles;
        real got_real;
        real ref_real;
        int unsigned seq_a [0:3];
        int unsigned seq_b [0:4];

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        seq_a[0] = 0;
        seq_a[1] = 8;
        seq_a[2] = 16;
        seq_a[3] = 24;

        seq_b[0] = 5;
        seq_b[1] = 10;
        seq_b[2] = 15;
        seq_b[3] = 20;
        seq_b[4] = 25;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[3] !== 1'b1 || r[0] !== 1'b0 || r[1] !== 1'b0 || r[2] !== 1'b0) begin
            $fatal(1, "default status mismatch");
        end
        if (cycles < 0) begin
            $fatal(1, "unexpected negative cycle count");
        end
        if (r[31:16] == 16'd0) begin
            $fatal(1, "ballast signature should be observable in status");
        end

        run_frame(seq_a, 4, got_bits, got_real, ref_real);
        check_close("frame_a", got_real, ref_real);

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, got_bits_repeat, cycles);
        if (got_bits_repeat != got_bits) begin
            $fatal(1, "repeated GET_RESULT should return the same latched value");
        end

        run_frame(seq_b, 5, got_bits, got_real, ref_real);
        check_close("frame_b", got_real, ref_real);

        ci_call(OP_INIT, 32'd0, 32'd0, r, cycles);
        if (r != 32'd0) begin
            $fatal(1, "zero-length INIT should acknowledge with zero");
        end
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, got_bits, cycles);
        if (got_bits != 32'd0) begin
            $fatal(1, "zero-length frame should return 0");
        end

        $display("tb_task8_ci_demo_replay PASSED");
        $finish;
    end
endmodule
