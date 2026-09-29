`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/07 10:03:36
// Design Name: 
// Module Name: CBD_sample
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


module CBD_sample#(
    parameter ADDR_WIDTH = 8
    )(
    input clk,
    input rst,
    input [7:0] data_in,
    input       din_vld,

    output reg                   out_vld,
    output reg [11:0]            data_out_1,
    output reg [11:0]            data_out_2,
    output reg [ADDR_WIDTH-1:0]  adder_1,
    output reg [ADDR_WIDTH-1:0]  adder_2,
    output reg                   finish
    );

//标志信号
    //reg finish;
    reg first;

//中间计算变量
    wire [1:0] a0;
    wire [1:0] a1;
    wire [1:0] b0;
    wire [1:0] b1;
    wire [1:0] x0;
    wire [1:0] x1;
    wire [1:0] y0;
    wire [1:0] y1;
    wire [11:0] d0;
    wire [11:0] d1;

//将数据拆分为两个系数，并按对应规则计算出来
    assign a0[0] = data_in[0];
    assign a1[0] = data_in[1];
    assign b0[0] = data_in[2];
    assign b1[0] = data_in[3];
    assign a0[1] = data_in[4];
    assign a1[1] = data_in[5];
    assign b0[1] = data_in[6];
    assign b1[1] = data_in[7];

    assign x0 = a0[0] + a1[0];
    assign x1 = a0[1] + a1[1];
    assign y0 = b0[0] + b1[0];
    assign y1 = b0[1] + b1[1];
    
    assign d0 =(y0 == x0 + 2)? 3327:((y0 == x0 + 1)? 3328 : x0 - y0);
    assign d1 =(y1 == x1 + 2)? 3327:((y1 == x1 + 1)? 3328 : x1 - y1);

//主控制逻辑
//地址移动与输出赋值
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            adder_1    <= 0;
            adder_2    <= 0;
            first      <= 0;
            finish     <= 0;
            data_out_1 <= 0;
            data_out_2 <= 0;
            out_vld    <= 0;

            
        end
        else if (din_vld) begin
           if (adder_2 == 253) begin
               //adder_1 <= 0;
               //adder_2 <= 1;
               finish  <= 1;
               out_vld <= 1;
               first   <= 0;
               adder_1 <= 254;
               adder_2 <= 255;
               data_out_1 <= d0;
               data_out_2 <= d1;

           end
           else begin
               if (!first) begin
                   adder_1 <= 0;
                   adder_2 <= 1;
                   data_out_1 <= d0;
                   data_out_2 <= d1;
                   first      <= 1;
                   out_vld    <= 1;
                   finish     <= 0;

               end
               else begin
                   adder_1    <= adder_1+2;
                   adder_2    <= adder_2+2;
                   data_out_1 <= d0;
                   data_out_2 <= d1;
                   //first      <= 1;
                   out_vld    <= 1;
                   finish     <= 0;
               end
           end
        end
        else begin
            out_vld    <= 0;
        end
              
    end
endmodule
