`timescale 1ns / 1ps

// top_NTT 全链路测试平台：
//   装载多项式 A/B -> NTT(A/B) -> NTT 域二项式基乘法（点乘）-> INTT。
//
// 本 TB 驱动真实 DUT 和同步 RAM/ROM，导出四个阶段的结果，不自行实现数学模型。
// verify_top_ntt.py 将这些结果与独立的 ML-KEM 参考模型逐系数比较。
// 仿真结束或输出文件写完不代表数值正确，必须结合 Python 校验结论。
// 可使用以下 plusarg 参数覆盖文件路径，+TRACE 开启 ntt_trace.csv 时序记录：
//   +A_HEX=<path> +B_HEX=<path> +NTT_A_HEX=<path> +NTT_B_HEX=<path>
//   +P2P_HEX=<path> +OUTPUT_HEX=<path> +ZETA_HEX=<path>
module tb_top_NTT;
    // 每个系数 12 位，多项式共 256 项；超时上限用于防止握手异常时无限等待。
    localparam WIDTH = 12;
    localparam N = 256;
    localparam Q = 3329;
    localparam ZETA_N = 128;
    localparam MAX_CYCLES = 10000;

    // rst 低有效；每拍同时给 A、B 各送两个相邻系数，共四个输入数据端口。
    reg clk;
    reg rst;
    reg din_vld;
    reg [WIDTH-1:0] ram1_in_1;
    reg [WIDTH-1:0] ram1_in_2;
    reg [WIDTH-1:0] ram3_in_1;
    reg [WIDTH-1:0] ram3_in_2;

    // 仅作为输入激励缓存，不直接初始化 DUT 的计算 RAM，避免掩盖漏写造成的 X。
    reg [WIDTH-1:0] input_a [0:N-1];
    reg [WIDTH-1:0] input_b [0:N-1];
    reg [WIDTH-1:0] zeta_memory [0:ZETA_N-1];

    // 用打包向量保存最多 512 字节的路径，兼容当前 Verilog 编译模式。
    reg [8*512-1:0] input_a_path;
    reg [8*512-1:0] input_b_path;
    reg [8*512-1:0] ntt_a_path;
    reg [8*512-1:0] ntt_b_path;
    reg [8*512-1:0] p2p_path;
    reg [8*512-1:0] output_path;
    reg [8*512-1:0] zeta_path;

    // zeta_cnt 为 DUT 的旋转因子地址，zeta_in 为同步 ROM 返回的数据。
    // finsh 保留被测模块的原始拼写；ram*_cnt 为 DUT 暴露的结果地址。
    reg [WIDTH-1:0] zeta_in;
    wire [7:0] zeta_cnt;
    wire [7:0] ram1_cnt_1;
    wire [7:0] ram1_cnt_2;
    wire [7:0] ram3_cnt_1;
    wire [7:0] ram3_cnt_2;
    wire finsh;

    // 五块双口 RAM 的接口：we 写使能、adder 地址、din 写数据、dout 读数据。
    // RAM0/1 供 A 正变换乒乓使用，RAM2/3 供 B 使用，RAM4 保存点乘结果；
    // 逆变换复用 RAM4/1。具体读写方向由 DUT 的 which_ram 控制。
    wire ram0_we_a, ram0_we_b;
    wire ram1_we_a, ram1_we_b;
    wire ram2_we_a, ram2_we_b;
    wire ram3_we_a, ram3_we_b;
    wire ram4_we_a, ram4_we_b;
    wire [7:0] ram0_adder_a, ram0_adder_b;
    wire [7:0] ram1_adder_a, ram1_adder_b;
    wire [7:0] ram2_adder_a, ram2_adder_b;
    wire [7:0] ram3_adder_a, ram3_adder_b;
    wire [7:0] ram4_adder_a, ram4_adder_b;
    wire [WIDTH-1:0] ram0_din_a, ram0_din_b;
    wire [WIDTH-1:0] ram1_din_a, ram1_din_b;
    wire [WIDTH-1:0] ram2_din_a, ram2_din_b;
    wire [WIDTH-1:0] ram3_din_a, ram3_din_b;
    wire [WIDTH-1:0] ram4_din_a, ram4_din_b;
    wire [WIDTH-1:0] ram0_dout_a, ram0_dout_b;
    wire [WIDTH-1:0] ram1_dout_a, ram1_dout_b;
    wire [WIDTH-1:0] ram2_dout_a, ram2_dout_b;
    wire [WIDTH-1:0] ram3_dout_a, ram3_dout_b;
    wire [WIDTH-1:0] ram4_dout_a, ram4_dout_b;

    // i/fd 供顺序执行的激励与导出任务共用；trace_fd 独立用于并行时序记录。
    // cycle_count 是复位释放后的周期计数，finish_seen 锁存是否见过完成脉冲。
    integer i;
    integer fd;
    integer cycle_count;
    integer finish_seen;
    integer trace_fd;
    integer input_a_from_plusarg;
    integer input_b_from_plusarg;
    integer zeta_from_plusarg;

    // 只读记录：在上升沿的非阻塞赋值更新之前取样，记录 RAM 该拍看到的值。
    // stage_a/b 为两路 NTT 的层状态，over 为排空标志，bank 为乒乓选择；
    // read/out 为读/写地址，valid 为输出有效，post/neg 为两路蝶形输出。
    // 数据按十六进制输出，保留 X；状态、地址和周期按十进制输出。
    initial begin
        trace_fd = 0;
        if ($test$plusargs("TRACE")) begin
            trace_fd = $fopen("ntt_trace.csv", "w");
            $fdisplay(trace_fd, "cycle,top_stage,din_vld,input_a1,input_a2,input_b1,input_b2,stage_a,stage_b,over_a,over_b,done_a,done_b,bank_a,bank_b,read_a1,read_a2,out_a1,out_a2,valid_a,post_a,neg_a,read_b1,read_b2,out_b1,out_b2,valid_b,post_b,neg_b,zeta_addr,zeta_value");
        end
    end
    always @(posedge clk) begin
        if (rst && trace_fd != 0)
            $fdisplay(trace_fd, "%0d,%0d,%0d,%03x,%03x,%03x,%03x,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%03x,%03x,%0d,%0d,%0d,%0d,%0d,%03x,%03x,%0d,%03x",
                cycle_count, dut.stage, din_vld,
                ram1_in_1, ram1_in_2, ram3_in_1, ram3_in_2,
                dut.com_NTT.stage, dut.NTT_2.stage,
                dut.com_NTT.over, dut.NTT_2.over, dut.done_NTT1, dut.done_NTT2,
                dut.which_ram[0], dut.which_ram[1], dut.NTT1_adder_1, dut.NTT1_adder_2,
                dut.NTT1_cnt_1, dut.NTT1_cnt_2, dut.NTT1_out_vld, dut.NTT1_out_1, dut.NTT1_out_2,
                dut.NTT2_adder_1, dut.NTT2_adder_2, dut.NTT2_cnt_1, dut.NTT2_cnt_2,
                dut.NTT2_out_vld, dut.NTT2_out_1, dut.NTT2_out_2, zeta_cnt, zeta_in);
    end

    // 被测顶层：只通过真实端口送输入，不 force 内部状态或绕过计算逻辑。
    top_NTT #(
        .width(WIDTH),
        .n(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .din_vld(din_vld),
        .ram1_in_1(ram1_in_1),
        .ram1_in_2(ram1_in_2),
        .ram3_in_1(ram3_in_1),
        .ram3_in_2(ram3_in_2),
        .zeta_in(zeta_in),
        .ram0_we_a(ram0_we_a), .ram0_adder_a(ram0_adder_a),
        .ram0_din_a(ram0_din_a), .ram0_dout_a(ram0_dout_a),
        .ram0_we_b(ram0_we_b), .ram0_adder_b(ram0_adder_b),
        .ram0_din_b(ram0_din_b), .ram0_dout_b(ram0_dout_b),
        .ram1_we_a(ram1_we_a), .ram1_adder_a(ram1_adder_a),
        .ram1_din_a(ram1_din_a), .ram1_dout_a(ram1_dout_a),
        .ram1_we_b(ram1_we_b), .ram1_adder_b(ram1_adder_b),
        .ram1_din_b(ram1_din_b), .ram1_dout_b(ram1_dout_b),
        .ram2_we_a(ram2_we_a), .ram2_adder_a(ram2_adder_a),
        .ram2_din_a(ram2_din_a), .ram2_dout_a(ram2_dout_a),
        .ram2_we_b(ram2_we_b), .ram2_adder_b(ram2_adder_b),
        .ram2_din_b(ram2_din_b), .ram2_dout_b(ram2_dout_b),
        .ram3_we_a(ram3_we_a), .ram3_adder_a(ram3_adder_a),
        .ram3_din_a(ram3_din_a), .ram3_dout_a(ram3_dout_a),
        .ram3_we_b(ram3_we_b), .ram3_adder_b(ram3_adder_b),
        .ram3_din_b(ram3_din_b), .ram3_dout_b(ram3_dout_b),
        .ram4_we_a(ram4_we_a), .ram4_adder_a(ram4_adder_a),
        .ram4_din_a(ram4_din_a), .ram4_dout_a(ram4_dout_a),
        .ram4_we_b(ram4_we_b), .ram4_adder_b(ram4_adder_b),
        .ram4_din_b(ram4_din_b), .ram4_dout_b(ram4_dout_b),
        .zeta_cnt(zeta_cnt),
        .ram1_cnt_1(ram1_cnt_1), .ram1_cnt_2(ram1_cnt_2),
        .ram3_cnt_1(ram3_cnt_1), .ram3_cnt_2(ram3_cnt_2),
        .finsh(finsh)
    );

    // 例化项目中的真实同步 RAM：上升沿采样地址，读出有一拍延迟；
    // 同地址读写按 ram.v 的非阻塞赋值语义读到旧值，不替换成异步理想存储器。
    ram ram0_i (
        .clk(clk), .we_a(ram0_we_a), .addr_a(ram0_adder_a),
        .din_a(ram0_din_a), .dout_a(ram0_dout_a),
        .we_b(ram0_we_b), .addr_b(ram0_adder_b),
        .din_b(ram0_din_b), .dout_b(ram0_dout_b)
    );
    ram ram1_i (
        .clk(clk), .we_a(ram1_we_a), .addr_a(ram1_adder_a),
        .din_a(ram1_din_a), .dout_a(ram1_dout_a),
        .we_b(ram1_we_b), .addr_b(ram1_adder_b),
        .din_b(ram1_din_b), .dout_b(ram1_dout_b)
    );
    ram ram2_i (
        .clk(clk), .we_a(ram2_we_a), .addr_a(ram2_adder_a),
        .din_a(ram2_din_a), .dout_a(ram2_dout_a),
        .we_b(ram2_we_b), .addr_b(ram2_adder_b),
        .din_b(ram2_din_b), .dout_b(ram2_dout_b)
    );
    ram ram3_i (
        .clk(clk), .we_a(ram3_we_a), .addr_a(ram3_adder_a),
        .din_a(ram3_din_a), .dout_a(ram3_dout_a),
        .we_b(ram3_we_b), .addr_b(ram3_adder_b),
        .din_b(ram3_din_b), .dout_b(ram3_dout_b)
    );
    ram ram4_i (
        .clk(clk), .we_a(ram4_we_a), .addr_a(ram4_adder_a),
        .din_a(ram4_din_a), .dout_a(ram4_dout_a),
        .we_b(ram4_we_b), .addr_b(ram4_adder_b),
        .din_b(ram4_din_b), .dout_b(ram4_dout_b)
    );

    // 测试平台只负责向 top_NTT 提供外部旋转因子接口。这里保留 rom.v 相同的
    // 同步读时序，但由 TB 解析文件路径，避免 Vivado GUI 工作目录中缺少 zeta.txt。
    // top_NTT 的验证范围不包含 rom.v 的存储器推断方式。
    always @(posedge clk)
        zeta_in <= zeta_memory[zeta_cnt[6:0]];

    always #5 clk = ~clk; // 时间单位为 ns，10 ns 周期，即 100 MHz。

    // 监测完成脉冲和全局超时；使用 === 避免把 X 错当成有效完成。
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= 0;
            finish_seen <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (finsh === 1'b1)
                finish_seen <= 1;
            if (cycle_count >= MAX_CYCLES) begin
                $display("[TB-FAIL] timeout after %0d cycles", MAX_CYCLES);
                $finish;
            end
        end
    end

    // 检查点 1：按 DUT 当前选作读源的 bank 导出 A 的 256 个 NTT 系数。
    // 这是 DUT 认为已完成的结果，不由 TB 修正错误的 bank 选择。
    // 下列任务均按地址 0..255 每行写一个值；%03x 会保留未知位供 Python 检出。
    task dump_ntt_a;
        begin
            fd = $fopen(ntt_a_path, "w");
            if (fd == 0) begin
                $display("[TB-FAIL] cannot open %0s", ntt_a_path);
                $finish;
            end
            for (i = 0; i < N; i = i + 1) begin
                if (dut.which_ram[0])
                    $fdisplay(fd, "%03x", ram1_i.ram_block[i]);
                else
                    $fdisplay(fd, "%03x", ram0_i.ram_block[i]);
            end
            $fclose(fd);
        end
    endtask

    // 检查点 2：与 A 同理，B 根据 which_ram[1] 从 RAM2 或 RAM3 导出。
    task dump_ntt_b;
        begin
            fd = $fopen(ntt_b_path, "w");
            if (fd == 0) begin
                $display("[TB-FAIL] cannot open %0s", ntt_b_path);
                $finish;
            end
            for (i = 0; i < N; i = i + 1) begin
                if (dut.which_ram[1])
                    $fdisplay(fd, "%03x", ram3_i.ram_block[i]);
                else
                    $fdisplay(fd, "%03x", ram2_i.ram_block[i]);
            end
            $fclose(fd);
        end
    endtask

    // 检查点 3：点乘结果固定写到 RAM4，调用方须先等待最后一次同步写入提交。
    task dump_p2p;
        begin
            fd = $fopen(p2p_path, "w");
            if (fd == 0) begin
                $display("[TB-FAIL] cannot open %0s", p2p_path);
                $finish;
            end
            for (i = 0; i < N; i = i + 1)
                $fdisplay(fd, "%03x", ram4_i.ram_block[i]);
            $fclose(fd);
        end
    endtask

    // 检查点 4：读取 INTT 结束时所选的 RAM，供 Python 与朴素多项式乘积比较。
    task dump_output;
        begin
            fd = $fopen(output_path, "w");
            if (fd == 0) begin
                $display("[TB-FAIL] cannot open %0s", output_path);
                $finish;
            end
            // 遵循 which_ram[0] 指示的逆变换读源：1 选 RAM1，0 选 RAM4。
            // 不假设结果必定留在 RAM4；bank 控制出错也会反映为校验失败。
            for (i = 0; i < N; i = i + 1) begin
                if (dut.which_ram[0])
                    $fdisplay(fd, "%03x", ram1_i.ram_block[i]);
                else
                    $fdisplay(fd, "%03x", ram4_i.ram_block[i]);
            end
            $fclose(fd);
        end
    endtask

    // 主激励流程：复位 -> 输入 -> 四个检查点 -> 顶层完成确认 -> 结束。
    initial begin
        clk = 1'b0;
        rst = 1'b0;
        din_vld = 1'b0;
        ram1_in_1 = 0;
        ram1_in_2 = 0;
        ram3_in_1 = 0;
        ram3_in_2 = 0;
        zeta_in = 0;
        cycle_count = 0;
        finish_seen = 0;

        // [TB REVIEW][TB-INPUT-01][P1] 若 input_a.hex 没有被 $readmemh 成功读取，
        // input_a[] 会保持 X；下方 ram1_in_1=input_a[0] 随后会把 X 送进 top_NTT。
        // 已复现的旧 XSim 日志明确报告：cannot open input_a.hex/input_b.hex。
        // 当前源码已经采用“GUI 相对路径 + plusarg 绝对路径 + $fopen 预检查”；
        // 若波形仍显示有效输入周期为 X，通常是 Vivado 仍在运行修改前的 snapshot。
        // 处理方案（操作建议，不修改 RTL）：在 Vivado 中先 Reset Simulation，
        // 重新 Compile/Elaborate 后再 Run；确认日志打印的 TB 行号和下方新提示一致。
        // 推荐的命令行参数（路径可替换；仅建议，不写入工程配置）：
        // -testplusarg A_HEX=C:/Users/Suess/Desktop/design/KL_KEM/top_ntt_tb_data/input_a.hex
        // -testplusarg B_HEX=C:/Users/Suess/Desktop/design/KL_KEM/top_ntt_tb_data/input_b.hex
        // -testplusarg ZETA_HEX=C:/Users/Suess/Desktop/design/KL_KEM/zeta.txt
        // 无 plusarg 时优先使用 Vivado GUI 工作目录对应的工程相对路径；
        // Python 一键运行会传入独立目录的绝对路径。
        input_a_path = "../../../../top_ntt_tb_data/input_a.hex";
        input_b_path = "../../../../top_ntt_tb_data/input_b.hex";
        ntt_a_path = "dut_ntt_a.hex";
        ntt_b_path = "dut_ntt_b.hex";
        p2p_path = "dut_p2p.hex";
        output_path = "dut_output.hex";
        zeta_path = "../../../../zeta.txt";
        input_a_from_plusarg = $value$plusargs("A_HEX=%s", input_a_path);
        input_b_from_plusarg = $value$plusargs("B_HEX=%s", input_b_path);
        if ($value$plusargs("NTT_A_HEX=%s", ntt_a_path)) begin end
        if ($value$plusargs("NTT_B_HEX=%s", ntt_b_path)) begin end
        if ($value$plusargs("P2P_HEX=%s", p2p_path)) begin end
        if ($value$plusargs("OUTPUT_HEX=%s", output_path)) begin end
        zeta_from_plusarg = $value$plusargs("ZETA_HEX=%s", zeta_path);

        // 命令行显式路径必须存在；只有未传 plusarg 时才尝试 Vivado GUI 的
        // 默认工作目录回退。GUI 从 KL_KEM.sim/sim_1/behav/xsim 运行，
        // 向上四级正好回到工程根目录；第二路径兼容手工从含 hex 的目录运行。
        fd = $fopen(input_a_path, "r");
        if ((fd == 0) && (input_a_from_plusarg == 0)) begin
            input_a_path = "input_a.hex";
            fd = $fopen(input_a_path, "r");
        end
        if (fd == 0) begin
            $display("[TB-FAIL] cannot find input A; pass +A_HEX=<absolute path>");
            $finish;
        end
        else
            $fclose(fd);

        fd = $fopen(input_b_path, "r");
        if ((fd == 0) && (input_b_from_plusarg == 0)) begin
            input_b_path = "input_b.hex";
            fd = $fopen(input_b_path, "r");
        end
        if (fd == 0) begin
            $display("[TB-FAIL] cannot find input B; pass +B_HEX=<absolute path>");
            $finish;
        end
        else
            $fclose(fd);

        fd = $fopen(zeta_path, "r");
        if ((fd == 0) && (zeta_from_plusarg == 0)) begin
            zeta_path = "zeta.txt";
            fd = $fopen(zeta_path, "r");
        end
        if (fd == 0) begin
            $display("[TB-FAIL] cannot find zeta table; pass +ZETA_HEX=<absolute path>");
            $finish;
        end
        else
            $fclose(fd);

        $display("[TB] input A: %0s", input_a_path);
        $display("[TB] input B: %0s", input_b_path);
        $display("[TB] zeta table: %0s", zeta_path);
        // [TB REVIEW][TB-INPUT-01][修改后代码说明（当前已实现，无需重复添加）]
        // 正确顺序必须是：$value$plusargs 取得路径 -> $fopen 验证可读 ->
        // $readmemh 装载 -> 逐项检查 X/Z -> 最后才释放复位并驱动 DUT。
        // 不能只调用 $readmemh 后继续仿真，因为文件不存在时数组会保留 X。
        $readmemh(input_a_path, input_a);
        $readmemh(input_b_path, input_b);
        $readmemh(zeta_path, zeta_memory);

        // 在复位释放之前检查文件内容。归约异或遇到任意 X/Z 会得到 X，
        // 因而不会再把“文件没读到”误当成合法输入送给 DUT。
        for (i = 0; i < N; i = i + 1) begin
            if ((^input_a[i] === 1'bx) || (^input_b[i] === 1'bx)) begin
                $display("[TB-FAIL] input vector contains X/Z at coefficient %0d", i);
                $finish;
            end
            if ((input_a[i] >= Q) || (input_b[i] >= Q)) begin
                $display("[TB-FAIL] input coefficient %0d is outside [0,%0d]", i, Q-1);
                $finish;
            end
        end
        for (i = 0; i < ZETA_N; i = i + 1) begin
            if ((^zeta_memory[i] === 1'bx) || (zeta_memory[i] >= Q)) begin
                $display("[TB-FAIL] invalid zeta[%0d]", i);
                $finish;
            end
        end
        $display("[TB] input and zeta files verified before reset release");

        // 保持复位五个上升沿，在下降沿释放，避开 DUT 上升沿采样竞争。
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b1;

        // state_wait -> state_in 的过渡拍尚未推进装载地址，所以先送第 0 对，
        // 随后在正式循环中再送一次第 0 对，避免漏掉最初两个系数。
        din_vld = 1'b1;
        // [TB REVIEW][TB-INPUT-02][P2] 波形在 time=0 的初始 delta 出现短暂 X
        // 不代表有效事务错误；应只在 rst=1 且 din_vld=1 的上升沿检查输入。
        // 可选诊断代码（仅建议，未应用）：放在模块级，仿真时遇到有效 X 立即停止。
        // always @(posedge clk) begin
        //     if (rst && din_vld &&
        //         ((^ram1_in_1 === 1'bx) || (^ram1_in_2 === 1'bx) ||
        //          (^ram3_in_1 === 1'bx) || (^ram3_in_2 === 1'bx))) begin
        //         $display("[TB-FAIL] DUT input contains X/Z at cycle %0d", cycle_count);
        //         $finish;
        //     end
        // end
        ram1_in_1 = input_a[0];
        ram1_in_2 = input_a[1];
        ram3_in_1 = input_b[0];
        ram3_in_2 = input_b[1];
        @(posedge clk);
        for (i = 0; i < N/2; i = i + 1) begin
            // 下降沿更新激励，上升沿由 DUT/RAM 采样；128 对即完整的 256 项。
            @(negedge clk);
            ram1_in_1 = input_a[2*i];
            ram1_in_2 = input_a[2*i+1];
            ram3_in_1 = input_b[2*i];
            ram3_in_2 = input_b[2*i+1];
            @(posedge clk);
        end
        @(negedge clk);
        din_vld = 1'b0;
        ram1_in_1 = 0;
        ram1_in_2 = 0;
        ram3_in_1 = 0;
        ram3_in_2 = 0;
        $display("[TB] input load complete at cycle %0d", cycle_count);
        // 输入结束后直接核对同步 RAM 的内容，而不只检查输入文件是否正确。
        // !== 是四态比较，漏写造成的 X 同样会报错，不会被普通 != 忽略。
        for (i = 0; i < N; i = i + 1) begin
            if ((^ram0_i.ram_block[i] === 1'bx) ||
                (^ram2_i.ram_block[i] === 1'bx) ||
                ram0_i.ram_block[i] !== input_a[i] ||
                ram2_i.ram_block[i] !== input_b[i]) begin
                $display("[TB-FAIL] input RAM mismatch at coefficient %0d", i);
                $finish;
            end
        end
        $display("[TB] input RAM contents verified: A/B 256 coefficients each");

        // DUT 启动点乘表示其认为正变换完成；延迟 1 ns 避开本拍 NBA 更新。
        wait (dut.vld_p2p === 1'b1);
        #1;
        dump_ntt_a;
        dump_ntt_b;
        $display("[TB] NTT checkpoints written at cycle %0d", cycle_count);

        wait (dut.done_p2p === 1'b1);
        // done_p2p 在 RAM4 提交最后一对系数之前可见；再等一个上升沿和 1 ns，
        // 确保导出的 RAM4 包含最后一拍写入的数据。
        @(posedge clk);
        #1;
        dump_p2p;
        $display("[TB] pointwise checkpoint written at cycle %0d", cycle_count);

        wait (dut.INTT_begin === 1'b1);
        // 用内部完成信号确定 INTT 导出时刻；这不是跳过顶层完成检查，
        // 下方仍要求观察到公开的 finsh，否则 TB 报失败。
        wait (dut.finsh_NTT1 === 1'b1);
        #1;
        dump_output;
        // 内部完成早于顶层寄存后的 finsh；留出传播与监测寄存器更新的时间，
        // 防止 TB 因检查过早而误报“没有完成信号”。
        repeat (3) @(posedge clk);
        #1;
        if (finish_seen == 0) begin
            $display("[TB-FAIL] top_NTT.finsh was not observed high");
            $finish;
        end
        // TB-DONE 只说明已写出检查点并观察到完成；数值 PASS 必须由 Python 给出。
        $display("[TB-DONE] checkpoint files written, finsh observed at cycle %0d; numerical correctness requires Python check", cycle_count);
        if (trace_fd != 0) $fclose(trace_fd);
        $finish;
    end
endmodule
