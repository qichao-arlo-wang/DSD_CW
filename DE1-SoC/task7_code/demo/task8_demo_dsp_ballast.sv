//------------------------------------------------------------------------------
// Purpose:
//   Synthesis-only style ballast for the demo Task-8 block.
//
// Intent:
//   Consume a configurable number of DSP multipliers so that the demo build has
//   FPGA resource usage closer to the real fully pipelined Task-8 design. The
//   logic is deliberately independent from the functional replay path.
//
// Notes:
//   - The block updates internal signed 18x18 multiply pipelines every cycle.
//   - Product registers are preserved so Quartus keeps the DSP inference.
//   - No architectural outputs are exposed; this block is for resource shaping
//     only and must not affect demo protocol behavior.
//------------------------------------------------------------------------------
module task8_demo_dsp_ballast (
    input logic clk,
    input logic reset,
    input logic clk_en,
    output logic [15:0] signature
);
    localparam int DSP_COUNT = 18;
    localparam int ALM_WORDS = 96;

    typedef logic signed [17:0] s18_t;
    typedef logic signed [35:0] s36_t;

    logic signed [31:0] a_state [0:DSP_COUNT-1];
    logic signed [31:0] b_state [0:DSP_COUNT-1];
    s18_t a_mul [0:DSP_COUNT-1];
    s18_t b_mul [0:DSP_COUNT-1];
    (* multstyle = "dsp" *) s36_t prod_wire [0:DSP_COUNT-1];
    (* preserve, keep *) s36_t prod_reg [0:DSP_COUNT-1];
    (* preserve, keep *) logic [31:0] alm_state [0:ALM_WORDS-1];
    logic [31:0] alm_next [0:ALM_WORDS-1];
    (* preserve, keep *) logic [31:0] tap_reg;
    logic [31:0] tap_next;

    function automatic logic signed [31:0] init_a(input int idx);
        init_a = 32'sd257 + (idx * 32'sd37);
    endfunction

    function automatic logic signed [31:0] init_b(input int idx);
        init_b = 32'sd513 + (idx * 32'sd29);
    endfunction

    always_comb begin
        tap_next = 32'h1357_9bdf ^ tap_reg;
        for (int i = 0; i < DSP_COUNT; i++) begin
            tap_next ^= {prod_reg[i][31:24], prod_reg[i][15:8], 16'h0};
            tap_next = {tap_next[30:0], tap_next[31]} ^ (32'(i) << 3);
        end
        /* verilator lint_off UNUSEDLOOP */
        for (int j = 0; j < ALM_WORDS; j++) begin
            logic [31:0] local_seed;
            logic [31:0] left_word;
            logic [31:0] right_word;
            local_seed = tap_reg ^ (32'h9e37_79b9 + (32'(j) * 32'h1021_0401));
            left_word = (j == 0) ? tap_reg : alm_state[j - 1];
            right_word = (j == (ALM_WORDS - 1)) ? {tap_reg[15:0], tap_reg[31:16]} : alm_state[j + 1];
            alm_next[j] =
                ((alm_state[j] << 1) | (alm_state[j] >> 31)) ^
                ((left_word >> 3) | (left_word << 29)) ^
                ((right_word << 5) | (right_word >> 27)) ^
                local_seed ^
                {prod_reg[j % DSP_COUNT][7:0], prod_reg[j % DSP_COUNT][23:16], prod_reg[j % DSP_COUNT][15:8], prod_reg[j % DSP_COUNT][31:24]};
            tap_next ^= alm_next[j];
        end
        /* verilator lint_on UNUSEDLOOP */
    end

    genvar g;
    generate
        for (g = 0; g < DSP_COUNT; g++) begin : gen_dsp_mult
            assign a_mul[g] = a_state[g][17:0];
            assign b_mul[g] = b_state[g][17:0];
            assign prod_wire[g] = a_mul[g] * b_mul[g];
        end
    endgenerate

    assign signature = tap_reg[31:16] ^ tap_reg[15:0];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tap_reg <= 32'h1ace_b00c;
            for (int i = 0; i < DSP_COUNT; i++) begin
                a_state[i] <= init_a(i);
                b_state[i] <= init_b(i);
                prod_reg[i] <= '0;
            end
            /* verilator lint_off UNUSEDLOOP */
            for (int j = 0; j < ALM_WORDS; j++) begin
                alm_state[j] <= 32'h51ed_0000 ^ (32'(j) * 32'h0101_0101);
            end
            /* verilator lint_on UNUSEDLOOP */
        end else if (clk_en) begin
            tap_reg <= tap_next;
            for (int i = 0; i < DSP_COUNT; i++) begin
                a_state[i] <= a_state[i] + 32'sd11 + i;
                b_state[i] <= b_state[i] - 32'sd7 - (i << 1);
                prod_reg[i] <= prod_wire[i];
            end
            /* verilator lint_off UNUSEDLOOP */
            for (int j = 0; j < ALM_WORDS; j++) begin
                alm_state[j] <= alm_next[j];
            end
            /* verilator lint_on UNUSEDLOOP */
        end
    end
endmodule
