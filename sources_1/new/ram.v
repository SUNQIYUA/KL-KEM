`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/12 17:59:54
// Design Name: 
// Module Name: ram
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




module ram #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 8, // 2^8 = 256
    parameter DEPTH = 256
)(
    input  wire clk,
    
    // 端口 A (可以读，也可以写)
    input  wire                  we_a,   // 写入使能 A
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] din_a,
    output reg  [DATA_WIDTH-1:0] dout_a,
    
    // 端口 B (可以读，也可以写)
    input  wire                  we_b,   // 写入使能 B
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] din_b,
    output reg  [DATA_WIDTH-1:0] dout_b
);

    // 声明寄存器数组
    reg [DATA_WIDTH-1:0] ram_block [0:DEPTH-1];

    // 端口 A 的行为逻辑
    always @(posedge clk) begin
        if (we_a) begin
            ram_block[addr_a] <= din_a;
        end
        // 哪怕是写操作，dout 也通常输出当前地址的数据（或者新写入的数据）
        dout_a <= ram_block[addr_a]; 
    end

    // 端口 B 的行为逻辑
    always @(posedge clk) begin
        if (we_b) begin
            ram_block[addr_b] <= din_b;
        end
        dout_b <= ram_block[addr_b];
    end

endmodule
