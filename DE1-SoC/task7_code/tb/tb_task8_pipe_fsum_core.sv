`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   End-to-end verification of the fully pipelined Task 8 streaming reduction
//   core without MM/DMA wrapper.
//
// What this test checks:
//   - zero-length frame handling
//   - continuous one-sample-per-cycle input acceptance
//   - end-to-end correctness of F(X) against software reference
//   - internal counters and sticky error flag
//------------------------------------------------------------------------------
module tb_task8_pipe_fsum_core;
    localparam bit TRACE_SINGLE = 1'b0;

    integer cos_seen;
    integer x2_seen;
    integer x3_seen;
    integer term_seen;
    integer fx_seen_mon;

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
            while ((done !== 1'b1) && (timeout < 20000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 20000) begin
                $display("timeout debug: busy=%0b done=%0b error=%0b accepted=%0d fx=%0d reduced=%0d",
                         busy, done, error, accepted_count, fx_count, reduced_count);
                $display("timeout debug: state=%0d x3_count=%0d acc_state=%0d acc_accepted=%0d acc_reduced=%0d",
                         dut.state, dut.x3_count, dut.u_acc.state, dut.u_acc.accepted_count, dut.u_acc.reduced_count);
                $display("timeout debug: cos=%0d x2=%0d x3=%0d term=%0d fx_mon=%0d",
                         cos_seen, x2_seen, x3_seen, term_seen, fx_seen_mon);
                $fatal(1, "Timeout waiting for done");
            end
        end
    endtask

    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clk) begin
        if (reset) begin
            cos_seen   <= 0;
            x2_seen    <= 0;
            x3_seen    <= 0;
            term_seen  <= 0;
            fx_seen_mon <= 0;
        end else begin
            if (dut.cos_valid) begin
                cos_seen <= cos_seen + 1;
                if (TRACE_SINGLE) begin
                    $display("single-stage cos=%f", $itor(dut.cos_fx) / (2.0 ** 22));
                end
            end
            if (dut.x2_valid) begin
                x2_seen <= x2_seen + 1;
                if (TRACE_SINGLE) begin
                    $display("single-stage x2=%f", fp32_bits_to_real(dut.x2_value));
                end
            end
            if (dut.x3_valid) begin
                x3_seen <= x3_seen + 1;
                if (TRACE_SINGLE) begin
                    $display("single-stage x3=%f half=%f", fp32_bits_to_real(dut.x3_value), fp32_bits_to_real(dut.x3_side));
                end
            end
            if (dut.term_valid) begin
                term_seen <= term_seen + 1;
                if (TRACE_SINGLE) begin
                    $display("single-stage term=%f half=%f", fp32_bits_to_real(dut.term_value), fp32_bits_to_real(dut.term_side));
                end
            end
            if (dut.fx_valid) begin
                fx_seen_mon <= fx_seen_mon + 1;
                if (TRACE_SINGLE) begin
                    $display("single-stage fx=%f", fp32_bits_to_real(dut.fx_value));
                end
            end
        end
    end
    /* verilator lint_on SYNCASYNCNET */

    initial begin
        int unsigned vec [0:19];
        int unsigned gap_vec [0:5];
        int i;
        real ref_sum;
        real got_sum;

        vec[0]  = 0;
        vec[1]  = 2;
        vec[2]  = 4;
        vec[3]  = 8;
        vec[4]  = 12;
        vec[5]  = 20;
        vec[6]  = 24;
        vec[7]  = 31;
        vec[8]  = 40;
        vec[9]  = 48;
        vec[10] = 63;
        vec[11] = 64;
        vec[12] = 65;
        vec[13] = 90;
        vec[14] = 96;
        vec[15] = 127;
        vec[16] = 128;
        vec[17] = 160;
        vec[18] = 192;
        vec[19] = 255;

        gap_vec[0] = 3;
        gap_vec[1] = 11;
        gap_vec[2] = 17;
        gap_vec[3] = 29;
        gap_vec[4] = 64;
        gap_vec[5] = 200;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        len = 32'd0;
        in_valid = 1'b0;
        in_data = 32'd0;
        cos_seen = 0;
        x2_seen = 0;
        x3_seen = 0;
        term_seen = 0;
        fx_seen_mon = 0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        // Zero-length frame should finish immediately.
        pulse_start(0);
        @(posedge clk);
        if (done !== 1'b1) begin
            $error("zero-length frame should assert done immediately");
        end

        // Single-sample frame isolates the f(x) datapath from multi-sample
        // reduction effects.
        pulse_start(1);
        ref_sum = ref_f(128.0);
        feed_one(128);
        wait_done_with_timeout();
        got_sum = fp32_bits_to_real(result);
        check_close("pipe_single_128", got_sum, ref_sum);

        // Gapped frame checks that the pipeline also works when input valid has
        // bubbles and does not rely on a fully continuous stream.
        ref_sum = 0.0;
        pulse_start(6);
        for (i = 0; i < 6; i = i + 1) begin
            ref_sum = ref_sum + ref_f(gap_vec[i]);
            feed_one(gap_vec[i]);
            if ((i % 2) == 0) begin
                @(posedge clk);
            end
        end
        wait_done_with_timeout();
        got_sum = fp32_bits_to_real(result);
        check_close("pipe_gap_frame", got_sum, ref_sum);
        if (accepted_count != 32'd6 || fx_count != 32'd6 || reduced_count != 32'd6 || error !== 1'b0) begin
            $error("gapped frame counters/error mismatch");
        end

        // Main frame: keep input valid every cycle and expect no back-pressure.
        ref_sum = 0.0;
        pulse_start(20);
        for (i = 0; i < 20; i = i + 1) begin
            if (in_ready !== 1'b1) begin
                $fatal(1, "Core deasserted in_ready during continuous feed at sample %0d", i);
            end
            ref_sum = ref_sum + ref_f(vec[i]);
            in_valid = 1'b1;
            in_data  = int_to_fp32_bits(vec[i]);
            @(posedge clk);
        end
        in_valid = 1'b0;
        in_data  = 32'd0;

        wait_done_with_timeout();

        got_sum = fp32_bits_to_real(result);
        check_close("pipe_fsum", got_sum, ref_sum);

        if (accepted_count != 32'd20) begin
            $error("accepted_count mismatch: got=%0d expected=20", accepted_count);
        end
        if (fx_count != 32'd20) begin
            $error("fx_count mismatch: got=%0d expected=20", fx_count);
        end
        if (reduced_count != 32'd20) begin
            $error("reduced_count mismatch: got=%0d expected=20", reduced_count);
        end
        if (error !== 1'b0) begin
            $error("pipeline error flag asserted");
        end

        $display("tb_task8_pipe_fsum_core PASSED");
        $finish;
    end
endmodule
