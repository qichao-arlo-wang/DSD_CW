//------------------------------------------------------------------------------
// Purpose:
//   Round-robin multi-lane fp32 add stage for Task 8 streaming pipeline.
//
// Design Note:
//   Each lane uses the existing Task 7 start/done wrapper. With LANES set to
//   LATENCY+4, the stage can accept one new input per cycle in steady state.
//   Two extra cycles come from the registered parent/child boundary:
//   one cycle before the child FP unit sees `start`, and one more before the
//   parent retire logic sees `done` and clears `lane_pending`. The add unit
//   wrapper itself waits one extra cycle beyond the base latency before
//   reporting a result, so the round-robin stage needs one more lane than
//   the multiply path.
//------------------------------------------------------------------------------
module task8_fp_add_rr_stage #(
    parameter int LATENCY = 3,
    parameter int LANES = LATENCY + 4,
    parameter int SIDE_W = 1
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic clear_frame,
    input  logic in_valid,
    input  logic [31:0] in_a,
    input  logic [31:0] in_b,
    input  logic [SIDE_W-1:0] in_side,
    output logic out_valid,
    output logic [31:0] out_result,
    output logic [SIDE_W-1:0] out_side,
    output logic empty,
    output logic error
);
    localparam int PTR_W = (LANES <= 1) ? 1 : $clog2(LANES);

    logic [PTR_W-1:0] issue_ptr;
    logic [PTR_W-1:0] retire_ptr;

    logic [31:0] lane_a      [0:LANES-1];
    logic [31:0] lane_b      [0:LANES-1];
    logic [31:0] lane_result [0:LANES-1];
    logic [SIDE_W-1:0] lane_side [0:LANES-1];
    logic lane_start   [0:LANES-1];
    logic lane_busy    [0:LANES-1];
    logic lane_done    [0:LANES-1];
    logic lane_pending [0:LANES-1];
    logic any_pending;

    function automatic [PTR_W-1:0] next_ptr(input [PTR_W-1:0] cur);
        begin
            if (cur == PTR_W'(LANES - 1)) begin
                next_ptr = '0;
            end else begin
                next_ptr = cur + PTR_W'(1);
            end
        end
    endfunction

    genvar g;
    generate
        for (g = 0; g < LANES; g = g + 1) begin : gen_add_lane
            task7_fp_add_ip_unit #(
                .LATENCY(LATENCY)
            ) u_add (
                .clk(clk),
                .reset(reset),
                .clk_en(clk_en),
                .start(lane_start[g]),
                .a(lane_a[g]),
                .b(lane_b[g]),
                .busy(lane_busy[g]),
                .done(lane_done[g]),
                .result(lane_result[g])
            );
        end
    endgenerate

    integer i;
    always_comb begin
        any_pending = 1'b0;
        for (int k = 0; k < LANES; k = k + 1) begin
            if (lane_pending[k]) begin
                any_pending = 1'b1;
            end
        end
        empty = !any_pending;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            issue_ptr  <= '0;
            retire_ptr <= '0;
            out_valid  <= 1'b0;
            out_result <= 32'd0;
            out_side   <= '0;
            error      <= 1'b0;
            for (i = 0; i < LANES; i = i + 1) begin
                lane_a[i]       <= 32'd0;
                lane_b[i]       <= 32'd0;
                lane_side[i]    <= '0;
                lane_start[i]   <= 1'b0;
                lane_pending[i] <= 1'b0;
            end
        end else if (clk_en) begin
            out_valid <= 1'b0;
            if (clear_frame) begin
                issue_ptr  <= '0;
                retire_ptr <= '0;
                out_valid  <= 1'b0;
                out_result <= 32'd0;
                out_side   <= '0;
                error      <= 1'b0;
                for (i = 0; i < LANES; i = i + 1) begin
                    lane_start[i]   <= 1'b0;
                    lane_pending[i] <= 1'b0;
                end
            end else begin
                for (i = 0; i < LANES; i = i + 1) begin
                    lane_start[i] <= 1'b0;
                end

                if (in_valid) begin
                    if (lane_busy[issue_ptr] || lane_pending[issue_ptr]) begin
                        error <= 1'b1;
                    end else begin
                        lane_a[issue_ptr]       <= in_a;
                        lane_b[issue_ptr]       <= in_b;
                        lane_side[issue_ptr]    <= in_side;
                        lane_start[issue_ptr]   <= 1'b1;
                        lane_pending[issue_ptr] <= 1'b1;
                        issue_ptr               <= next_ptr(issue_ptr);
                    end
                end

                if (lane_pending[retire_ptr] && lane_done[retire_ptr]) begin
                    out_valid                <= 1'b1;
                    out_result               <= lane_result[retire_ptr];
                    out_side                 <= lane_side[retire_ptr];
                    lane_pending[retire_ptr] <= 1'b0;
                    retire_ptr               <= next_ptr(retire_ptr);
                end
            end
        end
    end
endmodule
