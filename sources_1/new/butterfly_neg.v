`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/06 17:18:34
// Design Name: 
// Module Name: butterfly_neg
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


module butterfly_neg#(
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

    output     [width-1:0] out_a,
    output     [width-1:0] out_b,


    output done

    );

    wire [width:0]  data_a;
    wire [width:0]  data_b;
    wire [width:0]  judge;
    wire [width-1:0] data_b_1;
    reg [width-1:0]  a [4:0];

    //计算系数A只需要相加，将另一项消除，取模即可
    assign data_a   = (din_vld)?(data_in_1+data_in_2):0;
    //assign a        = (data_a>q)?(data_a-q):data_a;

    //assign judge    = data_in_1-data_in_2+q;
    //assign data_b   = (din_vld)?((judge>=q)?data_in_1-data_in_2:judge):0;
    //assign data_b_1 = (data_b>=q)?(data_b-q):data_b;
    // [STATIC REVIEW][IBF-01][P1][独立逆蝶形的减法方向]
    // 此模块不在 top_NTT 实际层级中；top_NTT 的 INTT 由 com_NTT/com_butterfly 执行。
    // 如果独立使用本模块，并采用当前普通域 Zeta 表的倒序约定，需要 high-low。
    // 修改后代码（替换上方三条 assign；仅建议，未应用）：
    assign judge = {1'b0, data_in_2} + q - {1'b0, data_in_1};
    assign data_b = din_vld ? ((judge >= q) ? judge-q : judge) : 0;
    assign data_b_1 = data_b[width-1:0];
    // 前提为输入均在 [0,q-1]；若旋转因子表约定不同，须重新推导。

always @(posedge clk or negedge rst) begin:block_1
integer i;
    if (!rst) begin
        a[0] <= 0;
        a[1] <= 0;
        a[2] <= 0;
        a[3] <= 0;
        a[4] <= 0;

        
    end
    else begin
        for (i = 4; i > 0; i = i - 1)begin:wait_block
            a[i] <= a[i-1];
        end
        a[0] <= (data_a>=q)?(data_a-q):data_a;
    end
end

    //mod_mult mult(.clk(clk), .rst(rst), .data_in_1(data_b_1), .data_in_2(zeta), .din_vld(din_vld), .done(done), .data_out(out_b));

    //assign out_a = a[4];
    // [STATIC REVIEW][IBF-02][P1][独立逆蝶形的缩放方案]
    // 问题：本模块没有缩放；只有上层恰好运行七层且无末尾缩放时，才需要
    // 以下逐层模除 2。旧 INTT.v 控制器还需独立审查，不能据此宣称它正确。
    // 修改后代码（仅建议，未应用；各部分必须一起替换）：
    // 1. 端口声明替换原 output reg，避免与内部实例输出重复驱动：
    // 2. 模块级新增声明：
    wire [width-1:0] temp_mult;
    wire [width:0] out_a_half, out_b_half;
    // 3. 替换现有 mod_mult 实例，使原始模乘结果先进入 temp_mult：
     mod_mult mult (
         .clk(clk), .rst(rst), .data_in_1(data_b_1), .data_in_2(zeta),
         .din_vld(din_vld), .done(done), .data_out(temp_mult)
     );
    // 4. 替换现有 out_a 赋值，并增加 out_b 赋值：
    assign out_a_half = {1'b0, a[4]} + (a[4][0] ? q : 0);
    assign out_b_half = {1'b0, temp_mult} + (temp_mult[0] ? q : 0);
    assign out_a = out_a_half[width:1];
    assign out_b = out_b_half[width:1];
    
endmodule
