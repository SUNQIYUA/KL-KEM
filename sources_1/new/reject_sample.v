`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/07 08:48:08
// Design Name: 
// Module Name: reject_sample
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


module reject_sample#(
    parameter ADDR_WIDTH = 8,
    parameter q = 3329
    )(
    input clk,
    input rst,
    input din_vld,
    input [7:0] data_in_1,
    input [7:0] data_in_2,
    input [7:0] data_in_3,
    
    output reg [ADDR_WIDTH-1:0] adder_1, 
    output reg [ADDR_WIDTH-1:0] adder_2,
    output reg                  out_1_vld, 
    output reg                  out_2_vld, 
    output reg [11:0]           data_out_1,
    output reg [11:0]           data_out_2,
    output reg                  finish

    );

//将3个8bit数据重组为2个12bit数据
    wire [11:0] data_1;
    wire [11:0] data_2;
    assign data_1 = {data_in_2[3:0],data_in_1};
    assign data_2 = {data_in_3,data_in_2[7:4]};

//主控制逻辑
    //计数器，判断是否已经向多项式系数矩阵A提交了256个系数
    reg [8:0] cnt;
//采用状态机对2个数据进行并行判断与地址移动
    wire [1:0] judge;
    reg        first;
    assign judge = {(data_2 >= q),(data_1 >= q)};


    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            first <= 0;
            cnt   <= 0;
            data_out_1 <= 0;
            data_out_2 <= 0;
            out_1_vld  <= 0;
            out_2_vld  <= 0;
            adder_1    <= 0;
            adder_2    <= 0;
            finish     <= 0;   
        end
        else begin
           finish <= 0;
           if (cnt == 256) begin
               finish     <= 1;
               first      <= 0;
               out_1_vld  <= 0;
               out_2_vld  <= 0;
               adder_1    <= 0;
               adder_2    <= 0;
               cnt        <= 0;
               data_out_1 <= 0;
               data_out_2 <= 0;
           end
           else if (din_vld) begin
               case(judge)
                    2'b00:begin
                        data_out_1 <= data_1;
                        data_out_2 <= data_2;
                        out_1_vld  <= 1;
                        out_2_vld  <= (cnt<255);
                        adder_1    <= (first? adder_2 + 1 : 0);
                        adder_2    <= (first? adder_2 + 2 : 1);
                        first      <= 1;
                        cnt        <= (cnt == 255) ? 9'd256 : (cnt + 9'd2);
                    end
                    2'b01:begin
                        data_out_1 <= data_2;
                        data_out_2 <= data_2;
                        out_1_vld  <= 0;
                        out_2_vld  <= 1;
                        adder_1    <= (first? adder_2 + 1 : 0);
                        adder_2    <= (first? adder_2 + 1 : 0);
                        first      <= 1;
                        cnt        <= cnt + 1;
                    end
                    2'b10:begin
                        data_out_1 <= data_1;
                        data_out_2 <= data_1;
                        out_1_vld  <= 1;
                        out_2_vld  <= 0;
                        adder_1    <= (first? adder_2 + 1 : 0);
                        adder_2    <= (first? adder_2 + 1 : 0);
                        first      <= 1;
                        cnt        <= cnt + 1;
                    end
                    2'b11:begin
                        out_1_vld  <= 0;
                        out_2_vld  <= 0;
                    end 
               endcase
           end
           else begin
               out_1_vld <= 0;
               out_2_vld <= 0;
           end
        end
    end

endmodule
