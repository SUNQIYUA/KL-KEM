`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/24 00:12:06
// Design Name: 
// Module Name: com_butterfly
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


module com_butterfly#(
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

    input INTT_begin,

    output [width-1:0] post,
    output [width-1:0] neg,

    output  done

    );

//模乘模块输入输出
wire [width-1:0] data_1;
//wire [width-1:0] data_2;
wire [width-1:0] out_post;
wire [width-1:0] out_neg;

//NTT
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
        assign temp_plus = reg_in_1[4] + temp_mult;
        //assign temp_plus = data_in_1 - temp_mult;
    
        assign out_post = (temp_plus>=q)?(temp_plus-q):temp_plus;
        assign out_neg  = (reg_in_1[4]+q-temp_mult>=q)?(reg_in_1[4]-temp_mult):(reg_in_1[4]+q-temp_mult);

//INTT
    wire [width:0]  data_a;
    wire [width:0]  data_b;
    wire [width:0]  judge;
    wire [width-1:0] data_b_1;
    reg [width-1:0]  a [4:0];
    //计算系数A只需要相加，将另一项消除，取模即可
    assign data_a   = (din_vld)?(data_in_1+data_in_2):0;
    //assign a        = (data_a>q)?(data_a-q):data_a;

    //assign judge    = data_in_2-data_in_1+q;
    //assign data_b   = (din_vld)?((judge>q)?(judge-q):judge):0;
    //assign data_b_1 = (data_b>=q)?(data_b-q):data_b;
    
    assign judge = {1'b0, data_in_2} + q - {1'b0, data_in_1};
    assign data_b = din_vld ? ((judge >= q) ? judge-q : judge) : 0;
    assign data_b_1 = data_b[width-1:0];
    // 输入范围必须为 [0,q-1]，此时 judge 在 [1,2q-1]，一次减 q 即可。
    // 若改用另一套逆元表或取负表，需要重推减法符号，不能单独照搬此方案。

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

//输入控制逻辑
    assign data_1 =INTT_begin? data_b_1 : data_in_2;
    
    mod_mult mult(.clk(clk), .rst(rst), .data_in_1(data_1), .data_in_2(zeta), .din_vld(din_vld), .done(done), .data_out(temp_mult));

//输出控制逻辑
    //assign post = (INTT_begin? a[4] : out_post);
    //assign neg  = (INTT_begin? temp_mult : out_neg);
    // 在其余运算正确的前提下，七层未缩放的逆变换会多出 128 倍。
    // 每层两个输出分别做模除 2；七层累计为 128^-1 mod 3329=3303。
    // 奇数 x 先加奇数 q 再右移；必须保留 width+1 位避免加法溢出。
    // 修改后代码
    wire [width:0] intt_post_half;
    wire [width:0] intt_neg_half;
    assign intt_post_half = {1'b0, a[4]} + (a[4][0] ? q : 0);
    assign intt_neg_half = {1'b0, temp_mult} + (temp_mult[0] ? q : 0);
    assign post = INTT_begin ? intt_post_half[width:1] : out_post;
    assign neg  = INTT_begin ? intt_neg_half[width:1] : out_neg;


endmodule
