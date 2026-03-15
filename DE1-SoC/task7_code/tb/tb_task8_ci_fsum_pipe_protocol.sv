`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Protocol-stress regression for the stateful Task-8 streaming custom
//   instruction wrapper.
//
// Coverage beyond tb_task8_ci_fsum_pipe:
//   - extra PUSH after the frame is full raises the sticky protocol flag
//   - INIT while busy is rejected without corrupting the active frame
//   - repeated GET_RESULT after completion returns the same latched sum
//   - INIT clears sticky status and resets counters for the next frame
//------------------------------------------------------------------------------
module tb_task8_ci_fsum_pipe_protocol;
    localparam logic [7:0] OP_INIT         = 8'd0;
    localparam logic [7:0] OP_PUSH_X       = 8'd1;
    localparam logic [7:0] OP_GET_RESULT   = 8'd2;
    localparam logic [7:0] OP_GET_STATUS   = 8'd3;
    localparam logic [7:0] OP_GET_ACCEPTED = 8'd4;
    localparam logic [7:0] OP_GET_FX_COUNT = 8'd5;
    localparam logic [7:0] OP_GET_REDUCED  = 8'd6;
    localparam logic [7:0] OP_BAD          = 8'd99;

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

            timeout = 0;
            cycles = 0;
            while ((done !== 1'b1) && (timeout < 30000)) begin
                @(posedge clk);
                timeout = timeout + 1;
                cycles = cycles + 1;
            end

            if (timeout >= 30000) begin
                $fatal(1, "Timeout waiting for CI done (op=%0d)", op);
            end

            r = result;
        end
    endtask

    initial begin
        int i;
        int cycles;
        real ref_sum;
        real got_sum;
        logic [31:0] r;
        int unsigned vec0 [0:3];
        int unsigned vec1 [0:2];

        vec0[0] = 5;
        vec0[1] = 9;
        vec0[2] = 63;
        vec0[3] = 128;

        vec1[0] = 2;
        vec1[1] = 30;
        vec1[2] = 200;

        clk   = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n     = 8'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        ci_call(OP_BAD, 32'd0, 32'd0, r, cycles);
        if (r != 32'hBAD0_00FF) begin
            $error("invalid opcode should return BAD signature");
        end
        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[4] !== 1'b1) begin
            $error("invalid opcode should set protocol error flag");
        end

        ci_call(OP_INIT, 32'd4, 32'd0, r, cycles);
        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[4] !== 1'b0 || r[3] !== 1'b0 || r[0] !== 1'b1 || r[1] !== 1'b1) begin
            $error("INIT should clear sticky flags and enter busy+ready state");
        end

        ref_sum = 0.0;
        for (i = 0; i < 4; i = i + 1) begin
            ref_sum = ref_sum + ref_f(vec0[i]);
            ci_call(OP_PUSH_X, int_to_fp32_bits(vec0[i]), 32'd0, r, cycles);
        end

        ci_call(OP_PUSH_X, int_to_fp32_bits(255), 32'd0, r, cycles);
        if (r[4] !== 1'b1 || r[1] !== 1'b0) begin
            $error("extra PUSH after frame fill should return protocol error status");
        end

        ci_call(OP_INIT, 32'd2, 32'd0, r, cycles);
        if (r[4] !== 1'b1) begin
            $error("INIT while busy should be rejected and return protocol error status");
        end

        ci_call(OP_GET_ACCEPTED, 32'd0, 32'd0, r, cycles);
        if (r != 32'd4) begin
            $error("accepted_count should stay at the original frame length");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        got_sum = fp32_bits_to_real(r);
        check_close("ci_pipe_protocol_frame0", got_sum, ref_sum);

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        got_sum = fp32_bits_to_real(r);
        check_close("ci_pipe_protocol_frame0_repeat", got_sum, ref_sum);
        if (cycles > 2) begin
            $error("repeated GET_RESULT after completion should be quick, got cycles=%0d", cycles);
        end

        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[2] !== 1'b1 || r[4] !== 1'b1) begin
            $error("frame-done and sticky protocol error bits should remain latched");
        end

        ci_call(OP_INIT, 32'd3, 32'd0, r, cycles);
        ci_call(OP_GET_ACCEPTED, 32'd0, 32'd0, r, cycles);
        if (r != 32'd0) begin
            $error("INIT should reset accepted_count for the next frame");
        end
        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[4] !== 1'b0 || r[2] !== 1'b0) begin
            $error("INIT should clear sticky status from the previous frame");
        end

        ref_sum = 0.0;
        for (i = 0; i < 3; i = i + 1) begin
            ref_sum = ref_sum + ref_f(vec1[i]);
            ci_call(OP_PUSH_X, int_to_fp32_bits(vec1[i]), 32'd0, r, cycles);
            if (i == 1) begin
                ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
                if (r[0] !== 1'b1) begin
                    $error("frame should still report busy during mid-frame status poll");
                end
            end
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        got_sum = fp32_bits_to_real(r);
        check_close("ci_pipe_protocol_frame1", got_sum, ref_sum);

        ci_call(OP_GET_FX_COUNT, 32'd0, 32'd0, r, cycles);
        if (r != 32'd3) begin
            $error("fx_count mismatch on second frame");
        end
        ci_call(OP_GET_REDUCED, 32'd0, 32'd0, r, cycles);
        if (r != 32'd3) begin
            $error("reduced_count mismatch on second frame");
        end

        $display("tb_task8_ci_fsum_pipe_protocol PASSED");
        $finish;
    end
endmodule
