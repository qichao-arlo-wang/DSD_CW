`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Cycle-level latency sanity test for stateless Task 8 CI block.
//
// What this test checks:
//   - Baseline Task 7 single-f(x) call latency.
//   - Task 8 accumulate call latency and chained-accum correctness.
//------------------------------------------------------------------------------
module tb_task8_perf;
    logic clk;
    logic reset;
    logic clk_en;

    logic start_fx;
    logic [31:0] dataa_fx;
    logic done_fx;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] result_fx_unused;
    /* verilator lint_on UNUSEDSIGNAL */

    logic start_t8;
    logic [31:0] dataa_t8;
    logic [31:0] datab_t8;
    logic done_t8;
    logic [31:0] result_t8;

    integer c_fx;
    integer c_t8_1;
    integer c_t8_2;

    task7_ci_f_single u_fx (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_fx),
        .dataa(dataa_fx),
        .datab(32'd0),
        .n(8'd0),
        .done(done_fx),
        .result(result_fx_unused)
    );

    task8_ci_f2_accum u_t8 (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_t8),
        .dataa(dataa_t8),
        .datab(datab_t8),
        .done(done_t8),
        .result(result_t8)
    );

    always #10 clk = ~clk; // 50MHz

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
                $error("%s mismatch", tag);
            end
        end
    endtask

    task automatic pulse_and_measure_fx(
        input int unsigned x,
        output integer cycles_out
    );
        integer timeout;
        begin
            @(posedge clk);
            dataa_fx = int_to_fp32_bits(x);
            start_fx = 1'b1;
            @(posedge clk);
            start_fx = 1'b0;

            cycles_out = 0;
            timeout = 0;
            while (!done_fx && (timeout < 5000)) begin
                @(posedge clk);
                cycles_out = cycles_out + 1;
                timeout = timeout + 1;
            end
            if (timeout >= 5000) begin
                $fatal(1, "fx timeout");
            end
        end
    endtask

    task automatic pulse_and_measure_t8(
        input [31:0] acc_bits,
        input int unsigned x,
        output integer cycles_out,
        output [31:0] out_bits
    );
        integer timeout;
        begin
            @(posedge clk);
            dataa_t8 = acc_bits;
            datab_t8 = int_to_fp32_bits(x);
            start_t8 = 1'b1;
            @(posedge clk);
            start_t8 = 1'b0;

            cycles_out = 0;
            timeout = 0;
            while (!done_t8 && (timeout < 8000)) begin
                @(posedge clk);
                cycles_out = cycles_out + 1;
                timeout = timeout + 1;
            end
            if (timeout >= 8000) begin
                $fatal(1, "task8 timeout");
            end

            out_bits = result_t8;
        end
    endtask

    initial begin
        real y_fx_ref;
        real y_acc_ref;
        real y_acc_1;
        real y_acc_2;
        logic [31:0] acc_bits;
        logic [31:0] out_bits;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;

        start_fx = 1'b0;
        dataa_fx = 32'd0;

        start_t8 = 1'b0;
        dataa_t8 = 32'd0;
        datab_t8 = 32'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        pulse_and_measure_fx(64, c_fx);
        y_fx_ref = ref_f(64.0);

        acc_bits = int_to_fp32_bits(0);
        pulse_and_measure_t8(acc_bits, 64, c_t8_1, out_bits);
        y_acc_1 = fp32_bits_to_real(out_bits);
        check_close("t8_call1", y_acc_1, y_fx_ref);

        acc_bits = out_bits;
        pulse_and_measure_t8(acc_bits, 63, c_t8_2, out_bits);
        y_acc_2 = fp32_bits_to_real(out_bits);
        y_acc_ref = ref_f(64.0) + ref_f(63.0);
        check_close("t8_call2", y_acc_2, y_acc_ref);

        $display("task7_single_fx latency_cycles=%0d", c_fx);
        $display("task8_accum_call_1 latency_cycles=%0d", c_t8_1);
        $display("task8_accum_call_2 latency_cycles=%0d", c_t8_2);

        $display("tb_task8_perf PASSED");
        $finish;
    end
endmodule
