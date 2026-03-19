`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Protocol-focused regression for the teaching/demo Task-8 wrapper.
//
// Coverage:
//   - PUSH before INIT
//   - GET_RESULT before frame completion
//   - over-pushing beyond len
//   - INIT clears sticky protocol error and resets accumulated state
//------------------------------------------------------------------------------
module tb_task8_ci_demo_replay_protocol;
    localparam logic [7:0] OP_INIT       = 8'd0;
    localparam logic [7:0] OP_PUSH_X     = 8'd1;
    localparam logic [7:0] OP_GET_RESULT = 8'd2;
    localparam logic [7:0] OP_GET_STATUS = 8'd3;

    localparam logic [31:0] RESP_BAD_PROTOCOL  = 32'hBAD0_7070;
    localparam logic [31:0] RESP_BAD_NOT_READY = 32'hBAD0_1D1E;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
    logic [31:0] result;

    task8_ci_fsum_pipe dut (
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
        logic [31:0] good_result;
        int cycles;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        ci_call(OP_PUSH_X, int_to_fp32_bits(5), 32'd0, r, cycles);
        if (r != RESP_BAD_PROTOCOL) begin
            $fatal(1, "PUSH before INIT should raise protocol error");
        end
        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[2] !== 1'b1) begin
            $fatal(1, "status should report sticky protocol error");
        end

        ci_call(OP_INIT, 32'd2, 32'd0, r, cycles);
        if (r != 32'd0) begin
            $fatal(1, "INIT should clear sticky error and acknowledge with zero");
        end
        ci_call(OP_GET_STATUS, 32'd0, 32'd0, r, cycles);
        if (r[2] !== 1'b0 || r[4] !== 1'b1) begin
            $fatal(1, "status should show open frame without protocol error after INIT");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != RESP_BAD_NOT_READY) begin
            $fatal(1, "GET_RESULT before completion should be rejected");
        end

        ci_call(OP_INIT, 32'd2, 32'd0, r, cycles);
        ci_call(OP_PUSH_X, int_to_fp32_bits(8), 32'd0, r, cycles);
        if (cycles < 10) begin
            $fatal(1, "PUSH_X should exercise real multicycle backend latency");
        end
        ci_call(OP_PUSH_X, int_to_fp32_bits(16), 32'd0, r, cycles);
        ci_call(OP_PUSH_X, int_to_fp32_bits(24), 32'd0, r, cycles);
        if (r != RESP_BAD_PROTOCOL) begin
            $fatal(1, "over-push should be rejected");
        end

        ci_call(OP_GET_RESULT, 32'd0, 32'd0, good_result, cycles);
        if (good_result == 32'd0) begin
            $fatal(1, "completed 2-sample frame should produce non-zero result");
        end
        ci_call(OP_GET_RESULT, 32'd0, 32'd0, r, cycles);
        if (r != good_result) begin
            $fatal(1, "repeated GET_RESULT should remain stable");
        end

        $display("tb_task8_ci_demo_replay_protocol PASSED");
        $finish;
    end
endmodule
