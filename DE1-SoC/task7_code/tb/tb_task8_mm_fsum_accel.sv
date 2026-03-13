`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Functional testbench for task8_mm_fsum_accel (MM control + ST input stream).
//
// What it validates:
//   - CSR programming (LEN/CTRL/STATUS/RESULT).
//   - Stream-fed accumulation with ready/valid handshake.
//   - End-to-end correctness against software real-valued reference.
//------------------------------------------------------------------------------
module tb_task8_mm_fsum_accel;
    localparam logic [3:0] ADDR_CTRL      = 4'd0;
    localparam logic [3:0] ADDR_STATUS    = 4'd1;
    localparam logic [3:0] ADDR_LEN       = 4'd2;
    localparam logic [3:0] ADDR_RESULT    = 4'd3;
    localparam logic [3:0] ADDR_CYCLES    = 4'd4;
    localparam logic [3:0] ADDR_ACCEPTED  = 4'd5;
    localparam logic [3:0] ADDR_PROCESSED = 4'd6;

    logic        clk;
    logic        reset;

    logic [3:0]  avs_address;
    logic        avs_write;
    logic [31:0] avs_writedata;
    logic        avs_read;
    logic [31:0] avs_readdata;
    /* verilator lint_off UNUSEDSIGNAL */
    logic        avs_waitrequest;
    /* verilator lint_on UNUSEDSIGNAL */

    logic        in_valid;
    logic        in_ready;
    logic [31:0] in_data;

    /* verilator lint_off UNUSEDSIGNAL */
    logic irq;
    /* verilator lint_on UNUSEDSIGNAL */

    task8_mm_fsum_accel dut (
        .clk(clk),
        .reset(reset),
        .avs_address(avs_address),
        .avs_write(avs_write),
        .avs_writedata(avs_writedata),
        .avs_read(avs_read),
        .avs_readdata(avs_readdata),
        .avs_waitrequest(avs_waitrequest),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_data),
        .irq(irq)
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

    task automatic csr_write(input [3:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            avs_address   = addr;
            avs_writedata = data;
            avs_write     = 1'b1;
            avs_read      = 1'b0;
            @(posedge clk);
            avs_write     = 1'b0;
        end
    endtask

    task automatic csr_read(input [3:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            avs_address = addr;
            avs_read    = 1'b1;
            avs_write   = 1'b0;
            @(posedge clk);
            data = avs_readdata;
            avs_read = 1'b0;
        end
    endtask

    task automatic stream_send(input int unsigned xval);
        begin
            in_data  = int_to_fp32_bits(xval);
            in_valid = 1'b1;
            while (!in_ready) begin
                @(posedge clk);
            end
            @(posedge clk);
            in_valid = 1'b0;
        end
    endtask

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

    initial begin
        real ref_sum;
        real got_sum;
        int i;
        int unsigned vec [0:5];
        int timeout;
        /* verilator lint_off UNUSEDSIGNAL */
        logic [31:0] status;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [31:0] result;
        logic [31:0] accepted;
        logic [31:0] processed;
        logic [31:0] cycles;

        vec[0] = 2;
        vec[1] = 4;
        vec[2] = 8;
        vec[3] = 12;
        vec[4] = 20;
        vec[5] = 31;

        clk = 1'b0;
        reset = 1'b1;
        avs_address = '0;
        avs_write = 1'b0;
        avs_writedata = '0;
        avs_read = 1'b0;
        in_valid = 1'b0;
        in_data = 32'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        // Program run length.
        csr_write(ADDR_LEN, 32'd6);
        // Clear + start.
        csr_write(ADDR_CTRL, 32'b11);

        ref_sum = 0.0;
        for (i = 0; i < 6; i = i + 1) begin
            ref_sum = ref_sum + ref_f(vec[i]);
            stream_send(vec[i]);
        end

        timeout = 0;
        status = 32'd0;
        while (((status[1] !== 1'b1) && (timeout < 10000))) begin
            csr_read(ADDR_STATUS, status);
            timeout = timeout + 1;
        end

        if (timeout >= 10000) begin
            $fatal(1, "Timeout waiting done");
        end

        csr_read(ADDR_RESULT, result);
        csr_read(ADDR_ACCEPTED, accepted);
        csr_read(ADDR_PROCESSED, processed);
        csr_read(ADDR_CYCLES, cycles);

        got_sum = fp32_bits_to_real(result);
        check_close("mm_accum_result", got_sum, ref_sum);

        if (accepted != 32'd6) begin
            $error("accepted mismatch: got=%0d expected=6", accepted);
        end
        if (processed != 32'd6) begin
            $error("processed mismatch: got=%0d expected=6", processed);
        end
        if (cycles == 32'd0) begin
            $error("cycles should be non-zero");
        end

        // Zero-length sanity: immediate done.
        csr_write(ADDR_LEN, 32'd0);
        csr_write(ADDR_CTRL, 32'b11);
        csr_read(ADDR_STATUS, status);
        if (status[1] !== 1'b1) begin
            $error("zero-length run should finish immediately");
        end

        $display("tb_task8_mm_fsum_accel PASSED");
        $finish;
    end
endmodule
