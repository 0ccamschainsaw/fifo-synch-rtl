`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/27/2026 12:00:44 AM
// Design Name: 
// Module Name: tb1
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

module tb1;

    // Parameters
    parameter DEPTH = 8;
    parameter DATAW = 8;
    
    // Inputs
    reg clk;
    reg rstn;
    reg w_en;
    reg r_en;
    reg [DATAW-1:0] data_in;
    
    // Outputs
    wire [DATAW-1:0] data_out;
    wire full;
    wire empty;
    
    // Loop variable
    integer i;

    // Instantiate the Unit Under Test (UUT)
    FIFO #(.DEPTH(DEPTH), .DATAW(DATAW)) uut (
        .clk(clk), 
        .rstn(rstn), 
        .w_en(w_en), 
        .r_en(r_en), 
        .data_in(data_in), 
        .data_out(data_out), 
        .full(full), 
        .empty(empty)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    initial begin
        // Initialize Inputs
        clk = 0;
        rstn = 0;
        w_en = 0;
        r_en = 0;
        data_in = 0;

        // 1. Reset the FIFO
        $display("Reset");
        #15; 
        rstn = 1;
        #10;
        
        // 2. Write data until the FIFO is FULL (Testing full 8-slot capacity)
        $display("Testing Write & Full Flag");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            w_en = 1;
            data_in = i * 10 + 5; // Generating arbitrary data: 5, 15, 25...
        end
        
        // 3. Try one more write to test overflow protection
        @(posedge clk);
        $display("Time=%0t | Full Flag=%b | Last data written=%0d", $time, full, data_in);
        data_in = 99; // This should NOT be written because full==1
        $display("Time=%0t | Attempting overflow write (Data: 99)", $time);
        
        @(posedge clk);
        w_en = 0; // Stop writing
        #10;

        // 4. Read data until the FIFO is EMPTY
        $display("\nTesting Read & Empty Flag");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            r_en = 1;
        end
        
        // Wait one cycle for the last read to register on the output
        @(posedge clk);
        $display("Time=%0t | Empty Flag=%b", $time, empty);
        
        // 5. Try one more read to test underflow protection
        $display("Time=%0t | Attempting underflow read", $time);
        
        @(posedge clk);
        r_en = 0; // Stop reading
        #20;

        // 6. Test Concurrent Read and Write
        $display("\n Testing Concurrent Read and Write");
        // Pre-fill a couple of items first so we aren't reading from empty
        @(posedge clk);
        w_en = 1; data_in = 8'hAA;
        @(posedge clk);
        w_en = 1; data_in = 8'hBB;
        
        // Now read and write at the exact same time
        @(posedge clk);
        w_en = 1; r_en = 1; data_in = 8'hCC; 
        $display("Time=%0t | Wrote: %h | Read output will update next clock", $time, data_in);
        
        @(posedge clk);
        w_en = 1; r_en = 1; data_in = 8'hDD;
        $display("Time=%0t | Wrote: %h | Read: %h", $time, data_in, data_out);

        @(posedge clk);
        w_en = 0; r_en = 0;

        #50;
        $display("\n Simulation Complete");
        $finish;
    end
    
    // Optional: Monitor read outputs in the console
    always @(posedge clk) begin
        if (r_en && !empty) begin
            // We use non-blocking delay here purely for cleaner console display timing
            #1 $display("Time=%0t |   -> Read Data OUT: %0d", $time, data_out);
        end
    end
    
endmodule

