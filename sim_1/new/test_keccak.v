`timescale 1ns / 1ps

module tb_shake_padder();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    reg         clk;
    reg         rst;
    reg         start;
    reg  [2:0]  mod;
    reg  [63:0] data_in;
    reg  [2:0]  din_vld;
    reg         over;

    wire [1599:0] data_fin;
    wire          out_vld;

    // ==========================================
    // 2. 声明文件句柄 (File Handlers)
    // ==========================================
    integer fd_in;
    integer fd_out;

    // ==========================================
    // 3. 模块实例化 (UUT)
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
        .out_vld  (out_vld)
    );

    // ==========================================
    // 4. 时钟生成 (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns 周期
    end

    // ==========================================
    // 5. 自动记录输出 (Output Monitor)
    // ==========================================
integer byte_idx;
    
    always @(posedge clk) begin
        if (out_vld) begin
            
            // 1. 先打印一个抬头，注意用 $fwrite 不会自动换行
            $fwrite(fd_out, "data_fin: ");
            
            // 2. 用 for 循环，从第 0 个字节严格按顺序打到第 199 个字节
            // 200 个字节 * 8 位 = 1600 位
            for (byte_idx = 0; byte_idx < 200; byte_idx = byte_idx + 1) begin
                // %02x 保证如果数值是 4，会打印成 04 而不是 4
                $fwrite(fd_out, "%02x", data_fin[byte_idx*8 +: 8]);
            end
            
            // 3. 循环结束后，打印一个换行符 \n
            $fwrite(fd_out, "\n");
            
            // 控制台提示
            $display("-> [TB Monitor] 成功捕获一次哈希结果，并已按小端字节序格式写入 txt");
        end
    end

    // ==========================================
    // 6. 自动记录输入 (Input Monitor)
    // ==========================================
    always @(posedge clk) begin
        if (start && rst) begin 
            $fdisplay(fd_in, "%x", data_in);
        end
        else if (over) begin
            $fdisplay(fd_in, "%x", data_in);
        end
    end

    // ==========================================
    // 7. 主激励生成与文件控制
    // ==========================================
    integer i;

    initial begin
        // --- 0. 打开 TXT 文件 ---
        fd_in  = $fopen("input_stimulus.txt", "w");
        fd_out = $fopen("output_results.txt", "w");
        
        if (fd_in == 0 || fd_out == 0) begin
            $display("Error: 无法创建 txt 文件！");
            $finish;
        end

        // --- 初始化信号 (在Time 0时刻，使用阻塞赋值没问题) ---
        rst     = 0;
        start   = 0;
        mod     = 3'd0;
        data_in = 64'd0;
        din_vld = 3'd0;
        over    = 0;

        // --- 1. 释放复位 ---
        #20;
        rst = 1;
        #20;

        // --- 2. 启动 SHAKE-128 (mod = 3'd1) ---
        @(posedge clk);
        start <= 1;       // 【修改】改为非阻塞赋值
        mod   <= 3'd1;    // 【修改】改为非阻塞赋值

        $fdisplay(fd_in, "==== 开始测试: SHAKE-128 吸收阶段 ====");
        $fdisplay(fd_out, "==== SHAKE-128 (1600-bit) 最终状态输出 ====");
        
        /*
        // --- 3. 连续输入前 20 个完整周期的 64-bit 数据 ---
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); // 【修改】将等待时钟沿放在最前面
            data_in <= 64'h1122334455667788 + i; // 【修改】改为非阻塞赋值
            over    <= 0;                        // 【修改】改为非阻塞赋值
            din_vld <= 3'd0;                     // 【修改】改为非阻塞赋值
        end
        */

        // --- 4. 最后一个周期的输入 (触发 Padding) ---
        @(posedge clk);  // 【修改】将等待时钟沿放在赋值前面
        data_in <= 64'h0000000000AABBCC; 
        over    <= 1;                    
        start   <= 0;                    
        din_vld <= 3'd3;                 

        // --- 5. 停止输入，等待流水线出结果 ---
        @(posedge clk);  // 【修改】步入下一个时钟周期
        //start   <= 0;  // 保持注释
        over    <= 0;
        data_in <= 64'd0;

        // 等待轮函数运算完毕 (给点余量)
        #50;

        // --- 6. 关闭文件，结束仿真 ---
        $fclose(fd_in);
        $fclose(fd_out);
        $display("========================================");
        $display("仿真结束！文件已经安全保存。");
        $display("========================================");
        $finish;
    end

endmodule

// =======================================================
// 虚拟的底层轮函数 (Dummy Module)
// =======================================================
module function_turn (
    input  wire [1599:0] data_in,
    input  wire [63:0]   rc,
    output wire [1599:0] data_out
);
    assign data_out = ~data_in ^ {25{rc}}; 
endmodule