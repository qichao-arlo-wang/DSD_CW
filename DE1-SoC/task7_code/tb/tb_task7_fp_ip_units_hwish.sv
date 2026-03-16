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

module custom_fp_mul(
    input  logic        clk,
    input  logic        areset,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] q
);
    localparam int MODEL_LATENCY = 3;
    logic [31:0] pipe [0:MODEL_LATENCY-1];
    integer i;

    function automatic logic [31:0] fp_mul_model(
        input logic [31:0] a_bits,
        input logic [31:0] b_bits
    );
        shortreal a_r;
        shortreal b_r;
        shortreal y_r;
        begin
            a_r = $bitstoshortreal(a_bits);
            b_r = $bitstoshortreal(b_bits);
            y_r = a_r * b_r;
            fp_mul_model = $shortrealtobits(y_r);
        end
    endfunction

    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            q <= 32'd0;
            for (i = 0; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= 32'd0;
            end
        end else begin
            pipe[0] <= fp_mul_model(a, b);
            for (i = 1; i < MODEL_LATENCY; i = i + 1) begin
                pipe[i] <= pipe[i-1];
            end
            q <= pipe[MODEL_LATENCY-1];
        end
    end
endmodule

module tb_task7_fp_ip_units_hwish;
    logic clk;
    logic reset;
    logic clk_en;

    logic        add_start;
    logic        add_busy;
    logic        add_done;
    logic [31:0] add_a;
    logic [31:0] add_b;
    logic [31:0] add_result;

    logic        mul_start;
    logic        mul_busy;
    logic        mul_done;
    logic [31:0] mul_a;
    logic [31:0] mul_b;
    logic [31:0] mul_result;

    task7_fp_add_ip_unit #(.LATENCY(3)) u_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(add_start),
        .a(add_a),
        .b(add_b),
        .busy(add_busy),
        .done(add_done),
        .result(add_result)
    );

    task7_fp_mul_ip_unit #(.LATENCY(3)) u_mul (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(mul_start),
        .a(mul_a),
        .b(mul_b),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_result)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] fp32(input shortreal x);
        fp32 = $shortrealtobits(x);
    endfunction

    function automatic shortreal to_real(input logic [31:0] bits);
        to_real = $bitstoshortreal(bits);
    endfunction

    task automatic pulse_start_add(input logic [31:0] a_bits, input logic [31:0] b_bits, output logic [31:0] y_bits);
        int timeout;
        begin
            @(posedge clk);
            add_a <= a_bits;
            add_b <= b_bits;
            add_start <= 1'b1;
            @(posedge clk);
            add_start <= 1'b0;
            clk_en <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            clk_en <= 1'b1;
            timeout = 0;
            while (!add_done && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $fatal(1, "add timeout");
            end
            y_bits = add_result;
        end
    endtask

    task automatic pulse_start_mul(input logic [31:0] a_bits, input logic [31:0] b_bits, output logic [31:0] y_bits);
        int timeout;
        begin
            @(posedge clk);
            mul_a <= a_bits;
            mul_b <= b_bits;
            mul_start <= 1'b1;
            @(posedge clk);
            mul_start <= 1'b0;
            clk_en <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            clk_en <= 1'b1;
            timeout = 0;
            while (!mul_done && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $fatal(1, "mul timeout");
            end
            y_bits = mul_result;
        end
    endtask

    initial begin
        logic [31:0] y_bits;
        shortreal y;
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        add_start = 1'b0;
        add_a = 32'd0;
        add_b = 32'd0;
        mul_start = 1'b0;
        mul_a = 32'd0;
        mul_b = 32'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        pulse_start_add(fp32(0.0), fp32(1.0), y_bits);
        y = to_real(y_bits);
        if ((y < 0.999) || (y > 1.001)) $fatal(1, "add step0 got=%f", y);

        pulse_start_add(y_bits, fp32(2.0), y_bits);
        y = to_real(y_bits);
        if ((y < 2.999) || (y > 3.001)) $fatal(1, "add step1 got=%f", y);

        pulse_start_add(y_bits, fp32(3.0), y_bits);
        y = to_real(y_bits);
        if ((y < 5.999) || (y > 6.001)) $fatal(1, "add step2 got=%f", y);

        pulse_start_add(y_bits, fp32(4.0), y_bits);
        y = to_real(y_bits);
        if ((y < 9.999) || (y > 10.001)) $fatal(1, "add step3 got=%f", y);

        pulse_start_mul(fp32(1.5), fp32(2.0), y_bits);
        y = to_real(y_bits);
        if ((y < 2.999) || (y > 3.001)) $fatal(1, "mul step0 got=%f", y);

        pulse_start_mul(y_bits, fp32(4.0), y_bits);
        y = to_real(y_bits);
        if ((y < 11.999) || (y > 12.001)) $fatal(1, "mul step1 got=%f", y);

        $display("[tb_task7_fp_ip_units_hwish] PASS");
        $finish;
    end
endmodule
