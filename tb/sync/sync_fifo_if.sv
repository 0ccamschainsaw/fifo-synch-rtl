`timescale 1ns / 1ps

interface sync_fifo_if #(
    parameter integer DATAW = 8
) (
    input logic clk
);
    logic rstn;
    logic w_en;
    logic r_en;
    logic [DATAW-1:0] data_in;
    logic [DATAW-1:0] data_out;
    logic full;
    logic empty;

    clocking cb @(posedge clk);
        default input #1step output #1step;
        input rstn, data_out, full, empty;
        output w_en, r_en, data_in;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;
        input rstn, w_en, r_en, data_in, data_out, full, empty;
    endclocking
endinterface
