`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Functional regression for stateless Task 8 CI block task8_ci_f2_accum.
//
// Coverage:
//   - Software-style chained accumulation: acc_{k+1} = acc_k + f(x_k)
//   - Deterministic vectors and randomized vectors
//   - "Run reset" behavior by restarting chain with acc=0 in software
//------------------------------------------------------------------------------
module tb_task8_ci_f2_accum;
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic done;
    logic [31:0] result;

    task8_ci_f2_accum dut (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .dataa(dataa),
        .datab(datab),
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

    task automatic call_accum(
        input [31:0] acc_bits,
        input [31:0] x_bits,
        output real got,
        output [31:0] got_bits,
        output int cycles
    );
        int timeout;
        begin
            @(posedge clk);
            dataa = acc_bits;
            datab = x_bits;
            start = 1'b1;

            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 5000)) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end

            if (timeout >= 5000) begin
                $fatal(1, "Timeout waiting for done");
            end

            got_bits = result;
            got = fp32_bits_to_real(result);
            $display("acc_in=%f x=%f cycles=%0d acc_out=%f",
                     fp32_bits_to_real(acc_bits), fp32_bits_to_real(x_bits), cycles, got);
        end
    endtask

    initial begin
        int i;
        real got;
        real sum_ref;
        real x_real;
        int cycles;
        int total_cycles;
        int unsigned xv;
        logic [31:0] acc_bits;
        logic [31:0] x_bits;
        logic [31:0] got_bits;
        int unsigned x_seq [0:7];

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        x_seq[0] = 0;
        x_seq[1] = 2;
        x_seq[2] = 4;
        x_seq[3] = 8;
        x_seq[4] = 12;
        x_seq[5] = 20;
        x_seq[6] = 24;
        x_seq[7] = 31;

        // Run-1: deterministic vector
        sum_ref = 0.0;
        total_cycles = 0;
        acc_bits = int_to_fp32_bits(0);

        for (i = 0; i < 8; i = i + 1) begin
            x_real = x_seq[i];
            x_bits = int_to_fp32_bits(x_seq[i]);
            sum_ref = sum_ref + ref_f(x_real);
            call_accum(acc_bits, x_bits, got, got_bits, cycles);
            check_close("seq_accum", got, sum_ref);
            total_cycles = total_cycles + cycles;
            acc_bits = got_bits;
        end

        // Run-2: software reset via acc=0 plus randomized x values
        sum_ref = 0.0;
        acc_bits = int_to_fp32_bits(0);
        for (i = 0; i < 20; i = i + 1) begin
            xv = $urandom_range(2, 32);
            x_real = xv;
            x_bits = int_to_fp32_bits(xv);
            sum_ref = sum_ref + ref_f(x_real);
            call_accum(acc_bits, x_bits, got, got_bits, cycles);
            check_close("rand_accum", got, sum_ref);
            total_cycles = total_cycles + cycles;
            acc_bits = got_bits;
        end

        $display("tb_task8_ci_f2_accum total_cycles=%0d", total_cycles);
        $display("tb_task8_ci_f2_accum PASSED");
        $finish;
    end
endmodule
