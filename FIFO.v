`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/26/2026 11:41:11 PM
// Design Name: 
// Module Name: FIFO
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module FIFO #(parameter DEPTH=8, DATAW = 8)(
    input clk,
    input rstn,
    input w_en, 
    input r_en,
    input [DATAW-1:0] data_in,
    output reg [DATAW-1:0] data_out,
    output full,
    output empty
    );
    localparam PTRW = $clog2(DEPTH);
    reg [PTRW-1:0]     w_ptr, r_ptr;      // address pointers (mod DEPTH, not free binary wrap)
    reg [PTRW:0]        count;
    reg [DATAW -1:0] fifo [0:DEPTH-1];
    
    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    
    wire do_write = w_en & !full;
    wire do_read  = r_en & !empty;
    
    //reset 
    always @(posedge clk) begin
        if(!rstn) begin
            w_ptr <=0; r_ptr <= 0;
            data_out <= 0;
            count <= 0;
        end else begin
            if (do_write) begin
                fifo[w_ptr] <= data_in;
                w_ptr       <= (w_ptr == DEPTH-1) ? {PTRW{1'b0}} : w_ptr + 1'b1;
            end
            if (do_read) begin
                data_out <= fifo[r_ptr];
                r_ptr    <= (r_ptr == DEPTH-1) ? {PTRW{1'b0}} : r_ptr + 1'b1;
            end
            case ({do_write, do_read})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end      
endmodule
