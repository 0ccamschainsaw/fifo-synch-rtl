module sync_fifo_sva #(
    parameter integer DEPTH = 8
) (
    input logic clk,
    input logic rstn,
    input logic w_en,
    input logic r_en,
    input logic full,
    input logic empty
);
    a_not_full_and_empty: assert property (
        @(posedge clk) disable iff (!rstn) !(full && empty)
    );

    a_reset_state: assert property (
        @(posedge clk) $fell(rstn) |=> (empty && !full)
    );

    a_write_clears_empty: assert property (
        @(posedge clk) disable iff (!rstn) (w_en && !full && empty) |=> !empty
    );

    a_read_clears_full: assert property (
        @(posedge clk) disable iff (!rstn) (r_en && !empty && full) |=> !full
    );

    a_no_x_flags: assert property (
        @(posedge clk) disable iff (!rstn) !$isunknown({full, empty})
    );
endmodule

module sync_fifo_model_sva #(
    parameter integer DEPTH = 8
) (
    input logic clk,
    input logic rstn,
    input integer model_count,
    input logic full,
    input logic empty
);
    a_full_matches_model: assert property (
        @(posedge clk) disable iff (!rstn) full == (model_count == DEPTH)
    );

    a_empty_matches_model: assert property (
        @(posedge clk) disable iff (!rstn) empty == (model_count == 0)
    );
endmodule

bind sync_fifo sync_fifo_sva #(.DEPTH(DEPTH)) u_sync_fifo_sva (
    .clk(clk),
    .rstn(rstn),
    .w_en(w_en),
    .r_en(r_en),
    .full(full),
    .empty(empty)
);
