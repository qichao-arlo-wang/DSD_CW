`timescale 1ns/1ps

module tb_task7_cordic;
    localparam int W = 28;
    localparam int FRAC = 22;
    localparam int N_ITER = 18;
    localparam int ITER_PER_CYCLE = 3;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic signed [W-1:0] angle_in;
    logic busy;
    logic done;
    logic signed [W-1:0] cos_out;

    task7_cordic_cos_multi_iter #(
        .W(W),
        .FRAC(FRAC),
        .N_ITER(N_ITER),
        .ITER_PER_CYCLE(ITER_PER_CYCLE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(start),
        .angle_in(angle_in),
        .busy(busy),
        .done(done),
        .cos_out(cos_out)
    );

    always #10 clk = ~clk; // 50 MHz

    function automatic logic signed [W-1:0] real_to_fx(input real x);
        longint signed scaled;
        begin
            scaled = longint'(x * (2.0 ** FRAC));
            real_to_fx = scaled[W-1:0];
        end
    endfunction

    function automatic real fx_to_real(input logic signed [W-1:0] x);
        begin
            fx_to_real = $itor(x) / (2.0 ** FRAC);
        end
    endfunction

    task automatic run_case(input real theta);
        real expected;
        real got;
        real err;
        begin
            @(posedge clk);
            angle_in <= real_to_fx(theta);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            wait(done == 1'b1);
            got = fx_to_real(cos_out);
            expected = $cos(theta);
            err = (got > expected) ? (got - expected) : (expected - got);

            $display("theta=%f got=%f expected=%f abs_err=%e", theta, got, expected, err);
            if (err > 5e-5) begin
                $error("CORDIC error exceeded threshold");
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        angle_in = '0;

        repeat(5) @(posedge clk);
        reset <= 1'b0;

        run_case(-1.0);
        run_case(-0.5);
        run_case(0.0);
        run_case(0.5);
        run_case(1.0);

        $display("tb_task7_cordic PASSED");
        $finish;
    end
endmodule
