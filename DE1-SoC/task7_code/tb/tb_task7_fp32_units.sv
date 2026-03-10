`timescale 1ns/1ps

module tb_task7_fp32_units;
    logic clk;
    logic reset;
    logic clk_en;

    logic mul_start, mul_busy, mul_done;
    logic [31:0] mul_a, mul_b, mul_result;

    logic add_start, add_busy, add_done;
    logic [31:0] add_a, add_b, add_result;

    task7_fp32_mul_unit #(.LATENCY(2)) u_mul (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(mul_start),
        .a(mul_a), .b(mul_b), .busy(mul_busy), .done(mul_done), .result(mul_result)
    );

    task7_fp32_add_unit #(.LATENCY(1)) u_add (
        .clk(clk), .reset(reset), .clk_en(clk_en), .start(add_start),
        .a(add_a), .b(add_b), .busy(add_busy), .done(add_done), .result(add_result)
    );

    always #10 clk = ~clk;

    task automatic check_mul(input [31:0] a, input [31:0] b, input [31:0] exp_bits, input [255:0] name);
        begin
            @(posedge clk);
            mul_a <= a;
            mul_b <= b;
            mul_start <= 1'b1;
            @(posedge clk);
            mul_start <= 1'b0;
            wait(mul_done);
            if (mul_result !== exp_bits) begin
                $error("MUL %0s mismatch: got=%h expected=%h", name, mul_result, exp_bits);
            end
        end
    endtask

    task automatic check_add(input [31:0] a, input [31:0] b, input [31:0] exp_bits, input [255:0] name);
        begin
            @(posedge clk);
            add_a <= a;
            add_b <= b;
            add_start <= 1'b1;
            @(posedge clk);
            add_start <= 1'b0;
            wait(add_done);
            if (add_result !== exp_bits) begin
                $error("ADD %0s mismatch: got=%h expected=%h", name, add_result, exp_bits);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;

        mul_start = 1'b0;
        mul_a = 32'd0;
        mul_b = 32'd0;

        add_start = 1'b0;
        add_a = 32'd0;
        add_b = 32'd0;

        repeat(5) @(posedge clk);
        reset <= 1'b0;

        // Smallest normal * 0.5 = subnormal 0x00400000.
        check_mul(32'h00800000, 32'h3F000000, 32'h00400000, "min_normal_times_half");
        // Smallest subnormal * 1 = itself.
        check_mul(32'h00000001, 32'h3F800000, 32'h00000001, "min_subnormal_times_one");

        // Two equal subnormals add to min normal.
        check_add(32'h00400000, 32'h00400000, 32'h00800000, "subnorm_add_to_min_normal");
        // Min subnormal + min subnormal = next subnormal.
        check_add(32'h00000001, 32'h00000001, 32'h00000002, "subnorm_lsb_add");

        $display("tb_task7_fp32_units PASSED");
        $finish;
    end
endmodule
