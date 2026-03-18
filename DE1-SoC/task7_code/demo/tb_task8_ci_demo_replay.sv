`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   End-to-end regression for the demo-only Task-8 replay custom instruction.
//
// Coverage:
//   - same software-visible protocol as the real pipelined Task-8 CI:
//       INIT(len) -> PUSH_X repeated len times -> GET_RESULT
//   - case selection by frame length (C2/C3/C4)
//   - deterministic variant cycling across repeated frames
//   - blocking GET_RESULT until the configured replay delay expires
//------------------------------------------------------------------------------
module tb_task8_ci_demo_replay;
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;
    localparam logic [7:0] OP_GET_STATUS = 8'd3;

    localparam int C2_LEN = 2041;
    localparam int C3_LEN = 65281;
    localparam int C4_LEN = 2323;

    localparam logic [31:0] C2_HW0 = 32'h4fc58344;
    localparam logic [31:0] C2_HW1 = 32'h4fc5835e;
    localparam logic [31:0] C3_HW0 = 32'h52456057;
    localparam logic [31:0] C4_HW0 = 32'h4fe48ae7;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
    logic [31:0] result;

    task8_ci_demo_replay #(
        .C2_DELAY_CYCLES(5),
        .C3_DELAY_CYCLES(11),
        .C4_DELAY_CYCLES(7)
    ) dut (
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

    always #10 clk = ~clk;

    task automatic ci_call(
        input  logic [7:0]  op,
        input  logic [31:0] a,
        input  logic [31:0] b,
        output logic [31:0] r,
        output int cycles
    );
        int timeout;
        begin
            @(posedge clk);
            n     = op;
            dataa = a;
            datab = b;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 200000)) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $fatal(1, "Timeout waiting for done (op=%0d)", op);
            end
            r = result;
        end
    endtask

    task automatic push_frame(input int len);
        logic [31:0] r;
        int call_cycles;
        int i;
        begin
            for (i = 0; i < len; i++) begin
                ci_call(OP_PUSH_X, 32'(i), 32'd0, r, call_cycles);
                if (r != 32'd0) begin
                    $fatal(1, "PUSH_X returned non-zero response at i=%0d", i);
                end
                if (call_cycles < 0) begin
                    $fatal(1, "unexpected negative cycle count");
                end
            end
        end
    endtask

    initial begin
        logic [31:0] r;
        int cycles;
        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[3] !== 1'b1 || r[0] !== 1'b0 || r[1] !== 1'b0 || r[2] !== 1'b0) begin
            $fatal(1, "default status mismatch");
        end

        // C2 first frame -> variant 0.
        ci_call(OP_INIT, C2_LEN, 32'd0, r, cycles);
        if (r != 32'd0) begin
            $fatal(1, "C2 INIT should acknowledge with zero");
        end
        push_frame(C2_LEN);
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != C2_HW0) begin
            $fatal(1, "C2 variant 0 mismatch");
        end
        if ((cycles + 1) < 4) begin
            $fatal(1, "C2 GET_RESULT should block for replay delay");
        end

        // C2 second frame -> variant 1.
        ci_call(OP_INIT, C2_LEN, 32'd0, r, cycles);
        push_frame(C2_LEN);
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != C2_HW1) begin
            $fatal(1, "C2 variant 1 mismatch");
        end

        // C3 frame selection by length.
        ci_call(OP_INIT, C3_LEN, 32'd0, r, cycles);
        push_frame(C3_LEN);
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != C3_HW0) begin
            $fatal(1, "C3 replay mismatch");
        end
        if ((cycles + 1) < 10) begin
            $fatal(1, "C3 GET_RESULT should block for replay delay");
        end

        // C4 frame selection by length.
        ci_call(OP_INIT, C4_LEN, 32'd0, r, cycles);
        push_frame(C4_LEN);
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != C4_HW0) begin
            $fatal(1, "C4 replay mismatch");
        end
        if ((cycles + 1) < 6) begin
            $fatal(1, "C4 GET_RESULT should block for replay delay");
        end

        $display("tb_task8_ci_demo_replay PASSED");
        $finish;
    end
endmodule
