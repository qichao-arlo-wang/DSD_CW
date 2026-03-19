`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Protocol-focused regression for the demo replay CI.
//
// Coverage:
//   - PUSH before INIT
//   - invalid frame length on INIT
//   - GET_RESULT before frame completion
//   - over-pushing beyond len
//   - repeated GET_RESULT after ready returns the same latched value
//------------------------------------------------------------------------------
module tb_task8_ci_demo_replay_protocol;
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;
    localparam logic [7:0] OP_GET_STATUS = 8'd3;

    localparam int C2_LEN = 2041;
    localparam logic [31:0] C2_HW0 = 32'h4fc58344;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
    logic [31:0] result;

    task8_ci_demo_replay dut (
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
            while ((done !== 1'b1) && (timeout < 50000)) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end
            if (timeout >= 50000) begin
                $fatal(1, "Timeout waiting for done (op=%0d)", op);
            end
            r = result;
        end
    endtask

    initial begin
        logic [31:0] r;
        logic [31:0] first_result;
        int cycles;
        int i;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        ci_call(OP_PUSH_X, 32'd0, 32'd0, r, cycles);
        if (r[2] !== 1'b1) begin
            $fatal(1, "PUSH before INIT should raise protocol error status");
        end

        ci_call(OP_INIT, 32'd1234, 32'd0, r, cycles);
        if (r != 32'hBAD0_1E42) begin
            $fatal(1, "invalid len should be rejected");
        end

        ci_call(OP_INIT, C2_LEN, 32'd0, r, cycles);
        if (r != 32'd0) begin
            $fatal(1, "valid INIT should acknowledge with zero");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != 32'hBAD0_1D1E) begin
            $fatal(1, "GET_RESULT before frame completion should be rejected");
        end

        for (i = 0; i < C2_LEN; i++) begin
            ci_call(OP_PUSH_X, 32'(i), 32'd0, r, cycles);
        end

        ci_call(OP_PUSH_X, 32'd0, 32'd0, r, cycles);
        if (r[2] !== 1'b1) begin
            $fatal(1, "over-push should raise protocol error");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, first_result, cycles);
        if (first_result != C2_HW0) begin
            $fatal(1, "first replay result mismatch");
        end
        if ((cycles + 1) < 2) begin
            $fatal(1, "GET_RESULT should block until replay completes");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != first_result) begin
            $fatal(1, "latched replay result should be stable");
        end
        if ((cycles + 1) > 2) begin
            $fatal(1, "second GET_RESULT should return promptly once ready");
        end

        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[1] !== 1'b1 || r[3] !== 1'b1) begin
            $fatal(1, "status should report ready demo result");
        end

        $display("tb_task8_ci_demo_replay_protocol PASSED");
        $finish;
    end
endmodule
