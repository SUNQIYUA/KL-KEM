`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 20:29:29
// Design Name: 
// Module Name: butterfly
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


module butterfly#(
    parameter width = 12,
    parameter q     = 3329
    )(
    input clk,
    input rst,

    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,
    input [width-1:0] zeta,

    //input [width-1:0] q,

    input din_vld,

    output [width-1:0] post,
    output [width-1:0] neg,

    output  done

    );

    wire [width+1:0] temp_plus;
    //wire [width+1:0] temp_sub;
    wire [width-1:0] temp_mult;

    //wire over;

    reg [width-1:0] reg_in_1 [4:0];

    always @(posedge clk or negedge rst) begin:calculation_block
    integer i;
    integer j;
        
        
        if (!rst) begin
            reg_in_1 [0]<= 0;
 
            //done     <= 0;
            
        end
        else if (din_vld) begin
            for (i = 4; i > 0; i = i - 1)begin:buff_1_block
                reg_in_1[i] <= reg_in_1 [i-1];
            end
            reg_in_1[0] <= data_in_1;
        end
        else begin
            for (j = 4; j > 0; j = j - 1)begin:buff_2_block
                reg_in_1[j] <= reg_in_1 [j-1];
            end
            reg_in_1 [0]<= 0;
        end
    end

    mod_mult mult(.clk(clk), .rst(rst), .data_in_1(data_in_2), .data_in_2(zeta), .din_vld(din_vld), .done(done), .data_out(temp_mult));

    assign temp_plus = reg_in_1[4] + temp_mult;
    //assign temp_plus = data_in_1 - temp_mult;

    assign post = (temp_plus>=q)?(temp_plus-q):temp_plus;
    assign neg  = (reg_in_1[4]+q-temp_mult>=q)?(reg_in_1[4]-temp_mult):(reg_in_1[4]+q-temp_mult);


endmodule
