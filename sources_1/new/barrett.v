`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/16 17:45:22
// Design Name: 
// Module Name: barrett
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


module barrett #(
    parameter q = 3329
)(
    input          clk,
    input          rst,
    
    input          din_vld,     // 衔接上一级 Booth 的 dout_vld
    input   [23:0] data_in,     // 衔接上一级 Booth 的 24位 乘积
    
    output reg         dout_vld,    // 输出有效标志
    output reg  [11:0] data_out     // 绝对正确的 [0, 3328] 余数
);

    // Barrett 常数计算: 2^24/3329 = 5039
    parameter m = 13'd5039; 


    (* use_dsp = "no" *) wire [36:0] X_m = data_in * m;
    
    // 右移 24 位，相当于直接截取高位
    wire [12:0] Q = X_m[36:24];


    // 计算初步余数 R_temp = X - Q * 3329
    // 乘 3329，Vivado自动优化为移位加法树
    (* use_dsp = "no" *) wire [23:0] Q_q = Q * q;
    
    wire [13:0] R_temp = data_in - Q_q; 


    reg [13:0] R_reg;
    reg        vld_reg;
    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            R_reg   <= 0;
            vld_reg <= 0;
        end else begin
            R_reg   <= R_temp;
            vld_reg <= din_vld;
        end
    end


    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            data_out <= 0;
            dout_vld <= 0;
        end else begin
            dout_vld <= vld_reg; // 同步输出有效信号
            if (vld_reg) begin
                if (R_reg >= q)
                    data_out <= R_reg - q;
                else
                    data_out <= R_reg[11:0];
            end
        end
    end

endmodule
