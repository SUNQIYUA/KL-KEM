`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/11 13:29:43
// Design Name: 
// Module Name: test_keccak
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



module test_keccak();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    reg         clk;
    reg         rst;
    reg         start;
    reg  [1:0]  mod;
    reg  [63:0] data_in;
    reg  [2:0]  din_vld;
    reg         over;

    wire [1599:0] data_fin;
    wire          ready;

    // ==========================================
    // 2. 模块实例化 (UUT)
    // ==========================================
    shake_padder uut (
        .data_in  (data_in),
        .mod      (mod),
        .din_vld  (din_vld),
        .over     (over),
        .start    (start),
        .clk      (clk),
        .rst      (rst),
        .data_fin (data_fin),
        .ready    (ready)
    );

    // ==========================================
    // 3. 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns 周期
    end

    // ==========================================
    // 4. 激励生成 (Stimulus)
    // ==========================================
    integer i;

    initial begin
        // --- 初始化信号 ---
        rst     = 0;
        start   = 0;
        mod     = 3'b000;
        data_in = 64'd0;
        din_vld = 3'd0;
        over    = 0;

        // --- 1. 释放复位 ---
        #20;
        rst = 1;
        #20;

        // --- 2. 启动 SHAKE-128 (mod = s1) ---
        @(posedge clk);
        start = 1;
        mod   = 3'b001; // 选择 SHAKE-128

        // --- 3. 连续输入前 20 个完整周期的 64-bit 数据 ---
        // SHAKE-128 的 r=168字节=21个64-bit词。前20个属于未结束状态
        for (i = 0; i < 20; i = i + 1) begin
            data_in = 64'hAABBCCDD_11223344 + i; // 随便给点递增的测试数据
            over    = 0;
            din_vld = 3'd0; // 不是最后一拍，不关心这个值
            @(posedge clk);
        end

        // --- 4. 最后一个周期的输入 (触发 Padding) ---
        // 假设这最后一次，我们只有 3 个有效字节
        data_in = 64'h00000000_00FFFFFF; 
        over    = 1;
        din_vld = 3'd3; 
        @(posedge clk);

        // --- 5. 停止输入，等待流水线出结果 ---
        start   = 0;
        over    = 0;
        data_in = 64'd0;

        // 观察波形 100 纳秒
        #100;
        $finish;
    end

endmodule

// =======================================================
// 虚拟的底层轮函数 (Dummy Module)，仅供顶层编译通过和仿真使用
// =======================================================
module function_turn (
    input  wire [1599:0] data_in,
    input  wire [63:0]   rc,
    output wire [1599:0] data_out
);
    // 随便写一个异或逻辑代表“处理过了”
    assign data_out = data_in ^ {25{rc}}; 
endmodule
