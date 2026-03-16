`timescale 1ns/1ps

module custom_fp_add(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = 3;
    logic [31:0] pipe [0:MODEL_LATENCY-1];
    integer i;

    function automatic logic [31:0] fp_add_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r + b_r;
            fp_add_model = $shortrealtobits(y_r);
        end
    endfunction

    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            q <= 32'd0;
            for (i = 0; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= 32'd0;
            end
        end else begin
            pipe[0] <= fp_add_model(a, b);
            for (i = 1; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= pipe[i-1];
            end
            q <= pipe[MODEL_LATENCY-1];
        end
    end
endmodule

module tb_task7_fp_add_ip_unit_release;
    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic busy;
    logic done;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] result;

    task7_fp_add_ip_unit #(
        .LATENCY(3)
    ) dut (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .a(a),
        .b(b),
        .busy(busy),
        .done(done),
        .result(result)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] fp32(input shortreal x);
        fp32 = $shortrealtobits(x);
    endfunction

    function automatic shortreal to_real(input logic [31:0] bits);
        to_real = $bitstoshortreal(bits);
    endfunction

    task automatic run_add(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits,
        input shortreal expected,
        input string tag
    );
        int timeout;
        shortreal got;
        begin
            @(posedge clk);
            a <= a_bits;
            b <= b_bits;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // Exercise the wrapper while the child IP continues running.
            clk_en <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            clk_en <= 1'b1;

            timeout = 0;
            while (!done && (timeout < 200)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200) begin
                $fatal(1, "%s timeout", tag);
            end

            got = to_real(result);
            if ((got < expected - 1.0e-4) || (got > expected + 1.0e-4)) begin
                $fatal(1, "%s got=%f expected=%f", tag, got, expected);
            end
        end
    endtask

    initial begin
        clk   = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        a = 32'd0;
        b = 32'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        run_add(fp32(0.0), fp32(1.0), 1.0, "seq0");
        run_add(fp32(1.0), fp32(2.0), 3.0, "seq1");
        run_add(fp32(3.0), fp32(3.0), 6.0, "seq2");
        run_add(fp32(6.0), fp32(4.0), 10.0, "seq3");

        // Verify the first result after a prior large value is not stale.
        run_add(fp32(0.0), fp32(0.0), 0.0, "reset_like0");
        run_add(fp32(0.0), fp32(0.0635587876), 0.0635587876, "reset_like1");
        run_add(fp32(0.125), fp32(0.0084678829), 0.1334678829, "reset_like2");
        run_add(fp32(0.1875), fp32(0.0286223888), 0.2161223888, "reset_like3");

        $display("[tb_task7_fp_add_ip_unit_release] PASS");
        $finish;
    end
endmodule
