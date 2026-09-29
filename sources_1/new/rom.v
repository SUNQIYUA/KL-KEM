`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/12 22:58:56
// Design Name: 
// Module Name: rom
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



module rom #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 7   // 2^7 = 128 深度，完美适配 Kyber 的 128 个 Zeta 值
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] dout
);

    // 声明二维数组作为 ROM
    // Vivado 综合属性：你可以根据需要改成 "distributed" (使用 LUT) 或 "block" (使用 BRAM)
    (* rom_style = "distributed" *) 
    reg [DATA_WIDTH-1:0] rom [0:(1<<ADDR_WIDTH)-1];

    // 使用系统函数在综合/仿真时加载数据
    initial begin
        // 注意：你需要把 zeta.txt 放在 Vivado 工程的仿真和综合目录下
        $readmemh("zeta.txt", rom); 
    end

    // -------------------------------------------------------------
    // 【同步读出】 (业界标准，有 1 拍延迟，最高运行频率 Fmax 极高)
    // -------------------------------------------------------------
    always @(posedge clk) begin
        dout <= rom[addr];
    end

    /* // -------------------------------------------------------------
    // 【异步读出 (组合逻辑)】 
    // 如果你的 NTT 状态机没有为读取 ROM 预留 1 拍的等待时间（即要求地址一给，数据立刻出来），
    // 请注释掉上面的 always @(posedge clk) 块，并解开下面这句的注释：
    // -------------------------------------------------------------
    // always @(*) begin
    //     dout = rom[addr];
    // end
    */

endmodule
