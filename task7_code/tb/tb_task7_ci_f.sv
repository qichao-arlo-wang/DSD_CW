`timescale 1ns/1ps

module tb_task7_ci_f;
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
    logic [31:0] result;

    task7_ci_f_single dut (
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

            if (exp_raw == 0 && frac_raw == 0) begin
                fp32_bits_to_real = 0.0;
            end else if (exp_raw == 0) begin
                mant_r = frac_raw / (2.0 ** 23);
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (-126));
            end else if (exp_raw == 255) begin
                fp32_bits_to_real = sign_b ? -1.0e300 : 1.0e300;
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

    task automatic call_ci_and_check(input int unsigned x_int, input real abs_tol, input real rel_tol);
        real got;
        real expected;
        real abs_err;
        real tol;
        real x;
        integer timeout;
        begin
            x = x_int;
            @(posedge clk);
            dataa = int_to_fp32_bits(x_int);
            datab = 32'd0;
            n     = 8'd0;
            start = 1'b1;

            @(posedge clk);
            start = 1'b0;

            timeout = 0;
            while ((done !== 1'b1) && (timeout < 1000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 1000) begin
                $fatal(1, "Timeout waiting for done");
            end

            got = fp32_bits_to_real(result);
            expected = ref_f(x);

            abs_err = (got > expected) ? (got - expected) : (expected - got);
            tol = abs_tol + rel_tol * ((expected >= 0.0) ? expected : -expected);

            $display("x=%f got=%f expected=%f abs_err=%e tol=%e", x, got, expected, abs_err, tol);
            if (abs_err > tol) begin
                $error("Result mismatch for x=%f", x);
            end
        end
    endtask

    initial begin
        integer i;
        int unsigned x_rand;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = '0;
        datab = '0;
        n = '0;

        repeat(5) @(posedge clk);
        reset = 1'b0;

        call_ci_and_check(0,   2e-2, 2e-5);
        call_ci_and_check(32,  2e-2, 2e-5);
        call_ci_and_check(64,  2e-2, 2e-5);
        call_ci_and_check(96,  2e-2, 2e-5);
        call_ci_and_check(128, 2e-2, 2e-5);
        call_ci_and_check(192, 2e-2, 2e-5);
        call_ci_and_check(255, 2e-2, 2e-5);

        for (i = 0; i < 50; i = i + 1) begin
            x_rand = $urandom_range(0, 255);
            call_ci_and_check(x_rand, 2e-2, 2e-5);
        end

        $display("tb_task7_ci_f PASSED");
        $finish;
    end
endmodule
