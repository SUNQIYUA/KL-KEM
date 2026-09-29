`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 19:17:16
// Design Name: 
// Module Name: shake_padder
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


module shake_padder(
    input [63:0] data_in,           //输入总线，以字节为单位，64位即8个字节
    input [2:0]  mod,               //希望采用何种规则

    input [2:0] din_vld,            //最后一段中有效字节的数量
    input       over,               //是否是最后一段

    input start,

    input clk,
    input rst,

    output      [1599:0] data_all,  //未被截取的keccak处理后信号
    output reg  [1599:0] data_fin,
    output reg           out_vld    //输出有效信号      

    );

localparam s0 = 0;
localparam s1 = 1;
localparam s2 = 2;
localparam s3 = 3;
localparam s4 = 4;

parameter  r1 = 168;                //SHAKE-128
parameter  r2 = 136;                //SHAKE-256
parameter  r3 = 136;                //SHA-256
parameter  r4 = 72 ;                //SHA-512


reg  [63:0]   padder_sha;
reg  [63:0]   padder_shake;

wire  [7:0]   vld_num;

reg  [7:0]    cnt;                //字节计数器，但实际依然以bit数作为计数，将（cnt>>3）作为字节数，作为将输入数据分段的依据
reg  [3:0]    over_cnt;           //论数计数器

reg           ready;             //数据输入中止后使能信号

reg  [1:0]    rd_cnt;
reg  [3:0]    out_cnt;

reg   [63:0]   data_1   [24:0];  //采用二维数组拼接的形式，防止出现动态索引
wire  [1599:0] data;             //存储输入的数据，作为输入传输进轮函数

wire [63:0]   rc_par   [23:0];

reg           choose;
reg  [1599:0] data_out;

wire [1599:0] data_aft[23:0];

reg cfig;

assign vld_num = din_vld<<3;

//RC值
assign rc_par[0]  = 64'h0000000000000001;
assign rc_par[1]  = 64'h0000000000008082;
assign rc_par[2]  = 64'h800000000000808A;
assign rc_par[3]  = 64'h8000000080008000;
assign rc_par[4]  = 64'h000000000000808B;
assign rc_par[5]  = 64'h0000000080000001;
assign rc_par[6]  = 64'h8000000080008081;
assign rc_par[7]  = 64'h8000000000008009;
assign rc_par[8]  = 64'h000000000000008A;
assign rc_par[9]  = 64'h0000000000000088;
assign rc_par[10] = 64'h0000000080008009;
assign rc_par[11] = 64'h000000008000000A;
assign rc_par[12] = 64'h000000008000808B;
assign rc_par[13] = 64'h800000000000008B;
assign rc_par[14] = 64'h8000000000008089;
assign rc_par[15] = 64'h8000000000008003;
assign rc_par[16] = 64'h8000000000008002;
assign rc_par[17] = 64'h8000000000000080;
assign rc_par[18] = 64'h000000000000800A;
assign rc_par[19] = 64'h800000008000000A;
assign rc_par[20] = 64'h8000000080008081;
assign rc_par[21] = 64'h8000000000008080;
assign rc_par[22] = 64'h0000000080000001;
assign rc_par[23] = 64'h8000000080008008;



assign data_all = data_aft[23];

//拼接输入数据组data
generate
    genvar m;
    for (m = 0; m < 25; m = m + 1)begin:data_block
        assign data[64*m +: 64] = data_1[m];
    end
endgenerate



//根据不同填充规则进行填充
always @(*) begin
    case(din_vld)
        3'd0:
            begin
                padder_sha   = {56'h0, 8'h06};
                padder_shake = {56'h0, 8'h1F};
            end
        3'd1:
            begin
                padder_sha   = {48'h0, 8'h06, data_in[7:0]};
                padder_shake = {48'h0, 8'h1F, data_in[7:0]};
            end
        3'd2:
            begin
                padder_sha   = {40'h0, 8'h06, data_in[15:0]};
                padder_shake = {40'h0, 8'h1F, data_in[15:0]};
            end
        3'd3:
            begin
                padder_sha   = {32'h0, 8'h06, data_in[23:0]};
                padder_shake = {32'h0, 8'h1F, data_in[23:0]};
            end
        3'd4:
            begin
                padder_sha   = {24'h0, 8'h06, data_in[31:0]};
                padder_shake = {24'h0, 8'h1F, data_in[31:0]};
            end
        3'd5:
            begin
                padder_sha   = {16'h0, 8'h06, data_in[39:0]};
                padder_shake = {16'h0, 8'h1F, data_in[39:0]};
            end
        3'd6:
            begin
                padder_sha   = {8'h0,  8'h06, data_in[47:0]};
                padder_shake = {8'h0,  8'h1F, data_in[47:0]};
            end
        3'd7:
            begin
                padder_sha   = {8'h06, data_in[55:0]};
                padder_shake = {8'h1F, data_in[55:0]};
            end
        default:
            begin
                padder_sha   = 64'd0;
                padder_shake = 64'd0;
            end
    endcase
end

//不同规则下，r的取值不同
always @(posedge clk or negedge rst) begin:main_block

    //integer i;
    integer j;
    integer k;
    integer m;
    integer n;
    if (!rst) begin
        cnt      <= 0;
        ready    <= 0;
        over_cnt <= 0;
        rd_cnt   <= 0;
        choose   <= 0;
        out_vld  <= 0;
        out_cnt  <= 0;
        for (n = 0; n < 25; n = n + 1)begin:reset_2_block
                            data_1[n] <= 0;
        end
    end
    else begin
        // [MC-02][P1][2026-09-22] 默认清零不能保证单拍脉冲：下方ready/rd_cnt==2
        // 在模式不变时每拍重新赋out_vld=1。hold_mode两例均测到163个有效采样沿，
        // buffer空闲后重装同一块，出现额外采样输出。见tb_sample_multicycle。
        // 修改后代码（仅建议，未应用）：在s1、s2各自的rd_cnt==2输出分支中，
        // 保留data_fin/out_vld赋值，分别再加入以下两行，消费掉本次ready请求：
        // ready  <= 1'b0;
        // rd_cnt <= 2'd0;
        // 验证：与MC-01一起在临时副本应用后，XSim+Python的14组测试全部通过；工程RTL未应用。
        // 这是单消息首块输出的局部候选；下一消息仍需mod=0清状态。
        // 不能把此候选当成跨rate吸收或连续squeeze实现，后者需保留1600位状态和握手。
        out_vld <= 0; //out_vld默认为0，当输出准备完毕时，短暂拉高，形成脉冲
        case(mod)
            s0: 
                begin
                    for (k = 0; k < 25; k = k + 1)begin:reset_block
                        data_1[k] <= 0;
                    end
                    cnt       <= 0;
                    ready     <= 0;
                    choose    <= 0;
                    over_cnt  <= 0;
                    rd_cnt    <= 0;
                    out_vld   <= 0;
                end

            //SHAKE-128

            s1: 
                begin
                    if (over) begin
                        if (cnt == r1-8) begin
                            data_1[cnt>>3] <= padder_shake | 64'h8000_0000_0000_000;  //将最后一位，即data_1[63] = 1,使其符合pad 101规则
                            over_cnt       <= 1;
                            ready          <= 1;
                            rd_cnt         <= 1;
                            //cfig           <= 1;
                        end
                        else begin
                            data_1[cnt>>3] <= padder_shake;
                            data_1[20]     <= 64'h8000_0000_0000_0000;
                            over_cnt       <= 1;
                            rd_cnt         <= 1;
                            ready          <= 1;
                            // 将当前拼接位与末尾位之间的所有暂存器全部清零
                            for (m = 0; m < 20; m = m + 1) begin
                                if (m > (cnt>>3)) begin
                                    data_1[m] <= 64'd0;
                                end
                            end
                            //cfig           <= 1;
                        end
                    end
                    else if (start) begin
                        data_1[cnt>>3] <= data_in;
                        if (cnt == r1-8) begin
                            cnt      <= 0;
                        end
                        else if ((cnt == 0)&(!rd_cnt))begin
                            rd_cnt   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else if ((cnt == 0)&(rd_cnt))begin
                            data_out <= data[8*r1-1:0]^(choose ? data_fin[8*r1-1:0]:0);
                            choose   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else begin
                            cnt      <= cnt + 8;
                            data_fin <= data_aft[23][8*r1-1:0];
                        end
                    end
                    else if (ready) begin
                        if (rd_cnt == 1) begin
                            data_out <= data[8*r1-1:0]^(choose ? data_fin[8*r1-1:0]:0);
                            choose   <= 1;
                            rd_cnt   <= rd_cnt + 1;
                        end
                        else if (rd_cnt == 2) begin
                            data_fin <= data_aft[23][8*r1-1:0];
                            out_vld  <= 1;
                            //计算完成后复位
                            ready    <= 0;
                            rd_cnt   <= 0;
                        end
                        //over_cnt <= over_cnt + 1;
                    end
                end

            //SHAKE-256
            s2: 
                begin
                    if (over) begin
                         if (cnt == r2-8) begin
                            data_1[cnt>>3] <= padder_shake | 64'h8000_0000_0000_0000;
                            rd_cnt         <= 1;
                            ready          <= 1;
                            //over_cnt       <= 1;
                        end
                        else begin
                            data_1[cnt>>3] <= padder_shake;
                            data_1[16]  <= 64'h8000_0000_0000_0000;
                            over_cnt    <= 1;
                            rd_cnt      <= 1;
                            ready       <= 1;
                            // 将当前拼接位与末尾位之间的所有暂存器全部清零
                            for (m = 0; m < 16; m = m + 1) begin
                                if (m > (cnt>>3)) begin
                                    data_1[m] <= 64'd0;
                                end
                            end
                            //over_cnt <= over_cnt + 1;
                        end
                    end
                    else if (start) begin
                        data_1[cnt>>3] <= data_in;
                        if (cnt == r2-8) begin
                            cnt      <= 0;
                        end
                        else if ((cnt == 0)&(!rd_cnt))begin
                            rd_cnt   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else if ((cnt == 0)&(rd_cnt))begin
                            //ready    <= 1;
                            data_out <= data[8*r2-1:0]^(choose ? data_fin[8*r2-1:0]:0);
                            choose   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else begin
                            cnt      <= cnt +8;
                            ready    <= 0;
                            data_fin <= data_aft[23][8*r2-1:0];
                        end
                    end
                    else if (ready) begin
                        if (rd_cnt == 1) begin
                            data_out <= data[8*r2-1:0]^(choose ? data_fin[8*r2-1:0]:0);
                            choose   <= 1;
                            rd_cnt   <= rd_cnt + 1;
                        end
                        else if (rd_cnt == 2) begin
                            data_fin <= data_aft[23][8*r2-1:0];
                            out_vld  <= 1;
                            //计算完成后复位
                            ready    <= 0;
                            rd_cnt   <= 0;
                        end
                    end
                end

            //SHA-256

            s3: 
                begin
                    if (over) begin
                     if (cnt == r3-8) begin
                        data_1[cnt>>3] <= padder_shake | 64'h8000_0000_0000_0000;
                        rd_cnt         <= 1;
                        ready          <= 1; 
                    end
                    else begin
                        data_1[cnt>>3] <= padder_shake;
                        data_1[16]     <= 64'h8000_0000_0000_0000;
                        rd_cnt         <= 1;
                        ready          <= 1; 
                        // 将当前拼接位与末尾位之间的所有暂存器全部清零
                            for (m = 0; m < 16; m = m + 1) begin
                                if (m > (cnt>>3)) begin
                                    data_1[m] <= 64'd0;
                                end
                            end
                    end
                end
                    else if (start) begin
                        data_1[cnt>>3] <= data_in;
                        if (cnt == r3-8) begin
                            cnt      <= 0;
                        end
                        else if ((cnt == 0)&(!rd_cnt))begin
                            rd_cnt   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else if ((cnt == 0)&(rd_cnt))begin
                            //ready    <= 1;
                            data_out <= data[8*r3-1:0]^(choose ? data_fin[8*r3-1:0]:0);
                            choose   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else begin
                            cnt      <= cnt +8;
                            ready    <= 0;
                            data_fin <= data_aft[23][8*r3-1:0];
                        end
                    end
                    else if (ready) begin
                        if (rd_cnt == 1) begin
                            data_out <= data[8*r3-1:0]^(choose ? data_fin[8*r3-1:0]:0);
                            choose   <= 1;
                            rd_cnt   <= rd_cnt + 1;
                        end
                        else if (rd_cnt == 2) begin
                            data_fin <= data_aft[23][8*r3-1:0];
                            out_vld  <= 1;
                            //计算完成后复位
                            ready    <= 0;
                            rd_cnt   <= 0;
                        end
                    end
                end

            //SHA-512

            s4:
                begin
                    if (over) begin
                         if (cnt == r4-8) begin
                            data_1[cnt>>3] <= padder_shake | 64'h8000_0000_0000_0000;
                            rd_cnt         <= 1;
                            ready       <= 1;
                        end
                        else begin
                            data_1[cnt>>3] <= padder_shake;
                            data_1[8]      <= 64'h8000_0000_0000_0000;
                            rd_cnt         <= 1;
                            ready          <= 1;
                            // 将当前拼接位与末尾位之间的所有暂存器全部清零
                            for (m = 0; m < 8; m = m + 1) begin
                                if (m > (cnt>>3)) begin
                                    data_1[m] <= 64'd0;
                                end
                            end
                            //over_cnt       <= 1;
                        end
                    end
                    else if (start) begin
                        data_1[cnt>>3] <= data_in;
                        if (cnt == r4-8) begin
                            cnt      <= 0;
                        end
                        else if ((cnt == 0)&(!rd_cnt))begin
                            rd_cnt   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else if ((cnt == 0)&(rd_cnt))begin
                            //ready    <= 1;
                            data_out <= data[8*r4-1:0]^(choose ? data_fin[8*r4-1:0]:0);
                            choose   <= 1;
                            cnt      <= cnt + 8;
                        end
                        else begin
                            cnt      <= cnt +8;
                            ready    <= 0;
                            data_fin <= data_aft[23][8*r4-1:0];
                        end
                    end
                    else if (ready) begin
                        if (rd_cnt == 1) begin
                            data_out <= data[8*r4-1:0]^(choose ? data_fin[8*r4-1:0]:0);
                            choose   <= 1;
                            rd_cnt   <= rd_cnt + 1;
                        end
                        else if (rd_cnt == 2) begin
                            data_fin <= data_aft[23][8*r4-1:0];
                            out_vld  <= 1;
                            //计算完成后复位
                            ready    <= 0;
                            rd_cnt   <= 0;
                        end
                    end
                end
            endcase
            /*
            if (ready) begin
                for(m = 0; m < 25; m = m + 1) begin:out_block
                    data_out[m*64 +: 64] <= data[m];
                end
            end
            */
    end

end



//轮函数
absorb function_turn(.data_in(data_out), .rc(rc_par[0]), .data_out(data_aft[0]));
generate
    genvar i;
    for (i = 1; i < 24; i = i + 1)begin:function_block
        absorb function_turn_i(.data_in(data_aft[i-1]), .rc(rc_par[i]), .data_out(data_aft[i]));
    end
endgenerate

endmodule
