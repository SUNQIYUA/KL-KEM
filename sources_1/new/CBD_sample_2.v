`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/22 22:03:58
// Design Name: 
// Module Name: CBD_sample_2
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


module CBD_sample_2#(
    parameter ADDR_WIDTH = 8
    )(
    input clk,
    input rst,
    input [11:0] data_in,
    input        din_vld,

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
     //计数器，判断是否满256个系数
    reg [8:0] cnt;

//中间计算变量
    wire [1:0] a0;
    wire [1:0] a1;
    wire [1:0] a2;
    wire [1:0] b0;
    wire [1:0] b1;
    wire [1:0] b2;
    wire [1:0] x0;
    wire [1:0] x1;
    wire [1:0] y0;
    wire [1:0] y1;
    wire [11:0] d0;
    wire [11:0] d1;

//将数据拆分为两个系数，并按对应规则计算出来
    assign a0[0] = data_in[0];
    assign a1[0] = data_in[1];
    assign a2[0] = data_in[2];
    assign b0[0] = data_in[3];
    assign b1[0] = data_in[4];
    assign b2[0] = data_in[5];
    assign a0[1] = data_in[6];
    assign a1[1] = data_in[7];
    assign a2[1] = data_in[8];
    assign b0[1] = data_in[9];
    assign b1[1] = data_in[10];
    assign b2[1] = data_in[11];

    assign x0 = a0[0] + a1[0] + a2[0];
    assign x1 = a0[1] + a1[1] + a2[1];
    assign y0 = b0[0] + b1[0] + b2[0];
    assign y1 = b0[1] + b1[1] + b2[1];
    
    assign d0 = (x0 >= y0) ? (x0 - y0) : (12'd3329 - (y0 - x0));
    assign d1 = (x1 >= y1) ? (x1 - y1) : (12'd3329 - (y1 - x1));

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
            cnt        <= 0;

            
        end
        else if (din_vld) begin
           // [TOP-22][2026-09-25 复查：比较值已修正]
           // 当前 cnt==254 正确；与本版 buffer 两块拼接连接的 XSim 定向测试已验证 128 组输入后恰好一次有效 finish。
           // 顶层必须在最后一对写提交后停止本任务输入，切换多项式时清空 buffer 余量；
           // 否则 finish 后额外输入会自动开启下一组，覆盖地址 0/1。此处比较值不是完整任务握手修复。
           if (cnt == 254) begin
               //adder_1 <= 0;
               //adder_2 <= 1;
               finish  <= 1;
               out_vld <= 1;
               first   <= 0;
               cnt     <= 0;
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
                   cnt        <= cnt + 2;

               end
               else begin
                   adder_1    <= adder_1+2;
                   adder_2    <= adder_2+2;
                   data_out_1 <= d0;
                   data_out_2 <= d1;
                   //first      <= 1;
                   out_vld    <= 1;
                   cnt        <= cnt + 2;
                   finish     <= 0;
               end
           end
        end
        else begin
            out_vld    <= 0;
        end
              
    end
endmodule
