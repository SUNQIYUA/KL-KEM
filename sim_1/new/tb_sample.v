`timescale 1ns / 1ps

module tb_sample();

    localparam TEST_IDLE = 2'd0;
    localparam TEST_CBD  = 2'd1;
    localparam TEST_REJ  = 2'd2;

    // 生成100 MHz时钟；工程内各模块使用低电平异步复位。
    reg clk;
    reg rst;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------
    // Keccak / SHAKE：接收测试种子，产生1600位Keccak状态。
    // ------------------------------------------------------------------
    reg  [63:0]   keccak_data_in;
    reg  [2:0]    keccak_mod;
    reg  [2:0]    keccak_din_vld;
    reg           keccak_over;
    reg           keccak_start;
    wire [1599:0] keccak_data_fin;
    wire          keccak_out_vld;

    shake_padder u_shake_padder (
        .data_in  (keccak_data_in),
        .mod      (keccak_mod),
        .din_vld  (keccak_din_vld),
        .over     (keccak_over),
        .start    (keccak_start),
        .clk      (clk),
        .rst      (rst),
        .data_fin (keccak_data_fin),
        .out_vld  (keccak_out_vld)
    );

    // ------------------------------------------------------------------
    // 真实buffer：锁存Keccak输出，并拆成1字节和3字节两条输出通道。
    // ------------------------------------------------------------------
    wire [7:0]  buffer_dout_1;
    wire [23:0] buffer_dout_2;
    wire        buffer_dout_1_vld;
    wire        buffer_dout_2_vld;

    squeeze_bufer u_squeeze_bufer (
        .clk        (clk),
        .rst        (rst),
        .din        (keccak_data_fin),
        .din_vld    (keccak_out_vld),
        .keccak_mod (keccak_mod),
        .dout_1     (buffer_dout_1),
        .dout_2     (buffer_dout_2),
        .dout_1_vld (buffer_dout_1_vld),
        .dout_2_vld (buffer_dout_2_vld)
    );

    // buffer的两个输出通道会同时工作。这里仿照top中的MUX，
    // 每次测试只使能对应的采样器，避免另一个采样器误接收数据。
    reg  [1:0] active_test;
    wire       cbd_din_vld;
    wire [7:0] cbd_data_in;
    wire       rej_din_vld;
    wire [7:0] rej_din_1;
    wire [7:0] rej_din_2;
    wire [7:0] rej_din_3;

    assign cbd_din_vld = (active_test == TEST_CBD) && buffer_dout_1_vld;
    assign cbd_data_in = buffer_dout_1;

    assign rej_din_vld = (active_test == TEST_REJ) && buffer_dout_2_vld;
    assign rej_din_1   = buffer_dout_2[7:0];
    assign rej_din_2   = buffer_dout_2[15:8];
    assign rej_din_3   = buffer_dout_2[23:16];

    // ------------------------------------------------------------------
    // CBD采样器：每次接收buffer输出的1个字节，生成2个系数。
    // ------------------------------------------------------------------
    wire        cbd_out_vld;
    wire [11:0] cbd_data_out_1;
    wire [11:0] cbd_data_out_2;
    wire [7:0]  cbd_addr_1;
    wire [7:0]  cbd_addr_2;
    wire        cbd_finish;

    CBD_sample u_CBD_sample (
        .clk        (clk),
        .rst        (rst),
        .data_in    (cbd_data_in),
        .din_vld    (cbd_din_vld),
        .out_vld    (cbd_out_vld),
        .data_out_1 (cbd_data_out_1),
        .data_out_2 (cbd_data_out_2),
        .adder_1    (cbd_addr_1),
        .adder_2    (cbd_addr_2),
        .finish     (cbd_finish)
    );

    // ------------------------------------------------------------------
    // 拒绝采样器：每次接收buffer输出的3个字节，重组为2个12位候选系数。
    // ------------------------------------------------------------------
    wire [7:0]  rej_addr_1;
    wire [7:0]  rej_addr_2;
    wire        rej_out_1_vld;
    wire        rej_out_2_vld;
    wire [11:0] rej_data_out_1;
    wire [11:0] rej_data_out_2;
    wire        rej_finish;

    reject_sample u_reject_sample (
        .clk        (clk),
        .rst        (rst),
        .din_vld    (rej_din_vld),
        .data_in_1  (rej_din_1),
        .data_in_2  (rej_din_2),
        .data_in_3  (rej_din_3),
        .adder_1    (rej_addr_1),
        .adder_2    (rej_addr_2),
        .out_1_vld  (rej_out_1_vld),
        .out_2_vld  (rej_out_2_vld),
        .data_out_1 (rej_data_out_1),
        .data_out_2 (rej_data_out_2),
        .finish     (rej_finish)
    );

    // ------------------------------------------------------------------
    // 自检计数器和参考值：用于逐拍检查整条数据链路，而不只依赖波形观察。
    // ------------------------------------------------------------------
    integer error_count;
    integer buffer_byte_count;
    integer buffer_word_count;
    integer cbd_output_count;
    integer rej_input_count;
    integer rej_output_count;
    integer result_fd;

    reg [1599:0] expected_buffer_data;
    reg          keccak_result_seen;

    reg [11:0] cbd_expected_1;
    reg [11:0] cbd_expected_2;
    reg        cbd_expected_valid;
    reg        cbd_unknown_reported;

    reg [11:0] rej_expected_1;
    reg [11:0] rej_expected_2;
    reg        rej_expected_vld_1;
    reg        rej_expected_vld_2;

    function [11:0] cbd_coefficient_0;
        input [7:0] value;
        integer x;
        integer y;
        begin
            x = value[0] + value[1];
            y = value[2] + value[3];
            if (y > x)
                cbd_coefficient_0 = 12'd3329 - (y - x);
            else
                cbd_coefficient_0 = x - y;
        end
    endfunction

    function [11:0] cbd_coefficient_1;
        input [7:0] value;
        integer x;
        integer y;
        begin
            x = value[4] + value[5];
            y = value[6] + value[7];
            if (y > x)
                cbd_coefficient_1 = 12'd3329 - (y - x);
            else
                cbd_coefficient_1 = x - y;
        end
    endfunction

    // 在Keccak结果有效时保存其rate区域，作为buffer输出的逐字节参考值。
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            expected_buffer_data <= 1600'd0;
            keccak_result_seen    <= 1'b0;
        end
        else if (keccak_out_vld && !keccak_result_seen) begin
            expected_buffer_data <= 1600'd0;
            if (keccak_mod == 3'd1)
                expected_buffer_data[1343:0] <= keccak_data_fin[1343:0];
            else if (keccak_mod == 3'd2)
                expected_buffer_data[1087:0] <= keccak_data_fin[1087:0];
            keccak_result_seen <= 1'b1;
            $display("[%0t] Keccak output captured by reference monitor (mode=%0d)",
                     $time, keccak_mod);
        end
    end

    // 在上升沿记录采样器实际接收的数据，并用独立公式计算期望结果。
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cbd_expected_1     <= 12'd0;
            cbd_expected_2     <= 12'd0;
            cbd_expected_valid <= 1'b0;
            rej_expected_1     <= 12'd0;
            rej_expected_2     <= 12'd0;
            rej_expected_vld_1 <= 1'b0;
            rej_expected_vld_2 <= 1'b0;
        end
        else begin
            cbd_expected_valid <= cbd_din_vld;
            if (cbd_din_vld) begin
                cbd_expected_1 <= cbd_coefficient_0(cbd_data_in);
                cbd_expected_2 <= cbd_coefficient_1(cbd_data_in);
            end

            rej_expected_vld_1 <= rej_din_vld && ({rej_din_2[3:0], rej_din_1} < 3329);
            rej_expected_vld_2 <= rej_din_vld && ({rej_din_3, rej_din_2[7:4]} < 3329);
            if (rej_din_vld) begin
                rej_expected_1 <= {rej_din_2[3:0], rej_din_1};
                rej_expected_2 <= {rej_din_3, rej_din_2[7:4]};
            end
        end
    end

    // 在下降沿比较结果，此时上升沿触发的非阻塞赋值已经全部稳定。
    always @(negedge clk) begin
        if (rst) begin
            if (buffer_dout_1_vld) begin
                // SHAKE-256测试使用1字节通道；按传输顺序写入结果文件。
                if (active_test == TEST_CBD) begin
                    $fwrite(result_fd, "%02x", buffer_dout_1);
                    if (buffer_byte_count == 127)
                        $fwrite(result_fd, "\n");
                end
                if (buffer_dout_1 !== expected_buffer_data[buffer_byte_count*8 +: 8]) begin
                    $display("[ERROR][BUFFER-1] index=%0d expected=%02x actual=%02x",
                             buffer_byte_count,
                             expected_buffer_data[buffer_byte_count*8 +: 8],
                             buffer_dout_1);
                    error_count = error_count + 1;
                end
                buffer_byte_count = buffer_byte_count + 1;
            end

            if (buffer_dout_2_vld) begin
                // 24位总线按低字节在前的顺序还原成SHAKE-128字节流。
                if (active_test == TEST_REJ) begin
                    $fwrite(result_fd, "%02x%02x%02x",
                            buffer_dout_2[7:0], buffer_dout_2[15:8],
                            buffer_dout_2[23:16]);
                    if (buffer_word_count == 55)
                        $fwrite(result_fd, "\n");
                end
                if (buffer_dout_2 !== expected_buffer_data[buffer_word_count*24 +: 24]) begin
                    $display("[ERROR][BUFFER-2] index=%0d expected=%06x actual=%06x",
                             buffer_word_count,
                             expected_buffer_data[buffer_word_count*24 +: 24],
                             buffer_dout_2);
                    error_count = error_count + 1;
                end
                buffer_word_count = buffer_word_count + 1;
            end

            if (cbd_expected_valid) begin
                if (!cbd_out_vld || (cbd_data_out_1 !== cbd_expected_1) ||
                    (cbd_data_out_2 !== cbd_expected_2)) begin
                    $display("[ERROR][CBD] input_index=%0d expected=(%0d,%0d) actual_vld=%b actual=(%0d,%0d)",
                             cbd_output_count, cbd_expected_1, cbd_expected_2,
                             cbd_out_vld, cbd_data_out_1, cbd_data_out_2);
                    error_count = error_count + 1;
                end
                cbd_output_count = cbd_output_count + 1;

                if (!cbd_unknown_reported &&
                    (((^cbd_addr_1) === 1'bx) || ((^cbd_addr_2) === 1'bx))) begin
                    $display("[ERROR][CBD-ADDR] sampler produced an unknown address at input_index=%0d",
                             cbd_output_count - 1);
                    error_count = error_count + 1;
                    cbd_unknown_reported = 1'b1;
                end
            end

            if ((rej_out_1_vld !== rej_expected_vld_1) ||
                (rej_out_2_vld !== rej_expected_vld_2)) begin
                $display("[ERROR][REJ-VLD] input_index=%0d expected=(%b,%b) actual=(%b,%b)",
                         rej_input_count, rej_expected_vld_1, rej_expected_vld_2,
                         rej_out_1_vld, rej_out_2_vld);
                error_count = error_count + 1;
            end
            if (rej_expected_vld_1 &&
                ((!rej_out_1_vld) || (rej_data_out_1 !== rej_expected_1))) begin
                $display("[ERROR][REJ-1] input_index=%0d expected=%0d actual=%0d",
                         rej_input_count, rej_expected_1, rej_data_out_1);
                error_count = error_count + 1;
            end
            if (rej_expected_vld_2 &&
                ((!rej_out_2_vld) || (rej_data_out_2 !== rej_expected_2))) begin
                $display("[ERROR][REJ-2] input_index=%0d expected=%0d actual=%0d",
                         rej_input_count, rej_expected_2, rej_data_out_2);
                error_count = error_count + 1;
            end
            if (rej_expected_vld_1)
                rej_output_count = rej_output_count + 1;
            if (rej_expected_vld_2)
                rej_output_count = rej_output_count + 1;
            if (rej_din_vld)
                rej_input_count = rej_input_count + 1;
        end
    end

    task reset_datapath;
        begin
            active_test       = TEST_IDLE;
            keccak_start      = 1'b0;
            keccak_over       = 1'b0;
            keccak_din_vld    = 3'd0;
            keccak_data_in    = 64'd0;
            keccak_mod        = 3'd0;
            rst               = 1'b0;
            buffer_byte_count = 0;
            buffer_word_count = 0;
            cbd_output_count  = 0;
            rej_input_count   = 0;
            rej_output_count  = 0;
            cbd_unknown_reported = 1'b0;
            repeat (3) @(negedge clk);
            rst = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task start_one_block;
        input [2:0]  mode;
        input [63:0] last_data;
        input [2:0]  valid_bytes;
        begin
            // 在下降沿施加激励，保证下一个上升沿采样时信号已经稳定。
            @(negedge clk);
            keccak_mod     = mode;
            keccak_data_in = last_data;
            keccak_din_vld = valid_bytes;
            keccak_start   = 1'b1;
            keccak_over    = 1'b1;
            @(negedge clk);
            keccak_start   = 1'b0;
            keccak_over    = 1'b0;
        end
    endtask

    initial begin
        error_count = 0;
        rst = 1'b0;
        active_test = TEST_IDLE;
        keccak_start = 1'b0;
        keccak_over = 1'b0;
        keccak_din_vld = 3'd0;
        keccak_data_in = 64'd0;
        keccak_mod = 3'd0;

        // 结果文件采用KEY=HEX格式，便于Python脚本直接读取并校验。
        result_fd = $fopen("tb_sample_results.txt", "w");
        if (result_fd == 0) begin
            $display("[ERROR] 无法创建tb_sample_results.txt");
            $finish;
        end

        // 测试1：7字节种子经过SHAKE-256和buffer后送入CBD采样器。
        reset_datapath;
        active_test = TEST_CBD;
        $display("========== [TEST 1] SHAKE-256 -> BUFFER -> CBD ==========");
        $fdisplay(result_fd, "SHAKE256_MSG=1100ffeeddccbb");
        $fwrite(result_fd, "SHAKE256_OUT=");
        start_one_block(3'd2, 64'h00BBCCDDEEFF0011, 3'd7);
        @(posedge keccak_out_vld);
        wait (buffer_dout_1_vld === 1'b1);
        // keccak_mod必须保持到buffer完成同步锁存，否则buffer无法判断rate宽度。
        @(negedge clk);
        keccak_mod = 3'd0;
        wait (buffer_byte_count == 128);
        @(negedge clk);
        active_test = TEST_IDLE;
        $display("[TEST 1] buffer bytes=%0d, CBD outputs=%0d, cbd_finish=%b",
                 buffer_byte_count, cbd_output_count, cbd_finish);
        if (cbd_output_count != 128) begin
            $display("[ERROR][CBD-COUNT] expected 128 output pairs, actual=%0d",
                     cbd_output_count);
            error_count = error_count + 1;
        end
        if (cbd_finish !== 1'b1) begin
            $display("[ERROR][CBD-FINISH] expected finish=1 after 128 input bytes, actual=%b",
                     cbd_finish);
            error_count = error_count + 1;
        end

        // 测试2：7字节种子经过SHAKE-128和buffer后送入拒绝采样器。
        reset_datapath;
        active_test = TEST_REJ;
        $display("========== [TEST 2] SHAKE-128 -> BUFFER -> REJECTION ==========");
        $fdisplay(result_fd, "SHAKE128_MSG=efcdab90785634");
        $fwrite(result_fd, "SHAKE128_OUT=");
        start_one_block(3'd1, 64'h0034567890ABCDEF, 3'd7);
        @(posedge keccak_out_vld);
        wait (buffer_dout_2_vld === 1'b1);
        @(negedge clk);
        keccak_mod = 3'd0;
        wait (buffer_word_count == 56);
        @(negedge clk);
        active_test = TEST_IDLE;
        $display("[TEST 2] buffer words=%0d, accepted coefficients=%0d, rej_finish=%b",
                 buffer_word_count, rej_output_count, rej_finish);
        if (rej_input_count != 56) begin
            $display("[ERROR][REJ-COUNT] expected 56 input words, actual=%0d",
                     rej_input_count);
            error_count = error_count + 1;
        end

        repeat (3) @(negedge clk);
        if (error_count == 0)
            $display("========== PASS: keccak-buffer-sample datapath ==========");
        else
            $display("========== FAIL: %0d datapath error(s) ==========" , error_count);
        $fclose(result_fd);
        $finish;
    end

    // 超时保护：有效信号或数据通路卡死时，仿真会明确报错而不是一直等待。
    initial begin
        #20000;
        $display("[ERROR][TIMEOUT] keccak-buffer-sample datapath did not complete");
        $finish;
    end

endmodule
