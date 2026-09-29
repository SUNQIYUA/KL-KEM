`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/12 20:44:12
// Design Name: 
// Module Name: booth_mult
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


module booth_mult#(
    parameter width = 12)(
    input clk,
    input rst,

    input      [width-1:0]   data_in_1,
    input      [width-1:0]   data_in_2,
    input                    din_vld,
    output reg [2*width-1:0] data_out,
    output reg               done

    );


wire [14:0] data_in;
assign data_in = {{2{1'b0}},data_in_2,1'b0};

reg [6:0]       double;
reg [6:0]       neg;
//reg [6:0] normal;
reg [6:0]       zero;
reg [width:0]   data_1;
reg [23:0]      data_2 [6:0];
reg [width:0]   data_3 [3:0];

reg      done_1;
reg      done_2;

//声明一个在时序always块中使用的组合逻辑变量
//reg类型在代码中只是代表在时序逻辑中赋值，并不等于电路中的寄存器
reg [13:0] data      [6:0];
reg        data_plus [6:0];


//CSA 压缩树
    // p0,p1,p2=>s1,p3,p4,p5=>s2,
    wire [23:0] s1 = data_2[0] ^ data_2[1] ^ data_2[2];
    wire [23:0] c1 = ((data_2[0] & data_2[1]) | (data_2[1] & data_2[2]) | (data_2[0] & data_2[2])) << 1;
    
    wire [23:0] s2 = data_2[3] ^ data_2[4] ^ data_2[5];
    wire [23:0] c2 = ((data_2[3] & data_2[4]) | (data_2[4] & data_2[5]) | (data_2[3] & data_2[5])) << 1;

    //s1,c1,s2 => s3
    wire [23:0] s3 = s1 ^ c1 ^ s2;
    wire [23:0] c3 = ((s1 & c1) | (c1 & s2) | (s1 & s2)) << 1;

    // s3,c3,c2 =>s4
    wire [23:0] s4 = s3 ^ c3 ^ c2;
    wire [23:0] c4 = ((s3 & c3) | (c3 & c2) | (s3 & c2)) << 1;

    // s4,c4,data_2[6] =>sum , carry
    wire [23:0] data_sum   = s4 ^ c4 ^ data_2[6];
    wire [23:0] data_carry = ((s4 & c4) | (c4 & data_2[6]) | (s4 & data_2[6])) << 1;

always @(posedge clk or negedge rst) begin:mult_block
    integer i;
    integer j;
    if (!rst) begin
        double   <= 0;
        neg      <= 0;
        zero     <= 0;
        done_1   <= 0;
        done_2   <= 0;
        done     <= 0;
        data_out <= 0;
        
    end
    else begin
         //有效信号保持流水形式传递，跟随数据计算流程
         done_1 <= din_vld;
         done_2 <= done_1;
         done   <= done_2;
        //第一阶段 生成操作指令
        if (din_vld) begin
            for (i = 2; i < 15; i = i + 2)begin:control_block
                double[(i>>1)-1] <= (data_in[i-:3] == 3'b011)||(data_in[i-:3] == 3'b100);
                zero[(i>>1)-1]   <= (data_in[i-:3] == 0)||(data_in[i-:3] == 3'b111);
                neg[(i>>1)-1]    <= data_in[i];
    
                data_1           <= {1'b0,data_in_1};
    
                //done_1           <= 1;
            end
        end

        //第二阶段 根据指令生成部分积
        //data2会比data1高一位，即多一个符号位
        if (done_1) begin
            for (j = 0; j < 7; j = j + 1)begin:value_block
                data_plus[j] <= neg[j];
                if (zero[j]) begin
                    data[j]= 0;
                end
                else if (double[j]) begin
                    data[j] = data_1<<1;
                end
                else begin
                    data[j] = data_1;
                end
                if (neg[j]) begin
                    data[j] = ~ data[j];
                end
                data_2[j] <= {{10{neg[j]}},data[j]}<<(2*j);
            end
        end

        //第三阶段，开始进行华莱士数的累加
        if (done_2) begin
            data_out <= data_sum + data_carry + data_plus[0]
                        + (data_plus[1] <<2)
                        + (data_plus[2] <<4)
                        + (data_plus[3] <<6)
                        + (data_plus[4] <<8)
                        + (data_plus[5] <<10)
                        + (data_plus[6] <<12);
        end
    end
    
    
end

endmodule
