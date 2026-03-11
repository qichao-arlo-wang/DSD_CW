`timescale 1ns/1ps

module tb_task7_step2_accels;
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic       n_addsub;

    logic done_mul, done_addsub, done_cos;
    logic [31:0] result_mul, result_addsub, result_cos;

    task7_ci_fp32_mul u_mul (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .done(done_mul), .result(result_mul)
    );

    task7_ci_fp32_addsub u_addsub (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .n(n_addsub), .done(done_addsub), .result(result_addsub)
    );

    task7_ci_cos_only u_cos (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .done(done_cos), .result(result_cos)
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
            end else begin
                mant_r = 1.0 + (frac_raw / (2.0 ** 23));
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (exp_raw - 127));
            end
        end
    endfunction

    task automatic pulse_start;
        begin
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        real rm, ra, rc;
        clk = 0;
        reset = 1;
        clk_en = 1;
        start = 0;
        dataa = 0;
        datab = 0;
        n_addsub = 0;

        repeat (5) @(posedge clk);
        reset = 0;

        dataa = int_to_fp32_bits(8);
        datab = int_to_fp32_bits(3);
        n_addsub = 0;

        pulse_start();
        wait(done_mul);
        rm = fp32_bits_to_real(result_mul);
        $display("step2 mul(8,3) = %f", rm);
        if ((rm < 23.9) || (rm > 24.1)) $error("mul mismatch");

        pulse_start();
        wait(done_addsub);
        ra = fp32_bits_to_real(result_addsub);
        $display("step2 add(8,3) = %f", ra);
        if ((ra < 10.9) || (ra > 11.1)) $error("add mismatch");

        pulse_start();
        wait(done_cos);
        rc = fp32_bits_to_real(result_cos);
        $display("step2 cos(8)   = %f", rc);

        n_addsub = 1'b1;
        pulse_start();
        wait(done_addsub);
        ra = fp32_bits_to_real(result_addsub);
        $display("step2 sub(8,3) = %f", ra);
        if ((ra < 4.9) || (ra > 5.1)) $error("sub mismatch");

        $display("tb_task7_step2_accels PASSED");
        $finish;
    end
endmodule


