`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/14 23:44:25
// Design Name: 
// Module Name: squeeze_bufer
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

module squeeze_bufer(
    input              clk,
    input              rst,
    input [1599:0]     din,
    input              din_vld,
    input [2:0]        keccak_mod,

    output reg [7:0]   dout_1,
    output reg [23:0]  dout_2,
    output reg [11:0]  dout_3,
    output reg         dout_1_vld,
    output reg         dout_2_vld,
    output reg         dout_3_vld
    );

// 接口约定（端口保持不变）：每个 din_vld 有效沿表示一块数据。
// mode=0 的有效拍清空任务；mode=1 输出56组24位；mode=2 首块输出128字节，
// 再与第二块前56字节拼接，供第三路输出128组12位。均从低位开始输出。
// 新多项式前必须清空，同一多项式两块之间不能清空；mode本身不能区分eta=2/3。
// 无 ready 端口：mode=1 连续块至少间隔56拍（支持末组输出同拍接收下一块）；
// mode=2 的两块可连续两拍输入。跨任务清空须在下游消费旧任务后执行。

reg [7:0] cnt_1, cnt_2, cnt_3;
reg [1599:0] data_1, data_2, data_3;
reg start_1, start_2, start_3;

localparam WAIT_FIRST  = 2'd0;
localparam WAIT_SECOND = 2'd1;
localparam COLLECTED   = 2'd2;
reg [1:0] phase_3;

// 不再用三路 busy 的公共条件阻塞第二块；每条输入只检查它会修改的上下文。
wire accept_128;
wire accept_256_first;
wire accept_256_second;
assign accept_128 = din_vld && (keccak_mod == 3'd1) && (phase_3 == WAIT_FIRST) && !start_1 && !start_3 && (!start_2 || (cnt_2 == 8'd55));
assign accept_256_first = din_vld && (keccak_mod == 3'd2) && (phase_3 == WAIT_FIRST) && !start_1 && !start_2 && !start_3;
assign accept_256_second = din_vld && (keccak_mod == 3'd2) && (phase_3 == WAIT_SECOND) && !start_2 && !start_3;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        cnt_1 <= 8'd0;
        cnt_2 <= 8'd0;
        cnt_3 <= 8'd0;
        data_1 <= 1600'd0;
        data_2 <= 1600'd0;
        data_3 <= 1600'd0;
        start_1 <= 1'b0;
        start_2 <= 1'b0;
        start_3 <= 1'b0;
        phase_3 <= WAIT_FIRST;
        dout_1 <= 8'd0;
        dout_2 <= 24'd0;
        dout_3 <= 12'd0;
        dout_1_vld <= 1'b0;
        dout_2_vld <= 1'b0;
        dout_3_vld <= 1'b0;
    end else if (din_vld && (keccak_mod == 3'd0)) begin
        // 同步清空最高优先级：忙时也生效，本拍不再执行输出或装载。
        cnt_1 <= 8'd0;
        cnt_2 <= 8'd0;
        cnt_3 <= 8'd0;
        data_1 <= 1600'd0;
        data_2 <= 1600'd0;
        data_3 <= 1600'd0;
        start_1 <= 1'b0;
        start_2 <= 1'b0;
        start_3 <= 1'b0;
        phase_3 <= WAIT_FIRST;
        dout_1 <= 8'd0;
        dout_2 <= 24'd0;
        dout_3 <= 12'd0;
        dout_1_vld <= 1'b0;
        dout_2_vld <= 1'b0;
        dout_3_vld <= 1'b0;
    end else begin
        // valid 只标记本拍新输出；最后一组后自动停止，不重复最后的数据。
        dout_1_vld <= 1'b0;
        dout_2_vld <= 1'b0;
        dout_3_vld <= 1'b0;

        if (start_1) begin
            dout_1 <= data_1[7:0];
            dout_1_vld <= 1'b1;
            data_1 <= data_1 >> 8;
            if (cnt_1 == 8'd127) begin
                cnt_1 <= 8'd0;
                start_1 <= 1'b0;
            end else begin
                cnt_1 <= cnt_1 + 8'd1;
            end
        end

        if (start_2) begin
            dout_2 <= data_2[23:0];
            dout_2_vld <= 1'b1;
            data_2 <= data_2 >> 24;
            if (cnt_2 == 8'd55) begin
                cnt_2 <= 8'd0;
                start_2 <= 1'b0;
            end else begin
                cnt_2 <= cnt_2 + 8'd1;
            end
        end

        if (start_3) begin
            dout_3 <= data_3[11:0];
            dout_3_vld <= 1'b1;
            data_3 <= data_3 >> 12;
            if (cnt_3 == 8'd127) begin
                cnt_3 <= 8'd0;
                start_3 <= 1'b0;
                // 保留 COLLECTED，后续多余块不重新生成多项式；下一任务由mode0清空。
            end else begin
                cnt_3 <= cnt_3 + 8'd1;
            end
        end

        // 装载放在移位之后：SHAKE128末组输出用旧data_2，同时新块覆盖移位结果，次拍继续输出。
        if (accept_128) begin
            data_2 <= {256'd0, din[1343:0]};
            cnt_2 <= 8'd0;
            start_2 <= 1'b1;
        end

        if (accept_256_first) begin
            data_1 <= {512'd0, din[1087:0]};
            cnt_1 <= 8'd0;
            start_1 <= 1'b1;
            data_3 <= {512'd0, din[1087:0]};
            cnt_3 <= 8'd0;
            phase_3 <= WAIT_SECOND;
        end else if (accept_256_second) begin
            // 第二块只操作第三路；第一路可继续输出，不被重装或截断。
            data_3 <= {64'd0, din[447:0], data_3[1087:0]};
            cnt_3 <= 8'd0;
            start_3 <= 1'b1;
            phase_3 <= COLLECTED;
        end
    end
end
endmodule
