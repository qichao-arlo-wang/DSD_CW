`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Boundary-condition regression for the fully pipelined Task 8 reduction
//   core.
//
// Coverage beyond tb_task8_pipe_fsum_core:
//   - extra input presented after the requested frame length is ignored
//   - stray start pulse while busy does not corrupt the active frame
//   - counters and result reset cleanly across back-to-back frames
//------------------------------------------------------------------------------
module tb_task8_pipe_fsum_core_boundary;
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] len;
    logic in_valid;
    logic [31:0] in_data;
    logic in_ready;
    logic busy;
    logic done;
    logic [31:0] result;
    logic [31:0] accepted_count;
    logic [31:0] fx_count;
    logic [31:0] reduced_count;
    logic error;

    task8_pipe_fsum_core dut (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .len(len),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_ready(in_ready),
        .busy(busy),
        .done(done),
        .result(result),
        .accepted_count(accepted_count),
        .fx_count(fx_count),
        .reduced_count(reduced_count),
        .error(error)
    );

    always #10 clk = ~clk; // 50 MHz

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

    task automatic pulse_start(input int unsigned frame_len);
        begin
            @(posedge clk);
            len   = frame_len;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    task automatic feed_one(input int unsigned xval);
        begin
            if (in_ready !== 1'b1) begin
                $fatal(1, "in_ready deasserted before sample %0d", xval);
            end
            in_valid = 1'b1;
            in_data  = int_to_fp32_bits(xval);
            @(posedge clk);
            in_valid = 1'b0;
            in_data  = 32'd0;
        end
    endtask

    task automatic wait_done_with_timeout;
        int timeout;
        begin
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 30000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 30000) begin
                $display("timeout debug: state=%0d busy=%0b in_ready=%0b error=%0b", dut.state, busy, in_ready, error);
                $display("timeout debug: accepted=%0d fx=%0d reduced=%0d x3_count=%0d", accepted_count, fx_count, reduced_count, dut.x3_count);
                $display("timeout debug: acc_state=%0d acc_accepted=%0d acc_reduced=%0d",
                         dut.u_acc.state, dut.u_acc.accepted_count, dut.u_acc.reduced_count);
                $fatal(1, "Timeout waiting for done");
            end
        end
    endtask

    initial begin
        int unsigned vec0 [0:3];
        int unsigned vec1 [0:4];
        int i;
        real ref_sum;
        real got_sum;

        vec0[0] = 1;
        vec0[1] = 7;
        vec0[2] = 64;
        vec0[3] = 255;

        vec1[0] = 5;
        vec1[1] = 11;
        vec1[2] = 25;
        vec1[3] = 33;
        vec1[4] = 128;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        len = 32'd0;
        in_valid = 1'b0;
        in_data = 32'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        // Frame 0: feed exactly len samples, then keep driving garbage and a
        // stray start pulse while the reduction tail is still busy.
        pulse_start(4);
        if (busy !== 1'b1) begin
            $error("core should assert busy after frame start");
        end
        ref_sum = 0.0;
        for (i = 0; i < 4; i = i + 1) begin
            ref_sum = ref_sum + ref_f(vec0[i]);
            feed_one(vec0[i]);
        end

        if (in_ready !== 1'b0) begin
            $error("in_ready should drop once len samples have been accepted");
        end

        in_valid = 1'b1;
        in_data  = int_to_fp32_bits(99);
        @(posedge clk);
        in_data  = int_to_fp32_bits(123);
        @(posedge clk);
        in_valid = 1'b0;
        in_data  = 32'd0;

        @(posedge clk);
        len   = 32'd9;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait_done_with_timeout();
        if (busy !== 1'b0) begin
            $error("core should deassert busy after frame completion");
        end
        got_sum = fp32_bits_to_real(result);
        check_close("pipe_boundary_frame0", got_sum, ref_sum);
        if (accepted_count != 32'd4 || fx_count != 32'd4 || reduced_count != 32'd4) begin
            $error("frame0 counters mismatch");
        end
        if (error !== 1'b0) begin
            $error("frame0 error flag asserted unexpectedly");
        end

        // Frame 1: start immediately after completion and verify state reset.
        pulse_start(5);
        if (busy !== 1'b1) begin
            $error("core should re-enter busy on the next frame");
        end
        ref_sum = 0.0;
        for (i = 0; i < 5; i = i + 1) begin
            ref_sum = ref_sum + ref_f(vec1[i]);
            feed_one(vec1[i]);
            if ((i == 1) || (i == 3)) begin
                @(posedge clk);
            end
        end

        wait_done_with_timeout();
        got_sum = fp32_bits_to_real(result);
        check_close("pipe_boundary_frame1", got_sum, ref_sum);
        if (accepted_count != 32'd5 || fx_count != 32'd5 || reduced_count != 32'd5) begin
            $error("frame1 counters mismatch after restart");
        end
        if (error !== 1'b0) begin
            $error("frame1 error flag asserted unexpectedly");
        end

        $display("tb_task8_pipe_fsum_core_boundary PASSED");
        $finish;
    end
endmodule
