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
    
    reg [$clog2(DEPTH)-1:0] w_ptr, r_ptr;  //make it one bit wider than needed
    reg [7:0] fifo [0:DEPTH-1];
    
    //reset 
    always @(posedge clk) begin
        if(!rstn) begin
            w_ptr <=0; r_ptr <= 0;
            data_out <= 0;
        end
        else begin 
            if (w_en & !full) begin   //write data into fifo
                fifo[w_ptr] <= data_in;
                w_ptr <= w_ptr + 1;
            end
            if (r_en & !empty) begin  //read data from fifo
                data_out <= fifo[r_ptr];
                r_ptr <= r_ptr + 1;
            end
        end
    end
    assign full = ((w_ptr+1'b1) == r_ptr);
    assign empty = (w_ptr == r_ptr);        
endmodule
