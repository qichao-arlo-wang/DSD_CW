`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Cycle-level throughput/latency comparison for Task 8 CI block.
//
// What this test checks:
//   - Baseline Task 7 single-f(x) call latency.
//   - Task 8 pair-call latency for two samples per call.
//   - Effective cycles/sample improvement from packing two inputs in one call.
//------------------------------------------------------------------------------
module tb_task8_perf;
    localparam logic [7:0] OP_PAIR_ACCUM = 8'd0;
    localparam logic [7:0] OP_RESET_SUM = 8'd1;

    logic clk;
    logic reset;
    logic clk_en;

    logic start_fx;
    logic [31:0] dataa_fx;
    logic done_fx;
    logic [31:0] result_fx;

    logic start_t8;
    logic [31:0] dataa_t8;
    logic [31:0] datab_t8;
    logic [7:0] n_t8;
    logic done_t8;
    logic [31:0] result_t8;

    integer c_fx;
    integer c_t8_pair;
    integer c_t8_pair_2;

    task7_ci_f_single u_fx (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_fx),
        .dataa(dataa_fx),
        .datab(32'd0),
        .n(8'd0),
        .done(done_fx),
        .result(result_fx)
    );

    task8_ci_f2_accum u_t8 (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start_t8),
        .dataa(dataa_t8),
        .datab(datab_t8),
        .n(n_t8),
        .done(done_t8),
        .result(result_t8)
    );

    always #10 clk = ~clk; // 50MHz

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
        input logic [7:0] op,
        input int unsigned xa,
        input int unsigned xb,
        output integer cycles_out
    );
        integer timeout;
        begin
            @(posedge clk);
            n_t8 = op;
            dataa_t8 = int_to_fp32_bits(xa);
            datab_t8 = int_to_fp32_bits(xb);
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
        end
    endtask

    initial begin
        real eff_pair_cycles;
        real eff_pair_cycles_2;
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;

        start_fx = 1'b0;
        dataa_fx = 32'd0;

        start_t8 = 1'b0;
        dataa_t8 = 32'd0;
        datab_t8 = 32'd0;
        n_t8 = 8'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        pulse_and_measure_t8(OP_RESET_SUM, 0, 0, c_t8_pair);

        pulse_and_measure_fx(64, c_fx);
        pulse_and_measure_t8(OP_PAIR_ACCUM, 64, 63, c_t8_pair);
        pulse_and_measure_t8(OP_PAIR_ACCUM, 62, 61, c_t8_pair_2);

        eff_pair_cycles = c_t8_pair / 2.0;
        eff_pair_cycles_2 = c_t8_pair_2 / 2.0;

        $display("task7_single_fx latency_cycles=%0d", c_fx);
        $display("task8_pair_call_1 latency_cycles=%0d effective_cycles_per_sample=%f", c_t8_pair, eff_pair_cycles);
        $display("task8_pair_call_2 latency_cycles=%0d effective_cycles_per_sample=%f", c_t8_pair_2, eff_pair_cycles_2);

        // Throughput-oriented expectation: pair-call effective/sample should beat single-call cycles.
        if (!((eff_pair_cycles < c_fx) && (eff_pair_cycles_2 < c_fx))) begin
            $error("Task8 pair effective cycles/sample did not improve over Task7 single.");
        end

        $display("tb_task8_perf PASSED");
        $finish;
    end
endmodule
