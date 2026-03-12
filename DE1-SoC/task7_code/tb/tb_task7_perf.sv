`timescale 1ns/1ps

module tb_task7_perf;
    // Detailed note:
    // This TB is meant for quick latency sanity checks during iteration.
    // For strict per-block isolation, instantiate and trigger one DUT at a time.
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;

    logic done_mul, done_add, done_cos, done_f;
    logic [31:0] result_mul, result_add, result_cos, result_f;

    integer c_mul, c_add, c_cos, c_f;

    // This TB intentionally uses a shared start/data bus to mimic a common CI interface style.
    // Important interpretation note:
    // - A start pulse can trigger all instantiated DUTs here.
    // - pulse_and_measure() tracks only one selected done signal per run.
    // - Measured cycle count is "from shared trigger edge to selected done edge".
    // Therefore this TB is good for quick relative latency checks, but not an isolated
    // single-DUT latency benchmark unless only one DUT is active in the test.
    task7_ci_fp32_mul u_mul (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .done(done_mul), .result(result_mul)
    );

    task7_ci_fp32_add u_add (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
         .dataa(dataa), .datab(datab), .done(done_add), .result(result_add)
    );

    task7_ci_cos_only u_cos (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .done(done_cos), .result(result_cos)
    );

    task7_ci_f_single u_f (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(start),
        .dataa(dataa), .datab(datab), .n(n), .done(done_f), .result(result_f)
    );

    always #10 clk = ~clk;

    function automatic [31:0] int_to_fp32_bits(input int unsigned val);
        int msb;
        int unsigned rem;
        int unsigned mant;
        begin
            if (val == 0) begin
                int_to_fp32_bits = 32'd0;
            end else begin
                msb = 31;
                while ((msb > 0) && (val[msb] == 1'b0)) msb = msb - 1;
                rem = val - (1 << msb);
                if (msb >= 23) mant = rem >> (msb - 23);
                else mant = rem << (23 - msb);
                int_to_fp32_bits = {1'b0, (8'd127 + msb[7:0]), mant[22:0]};
            end
        end
    endfunction

    task automatic pulse_and_measure(
        input string tag,
        ref logic done_sig,
        input logic [7:0] n_in,
        output integer cycles_out
    );
        begin
            @(posedge clk);
            n = n_in;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Count cycles from start deassertion until selected done rises.
            // Timeout guard avoids infinite wait if handshake is broken.
            cycles_out = 0;
            while (!done_sig && (cycles_out < 2000)) begin
                @(posedge clk);
                cycles_out = cycles_out + 1;
            end
            if (cycles_out >= 2000) begin
                $error("%s timeout", tag);
            end
            $display("%s latency_cycles=%0d", tag, cycles_out);
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        clk_en = 1;
        start = 0;
        dataa = 0;
        datab = 0;
        n = 0;

        repeat (5) @(posedge clk);
        reset = 0;

        dataa = int_to_fp32_bits(128);
        datab = int_to_fp32_bits(3);
        pulse_and_measure("step2_mul", done_mul, 8'd0, c_mul);
        pulse_and_measure("step2_add", done_add, 8'd0, c_add);
        pulse_and_measure("step2_cos", done_cos, 8'd0, c_cos);
        pulse_and_measure("step3_f",   done_f,   8'd0, c_f);

        $display("PERF_SUMMARY step2_mul=%0d step2_add=%0d step2_cos=%0d step3_f=%0d", c_mul, c_add, c_cos, c_f);
        $finish;
    end
endmodule


