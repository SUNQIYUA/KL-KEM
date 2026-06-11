`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/25 20:37:39
// Design Name: 
// Module Name: mod_subtraction
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


module mod_subtraction#(
    parameter width =16
    //parameter r_mod_q =2365951
    )(
    input             clk,
    input             rst,
    input [width-1:0] data_in,
    input [22:0]      q,
    input             start,
    output reg        done,
    output reg [22:0] data_out


    );


    wire [width-1:0] data_1;
    wire [width-1:0] data_2;
    wire [width-1:0] data_3;


    assign data_1 = 13*data_in[7:0] - data_in[width-1:8] + 16'd43277;
    assign data_2 = 13*data_1[7:0] - data_1[width-1:8] +13'd3329;
    assign data_3 = (data_2 >= 13'd3329) ? (data_2 - 13'd3329) : data_2[11:0];

    always @(posedge clk or negedge rst) begin
        if (! rst) begin
            data_out <= 0;
            done     <= 0;
            
        end
        else if (start) begin
            data_out <= data_3;
            done     <= 1;
        end
        else begin
            done <= 0;
        end
    end




endmodule
