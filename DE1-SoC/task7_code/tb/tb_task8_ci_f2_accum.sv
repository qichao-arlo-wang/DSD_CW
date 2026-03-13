`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Purpose:
//   Functional regression for Task 8 CI block task8_ci_f2_accum.
//
// Coverage:
//   - All opcodes (reset/read/pair accumulate/single accumulate/pair only/single only)
//   - Running-sum consistency across mixed operation sequences
//------------------------------------------------------------------------------
module tb_task8_ci_f2_accum;
    localparam logic [7:0] OP_PAIR_ACCUM = 8'd0;
    localparam logic [7:0] OP_RESET_SUM = 8'd1;
    localparam logic [7:0] OP_READ_SUM = 8'd2;
    localparam logic [7:0] OP_SINGLE_A_ACCUM = 8'd3;
    localparam logic [7:0] OP_SINGLE_B_ACCUM = 8'd4;
    localparam logic [7:0] OP_PAIR_ONLY = 8'd5;
    localparam logic [7:0] OP_SINGLE_A_ONLY = 8'd6;
    localparam logic [7:0] OP_SINGLE_B_ONLY = 8'd7;

    logic clk;
    logic reset;
    logic clk_en;
    logic start;
    logic [31:0] dataa;
    logic [31:0] datab;
    logic [7:0] n;
    logic done;
    logic [31:0] result;

    task8_ci_f2_accum dut (
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

    always #10 clk = ~clk; // 50 MHz

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
            end else if (exp_raw == 0) begin
                mant_r = frac_raw / (2.0 ** 23);
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (-126));
            end else begin
                mant_r = 1.0 + (frac_raw / (2.0 ** 23));
                fp32_bits_to_real = sign_r * mant_r * (2.0 ** (exp_raw - 127));
            end
        end
    endfunction

    function automatic real ref_f(input real x);
        real t;
        begin
            t = (x - 128.0) / 128.0;
            ref_f = 0.5 * x + x * x * x * $cos(t);
        end
    endfunction

    task automatic check_close(
        input string tag,
        input real got,
        input real expected
    );
        real abs_err;
        real tol;
        begin
            abs_err = (got > expected) ? (got - expected) : (expected - got);
            tol = 5e-2 + 5e-5 * ((expected >= 0.0) ? expected : -expected);
            $display("%s got=%f expected=%f abs_err=%e tol=%e", tag, got, expected, abs_err, tol);
            if (abs_err > tol) begin
                $error("%s mismatch", tag);
            end
        end
    endtask

    task automatic call_cmd(
        input logic [7:0] op,
        input int unsigned xa,
        input int unsigned xb,
        output real got,
        output int cycles
    );
        int timeout;
        begin
            @(posedge clk);
            dataa = int_to_fp32_bits(xa);
            datab = int_to_fp32_bits(xb);
            n = op;
            start = 1'b1;

            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 5000)) begin
                @(posedge clk);
                cycles = cycles + 1;
                timeout = timeout + 1;
            end

            if (timeout >= 5000) begin
                $fatal(1, "Timeout waiting for done (op=%0d)", op);
            end

            got = fp32_bits_to_real(result);
            $display("op=%0d xa=%0d xb=%0d cycles=%0d result=%f", op, xa, xb, cycles, got);
        end
    endtask

    initial begin
        real got;
        real sum_ref;
        real expected;
        int cycles;
        int i;
        int unsigned xa;
        int unsigned xb;
        int op_sel;

        clk = 1'b0;
        reset = 1'b1;
        clk_en = 1'b1;
        start = 1'b0;
        dataa = 32'd0;
        datab = 32'd0;
        n = 8'd0;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        sum_ref = 0.0;

        call_cmd(OP_RESET_SUM, 0, 0, got, cycles);
        check_close("reset", got, 0.0);

        call_cmd(OP_READ_SUM, 0, 0, got, cycles);
        check_close("read_after_reset", got, 0.0);

        expected = ref_f(8.0) + ref_f(3.0);
        sum_ref = sum_ref + expected;
        call_cmd(OP_PAIR_ACCUM, 8, 3, got, cycles);
        check_close("pair_accum_8_3", got, sum_ref);

        call_cmd(OP_READ_SUM, 0, 0, got, cycles);
        check_close("read_after_pair", got, sum_ref);

        expected = ref_f(5.0);
        sum_ref = sum_ref + expected;
        call_cmd(OP_SINGLE_A_ACCUM, 5, 0, got, cycles);
        check_close("single_a_accum_5", got, sum_ref);

        expected = ref_f(7.0);
        sum_ref = sum_ref + expected;
        call_cmd(OP_SINGLE_B_ACCUM, 0, 7, got, cycles);
        check_close("single_b_accum_7", got, sum_ref);

        expected = ref_f(2.0) + ref_f(4.0);
        call_cmd(OP_PAIR_ONLY, 2, 4, got, cycles);
        check_close("pair_only_2_4", got, expected);

        call_cmd(OP_READ_SUM, 0, 0, got, cycles);
        check_close("read_after_pair_only", got, sum_ref);

        expected = ref_f(9.0);
        call_cmd(OP_SINGLE_A_ONLY, 9, 0, got, cycles);
        check_close("single_a_only_9", got, expected);

        expected = ref_f(11.0);
        call_cmd(OP_SINGLE_B_ONLY, 0, 11, got, cycles);
        check_close("single_b_only_11", got, expected);

        // Randomized mixed operations with bounded input range for stable tolerances.
        for (i = 0; i < 20; i = i + 1) begin
            xa = $urandom_range(0, 32);
            xb = $urandom_range(0, 32);
            op_sel = $urandom_range(0, 3);

            case (op_sel)
                0: begin
                    expected = ref_f(xa) + ref_f(xb);
                    sum_ref = sum_ref + expected;
                    call_cmd(OP_PAIR_ACCUM, xa, xb, got, cycles);
                    check_close("rand_pair_accum", got, sum_ref);
                end
                1: begin
                    expected = ref_f(xa);
                    sum_ref = sum_ref + expected;
                    call_cmd(OP_SINGLE_A_ACCUM, xa, xb, got, cycles);
                    check_close("rand_single_a_accum", got, sum_ref);
                end
                2: begin
                    expected = ref_f(xb);
                    sum_ref = sum_ref + expected;
                    call_cmd(OP_SINGLE_B_ACCUM, xa, xb, got, cycles);
                    check_close("rand_single_b_accum", got, sum_ref);
                end
                default: begin
                    expected = ref_f(xa) + ref_f(xb);
                    call_cmd(OP_PAIR_ONLY, xa, xb, got, cycles);
                    check_close("rand_pair_only", got, expected);
                end
            endcase
        end

        call_cmd(OP_READ_SUM, 0, 0, got, cycles);
        check_close("read_final_sum", got, sum_ref);

        $display("tb_task8_ci_f2_accum PASSED");
        $finish;
    end
endmodule
