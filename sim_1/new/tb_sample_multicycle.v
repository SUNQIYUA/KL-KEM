`timescale 1ns / 1ps

// 独立通路测试：不例化尚未完成的top发送状态机，不修改/force任何DUT内部寄存器。
// 字节约定：种子第0字节放在总线[7:0]，每个start有效拍发送8字节。
// over拍发送0..7字节尾段；32字节整消息也需要额外的over=1,din_vld=0填充拍。
// 使用 verification/sample_multicycle/run.ps1 生成输入、运行XSim并交给Python校验。
module tb_sample_multicycle;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 0;
    reg [63:0] data_in = 0;
    reg [2:0] mode = 0, last_bytes = 0;
    reg start = 0, over = 0;
    wire [1599:0] hash_data;
    wire hash_valid;
    wire [7:0] byte_data;
    wire [23:0] word_data;
    wire byte_valid, word_valid;
    wire cbd_valid, cbd_finish, rej_valid_1, rej_valid_2, rej_finish;
    wire [7:0] cbd_addr_1, cbd_addr_2, rej_addr_1, rej_addr_2;
    wire [11:0] cbd_data_1, cbd_data_2, rej_data_1, rej_data_2;
    integer case_id = -1, test_mode = 0;
    reg active = 0;

    shake_padder u_keccak (
        .clk(clk), .rst(rst), .data_in(data_in), .mod(mode),
        .din_vld(last_bytes), .start(start), .over(over),
        .data_fin(hash_data), .out_vld(hash_valid)
    );
    squeeze_bufer u_buffer (
        .clk(clk), .rst(rst), .din(hash_data), .din_vld(hash_valid),
        .keccak_mod(mode), .dout_1(byte_data), .dout_2(word_data),
        .dout_1_vld(byte_valid), .dout_2_vld(word_valid)
    );
    // 只把当前模式对应的通道送入采样器，与top的通路选择意图一致。
    CBD_sample u_cbd (
        .clk(clk), .rst(rst), .din_vld(active && test_mode == 2 && byte_valid),
        .data_in(byte_data), .out_vld(cbd_valid), .finish(cbd_finish),
        .adder_1(cbd_addr_1), .adder_2(cbd_addr_2),
        .data_out_1(cbd_data_1), .data_out_2(cbd_data_2)
    );
    reject_sample u_rej (
        .clk(clk), .rst(rst), .din_vld(active && test_mode == 1 && word_valid),
        .data_in_1(word_data[7:0]), .data_in_2(word_data[15:8]),
        .data_in_3(word_data[23:16]), .out_1_vld(rej_valid_1),
        .out_2_vld(rej_valid_2), .finish(rej_finish),
        .adder_1(rej_addr_1), .adder_2(rej_addr_2),
        .data_out_1(rej_data_1), .data_out_2(rej_data_2)
    );

    // 逐拍记录：IN为上升沿实际输入；HASH/BUF为下游在该沿实际接收的数据。
    // CBD/REJ在#1后记录本拍计算结果，Python据此验证逐拍valid与延迟、地址和数据。
    integer fd, stim, rc, total_cases, length, gap, hold_mode;
    integer i, j, w, t, b, cycle = 0, hash_count = 0;
    reg [7:0] message [0:199];
    reg [1599:0] packed_message;
    reg seen_hash = 0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (rst && active) begin
            if (start || over)
                $fdisplay(fd, "IN %0d %0d %0d %0d %0d %016x %0d",
                          case_id, cycle, start, over, last_bytes, data_in, u_keccak.cnt);
            if (hash_valid) begin
                hash_count = hash_count + 1;
                if (!seen_hash) begin
                    $fwrite(fd, "HASH %0d %0d ", case_id, cycle);
                    for (b = 0; b < ((test_mode == 1) ? 168 : 136); b = b + 1)
                        $fwrite(fd, "%02x", hash_data[b*8 +: 8]);
                    $fwrite(fd, "\n");
                    seen_hash = 1;
                end
            end
            if (test_mode == 2 && byte_valid)
                $fdisplay(fd, "BUF %0d %0d %02x", case_id, cycle, byte_data);
            if (test_mode == 1 && word_valid)
                $fdisplay(fd, "BUF %0d %0d %02x%02x%02x", case_id, cycle,
                          word_data[7:0], word_data[15:8], word_data[23:16]);
            #1;
            if (test_mode == 2)
                $fdisplay(fd, "CBD %0d %0d %b %02x %03x %02x %03x %b", case_id,
                          cycle, cbd_valid, cbd_addr_1, cbd_data_1, cbd_addr_2, cbd_data_2, cbd_finish);
            else
                $fdisplay(fd, "REJ %0d %0d %b %02x %03x %b %02x %03x %b", case_id,
                          cycle, rej_valid_1, rej_addr_1, rej_data_1,
                          rej_valid_2, rej_addr_2, rej_data_2, rej_finish);
        end
    end

    initial begin
        stim = $fopen("vectors.txt", "r");
        fd = $fopen("trace.txt", "w");
        if (!stim || !fd) $fatal(1, "Cannot open stimulus/trace file");
        rc = $fscanf(stim, "%d", total_cases);
        if (rc != 1) $fatal(1, "Bad vector header");
        for (i = 0; i < total_cases; i = i + 1) begin
            // 每个用例独立复位；此套测试验证单条消息多拍输入，不宣称覆盖连续任务重启。
            @(negedge clk);
            active = 0; rst = 0; mode = 0; start = 0; over = 0;
            data_in = 0; last_bytes = 0; seen_hash = 0; hash_count = 0;
            case_id = i;
            rc = $fscanf(stim, "%d %d %d %d", test_mode, length, gap, hold_mode);
            if (rc != 4 || length < 0 || length > 199) $fatal(1, "Bad case header");
            packed_message = 0;
            for (j = 0; j < length; j = j + 1) begin
                rc = $fscanf(stim, "%h", message[j]);
                if (rc != 1) $fatal(1, "Missing message byte");
                packed_message[j*8 +: 8] = message[j];
            end
            repeat (3) @(negedge clk);
            rst = 1; active = 1; mode = test_mode;
            $fdisplay(fd, "CASE %0d %0d %0d %0d %0d", case_id, test_mode, length, gap, hold_mode);
            // 四个64位字正常只各发送一次，不重复首字去迁就DUT。
            for (w = 0; w < length / 8; w = w + 1) begin
                data_in = packed_message[w*64 +: 64];
                start = 1; over = 0; last_bytes = 0;
                @(negedge clk);
                start = 0;
                repeat (gap) @(negedge clk);
            end
            data_in = packed_message >> (8*(length - length % 8));
            start = 0; over = 1; last_bytes = length % 8;
            @(negedge clk);
            over = 0; data_in = 0;
            // 正常用例：buffer在上升沿接收首块后才清mode。
            // hold_mode用例：刻意保持mode，验证“一条请求只产生一个结果脉冲”。
            for (t = 0; t < 165; t = t + 1) begin
                @(negedge clk);
                if (seen_hash && !hold_mode) mode = 0;
            end
            $fdisplay(fd, "END %0d %0d %b %b", case_id, hash_count, cbd_finish, rej_finish);
            $display("[CASE %0d] mode=%0d bytes=%0d gaps=%0d hold=%0d hash_valid_cycles=%0d",
                     case_id, test_mode, length, gap, hold_mode, hash_count);
            active = 0;
        end
        $fdisplay(fd, "DONE %0d", total_cases);
        $fclose(stim); $fclose(fd);
        $display("Trace complete; run Python verification for PASS/FAIL.");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Multicycle test timed out");
    end
endmodule
