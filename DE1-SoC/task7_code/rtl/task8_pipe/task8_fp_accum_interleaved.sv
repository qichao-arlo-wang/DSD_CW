//------------------------------------------------------------------------------
// Purpose:
//   Fully pipelined Task 8 reduction backend using interleaved partial sums.
//
// Design Note:
//   Incoming samples are distributed round-robin across ACC_LANES independent
//   feedback lanes. This breaks the loop-carried dependency of a single fp32
//   accumulator and allows one input per cycle when ACC_LANES >= LATENCY+4.
//   Two extra cycles come from the registered parent/child boundary:
//   one cycle before the child FP add unit sees `start`, and one more before
//   the parent retire logic sees `done` and clears `lane_pending`. The shared
//   add wrapper itself waits one extra cycle beyond the base latency before
//   reporting a result, so the interleaved accumulator also needs one
//   additional lane.
//------------------------------------------------------------------------------
module task8_fp_accum_interleaved #(
    parameter int ADD_LATENCY = 3,
    parameter int ACC_LANES = ADD_LATENCY + 4
) (
    input  logic clk,
    input  logic reset,
    input  logic clk_en,
    input  logic start,
    input  logic [31:0] total_len,
    input  logic in_valid,
    input  logic [31:0] in_data,
    output logic busy,
    output logic done,
    output logic [31:0] sum_out,
    output logic [31:0] accepted_count,
    output logic [31:0] reduced_count,
    output logic error
);
    localparam int PTR_W = (ACC_LANES <= 1) ? 1 : $clog2(ACC_LANES);
    localparam logic [PTR_W:0] REDUCE_DONE_IDX = ACC_LANES[PTR_W:0];

    typedef enum logic [1:0] {
        S_IDLE,
        S_ACCUM,
        S_REDUCE_LAUNCH,
        S_REDUCE_WAIT
    } state_t;

    state_t state;

    logic [PTR_W-1:0] issue_ptr;
    logic [31:0] partial_sum [0:ACC_LANES-1];

    logic [31:0] lane_a       [0:ACC_LANES-1];
    logic [31:0] lane_b       [0:ACC_LANES-1];
    logic [31:0] lane_result  [0:ACC_LANES-1];
    logic        lane_start   [0:ACC_LANES-1];
    logic        lane_busy    [0:ACC_LANES-1];
    logic        lane_done    [0:ACC_LANES-1];
    logic        lane_pending [0:ACC_LANES-1];

    logic [31:0] reduce_acc;
    logic [31:0] reduce_add_a;
    logic [31:0] reduce_add_b;
    logic [31:0] reduce_add_result;
    logic        reduce_add_start;
    logic        reduce_add_done;
    logic [PTR_W:0] reduce_idx;

    function automatic [PTR_W-1:0] next_ptr(input [PTR_W-1:0] cur);
        begin
            if (cur == PTR_W'(ACC_LANES - 1)) begin
                next_ptr = '0;
            end else begin
                next_ptr = cur + PTR_W'(1);
            end
        end
    endfunction

    genvar g;
    generate
        for (g = 0; g < ACC_LANES; g = g + 1) begin : gen_acc_lane
            task7_fp_add_ip_unit #(
                .LATENCY(ADD_LATENCY)
            ) u_lane_add (
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

    /* verilator lint_off PINCONNECTEMPTY */
    task7_fp_add_ip_unit #(
        .LATENCY(ADD_LATENCY)
    ) u_reduce_add (
        .clk(clk),
        .reset(reset),
        .clk_en(clk_en),
        .start(reduce_add_start),
        .a(reduce_add_a),
        .b(reduce_add_b),
        .busy(),
        .done(reduce_add_done),
        .result(reduce_add_result)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    integer i;
    integer done_hits;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            sum_out        <= 32'd0;
            accepted_count <= 32'd0;
            reduced_count  <= 32'd0;
            error          <= 1'b0;
            issue_ptr      <= '0;
            reduce_acc     <= 32'd0;
            reduce_add_a   <= 32'd0;
            reduce_add_b   <= 32'd0;
            reduce_add_start <= 1'b0;
            reduce_idx     <= '0;
            for (i = 0; i < ACC_LANES; i = i + 1) begin
                partial_sum[i]  <= 32'd0;
                lane_a[i]       <= 32'd0;
                lane_b[i]       <= 32'd0;
                lane_start[i]   <= 1'b0;
                lane_pending[i] <= 1'b0;
            end
        end else if (clk_en) begin
            done <= 1'b0;
            reduce_add_start <= 1'b0;
            for (i = 0; i < ACC_LANES; i = i + 1) begin
                lane_start[i] <= 1'b0;
            end

            /* verilator lint_off BLKSEQ */
            done_hits = 0;
            for (i = 0; i < ACC_LANES; i = i + 1) begin
                if (lane_pending[i] && lane_done[i]) begin
                    partial_sum[i]  <= lane_result[i];
                    lane_pending[i] <= 1'b0;
                    done_hits = done_hits + 1;
                end
            end
            /* verilator lint_on BLKSEQ */
            if (done_hits != 0) begin
                reduced_count <= reduced_count + done_hits;
            end

            case (state)
                S_IDLE: begin
                    if (start) begin
                        accepted_count <= 32'd0;
                        reduced_count  <= 32'd0;
                        sum_out        <= 32'd0;
                        error          <= 1'b0;
                        issue_ptr      <= '0;
                        reduce_acc     <= 32'd0;
                        reduce_idx     <= '0;
                        for (i = 0; i < ACC_LANES; i = i + 1) begin
                            partial_sum[i]  <= 32'd0;
                            lane_pending[i] <= 1'b0;
                        end
                        if (total_len == 32'd0) begin
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            sum_out <= 32'd0;
                        end else begin
                            busy  <= 1'b1;
                            state <= S_ACCUM;
                        end
                    end
                end

                S_ACCUM: begin
                    if (in_valid && (accepted_count < total_len)) begin
                        if (lane_busy[issue_ptr] || lane_pending[issue_ptr]) begin
                            error <= 1'b1;
                        end else begin
                            lane_a[issue_ptr]       <= partial_sum[issue_ptr];
                            lane_b[issue_ptr]       <= in_data;
                            lane_start[issue_ptr]   <= 1'b1;
                            lane_pending[issue_ptr] <= 1'b1;
                            accepted_count          <= accepted_count + 32'd1;
                            issue_ptr               <= next_ptr(issue_ptr);
                        end
                    end

                    // Wait until the registered partial sums already contain
                    // the final returned lane results before starting the
                    // serial reduction tree.
                    if ((accepted_count == total_len) &&
                        (reduced_count == total_len)) begin
                        reduce_acc <= partial_sum[0];
                        reduce_idx <= {{PTR_W{1'b0}}, 1'b1};
                        state      <= S_REDUCE_LAUNCH;
                    end
                end

                S_REDUCE_LAUNCH: begin
                    if (reduce_idx >= REDUCE_DONE_IDX) begin
                        busy    <= 1'b0;
                        done    <= 1'b1;
                        sum_out <= reduce_acc;
                        state   <= S_IDLE;
                    end else begin
                        reduce_add_a     <= reduce_acc;
                        reduce_add_b     <= partial_sum[reduce_idx[PTR_W-1:0]];
                        reduce_add_start <= 1'b1;
                        state            <= S_REDUCE_WAIT;
                    end
                end

                S_REDUCE_WAIT: begin
                    if (reduce_add_done) begin
                        reduce_acc <= reduce_add_result;
                        reduce_idx <= reduce_idx + 1'b1;
                        state      <= S_REDUCE_LAUNCH;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
