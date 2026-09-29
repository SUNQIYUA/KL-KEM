`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/05 10:14:36
// Design Name: 
// Module Name: tri_mult
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


module tri_mult#(
    parameter width = 12
    )(
    input             clk,
    input             rst,

    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,
    input [width-1:0] zeta,
    
    input              din_vld,

    output             done,
    output [width-1:0] data_out

    );
    wire [width-1:0] data;
    wire data_done;

    reg [width-1:0] zeta_buff [4:0];

    always @(posedge clk or negedge rst) begin:zeta_delay_block
    integer i,j;
        if (!rst) begin
            for (i = 0; i < 5; i = i + 1) begin:reset_block
               zeta_buff[i] <= 0; 
            end
        end
        else begin
            for (j = 4; j > 0; j = j - 1) begin:zeta_buff_block
               zeta_buff[j] <= zeta_buff[j-1]; 
            end
            zeta_buff[0] <= zeta;
        end
    end

    mod_mult mult_1 (.clk(clk), .rst(rst), .data_in_1(data_in_1), .data_in_2(data_in_2), .din_vld(din_vld), .done(data_done), .data_out(data));
    mod_mult mult_2 (.clk(clk), .rst(rst), .data_in_1(data), .data_in_2(zeta_buff[4]), .din_vld(data_done), .done(done), .data_out(data_out));

endmodule
