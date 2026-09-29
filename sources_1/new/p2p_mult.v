`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/04 10:02:00
// Design Name: 
// Module Name: p2p_mult
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


module p2p_mult#(
    parameter width = 12,
    parameter q     = 3329
    )(
    input clk,
    input rst,
    input [width-1:0] RAM_a_1,
    input [width-1:0] RAM_a_2,
    input [width-1:0] RAM_b_1,
    input [width-1:0] RAM_b_2,
    input [width-1:0] zeta_in,
    input din_vld,

    output reg [7:0] zeta_cnt,
    output reg [7:0] ramA_adder_1,
    output reg [7:0] ramA_adder_2,
    output reg [7:0] ramB_adder_1,
    output reg [7:0] ramB_adder_2,
    output     [7:0] out_adder_1,
    output     [7:0] out_adder_2,

    output [width-1:0] ram_data_1,
    output [width-1:0] ram_data_2,
    output out_vld,   //输出有效信号，标志着流水线前期计算完成，开始流水计算
    output done       //计算完成标志信号，标志点对点相乘计算完成

    );

    //reg [13:0]done_1,done_2,done_3;
    wire done_4;

    reg [7:0] out_cnt_1 [10:0];
    reg [7:0] out_cnt_2 [10:0];
    
    //加入一个中间信号作为缓冲
    reg [7:0] issued;
    reg ram_vld;
    // wire read_issue;
    wire read_issue; 
    assign read_issue = din_vld && (issued < 8'd128) && !done;
    

    reg [width-1:0] out_1 [4:0];
    reg [width-1:0] out_2 [4:0];
    reg [width-1:0] out_3 [4:0];
    wire [width-1:0] out_4;

    wire [width-1:0] data_out_1;
    wire [width-1:0] data_out_2;
    wire [width-1:0] data_out_3;

    wire [width:0] sum1;
    wire [width:0] sum2;

    mod_mult mult_1(.clk(clk), .rst(rst), .data_in_1(RAM_a_1), .data_in_2(RAM_b_1), .din_vld(ram_vld), .done(), .data_out(data_out_1));
    mod_mult mult_2(.clk(clk), .rst(rst), .data_in_1(RAM_a_1), .data_in_2(RAM_b_2), .din_vld(ram_vld), .done(), .data_out(data_out_2));
    mod_mult mult_3(.clk(clk), .rst(rst), .data_in_1(RAM_a_2), .data_in_2(RAM_b_1), .din_vld(ram_vld), .done(), .data_out(data_out_3));
    // 现有计数从 0 每拍加 1；需要的 128 个 pair 则对应
    // +zeta[64], -zeta[64], +zeta[65], -zeta[65], ... , -zeta[127]。
    // 索引每两个 pair 加 1，负号与同步 RAM/ROM 返回数据一起延迟一拍。
    reg zeta_negate;
    wire [width-1:0] zeta_effective;
    assign zeta_effective = zeta_negate?
                                        ((zeta_in == 0) ? {width{1'b0}} : q-zeta_in)
                                       : zeta_in;

    tri_mult mult_4 (
        .clk(clk), .rst(rst),
        .data_in_1(RAM_a_2), .data_in_2(RAM_b_2),
        .zeta(zeta_effective), .din_vld(ram_vld),
        .done(done_4), .data_out(out_4)
    );
    
assign out_vld = done_4;
assign done = (out_vld == 1'b1)&&(out_cnt_1[10] == 8'd254);

assign sum1 = out_1[4]+out_4;
assign sum2 = out_2[4]+out_3[4];

assign ram_data_1 = (sum1 >= q)? (sum1-q) : sum1;
assign ram_data_2 = (sum2 >= q)? (sum2-q) : sum2;

assign out_adder_1 = out_cnt_1[10];
assign out_adder_2 = out_cnt_2[10];

//地址移动与数据移位寄存
    //*********************************************
    always @(posedge clk or negedge rst) begin:p2p_mult_block
        integer i;
        integer j;
        if (!rst) begin
        /*
            done_1 <= 0;
            done_2 <= 0;
            done_3 <= 0;
        */
            //done_4 <= 0;
            issued  <= 8'd0;
            ram_vld <= 1'b0;
            //zeta_cnt <= 0;
            zeta_cnt    <= 8'd64;
            zeta_negate <= 1'b0;
/*
            out_1[0] <= 0;
            out_1[1] <= 0;
            out_1[2] <= 0;
            out_1[3] <= 0;
    
            out_2[0] <= 0;
            out_2[1] <= 0;
            out_2[2] <= 0;
            out_2[3] <= 0;
            
            out_3[0] <= 0;
            out_3[1] <= 0;
            out_3[2] <= 0;
            out_3[3] <= 0;
*/

            for (i = 0; i < 5; i = i + 1) begin
                out_1[i] <= 0;
                out_2[i] <= 0;
                out_3[i] <= 0;
            end
            
            ramA_adder_1 <= 0;
            ramA_adder_2 <= 1;
            ramB_adder_1 <= 0;
            ramB_adder_2 <= 1;
    
            //out_adder_1  <= 0;
            //out_adder_2  <= 1;
/*
            out_cnt_1[0] <= 0;
            out_cnt_2[0] <= 0;
*/

            for (j = 0; j < 11; j = j + 1) begin
                out_cnt_1[j] <= 8'd0;
                out_cnt_2[j] <= 8'd0;
            end
            // 复位为 0 仅定义无效周期，不代替有效地址与写使能对齐检查。

    
        end
        else  begin
            if (done) begin
                issued  <= 8'd0;
                ram_vld <= 1'b0;
                zeta_cnt    <= 8'd64;
                zeta_negate <= 1'b0;
                for (i = 0; i < 5; i = i + 1) begin
                    out_1[i] <= 0;
                    out_2[i] <= 0;
                    out_3[i] <= 0;
                end
                
                ramA_adder_1 <= 0;
                ramA_adder_2 <= 1;
                ramB_adder_1 <= 0;
                ramB_adder_2 <= 1;
                for (j = 0; j < 11; j = j + 1) begin
                    out_cnt_1[j] <= 8'd0;
                    out_cnt_2[j] <= 8'd0;
                end
            end
            else begin
                    ram_vld <= read_issue;
                    if (read_issue) begin
                        issued      <= issued + 1;
                        zeta_negate <= ramA_adder_1[1];
                        if (ramA_adder_1[1])
                            zeta_cnt <= zeta_cnt + 8'd1;
                        // 地址低两位为 00/10，对应同一 Zeta 的正/负两个 pair。
                        // 最后一个 pair 的请求发出后应停止发新请求，仅排空流水线；
                        // 重新启动时须在明确的任务边界重置地址到 0/1、索引到 64。
        
                        ramA_adder_1 <= ramA_adder_1 + 2;
                        ramA_adder_2 <= ramA_adder_2 + 2;
                        ramB_adder_1 <= ramB_adder_1 + 2;
                        ramB_adder_2 <= ramB_adder_2 + 2;
                    
                        //out_adder_1  <= out_adder_1 + 1;
                        //out_adder_2  <= out_adder_2 + 1; 
                    end
                 /*
                     done_1 <= {done_1[12:0],done_1[13]};
                     done_2 <= {done_2[12:0],done_2[13]};
                     done_3 <= {done_3[12:0],done_3[13]};
                 */
                out_1[0] <= data_out_1;
                out_2[0] <= data_out_2;
                out_3[0] <= data_out_3;    
                out_cnt_1[0] <= ramA_adder_1;
                out_cnt_2[0] <= ramA_adder_2;    
                for (i = 4; i > 0; i = i - 1)begin:out_wait_block
                   out_1[i] <= out_1[i-1];
                   out_2[i] <= out_2[i-1];
                   out_3[i] <= out_3[i-1];
                end
        
                for (j = 10; j > 0; j = j - 1)begin:out_adder_block
                   out_cnt_1[j] <= out_cnt_1[j-1];
                   out_cnt_2[j] <= out_cnt_2[j-1];
                end
            end   
        end
         
        

    end
    //****************************************************************
endmodule
