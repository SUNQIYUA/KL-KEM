`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/09 16:04:03
// Design Name: 
// Module Name: top
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


    // [TOP-20][P2][2026-09-19 复查：配置/接口范围]
    // 当前仅实现 bank 0/1，末地址固定 255，子模块使用固定/默认参数；k 等参数尚不代表完整可配置设计。
    // 输出只有完成标志，尚无 t/u/v、恢复消息读口。本轮按内部算术顶层检查，不把接口未实现当作已完成的 KEM。
    // 修改思路：当前先固定 k=2、q=3329、DATA_WIDTH=12、ADDR_WIDTH=8、byte_WIDTH=8；
    // 后续明确外部 stage 请求/完成握手和结果读出协议，再扩展参数化，不在此处放未定义接口代码。
module top#(
    parameter ADDR_WIDTH = 8,
    parameter byte_WIDTH = 8,
    parameter DATA_WIDTH = 12,
    parameter q = 3329,
    parameter k = 2           //规模
    )(
    input                  clk,
    input                  rst,
    input                  din_vld,
    input [255:0]          data_in_A,     //通用种子
    input [255:0]          data_in_r,     //通用种子
    input [255:0]          m_in,          //明文输入
    input [1:0]            stage,         //模式输入
    output reg             out_vld,
    output reg             finish_keygen,
    output reg             finish_encaps,
    output reg             finish_decaps
    );

reg next_stage;

//标志信号
         reg jud_A;
         reg jud_s;
         reg jud_e;
         reg jud_y;
         reg jud_mult;
         reg jud_plus_1;
         reg jud_plus_2;
         reg jud_plus_3;
         reg jud_mult_2;
         reg jud_plus_4;
         reg jud_sub;
         reg cnt_plus;
         reg [1:0] cnt_A;
         reg [3:0] cnt_n;
         reg cnt_s;
         reg cnt_t; //关于cnt_t信号：牵扯太多不想修改了，规定keygen阶段时用于调控矩阵t，encaps阶段时用于调控矩阵u，
         reg cnt_y;
         reg cnt_u; //用于decaps阶段调控矩阵u
         reg count_t; //encaps阶段作为cnt_t的代替，用于调控矩阵t

//种子输入
    //矩阵A
    reg [255:0]    pho_A;  //锁存输入的矩阵A种子
    reg [255:0]    pho_r;  //锁存输入的其余向量r的种子
    reg [1:0] col_cnt;
    reg [1:0] row_cnt;              //矩阵A中每一个元素的行列坐标
    wire [271:0]  data_A_reg;
    wire [271:0]  data_A_t_reg;
    reg  [63:0]   data_A;
    reg  [63:0]   data_A_t;
    wire [263:0]  data_r_reg;
    wire [1599:0] keccak_all;
    reg [3:0] stage_gen;
    reg [3:0] stage_caucl;
    reg [63:0]   data_r;
    reg  jud_rej; //标志信号，用于判断矩阵A的系数是否生成足够，不足够则拉升，使得keccak处理后的数据再次返回keccak输入，制造数据流
    reg  jud_cbd; //标志信号，用于判断矩阵A的系数是否生成足够，不足够则拉升，使得keccak处理后的数据再次返回keccak输入，制造数据流
    //缓冲输入的A种子与转置A种子，作为数据源供keccak取用
    // [TOP-07][P1][2026-09-23 复查：输出回灌不等于 SHAKE squeeze]
    // eta=3 每多项式需 192 字节，SHAKE256 一块仅 136 字节，必需第二块；A 拒绝采样也需续块。
    // 首块吸收一次种子；需要续块时等待 buffer 可接收后发 squeeze；采满 256 项后结束本多项式。
    // 2026-09-25：buffer 已改为先拼齐 192 字节，拆包定向测试通过；多项式切换仍需清其上下文。
    // 当前新 data_all 端口在 shake_padder 中只有声明、无驱动；即使补驱动，下面 272/264 位线网仍截断状态。
    // 且这些片段仍走消息吸收/填充，不能作为完整 1600 位状态的直接 Keccak-f 续块。
    // 这是跨模块接口修改，此处不给会重新散列消息的局部代码冒充完整修复。
    assign data_A_reg   = {6'd0,row_cnt,6'd0,col_cnt,pho_A};
    assign data_A_t_reg = {6'd0,col_cnt,6'd0,row_cnt,pho_A};
    assign data_r_reg   = {4'd0,cnt_n,pho_r};
    
    //种子输入完成标志，告诉主模块可以开始了
    reg start;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pho_A <= 0;
            pho_r <= 0;
            start <= 0;
        end
        else begin
            start <= 0;
            if (din_vld && !start && (stage_gen == 0) && (stage_caucl == 0)) begin
                pho_A <= data_in_A;
                pho_r <= data_in_r;
                start <= 1;
            end
        end
    end
         //assign cnt_t         = cnt_plus ? 0 : 1;


//keccak模块
    wire [63:0]   keccak_in;
    wire [2:0]    keccak_mod;
    wire [2:0]    keccak_in_vld;
    wire          keccak_over;
    wire          keccak_start;
    
    //wire [1599:0] keccak_all;
    wire   [1599:0] keccak_out;
    wire            keccak_out_vld;
    
    shake_padder keccak(
        .data_in(keccak_in),
        .mod(keccak_mod),
        .din_vld(keccak_in_vld),
        .over(keccak_over),
        .start(keccak_start),
        .clk(clk),
        .rst(rst),
    
        .data_all(_all),
        .data_fin(keccak_out),
        .out_vld(keccak_out_vld));
    
//内部连线声明：NTT 与 RAM 阵列

    wire                  ntt_din_vld;
    wire [DATA_WIDTH-1:0] ntt_ram1_in_1, ntt_ram1_in_2;
    wire [DATA_WIDTH-1:0] ntt_ram3_in_1, ntt_ram3_in_2;
    wire [DATA_WIDTH-1:0] zeta_in;
    wire [ADDR_WIDTH-1:0] zeta_cnt;
    //ram
        // RAM 0 连线
        wire                  ram0_we_a, ram0_we_b;
        wire [ADDR_WIDTH-1:0] ram0_addr_a, ram0_addr_b;
        wire [DATA_WIDTH-1:0] ram0_din_a, ram0_din_b;
        wire [DATA_WIDTH-1:0] ram0_dout_a, ram0_dout_b;
    
        // RAM 1 连线
        wire                  ram1_we_a, ram1_we_b;
        wire [ADDR_WIDTH-1:0] ram1_addr_a, ram1_addr_b;
        wire [DATA_WIDTH-1:0] ram1_din_a, ram1_din_b;
        wire [DATA_WIDTH-1:0] ram1_dout_a, ram1_dout_b;
    
        // RAM 2 连线
        wire                  ram2_we_a, ram2_we_b;
        wire [ADDR_WIDTH-1:0] ram2_addr_a, ram2_addr_b;
        wire [DATA_WIDTH-1:0] ram2_din_a, ram2_din_b;
        wire [DATA_WIDTH-1:0] ram2_dout_a, ram2_dout_b;
    
        // RAM 3 连线
        wire                  ram3_we_a, ram3_we_b;
        wire [ADDR_WIDTH-1:0] ram3_addr_a, ram3_addr_b;
        wire [DATA_WIDTH-1:0] ram3_din_a, ram3_din_b;
        wire [DATA_WIDTH-1:0] ram3_dout_a, ram3_dout_b;
    
        // RAM 4 连线
        wire                  ram4_we_a, ram4_we_b;
        wire [ADDR_WIDTH-1:0] ram4_addr_a, ram4_addr_b;
        wire [DATA_WIDTH-1:0] ram4_din_a, ram4_din_b;
        wire [DATA_WIDTH-1:0] ram4_dout_a, ram4_dout_b;

        //ramA
        wire                  ramA_we_a, ramA_we_b;
        wire [ADDR_WIDTH-1:0] ramA_addr_a, ramA_addr_b;
        wire [DATA_WIDTH-1:0] ramA_din_a, ramA_din_b;
        wire [DATA_WIDTH-1:0] ramA_dout_a, ramA_dout_b;

        //rams
        wire                  rams_we_a   [k-1:0];
        wire                  rams_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] rams_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] rams_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] rams_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] rams_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] rams_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] rams_dout_b [k-1:0];

        //rame
        wire                  rame_we_a, rame_we_b;
        wire [ADDR_WIDTH-1:0] rame_addr_a, rame_addr_b;
        wire [DATA_WIDTH-1:0] rame_din_a, rame_din_b;
        wire [DATA_WIDTH-1:0] rame_dout_a, rame_dout_b;
        
        //ramy
        wire                  ramy_we_a, ramy_we_b;
        wire [ADDR_WIDTH-1:0] ramy_addr_a, ramy_addr_b;
        wire [DATA_WIDTH-1:0] ramy_din_a, ramy_din_b;
        wire [DATA_WIDTH-1:0] ramy_dout_a, ramy_dout_b;

        //ramt
        wire                  ramt_we_a   [k-1:0];
        wire                  ramt_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] ramt_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] ramt_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_dout_b [k-1:0];

        //ramu
        wire                  ramu_we_a   [k-1:0];
        wire                  ramu_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] ramu_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] ramu_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_dout_b [k-1:0];
        
        //ramv
        wire                  ramv_we_a, ramv_we_b;
        wire [ADDR_WIDTH-1:0] ramv_addr_a, ramv_addr_b;
        wire [DATA_WIDTH-1:0] ramv_din_a, ramv_din_b;
        wire [DATA_WIDTH-1:0] ramv_dout_a, ramv_dout_b;


    //NTT

        wire    first_NTT; // 经过keccak处理后的种子再拒绝采样后，直接规定为进入NTT域的多项式A的系数
                           // 因此需要外部信号告诉是否需要先进NTT域
        //keygen部分乘法只有A*s,encaps部分乘法mult1负责At*y,负责计算tt*y的mult2则不涉及这个，不需要跳过进域
        
        assign first_NTT = (stage == keygen) ? 1'b1 : (stage == encaps) ? !jud_mult_2 : 1'b0;
        // NTT 输出监控连线
        wire [ADDR_WIDTH-1:0] ntt_ram1_cnt_1, ntt_ram1_cnt_2;
        wire [ADDR_WIDTH-1:0] ntt_ram3_cnt_1, ntt_ram3_cnt_2;
        //wire [DATA_WIDTH-1:0] ntt_ram1_out_1, ntt_ram1_out_2;
        //wire [DATA_WIDTH-1:0] ntt_ram3_out_1, ntt_ram3_out_2;
        //wire                  ntt_ram1_out_vld, ntt_ram3_out_vld;
        wire                  import_finish; // 连接外部top模块的信号，告诉外部模块可以终止输入了
        wire                  ntt_finish;

        //ram4 ntt模块连线
        wire                  ntt_ram4_we_a, ntt_ram4_we_b;
        wire [ADDR_WIDTH-1:0] ntt_ram4_addr_a, ntt_ram4_addr_b;
        wire [DATA_WIDTH-1:0] ntt_ram4_din_a, ntt_ram4_din_b;
        wire [DATA_WIDTH-1:0] ntt_ram4_dout_a, ntt_ram4_dout_b;
        //ntt ram切换信号
        //wire [1:0] which_ram;
    
//NTT 运算核心引擎
    top_NTT NTT(
        .clk(clk),
        .rst(rst),
        .din_vld(ntt_din_vld),
        
        // 采样器输入接口 (需由顶层FSM分配)
        .ram1_in_1(ntt_ram1_in_1),
        .ram1_in_2(ntt_ram1_in_2),
        .ram3_in_1(ntt_ram3_in_1),
        .ram3_in_2(ntt_ram3_in_2),
        .zeta_in(zeta_in),
        .first_NTT(first_NTT),
        
        // 外部 RAM 0
        .ram0_we_a(ram0_we_a), .ram0_adder_a(ram0_addr_a), .ram0_din_a(ram0_din_a), .ram0_dout_a(ram0_dout_a),
        .ram0_we_b(ram0_we_b), .ram0_adder_b(ram0_addr_b), .ram0_din_b(ram0_din_b), .ram0_dout_b(ram0_dout_b),
        
        // 外部 RAM 1
        .ram1_we_a(ram1_we_a), .ram1_adder_a(ram1_addr_a), .ram1_din_a(ram1_din_a), .ram1_dout_a(ram1_dout_a),
        .ram1_we_b(ram1_we_b), .ram1_adder_b(ram1_addr_b), .ram1_din_b(ram1_din_b), .ram1_dout_b(ram1_dout_b),
        
        // 外部 RAM 2
        .ram2_we_a(ram2_we_a), .ram2_adder_a(ram2_addr_a), .ram2_din_a(ram2_din_a), .ram2_dout_a(ram2_dout_a),
        .ram2_we_b(ram2_we_b), .ram2_adder_b(ram2_addr_b), .ram2_din_b(ram2_din_b), .ram2_dout_b(ram2_dout_b),
        
        // 外部 RAM 3
        .ram3_we_a(ram3_we_a), .ram3_adder_a(ram3_addr_a), .ram3_din_a(ram3_din_a), .ram3_dout_a(ram3_dout_a),
        .ram3_we_b(ram3_we_b), .ram3_adder_b(ram3_addr_b), .ram3_din_b(ram3_din_b), .ram3_dout_b(ram3_dout_b),
        
        // 外部 RAM 4
        .ram4_we_a(ntt_ram4_we_a), .ram4_adder_a(ntt_ram4_addr_a), .ram4_din_a(ram4_din_a), .ram4_dout_a(ram4_dout_a),
        .ram4_we_b(ntt_ram4_we_b), .ram4_adder_b(ntt_ram4_addr_b), .ram4_din_b(ram4_din_b), .ram4_dout_b(ram4_dout_b),

        // 状态监控输出
        .zeta_cnt(zeta_cnt),
        .ram1_cnt_1(ntt_ram1_cnt_1), .ram1_cnt_2(ntt_ram1_cnt_2),
        .ram3_cnt_1(ntt_ram3_cnt_1), .ram3_cnt_2(ntt_ram3_cnt_2),
        //.ram1_out_1(ntt_ram1_out_1), .ram1_out_2(ntt_ram1_out_2),
        //.ram3_out_1(ntt_ram3_out_1), .ram3_out_2(ntt_ram3_out_2),
        //.ram1_out_vld(ntt_ram1_out_vld),
        //.ram3_out_vld(ntt_ram3_out_vld),
        //.which_ram(which_ram),
        .import_finish(import_finish),
        .finsh(ntt_finish)
    );

//中央存储器阵列
    //ram0-ram4用于ntt计算
        ram ram0 (
            .clk(clk),
            .we_a(ram0_we_a), .addr_a(ram0_addr_a), .din_a(ram0_din_a), .dout_a(ram0_dout_a),
            .we_b(ram0_we_b), .addr_b(ram0_addr_b), .din_b(ram0_din_b), .dout_b(ram0_dout_b)
        );
    
        ram ram1 (
            .clk(clk),
            .we_a(ram1_we_a), .addr_a(ram1_addr_a), .din_a(ram1_din_a), .dout_a(ram1_dout_a),
            .we_b(ram1_we_b), .addr_b(ram1_addr_b), .din_b(ram1_din_b), .dout_b(ram1_dout_b)
        );
    
        ram ram2 (
            .clk(clk),
            .we_a(ram2_we_a), .addr_a(ram2_addr_a), .din_a(ram2_din_a), .dout_a(ram2_dout_a),
            .we_b(ram2_we_b), .addr_b(ram2_addr_b), .din_b(ram2_din_b), .dout_b(ram2_dout_b)
        );
    
        ram ram3 (
            .clk(clk),
            .we_a(ram3_we_a), .addr_a(ram3_addr_a), .din_a(ram3_din_a), .dout_a(ram3_dout_a),
            .we_b(ram3_we_b), .addr_b(ram3_addr_b), .din_b(ram3_din_b), .dout_b(ram3_dout_b)
        );
    
        ram ram4 (
            .clk(clk),
            .we_a(ram4_we_a), .addr_a(ram4_addr_a), .din_a(ram4_din_a), .dout_a(ram4_dout_a),
            .we_b(ram4_we_b), .addr_b(ram4_addr_b), .din_b(ram4_din_b), .dout_b(ram4_dout_b)
        );
    //rmA用于存储矩阵A的其中一个元素
    ram ramA (
                .clk(clk),
                .we_a(ramA_we_a), .addr_a(ramA_addr_a), .din_a(ramA_din_a), .dout_a(ramA_dout_a),
                .we_b(ramA_we_b), .addr_b(ramA_addr_b), .din_b(ramA_din_b), .dout_b(ramA_dout_b)
            );
    //rams_0，rams_1…rams_k用于存储向量s
    generate
            genvar i;
            for (i = 0; i < k; i = i + 1)begin:rams_difi_block
                ram rams_i (
                    .clk(clk),
                    .we_a(rams_we_a[i]), .addr_a(rams_addr_a[i]), .din_a(rams_din_a[i]), .dout_a(rams_dout_a[i]),
                    .we_b(rams_we_b[i]), .addr_b(rams_addr_b[i]), .din_b(rams_din_b[i]), .dout_b(rams_dout_b[i])
                );
            end
        endgenerate

    //rame用于存储向量e的一个元素
     ram rame (
                .clk(clk),
                .we_a(rame_we_a), .addr_a(rame_addr_a), .din_a(rame_din_a), .dout_a(rame_dout_a),
                .we_b(rame_we_b), .addr_b(rame_addr_b), .din_b(rame_din_b), .dout_b(rame_dout_b)
            );
    //ramt_0…用于存储最后的计算结果t
        generate
            genvar j;
            for (j = 0; j < k; j = j + 1)begin:ramt_difi_block
                ram ramt_j (
                    .clk(clk),
                    .we_a(ramt_we_a[j]), .addr_a(ramt_addr_a[j]), .din_a(ramt_din_a[j]), .dout_a(ramt_dout_a[j]),
                    .we_b(ramt_we_b[j]), .addr_b(ramt_addr_b[j]), .din_b(ramt_din_b[j]), .dout_b(ramt_dout_b[j])
                );
            end
        endgenerate
    //ramy用于存储向量y的一个元素
     ram ramy (
                .clk(clk),
                .we_a(ramy_we_a), .addr_a(ramy_addr_a), .din_a(ramy_din_a), .dout_a(ramy_dout_a),
                .we_b(ramy_we_b), .addr_b(ramy_addr_b), .din_b(ramy_din_b), .dout_b(ramy_dout_b)
            );
    //ramu用于存储密文向量u的一个元素
     generate
            genvar p;
            for (p = 0; p < k; p = p + 1)begin:ram_block
                ram ramu_p (
                    .clk(clk),
                    .we_a(ramu_we_a[p]), .addr_a(ramu_addr_a[p]), .din_a(ramu_din_a[p]), .dout_a(ramu_dout_a[p]),
                    .we_b(ramu_we_b[p]), .addr_b(ramu_addr_b[p]), .din_b(ramu_din_b[p]), .dout_b(ramu_dout_b[p])
                );
            end
        endgenerate
    //ramy用于存储密文向量v的一个元素
     ram ramv (
                .clk(clk),
                .we_a(ramv_we_a), .addr_a(ramv_addr_a), .din_a(ramv_din_a), .dout_a(ramv_dout_a),
                .we_b(ramv_we_b), .addr_b(ramv_addr_b), .din_b(ramv_din_b), .dout_b(ramv_dout_b)
            );
    //Zeta 旋转因子 ROM (需提供此模块)
        rom zeta_rom(
            .clk(clk),
            .addr(zeta_cnt),
            .dout(zeta_in)
        );

//reject采样器
    wire                  rej_in_vld;
    wire [byte_WIDTH-1:0] rej_in_1;
    wire [byte_WIDTH-1:0] rej_in_2;
    wire [byte_WIDTH-1:0] rej_in_3;
    
    wire [ADDR_WIDTH-1:0] rej_add_1;
    wire [ADDR_WIDTH-1:0] rej_add_2;
    wire                  rej_out_vld_1;
    wire                  rej_out_vld_2;
    wire [DATA_WIDTH-1:0] rej_out_1;
    wire [DATA_WIDTH-1:0] rej_out_2;
    wire                  rej_finish;
    
    reject_sample reject_sample(
        .clk(clk),
        .rst(rst),
        .din_vld(rej_in_vld),
        .data_in_1(rej_in_1),
        .data_in_2(rej_in_2),
        .data_in_3(rej_in_3),
    
        .adder_1(rej_add_1),
        .adder_2(rej_add_2),
        .out_1_vld(rej_out_vld_1),
        .out_2_vld(rej_out_vld_2),
        .data_out_1(rej_out_1),
        .data_out_2(rej_out_2),
        .finish(rej_finish));

//CBD采样器
    //CBD（eta=2）
    wire cbd_in_vld;
    wire [byte_WIDTH-1:0] cbd_in;
    
    wire [ADDR_WIDTH-1:0] cbd_add_1;
    wire [ADDR_WIDTH-1:0] cbd_add_2;
    wire                  cbd_out_vld;
    wire [DATA_WIDTH-1:0] cbd_out_1;
    wire [DATA_WIDTH-1:0] cbd_out_2;
    wire                  cbd_finish;

    CBD_sample CBD_sample(
        .clk(clk),
        .rst(rst),
        .din_vld(cbd_in_vld),
        .data_in(cbd_in),
    
        .adder_1(cbd_add_1),
        .adder_2(cbd_add_2),
        .out_vld(cbd_out_vld),
        .data_out_1(cbd_out_1),
        .data_out_2(cbd_out_2),
        .finish(cbd_finish));
    
    //CBD(eta=3)
    wire cbd_2_in_vld;
    wire [11:0] cbd_2_in;
    wire [ADDR_WIDTH-1:0] cbd_2_add_1;
    wire [ADDR_WIDTH-1:0] cbd_2_add_2;
    wire                  cbd_2_out_vld;
    wire [DATA_WIDTH-1:0] cbd_2_out_1;
    wire [DATA_WIDTH-1:0] cbd_2_out_2;
    wire                  cbd_2_finish;

    CBD_sample_2 CBD_sample_2(
        .clk(clk),
        .rst(rst),
        .din_vld(cbd_2_in_vld),
        .data_in(cbd_2_in),

        .adder_1(cbd_2_add_1),
        .adder_2(cbd_2_add_2),
        .out_vld(cbd_2_out_vld),
        .data_out_1(cbd_2_out_1),
        .data_out_2(cbd_2_out_2),
        .finish(cbd_2_finish));

    // eta1: k=2 时 KeyGen 的 s/e 和 Encrypt 的 y 使用 eta=3；其余参数集使用 eta=2。
    // Encrypt 的 e1/e2 始终直接使用原 cbd_*（eta=2）通路。
    wire cbd_eta1_out_vld;
    wire [ADDR_WIDTH-1:0] cbd_eta1_add_1, cbd_eta1_add_2;
    wire [DATA_WIDTH-1:0] cbd_eta1_out_1, cbd_eta1_out_2;
    wire cbd_eta1_finish;
    wire cbd_task_finish;
    assign cbd_eta1_out_vld = (k == 2) ? cbd_2_out_vld : cbd_out_vld;
    assign cbd_eta1_add_1   = (k == 2) ? cbd_2_add_1   : cbd_add_1;
    assign cbd_eta1_add_2   = (k == 2) ? cbd_2_add_2   : cbd_add_2;
    assign cbd_eta1_out_1   = (k == 2) ? cbd_2_out_1   : cbd_out_1;
    assign cbd_eta1_out_2   = (k == 2) ? cbd_2_out_2   : cbd_out_2;
    assign cbd_eta1_finish  = (k == 2) ? cbd_2_finish  : cbd_finish;

//squeeze buffer
    wire [1599:0] squeze_din;
    wire          squeze_din_vld;
    wire [7:0]    squeze_dout_1;     //一字节
    wire [23:0]   squeze_dout_2;     //三字节
    wire [11:0]   squeze_dout_3;     //12比特
    wire          squeze_dout_1_vld;
    wire          squeze_dout_2_vld;
    wire          squeze_dout_3_vld;
    reg           squeeze_flush;
    wire [2:0]    squeeze_buffer_mode;
    wire          buffer_task_active;

    // [TOP-23] 新任务送一拍mode0+valid清空；mode1数满56组输出后才请求续块。
    // 这里只处理块间节拍与任务边界，正确的Keccak续挤压仍需完成TOP-07。
    assign squeze_din     = keccak_out;
    // 新多项式开始时给buffer送一拍mode=0、valid=1的清空事件。
    assign squeeze_buffer_mode = squeeze_flush ? 3'd0 : keccak_mod;
    assign squeze_din_vld      = squeeze_flush | keccak_out_vld;
    
    squeeze_bufer squeeze_bufer(
        .clk(clk),
        .rst(rst),
        .din(squeze_din),
        .din_vld(squeze_din_vld),
        .keccak_mod(squeeze_buffer_mode),
        .dout_1(squeze_dout_1),
        .dout_2(squeze_dout_2),
        .dout_3(squeze_dout_3),
        .dout_1_vld(squeze_dout_1_vld),
        .dout_2_vld(squeze_dout_2_vld),
        .dout_3_vld(squeze_dout_3_vld));

//逻辑信号
    //三个状态
    parameter keygen = 1;
    parameter encaps = 2;
    parameter decaps = 3;
    //MUX控制逻辑
        // --- Squeeze Buffer 虚拟线网 ---
        //wire [1599:0] squeze_din_kg,     squeze_din_enc,     squeze_din_dec;
        //wire          squeze_din_vld_kg, squeze_din_vld_enc, squeze_din_vld_dec;
        
        // --- Reject Sampler 虚拟线网 ---
         wire          rej_in_vld_kg, rej_in_vld_enc;
         wire [7:0]    rej_in_1_kg,   rej_in_1_enc;   
         wire [7:0]    rej_in_2_kg,   rej_in_2_enc;   
         wire [7:0]    rej_in_3_kg,   rej_in_3_enc;   
        
        // --- CBD Sampler (eta=2)虚拟线网 ---
         wire          cbd_in_vld_kg, cbd_in_vld_enc;
         wire [7:0]    cbd_in_kg,     cbd_in_enc;
        
        // --- CBD Sampler2 (eta=3)虚拟线网 ---
         wire          cbd_2_in_vld_kg, cbd_2_in_vld_enc;
         wire [11:0]   cbd_2_in_kg,     cbd_2_in_enc;
        
        // --- RAM A 虚拟线网 ---
         wire                  ramA_we_a_kg,   ramA_we_a_enc; 
         wire                  ramA_we_b_kg,   ramA_we_b_enc; 
         wire [ADDR_WIDTH-1:0] ramA_addr_a_kg, ramA_addr_a_enc;
         wire [ADDR_WIDTH-1:0] ramA_addr_b_kg, ramA_addr_b_enc;
         wire [DATA_WIDTH-1:0] ramA_din_a_kg,  ramA_din_a_enc;
         wire [DATA_WIDTH-1:0] ramA_din_b_kg,  ramA_din_b_enc;

        // --- RAM S 0 虚拟线网 ---
         wire                  rams_we_a_kg_0;
         wire                  rams_we_b_kg_0;
         wire [ADDR_WIDTH-1:0] rams_addr_a_kg_0, rams_addr_a_dec_0;
         wire [ADDR_WIDTH-1:0] rams_addr_b_kg_0, rams_addr_b_dec_0;
         wire [DATA_WIDTH-1:0] rams_din_a_kg_0;
         wire [DATA_WIDTH-1:0] rams_din_b_kg_0;
        
        // --- RAM S 1 虚拟线网 ---
         wire                  rams_we_a_kg_1;
         wire                  rams_we_b_kg_1;
         wire [ADDR_WIDTH-1:0] rams_addr_a_kg_1, rams_addr_a_dec_1;
         wire [ADDR_WIDTH-1:0] rams_addr_b_kg_1, rams_addr_b_dec_1;
         wire [DATA_WIDTH-1:0] rams_din_a_kg_1;
         wire [DATA_WIDTH-1:0] rams_din_b_kg_1;
        
        // --- RAM E 虚拟线网 ---
         wire                  rame_we_a_kg,   rame_we_a_enc;
         wire                  rame_we_b_kg,   rame_we_b_enc;
         wire [ADDR_WIDTH-1:0] rame_addr_a_kg, rame_addr_a_enc;
         wire [ADDR_WIDTH-1:0] rame_addr_b_kg, rame_addr_b_enc;
         wire [DATA_WIDTH-1:0] rame_din_b_kg,  rame_din_b_enc;
         wire [DATA_WIDTH-1:0] rame_din_a_kg,  rame_din_a_enc;
        
        // --- RAM 4 虚拟线网 ---
         wire                  ram4_we_a_kg,   ram4_we_a_enc, ram4_we_a_dec;
         wire                  ram4_we_b_kg,   ram4_we_b_enc, ram4_we_b_dec;
         wire [ADDR_WIDTH-1:0] ram4_addr_b_kg,  ram4_addr_b_enc, ram4_addr_b_dec;
         wire [ADDR_WIDTH-1:0] ram4_addr_a_kg,  ram4_addr_a_enc, ram4_addr_a_dec;
        
        // --- RAM T 0 虚拟线网 ---
         wire                  ramt_we_a_kg_0,   ramt_we_a_enc_0;
         wire                  ramt_we_b_kg_0;
         wire [ADDR_WIDTH-1:0] ramt_addr_a_kg_0, ramt_addr_a_enc_0;
         wire [ADDR_WIDTH-1:0] ramt_addr_b_kg_0, ramt_addr_b_enc_0;
         wire [DATA_WIDTH-1:0] ramt_din_a_kg_0;
         wire [DATA_WIDTH-1:0] ramt_din_b_kg_0;
        
        // --- RAM T 1 虚拟线网 ---
         wire                  ramt_we_a_kg_1;
         wire                  ramt_we_b_kg_1;
         wire [ADDR_WIDTH-1:0] ramt_addr_a_kg_1, ramt_addr_a_enc_1;
         wire [ADDR_WIDTH-1:0] ramt_addr_b_kg_1, ramt_addr_b_enc_1;
         wire [DATA_WIDTH-1:0] ramt_din_a_kg_1;
         wire [DATA_WIDTH-1:0] ramt_din_b_kg_1;

        // --- NTT 控制接口虚拟线网 ---
         wire                  ntt_din_vld_kg,   ntt_din_vld_enc ,  ntt_din_vld_dec;
         wire [DATA_WIDTH-1:0] ntt_ram1_in_1_kg, ntt_ram1_in_1_enc, ntt_ram1_in_1_dec;
         wire [DATA_WIDTH-1:0] ntt_ram1_in_2_kg, ntt_ram1_in_2_enc, ntt_ram1_in_2_dec;
         wire [DATA_WIDTH-1:0] ntt_ram3_in_1_kg, ntt_ram3_in_1_enc, ntt_ram3_in_1_dec;
         wire [DATA_WIDTH-1:0] ntt_ram3_in_2_kg, ntt_ram3_in_2_enc, ntt_ram3_in_2_dec;

        // --- RAM u 0 虚拟线网 ---
         wire                  ramu_we_a_enc_0;
         wire                  ramu_we_b_enc_0;
         wire [ADDR_WIDTH-1:0] ramu_addr_a_enc_0,ramu_addr_a_dec_0;
         wire [ADDR_WIDTH-1:0] ramu_addr_b_enc_0,ramu_addr_b_dec_0;
         wire [DATA_WIDTH-1:0] ramu_din_a_enc_0;
         wire [DATA_WIDTH-1:0] ramu_din_b_enc_0;
        
        // --- RAM u 1 虚拟线网 ---
         wire                  ramu_we_a_enc_1;
         wire                  ramu_we_b_enc_1;
         wire [ADDR_WIDTH-1:0] ramu_addr_a_enc_1,ramu_addr_a_dec_1;
         wire [ADDR_WIDTH-1:0] ramu_addr_b_enc_1,ramu_addr_b_dec_1;
         wire [DATA_WIDTH-1:0] ramu_din_a_enc_1;
         wire [DATA_WIDTH-1:0] ramu_din_b_enc_1;

        // --- RAM v 虚拟线网 ---
         wire                  ramv_we_a_enc  ,ramv_we_a_dec;
         wire                  ramv_we_b_enc  ,ramv_we_b_dec;
         wire [ADDR_WIDTH-1:0] ramv_addr_a_enc,ramv_addr_a_dec;
         wire [ADDR_WIDTH-1:0] ramv_addr_b_enc,ramv_addr_b_dec;
         wire [DATA_WIDTH-1:0] ramv_din_a_enc;
         wire [DATA_WIDTH-1:0] ramv_din_b_enc;

        // --- OTHERS 虚拟线网 ---
         wire [13:0] data_a_temp_kg , data_a_temp_enc , data_a_temp_dec;
         wire [13:0] data_b_temp_kg , data_b_temp_enc , data_b_temp_dec;

    //经过ntt运算后的结果移至其他ram
     reg [ADDR_WIDTH-1:0] ram4_addr_a_temp;
     reg [ADDR_WIDTH-1:0] ram4_addr_b_temp;
     reg [ADDR_WIDTH-1:0] ramt_addr_a_temp;
     reg [ADDR_WIDTH-1:0] ramt_addr_a_temp_delay[1:0];
     reg [ADDR_WIDTH-1:0] ramt_addr_b_temp;
     reg [ADDR_WIDTH-1:0] rame_addr_a_temp;
     reg [ADDR_WIDTH-1:0] rame_addr_b_temp;
     reg [ADDR_WIDTH-1:0] ramv_addr_a_temp;
     reg [ADDR_WIDTH-1:0] ramv_addr_b_temp;
     reg [ADDR_WIDTH-1:0] ramv_addr_a_temp_delay[1:0];

//状态编码
        
         wire [DATA_WIDTH-1:0] data_a_temp;
         wire [DATA_WIDTH-1:0] data_b_temp;
         reg       move_start;
         reg [2:0] move_stage;
         reg       old_vld;       // 上一拍的读请求：本拍对应结果可写回
         reg       t_first;       // 当前搬运任务是否已初始化地址
         reg [2:0] move_stage_d;  // 上一拍的搬运类型，用于识别新任务
         reg       move_done;     // 最后一项写入后保持完成，防止重复启动
         wire      move_write_vld;
         // 只有当前任务的同步 RAM 读结果有效，才允许写目标 RAM。
         assign move_write_vld = move_start && (move_stage == move_stage_d) &&
                                 t_first && old_vld && !move_done;
         //wire code_state;
    
    //keccak输入判断
    reg [7:0] keccak_op;
    reg       keccak_in_jud;

    reg [2:0] k_mod;
    reg [2:0] k_in_vld;
    reg       k_start;
    reg       k_over;


    assign keccak_in     = (jud_s||jud_e||jud_y) ? (jud_cbd? keccak_all : data_r) : 
                           (keccak_in_jud ? ((stage== keygen)? (jud_rej? keccak_all : data_A) : (jud_rej? keccak_all : data_A_t)) : 0);
    assign keccak_in_vld = keccak_op[2:0];
    assign keccak_mod    = keccak_op[6:4];
    assign keccak_start  = keccak_op[3];
    assign keccak_over   = keccak_op[7];
    
//明文输入
    reg  [255:0] data_m;
    wire [10:0]  data_m_aft_a;
    wire [10:0]  data_m_aft_b;

    //寄存明文数据
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            data_m <= 0;            
        end
        else if (din_vld) begin
            data_m <= m_in;
        end
    end

    assign data_m_aft_a = data_m[ramv_addr_a_temp] ? 1665 : 0;
    assign data_m_aft_b = data_m[ramv_addr_b_temp] ? 1665 : 0;
  
//操作编码逻辑
    //reg [2:0] stage;

    //reg [3:0] stage_gen;
    //reg [3:0] stage_caucl;

    reg gen_ing;    //生成模块被执行标志信号
    reg gen_done;   //生成模块完成信号
    reg caucl_ing;  //计算模块被执行标志信号
    reg caucl_done; //计算模块完成信号
    wire switch;     //硬掩码，当两边均执行完成之后拉升，告诉电路可以切换了状态了
    assign switch = (gen_done||(!gen_ing))&&(caucl_done||(!caucl_ing)); //单任务可以只看一边，并行双任务两边均输出done才拉升

    //parameter stage_reset   = 0;


    //parameter stage_keccak  = 1;
    parameter stage_A       = 1;
    parameter stage_s       = 2;
    parameter stage_y       = 2;
    parameter stage_e       = 3; 

    parameter stage_mult    = 1;   //将矩阵A与向量s相乘
    parameter stage_plus_1  = 2;   //将乘法结果与小向量e相加，结果暂存在ramt中
    parameter stage_plus_2  = 3;   //将暂存在ramt的结果与新的乘法结果相加，得出最终结果
    parameter stage_plus_3  = 4;   //将矩阵加上e2
    parameter stage_mult_2  = 5;   //修改后的补充状态
    parameter stage_plus_4  = 6;   //同上

    parameter stage_sub     = 2;

       
        // --- Squeeze Buffer MUX ---
        //assign squeze_din     = (stage == keygen) ? squeze_din_kg     :
        //                        (stage == encaps) ? squeze_din_enc    : 
        //                        (stage == decaps) ? squeze_din_dec    : 0;
        //
        //assign squeze_din_vld = (stage == keygen) ? squeze_din_vld_kg :
        //                        (stage == encaps) ? squeze_din_vld_enc: 
        //                        (stage == decaps) ? squeze_din_vld_dec: 0;
        

        // --- Reject Sampler MUX ---
        assign rej_in_vld = (stage == keygen) ? rej_in_vld_kg : (stage == encaps) ? rej_in_vld_enc : 0;
        assign rej_in_1   = (stage == keygen) ? rej_in_1_kg   : (stage == encaps) ? rej_in_1_enc   : 0;
        assign rej_in_2   = (stage == keygen) ? rej_in_2_kg   : (stage == encaps) ? rej_in_2_enc   : 0;
        assign rej_in_3   = (stage == keygen) ? rej_in_3_kg   : (stage == encaps) ? rej_in_3_enc   : 0;
        
        // --- CBD Sampler MUX ---
        //eta = 2
        assign cbd_in_vld = (stage == keygen) ? cbd_in_vld_kg : (stage == encaps) ? cbd_in_vld_enc : 0;
        assign cbd_in     = (stage == keygen) ? cbd_in_kg     : (stage == encaps) ? cbd_in_enc     : 0;
        //eta = 3
        assign cbd_2_in_vld = (stage == keygen) ? cbd_2_in_vld_kg : (stage == encaps) ? cbd_2_in_vld_enc : 0;
        assign cbd_2_in     = (stage == keygen) ? cbd_2_in_kg     : (stage == encaps) ? cbd_2_in_enc     : 0;

        // 完成事件只来自当前任务选中的采样器，且与最后一对有效输出同时出现。
        assign cbd_task_finish = ((stage == keygen) && (jud_s || jud_e)) || ((stage == encaps) && jud_y) ? (cbd_eta1_out_vld && cbd_eta1_finish)
                               : (((stage == encaps) && jud_e) ? (cbd_out_vld && cbd_finish) : 1'b0);

        // --- RAM A MUX ---
        assign ramA_we_a   = (stage == keygen) ? ramA_we_a_kg   : (stage == encaps) ? ramA_we_a_enc   : 0;
        assign ramA_we_b   = (stage == keygen) ? ramA_we_b_kg   : (stage == encaps) ? ramA_we_b_enc   : 0;
        assign ramA_addr_a = (stage == keygen) ? ramA_addr_a_kg : (stage == encaps) ? ramA_addr_a_enc : 0;
        assign ramA_addr_b = (stage == keygen) ? ramA_addr_b_kg : (stage == encaps) ? ramA_addr_b_enc : 0;
        assign ramA_din_a  = (stage == keygen) ? ramA_din_a_kg  : (stage == encaps) ? ramA_din_a_enc  : 0;
        assign ramA_din_b  = (stage == keygen) ? ramA_din_b_kg  : (stage == encaps) ? ramA_din_b_enc  : 0;
        
        // --- RAM S 0 MUX ---
        assign rams_we_a[0]   = (stage == keygen) ? rams_we_a_kg_0   : 0;
        assign rams_we_b[0]   = (stage == keygen) ? rams_we_b_kg_0   : 0;
        assign rams_addr_a[0] = (stage == keygen) ? rams_addr_a_kg_0 : (stage == decaps) ? rams_addr_a_dec_0 : 0;
        assign rams_addr_b[0] = (stage == keygen) ? rams_addr_b_kg_0 : (stage == decaps) ? rams_addr_b_dec_0 : 0;
        assign rams_din_a[0]  = (stage == keygen) ? rams_din_a_kg_0  : 0;
        assign rams_din_b[0]  = (stage == keygen) ? rams_din_b_kg_0  : 0;
        
        // --- RAM S 1 MUX ---
        assign rams_we_a[1]   = (stage == keygen) ? rams_we_a_kg_1   : 0;
        assign rams_we_b[1]   = (stage == keygen) ? rams_we_b_kg_1   : 0;
        assign rams_addr_a[1] = (stage == keygen) ? rams_addr_a_kg_1 : (stage == decaps) ? rams_addr_a_dec_1 : 0;
        assign rams_addr_b[1] = (stage == keygen) ? rams_addr_b_kg_1 : (stage == decaps) ? rams_addr_b_dec_1 : 0;
        assign rams_din_a[1]  = (stage == keygen) ? rams_din_a_kg_1  : 0;
        assign rams_din_b[1]  = (stage == keygen) ? rams_din_b_kg_1  : 0;
        
        // --- RAM E MUX ---
        assign rame_we_a   = (stage == keygen) ? rame_we_a_kg   : (stage == encaps) ? rame_we_a_enc   : 0;
        assign rame_we_b   = (stage == keygen) ? rame_we_b_kg   : (stage == encaps) ? rame_we_b_enc   : 0;
        assign rame_addr_a = (stage == keygen) ? rame_addr_a_kg : (stage == encaps) ? rame_addr_a_enc : 0;
        assign rame_addr_b = (stage == keygen) ? rame_addr_b_kg : (stage == encaps) ? rame_addr_b_enc : 0;
        assign rame_din_a  = (stage == keygen) ? rame_din_a_kg  : (stage == encaps) ? rame_din_a_enc  : 0;
        assign rame_din_b  = (stage == keygen) ? rame_din_b_kg  : (stage == encaps) ? rame_din_b_enc  : 0;
        
        // --- RAM 4 MUX ---
        assign ram4_we_a = (stage == keygen) ? ram4_we_a_kg : (stage == encaps) ? ram4_we_a_enc : (stage == decaps) ? ram4_we_a_dec : 0;
        assign ram4_we_b = (stage == keygen) ? ram4_we_b_kg : (stage == encaps) ? ram4_we_b_enc : (stage == decaps) ? ram4_we_b_dec : 0;
        assign ram4_addr_a = (stage == keygen) ? ram4_addr_a_kg : (stage == encaps) ? ram4_addr_a_enc : (stage == decaps) ? ram4_addr_a_dec : 0;
        assign ram4_addr_b = (stage == keygen) ? ram4_addr_b_kg : (stage == encaps) ? ram4_addr_b_enc : (stage == decaps) ? ram4_addr_b_dec : 0;
        
        // --- RAM T 0 MUX ---
        assign ramt_we_a[0]   = (stage == keygen) ? ramt_we_a_kg_0   : (stage == encaps) ? ramt_we_a_enc_0   : 0;
        assign ramt_we_b[0]   = (stage == keygen) ? ramt_we_b_kg_0   : 0;
        assign ramt_addr_a[0] = (stage == keygen) ? ramt_addr_a_kg_0 : (stage == encaps) ? ramt_addr_a_enc_0 : 0;
        assign ramt_addr_b[0] = (stage == keygen) ? ramt_addr_b_kg_0 : (stage == encaps) ? ramt_addr_b_enc_0 : 0;
        assign ramt_din_a[0]  = (stage == keygen) ? ramt_din_a_kg_0  : 0;
        assign ramt_din_b[0]  = (stage == keygen) ? ramt_din_b_kg_0  : 0;
        
        // --- RAM T 1 MUX ---
        assign ramt_we_a[1]   = (stage == keygen) ? ramt_we_a_kg_1   : 0;
        assign ramt_we_b[1]   = (stage == keygen) ? ramt_we_b_kg_1   : 0;
        assign ramt_addr_a[1] = (stage == keygen) ? ramt_addr_a_kg_1 : (stage == encaps) ? ramt_addr_a_enc_1 : 0;
        assign ramt_addr_b[1] = (stage == keygen) ? ramt_addr_b_kg_1 : (stage == encaps) ? ramt_addr_b_enc_1 : 0;
        assign ramt_din_a[1]  = (stage == keygen) ? ramt_din_a_kg_1  : 0;
        assign ramt_din_b[1]  = (stage == keygen) ? ramt_din_b_kg_1  : 0;

        // --- NTT Core MUX ---
        assign ntt_din_vld   = (stage == keygen) ? ntt_din_vld_kg   : (stage == encaps) ? ntt_din_vld_enc   : (stage == decaps) ? ntt_din_vld_dec   : 0;
        assign ntt_ram1_in_1 = (stage == keygen) ? ntt_ram1_in_1_kg : (stage == encaps) ? ntt_ram1_in_1_enc : (stage == decaps) ? ntt_ram1_in_1_dec : 0;
        assign ntt_ram1_in_2 = (stage == keygen) ? ntt_ram1_in_2_kg : (stage == encaps) ? ntt_ram1_in_2_enc : (stage == decaps) ? ntt_ram1_in_2_dec : 0;
        assign ntt_ram3_in_1 = (stage == keygen) ? ntt_ram3_in_1_kg : (stage == encaps) ? ntt_ram3_in_1_enc : (stage == decaps) ? ntt_ram3_in_1_dec : 0;
        assign ntt_ram3_in_2 = (stage == keygen) ? ntt_ram3_in_2_kg : (stage == encaps) ? ntt_ram3_in_2_enc : (stage == decaps) ? ntt_ram3_in_2_dec : 0;

        //  --- RAM u 0 MUX ---
        assign ramu_we_a[0]   = (stage == encaps)? ramu_we_a_enc_0 : 0;
        assign ramu_we_b[0]   = (stage == encaps)? ramu_we_b_enc_0 : 0;
        assign ramu_addr_a[0] = (stage == encaps)? ramu_addr_a_enc_0 :(stage == decaps)? ramu_addr_a_dec_0 : 0;
        assign ramu_addr_b[0] = (stage == encaps)? ramu_addr_b_enc_0 :(stage == decaps)? ramu_addr_b_dec_0 : 0;
        assign ramu_din_a[0]  = (stage == encaps)? ramu_din_a_enc_0 : 0;
        assign ramu_din_b[0]  = (stage == encaps)? ramu_din_b_enc_0 : 0;

        //  --- RAM u 1 MUX ---
        assign ramu_we_a[1]   = (stage == encaps)? ramu_we_a_enc_1 : 0; 
        assign ramu_we_b[1]   = (stage == encaps)? ramu_we_b_enc_1 : 0;
        assign ramu_addr_a[1] = (stage == encaps)? ramu_addr_a_enc_1 :(stage == decaps)? ramu_addr_a_dec_1 : 0;
        assign ramu_addr_b[1] = (stage == encaps)? ramu_addr_b_enc_1 :(stage == decaps)? ramu_addr_b_dec_1 : 0;
        assign ramu_din_a[1]  = (stage == encaps)? ramu_din_a_enc_1 : 0;
        assign ramu_din_b[1]  = (stage == encaps)? ramu_din_b_enc_1 : 0;

        //  --- RAM v MUX ---
        assign ramv_we_a   = (stage == encaps)? ramv_we_a_enc : 0; 
        assign ramv_we_b   = (stage == encaps)? ramv_we_b_enc : (stage == decaps) ? ramv_we_b_dec : 0;
        assign ramv_addr_a = (stage == encaps)? ramv_addr_a_enc : (stage == decaps)? ramv_addr_a_dec : 0;
        assign ramv_addr_b = (stage == encaps)? ramv_addr_b_enc : (stage == decaps)? ramv_addr_b_dec : 0;
        assign ramv_din_a  = (stage == encaps)? ramv_din_a_enc : 0;
        assign ramv_din_b  = (stage == encaps)? ramv_din_b_enc : (stage == decaps) ? data_b_temp : 0;

        //  --- OTHERS MUX ---
        assign data_a_temp = (stage == keygen) ? ((data_a_temp_kg>=3329)? (data_a_temp_kg-3329) : data_a_temp_kg)   
        : (stage == encaps) ? ((data_a_temp_enc>=3329)? (data_a_temp_enc-3329) : data_a_temp_enc)   
        : (stage == decaps) ? ((data_a_temp_dec>=3329)? (data_a_temp_dec-3329) : data_a_temp_dec)   : 0;
        assign data_b_temp = (stage == keygen) ? ((data_b_temp_kg>=3329)? (data_b_temp_kg-3329) : data_b_temp_kg)   
        : (stage == encaps) ? ((data_b_temp_enc>=3329)? (data_b_temp_enc-3329) : data_b_temp_enc)   
        : (stage == decaps) ? ((data_b_temp_dec>=3329)? (data_b_temp_dec-3329) : data_b_temp_dec)   : 0;

    //keygen
        //种子输入keccak,调用shake-128处理种子
        //处理后种子输入buffer，传入rej_sample生成矩阵A0_0,矩阵A0_0传入ramA
            //assign squeze_din_kg     = (jud_mult||jud_plus_1)? 0 : keccak_out;
            //assign squeze_din_vld_kg = (jud_mult||jud_plus_1)? 0 : keccak_out_vld;
            assign rej_in_vld_kg     = jud_A && buffer_task_active && squeze_dout_2_vld && !rej_finish; //一次输入三字节
            assign rej_in_1_kg       = jud_A? squeze_dout_2[7:0] : 0;
            assign rej_in_2_kg       = jud_A? squeze_dout_2[15:8] : 0;
            assign rej_in_3_kg       = jud_A? squeze_dout_2[23:16] : 0;
            assign ramA_we_a_kg      = jud_A? rej_out_vld_1 : 0; 
            assign ramA_we_b_kg      = jud_A? rej_out_vld_2 : 0;
            assign ramA_addr_a_kg    = jud_A? rej_add_1 : (jud_mult ? ntt_ram1_cnt_1 : 0);
            assign ramA_addr_b_kg    = jud_A? rej_add_2 : (jud_mult ? ntt_ram1_cnt_2 : 0);
            assign ramA_din_a_kg     = jud_A? rej_out_1 : 0;
            assign ramA_din_b_kg     = jud_A? rej_out_2 : 0;
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量s0,向量s0传入rams
            assign cbd_in_vld_kg        = ((k != 2) && (jud_s || jud_e) && buffer_task_active) ? squeze_dout_1_vld : 1'b0;
            assign cbd_in_kg            = ((k != 2) && (jud_s || jud_e)) ? squeze_dout_1 : 8'd0;
            assign cbd_2_in_vld_kg      = ((k == 2) && (jud_s || jud_e) && buffer_task_active) ? squeze_dout_3_vld : 1'b0;
            assign cbd_2_in_kg          = ((k == 2) && (jud_s || jud_e)) ? squeze_dout_3 : 12'd0;
            assign rams_we_a_kg_0       = cnt_s? 0 : (jud_s ? cbd_eta1_out_vld : 1'b0); 
            assign rams_we_b_kg_0       = cnt_s? 0 : (jud_s ? cbd_eta1_out_vld : 1'b0);
            assign rams_addr_a_kg_0     = cnt_s? 0 : (jud_s ? cbd_eta1_add_1 : (jud_mult ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}}));
            assign rams_addr_b_kg_0     = cnt_s? 0 : (jud_s ? cbd_eta1_add_2 : (jud_mult ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}}));
            assign rams_din_a_kg_0      = cnt_s? 0 : (jud_s ? cbd_eta1_out_1 : (jud_mult ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}}));
            assign rams_din_b_kg_0      = cnt_s? 0 : (jud_s ? cbd_eta1_out_2 : (jud_mult ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}}));
            assign rams_we_a_kg_1       = cnt_s? (jud_s ? cbd_eta1_out_vld : 1'b0) : 0; 
            assign rams_we_b_kg_1       = cnt_s? (jud_s ? cbd_eta1_out_vld : 1'b0) : 0;
            assign rams_addr_a_kg_1     = cnt_s? (jud_s ? cbd_eta1_add_1 : (jud_mult ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}})) : 0;
            assign rams_addr_b_kg_1     = cnt_s? (jud_s ? cbd_eta1_add_2 : (jud_mult ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}})) : 0;
            assign rams_din_a_kg_1      = cnt_s? (jud_s ? cbd_eta1_out_1 : (jud_mult ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}})) : 0;
            assign rams_din_b_kg_1      = cnt_s? (jud_s ? cbd_eta1_out_2 : (jud_mult ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}})) : 0;
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量e0,向量e0传入rame
            assign rame_we_a_kg         = jud_e ? cbd_eta1_out_vld : 0; 
            assign rame_we_b_kg         = jud_e ? cbd_eta1_out_vld : 0;
            assign rame_addr_a_kg       = jud_e ? cbd_eta1_add_1 : (jud_plus_1 ? rame_addr_a_temp : 0);
            assign rame_addr_b_kg       = jud_e ? cbd_eta1_add_2 : (jud_plus_1 ? rame_addr_b_temp : 0);
            assign rame_din_a_kg        = jud_e ? cbd_eta1_out_1 : 0;
            assign rame_din_b_kg        = jud_e ? cbd_eta1_out_2 : 0;
        //将矩阵A与s相乘
            assign ntt_din_vld_kg    = jud_mult && !import_finish && !caucl_done;
            //assign ramA_we_a      = 0;
            //assign ramA_we_b      = 0;
            assign ntt_ram1_in_1_kg  = ramA_dout_a;
            assign ntt_ram1_in_2_kg  = ramA_dout_b;
            //assign ramA_addr_a_kg    = ntt_ram1_cnt_1;
            //assign ramA_addr_b_kg    = ntt_ram1_cnt_2;
            //assign rams_we_a   = 0;
            //assign rams_we_b   = 0;
            assign ntt_ram3_in_1_kg  = rams_dout_a[cnt_s];
            assign ntt_ram3_in_2_kg  = rams_dout_b[cnt_s];
            
        //将计算完成的乘积加上e，暂存进ramt里(并非最终结果)
            assign ram4_we_a_kg = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_a;
            assign ram4_we_b_kg = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_b;
            // [TOP-13] 只在同步 RAM 的上一拍读请求已有返回结果时写 t。
            assign ramt_we_a_kg_0 = jud_plus_1 && !cnt_t && move_write_vld;
            assign ramt_we_b_kg_0 = (jud_plus_1 || jud_plus_2) && !cnt_t && move_write_vld;
            assign ramt_we_a_kg_1 = jud_plus_1 && cnt_t && move_write_vld;
            assign ramt_we_b_kg_1 = (jud_plus_1 || jud_plus_2) && cnt_t && move_write_vld;
            //assign rame_we_a = 0;
            //assign rame_we_b = 0;
    
            assign ramt_din_a_kg_0 = (jud_plus_1 ? (cnt_t ? 0 : data_a_temp) : 0);
            assign ramt_din_b_kg_0 = (jud_plus_1||jud_plus_2) ? (cnt_t? 0 : data_b_temp) : 0;
            assign ramt_din_a_kg_1 = (jud_plus_1 ? (cnt_t ? data_a_temp : 0) : 0);
            assign ramt_din_b_kg_1 = (jud_plus_1||jud_plus_2) ? (cnt_t? data_b_temp : 0) : 0;

                    
            assign data_a_temp_kg = ram4_dout_a + rame_dout_a;

            assign data_b_temp_kg = jud_plus_2? (ram4_dout_a+ramt_dout_a[cnt_t]) : (ram4_dout_b + rame_dout_b);
            assign ram4_addr_a_kg    = (jud_plus_1||jud_plus_2) ? ram4_addr_a_temp : ntt_ram4_addr_a;
            assign ram4_addr_b_kg    = jud_plus_1 ? ram4_addr_b_temp : ntt_ram4_addr_b;
    
            assign ramt_addr_a_kg_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_a_temp) : 0;
            assign ramt_addr_b_kg_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_b_temp) : 0;
            assign ramt_addr_a_kg_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_a_temp : 0) : 0;
            assign ramt_addr_b_kg_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_b_temp : 0) : 0;
            //assign rame_addr_a = rame_addr_a_temp;
            //assign rame_addr_b = rame_addr_b_temp;
        /*    
        //将在ramt_0中暂存的数据与新相乘的结果相加，得出最后的结果
            //assign ram4_we_a = 0;
            //assign ram4_we_b = 0;
            //assign ramt_we_a[1] = 0;
            //assign ramt_we_b[1] = 1;
            //assign ramt_din_b[1] = data_b_temp;
            //assign data_a_temp = ram4_dout_a + rame_dout_a;
            //assign data_b_temp = ram4_dout_b + ramt_dout_a[1];
            assign ram4_addr_a[0] = ram4_addr_a_temp;
            assign ramt_addr_a[1] = ramt_addr_a_temp;
            assign ramt_addr_b[1] = ramt_addr_b_temp;
        */
    //encaps
        //种子输入keccak,调用shake-128处理种子
        //处理后种子输入buffer，传入rej_sample生成矩阵A_T_0_0,矩阵A_T_0_0传入ramA
            //assign squeze_din_enc     = (jud_mult||jud_plus_1)? 0 : keccak_out;
            //assign squeze_din_vld_enc = (jud_mult||jud_plus_1)? 0 : keccak_out_vld;
            assign rej_in_vld_enc     = jud_A && buffer_task_active && squeze_dout_2_vld && !rej_finish; //一次输入三字节
            assign rej_in_1_enc       = jud_A? squeze_dout_2[7:0] : 0;
            assign rej_in_2_enc       = jud_A? squeze_dout_2[15:8] : 0;
            assign rej_in_3_enc       = jud_A? squeze_dout_2[23:16] : 0;
            assign ramA_we_a_enc      = jud_A? rej_out_vld_1 : 0; 
            assign ramA_we_b_enc      = jud_A? rej_out_vld_2 : 0;
            assign ramA_addr_a_enc    = jud_A? rej_add_1 : (jud_mult ? ntt_ram1_cnt_1 : 0);
            assign ramA_addr_b_enc    = jud_A? rej_add_2 : (jud_mult ? ntt_ram1_cnt_2 : 0);
            assign ramA_din_a_enc     = jud_A? rej_out_1 : 0;
            assign ramA_din_b_enc     = jud_A? rej_out_2 : 0;
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量y,向量y传入ramy
            assign cbd_in_vld_enc        = (jud_e || ((k != 2) && jud_y)) && buffer_task_active ? squeze_dout_1_vld : 1'b0;
            assign cbd_in_enc            = (jud_e || ((k != 2) && jud_y)) ? squeze_dout_1 : 8'd0;
            assign cbd_2_in_vld_enc      = ((k == 2) && jud_y && buffer_task_active) ? squeze_dout_3_vld : 1'b0;
            assign cbd_2_in_enc          = ((k == 2) && jud_y) ? squeze_dout_3 : 12'd0;
            assign ramy_we_a             = (jud_y ? cbd_eta1_out_vld : 1'b0); 
            assign ramy_we_b             = (jud_y ? cbd_eta1_out_vld : 1'b0);
            assign ramy_addr_a           = (jud_y ? cbd_eta1_add_1 : ((jud_mult || jud_mult_2) ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}}));
            assign ramy_addr_b           = (jud_y ? cbd_eta1_add_2 : ((jud_mult || jud_mult_2) ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}}));
            assign ramy_din_a            = (jud_y ? cbd_eta1_out_1 : ((jud_mult||jud_mult_2) ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}}));
            assign ramy_din_b            = (jud_y ? cbd_eta1_out_2 : ((jud_mult||jud_mult_2) ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}}));
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量e0,向量e0传入rame
            assign rame_we_a_enc         = jud_e ? cbd_out_vld : 0; 
            assign rame_we_b_enc         = jud_e ? cbd_out_vld : 0;
            assign rame_addr_a_enc       = jud_e ? cbd_add_1 : ((jud_plus_1||jud_plus_3) ? rame_addr_a_temp : 0);
            assign rame_addr_b_enc       = jud_e ? cbd_add_2 : ((jud_plus_1||jud_plus_3) ? rame_addr_b_temp : 0);
            assign rame_din_a_enc        = jud_e ? cbd_out_1 : 0;
            assign rame_din_b_enc        = jud_e ? cbd_out_2 : 0;
        //将矩阵A与y相乘
            assign ntt_din_vld_enc    =  (jud_mult || jud_mult_2) && !import_finish && ! caucl_done;
            //assign ramA_we_a      = 0;
            //assign ramA_we_b      = 0;
            assign ntt_ram1_in_1_enc  = jud_mult_2? ramt_dout_a[count_t]  : (jud_mult ? ramA_dout_a : 0);
            assign ntt_ram1_in_2_enc  = jud_mult_2? ramt_dout_b[count_t]  : (jud_mult ? ramA_dout_b : 0);
            //assign ramA_addr_a_enc    = jud_mult ? ntt_ram1_cnt_1 : 0;
            //assign ramA_addr_b_enc    = jud_mult ? ntt_ram1_cnt_2 : 0;
            //assign rams_we_a   = 0;
            //assign rams_we_b   = 0;
            assign ntt_ram3_in_1_enc  = ramy_dout_a;
            assign ntt_ram3_in_2_enc  = ramy_dout_b;
            
        //将计算完成的乘积加上e，暂存进ramt里(并非最终结果)
            assign ram4_we_a_enc = (jud_plus_1||jud_plus_2||jud_plus_3||jud_plus_4) ? 0 : ntt_ram4_we_a;
            assign ram4_we_b_enc = (jud_plus_1||jud_plus_2||jud_plus_3||jud_plus_4) ? 0 : ntt_ram4_we_b;
            // [TOP-13] u 的写使能与实际返回结果对齐。
            assign ramu_we_a_enc_0 = jud_plus_1 && !cnt_t && move_write_vld;
            assign ramu_we_b_enc_0 = (jud_plus_1 || jud_plus_2) && !cnt_t && move_write_vld;
            assign ramu_we_a_enc_1 = jud_plus_1 && cnt_t && move_write_vld;
            assign ramu_we_b_enc_1 = (jud_plus_1 || jud_plus_2) && cnt_t && move_write_vld;
            //assign rame_we_a = 0;
            //assign rame_we_b = 0;
    
            assign ramu_din_a_enc_0 = (jud_plus_1 ? (cnt_t ? 0 : data_a_temp) : 0);
            assign ramu_din_b_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t? 0 : data_b_temp) : (jud_plus_3? (cnt_t? 0 : data_b_temp) : 0);
            assign ramu_din_a_enc_1 = (jud_plus_1 ? (cnt_t ? data_a_temp : 0) : 0);
            assign ramu_din_b_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t? data_b_temp : 0) : (jud_plus_3? (cnt_t? data_b_temp : 0) : 0);

                    
            assign data_a_temp_enc = jud_plus_4 ? (ram4_dout_a + data_m_aft_a) : (ram4_dout_a + rame_dout_a);

            assign data_b_temp_enc = jud_plus_4 ? (ram4_dout_b + data_m_aft_b) : (jud_plus_2? (ram4_dout_a + ramu_dout_a[cnt_t]) : (ram4_dout_b + rame_dout_b));
            assign ram4_addr_a_enc = (jud_plus_1 || jud_plus_2 || jud_plus_3 || jud_plus_4) ? ram4_addr_a_temp : ntt_ram4_addr_a;
            assign ram4_addr_b_enc = (jud_plus_1 || jud_plus_4) ? ram4_addr_b_temp : ntt_ram4_addr_b;

    
            assign ramu_addr_a_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_a_temp) : 0;
            assign ramu_addr_b_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_b_temp) : 0;
            assign ramu_addr_a_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_a_temp : 0) : 0;
            assign ramu_addr_b_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_b_temp : 0) : 0;

        //当执行t*y后，将数据+[q/2]m后，存入ramv中
            //assign ram4_we_a_enc = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_a;
            //assign ram4_we_b_enc = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_b;
            assign ramt_we_a_enc_0 = 0;
            assign ramt_we_a_enc_0 = 0;
            assign ramt_addr_a_enc_0 = (jud_mult_2 && !count_t)? ntt_ram1_cnt_1 : 0;
            assign ramt_addr_b_enc_0 = (jud_mult_2 && !count_t)? ntt_ram1_cnt_2 : 0;
            assign ramt_addr_a_enc_1 = (jud_mult_2 && count_t) ? ntt_ram1_cnt_1 : 0;
            assign ramt_addr_b_enc_1 = (jud_mult_2 && count_t) ? ntt_ram1_cnt_2 : 0;


            //增加中间变量计算 v+乘积+e2，并且模q
            wire [13:0] v_sum3 = {2'b0,ramv_dout_a} + {2'b0,ram4_dout_a} + {2'b0,rame_dout_a};
            wire [13:0] v_red3 = (v_sum3 >= 2*q) ? v_sum3 - 2*q :
                                (v_sum3 >= q) ? v_sum3 - q : v_sum3;
            // [TOP-13] 仅在 plus3/plus4 的结果有效时写 v。
            assign ramv_we_a_enc   = jud_plus_4 && move_write_vld;
            assign ramv_we_b_enc   = (jud_plus_4 || jud_plus_3) && move_write_vld;
            assign ramv_addr_a_enc = (jud_plus_4 || jud_plus_3) ? ramv_addr_a_temp : {ADDR_WIDTH{1'b0}};
            assign ramv_addr_b_enc = (jud_plus_4 || jud_plus_3) ? ramv_addr_b_temp : {ADDR_WIDTH{1'b0}};
            assign ramv_din_a_enc  = jud_plus_4 ? data_a_temp : 0;
            assign ramv_din_b_enc  = jud_plus_4 ? data_b_temp : (jud_plus_3 ? v_red3[DATA_WIDTH-1:0]  : 0);
    //decaps
        //矩阵v与t相乘



            assign ntt_din_vld_dec    =  jud_mult && !import_finish && !caucl_done;
            //assign ramA_we_a      = 0;
            //assign ramA_we_b      = 0;
            assign ntt_ram1_in_1_dec  = jud_mult ? rams_dout_a[cnt_s] : 0;
            assign ntt_ram1_in_2_dec  = jud_mult ? rams_dout_b[cnt_s] : 0;
            assign rams_addr_a_dec_0  = (jud_mult&& !cnt_s) ? ntt_ram1_cnt_1 : 0;
            assign rams_addr_b_dec_0  = (jud_mult&& !cnt_s) ? ntt_ram1_cnt_2 : 0;
            assign rams_addr_a_dec_1  = (jud_mult&& cnt_s)  ? ntt_ram1_cnt_1 : 0;
            assign rams_addr_b_dec_1  = (jud_mult&& cnt_s)  ? ntt_ram1_cnt_2 : 0;
            //assign rams_we_a   = 0;
            //assign rams_we_b   = 0;
            assign ntt_ram3_in_1_dec  = jud_mult ? ramu_dout_a[cnt_u] : 0;
            assign ntt_ram3_in_2_dec  = jud_mult ? ramu_dout_b[cnt_u] : 0;
            assign ramu_addr_a_dec_0  = (jud_mult&& !cnt_u) ? ntt_ram3_cnt_1 : 0;
            assign ramu_addr_b_dec_0  = (jud_mult&& !cnt_u) ? ntt_ram3_cnt_2 : 0;
            assign ramu_addr_a_dec_1  = (jud_mult&& cnt_u)  ? ntt_ram3_cnt_1 : 0;
            assign ramu_addr_b_dec_1  = (jud_mult&& cnt_u)  ? ntt_ram3_cnt_2 : 0;
    //v减去s与u之积
    //调整了减法逻辑，改为单端口读出，减去乘积之后，再写入原地址
            assign data_b_temp_dec = (ramv_dout_a >= ram4_dout_a)? (ramv_dout_a - ram4_dout_a) : (ramv_dout_a - ram4_dout_a + q);

            assign ramv_we_a_dec = 0;
            // [TOP-13] 解封装写回也受搬运边界约束，避免切换状态时残留写入。
            assign ramv_we_b_dec = jud_sub && move_write_vld;
            assign ramv_addr_a_dec = ramv_addr_a_temp;
            assign ramv_addr_b_dec = ramv_addr_b_temp;


            assign ram4_we_a_dec   = jud_sub ? 1'b0 : ntt_ram4_we_a;
            assign ram4_we_b_dec   = jud_sub ? 1'b0 : ntt_ram4_we_b;
            assign ram4_addr_b_dec = jud_sub ? {ADDR_WIDTH{1'b0}} : ntt_ram4_addr_b;
            //assign ram4_we_b_dec   = jud_sub ? 1'b0 : ntt_ram4_we_b;
            assign ram4_addr_a_dec = jud_sub ? ram4_addr_a_temp : ntt_ram4_addr_a;
            //assign ram4_addr_b_dec = jud_sub ? ram4_addr_b_temp : ntt_ram4_addr_b;
            /*
            //借用rame暂存结果
            assign rame_we_a_dec   = jud_sub ? 1 : 0;
            assign rame_we_b_dec   = jud_sub ? 1 : 0;
            assign rame_addr_a_dec = rame_addr_a_temp;
            assign rame_addr_b_dec = rame_addr_b_temp;
            assign rame_din_a_dec  = data_a_temp;
            assign rame_din_b_dec  = data_b_temp;
            */

//向量生成操作
    //keccak调控状态机
        reg  [1:0] stage_k; //用来调控负责控制keccak_op信号的状态机
        reg  [1:0] keccak_cnt; //用于调控内层状态机
        reg  [2:0] cnt;        //判断矩阵A的种子输入进行到第几段
        reg  [1:0] trans_keccak; //用来将调度信号的调度结果传给stage_keccak信号
        reg       keccak_done;   //keccak计算完成标志信号
        parameter keccak_IDLE     = 0;
        parameter keccak_A        = 1;  //生成矩阵A状态
        //内部状态由reset=0开始，因为闲置情况应由外部状态机控制，内部状态机只负责运算
        parameter stage_reset     = 0;  //两次keccak处理之间要清空内部数据
        parameter stage_first     = 1;  //keccak输入时，先告诉keccak数据特征
        parameter stage_hold      = 2;  //数据计算时所需要维持的状态
        parameter keccak_vector   = 2;  //生成向量状态

        reg [5:0] squeeze128_word_count;
        reg       squeeze128_block_drained;

        //buffer拆分keccak输出数据的时间远大于keccak处理数据的时间，为了防止数据覆盖，加入标志信号
        // 清空期间及新任务入口不接收上一多项式残留的buffer输出。
        assign buffer_task_active = (stage_k != keccak_IDLE) &&
                                    (keccak_cnt != stage_reset) && !squeeze_flush;

        // mode=1每块输出56组；最后一组被下游看到后才请求续块。
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                squeeze128_word_count    <= 6'd0;
                squeeze128_block_drained <= 1'b0;
            end else begin
                squeeze128_block_drained <= 1'b0;
                if (squeeze_flush) begin
                    squeeze128_word_count <= 6'd0;
                end else if ((stage_k == keccak_A) && squeze_dout_2_vld) begin
                    if (squeeze128_word_count == 6'd55) begin
                        squeeze128_word_count    <= 6'd0;
                        squeeze128_block_drained <= 1'b1;
                    end else begin
                        squeeze128_word_count <= squeeze128_word_count + 6'd1;
                    end
                end
            end
        end
        
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                keccak_op   <= 0;
                stage_k     <= 0;
                keccak_cnt  <= 0;
                keccak_done <= 0;
                squeeze_flush <= 1'b0;
                jud_cbd     <= 0;
                jud_rej     <= 0;
                cnt         <= 0;
                data_A      <= 0;
                data_A_t    <= 0;
                data_r      <= 0; 
            end
            else begin
                keccak_done <= 0; 
                squeeze_flush <= 1'b0;
                case(stage_k)
                    //闲置状态，当调控模块令trans_keccak拉高，启动调度
                    keccak_IDLE:begin
                        keccak_op <= 0;
                        jud_rej   <= 0;
                        // 等调度器消费上个完成事件，避免持续的旧请求再次启动并误清buffer。
                        if (k_in_vld && !keccak_done && !gen_done) begin
                            stage_k   <= trans_keccak;
                        end
                    end
                    //作为中间状态，排空上次keccak可能残留的数据
                    keccak_A:begin
                        case(keccak_cnt)
                            stage_reset:begin
                                keccak_op  <= 0;
                                squeeze_flush <= 1'b1;
                                cnt        <= 0;
                                keccak_cnt <= stage_first;    
                            end
                            stage_first:begin
                                //已将种子全部输入。准备开始运算
                                if (cnt>3) begin
                                    keccak_op    <= {1'b1,k_mod,1'b0,k_in_vld}; 
                                    keccak_cnt   <= stage_hold;
                                    data_A       <= {48'd0, data_A_reg[271:256]};
                                    data_A_t     <= {48'd0, data_A_t_reg[271:256]};
                                    keccak_cnt   <= stage_hold; 
                                end
                                //通过64位输入进keccak，一次输入其中8字节
                                else begin
                                    keccak_op  <= {1'b0,k_mod,1'b1,k_in_vld};
                                    cnt        <= cnt + 1; 
                                    data_A     <= (data_A_reg>>(64*cnt));
                                    data_A_t   <= (data_A_t_reg>>(64*cnt));
                                end
                            end
                            //数据计算时保持该状态，防止别的信号影响keccak计算
                            //计算完成后，将完成标志信号拉高，其余信号复位，状态恢复为闲置
                            stage_hold:begin
                                keccak_op <= {1'b0, k_mod, 1'b0, 3'd0};
                                //reject_sample里有足够多的系数，可以终止运算了
                                if (rej_finish) begin
                                    stage_k     <= 0;
                                    keccak_cnt  <= stage_reset;
                                    keccak_done <= 1;
                                end
                                // buffer输出完本块后再进入续块路径；
                                else if (squeeze128_block_drained) begin
                                    keccak_cnt  <= stage_first;
                                    jud_rej     <= 1;
                                    cnt         <= 0;
                                end
                            end
                        endcase
                    end
                    keccak_vector:begin
                        case(keccak_cnt)
                            stage_reset:begin
                                keccak_op  <= 0;
                                squeeze_flush <= 1'b1;
                                cnt        <= 0;
                                keccak_cnt <= stage_first;    
                            end
                            stage_first:begin
                                //已将种子全部输入。准备开始运算
                                if (cnt>3) begin
                                    keccak_op    <= {1'b1,k_mod,1'b0,k_in_vld}; 
                                    keccak_cnt   <= stage_hold;
                                    data_r       <= {56'd0, data_r_reg[263:256]};
                                    keccak_cnt <= stage_hold; 
                                end
                                //通过64位输入进keccak，一次输入其中8字节
                                else begin
                                    keccak_op  <= {1'b0,k_mod,1'b1,k_in_vld};
                                    cnt        <= cnt + 1; 
                                    data_r     <= (data_r_reg>>(64*cnt));
                                end 
                            end
                            //数据计算时保持该状态，防止别的信号影响keccak计算
                            //计算完成后，将完成标志信号拉高，其余信号复位，状态恢复为闲置
                            stage_hold:begin
                                keccak_op <= {1'b0, k_mod, 1'b0, 3'd0};
                                //数据计算时保持该状态，防止别的信号影响keccak计算
                                //计算完成后，将完成标志信号拉高，其余信号复位，状态恢复为闲置
                                if (cbd_task_finish) begin
                                    jud_cbd     <= 0;
                                    keccak_done <= 1;
                                    keccak_cnt  <= stage_reset;
                                    stage_k     <= 0;
                                    cnt         <= 0;
                                end
                                //系数数量不够，需要将经过keccak处理后重新返回至输入端，由keccak再次处理一遍，制造数据流
                                // [TOP-05/07][P1][2026-09-26：首轮输入修复，续块仍走错流程]
                                // 首次4个64位字+尾字节的分拍输入已在XSim观察到；原来“只送1字就hold”已修。
                                // 这里cnt仍为4，返回stage_first后直接进入尾字节分支；eta=2也无条件继续发请求。
                                // 不能只加cnt<=0：正确续挤压应在完整1600位状态上再做置换，不能重新送seed/尾字节/填充。
                                // 新多项式一次启动、足够数据后等待采样完成、同多项式续块单独握手，需与TOP-07/23统一。
                                // 当前k_in_vld来自stage_gen持续电平，返回IDLE后还会再次受理未撤销的旧任务。
                                else if (keccak_out_vld) begin
                                    keccak_cnt <= stage_first;
                                    jud_cbd    <= 1;
                                end
                            end
                        endcase
                    end
                endcase
            end
        end

    always @(*) begin
        keccak_in_jud = 0;
        trans_keccak  = 0;
        k_mod         = 0;
        k_in_vld      = 0;
        jud_A         = 0;
        jud_s         = 0;
        jud_y         = 0;
        jud_e         = 0;
        case(stage)
            keygen:begin
                    case(stage_gen)
                        stage_reset:begin
                            keccak_in_jud = 0;                     
                            //keccak_op     = 0; 
                            trans_keccak  = 0;
                            k_mod         = 0;
                            k_in_vld      = 0;
                            jud_A         = 0;
                            jud_s         = 0;
                            jud_y         = 0;
                            jud_e         = 0;
                            //jud_mult      = 0;
                        end
                        stage_A:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            trans_keccak  = keccak_A;
                            k_mod         = 1; 
                            k_in_vld      = 3'd2;
                            jud_A         = 1;
                            //jud_s         = 0;
                            //jud_y         = 0;
                            //jud_e         = 0;
                            //jud_mult      = 0;
                            //move_start    = 0;
                            //move_stage    = 0;
                            //cnt_t         = 0;
                            //复位输出标志信号
                        end
                        stage_s:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            trans_keccak  = keccak_vector;
                            k_mod         = 3'd2;
                            k_in_vld      = 3'd1; 
                            //jud_A         = 0;
                            jud_s         = 1;
                            //jud_y         = 0;
                            //jud_e         = 0;
                            //jud_mult      = 0;
                            //move_start    = 0;
                            //move_stage    = 0;
                            //cnt_t         = 0;
                        end
                        stage_e:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            trans_keccak  = keccak_vector;
                            k_mod         = 3'd2;
                            k_in_vld      = 3'd1;  
                            //jud_A         = 0;
                            //jud_s         = 0;
                            //jud_y         = 0;
                            jud_e         = 1;
                            //jud_mult      = 0;
                            //move_start    = 0;
                            //move_stage    = 0;
                            //cnt_t         = 0;
                        end  
                    endcase
            end
            encaps:begin
                case(stage_gen)
                stage_reset:begin
                    keccak_in_jud = 0;                     //keccak输入接至模块外部输入
                    trans_keccak  = 0;
                    k_mod         = 0;
                    k_in_vld      = 0;  
                    jud_A         = 0;
                    jud_s         = 0;
                    jud_y         = 0;
                    jud_e         = 0;
                    //jud_mult      = 0;
                end
                stage_A:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    trans_keccak  = keccak_A;
                    k_mod         = 3'd1;
                    k_in_vld      = 3'd2;  
                    jud_A         = 1;
                    //jud_s         = 0;
                    //jud_y         = 0;
                    //jud_e         = 0;
                    //jud_mult      = 0;
                    //move_start    = 0;
                    //move_stage    = 0;
                    //复位输出标志信号
                    //finish_keygen <= 0;
                    //finish_encaps <= 0;
                    //finish_decaps <= 0;
                    //out_vld       <= 0;
                end
                stage_y:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    trans_keccak  = keccak_vector;
                    k_mod         = 3'd2;
                    k_in_vld      = 3'd1;
                    //jud_A         = 0;
                    //jud_s         = 0;
                    jud_y         = 1;
                    //jud_e         = 0;
                    //jud_mult      = 0;
                end
                stage_e:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    trans_keccak  = keccak_vector;
                    k_mod         = 3'd2;
                    k_in_vld      = 3'd1; 
                    //jud_A         = 0;
                    //jud_s         = 0;
                    //jud_y         = 0;
                    jud_e         = 1;
                    //jud_mult      = 0;
                end
                endcase
            end
            decaps:begin
                
            end
        endcase
    end

//计算操作
    //T值运算控制逻辑信号
    reg new_vld;  //判断是否有新的请求进入，是否需要从ram中取出数据
    reg t_finish; //标志信号，告诉调度计算已完成


    always @(*) begin
    jud_mult      = 0;
    jud_plus_1    = 0;
    jud_plus_2    = 0;
    jud_plus_3    = 0;
    jud_mult_2    = 0;
    jud_plus_4    = 0;
    jud_sub       = 0;
    move_start    = 0;
    move_stage    = 0;
    case(stage)
        keygen:begin
            case(stage_caucl)
                stage_reset:begin
                    jud_mult      = 0;
                    jud_plus_1    = 0;
                    jud_plus_2    = 0;
                    jud_plus_3    = 0;
                    move_start    = 0;
                    move_stage    = 0;
                end
                stage_mult:begin
                    jud_mult      = 1;
                end 
                stage_plus_1:begin
                    jud_plus_1    = 1;
                    move_start    = 1;
                    move_stage    = 1;
                end
                stage_plus_2:begin
                    jud_plus_2    = 1;
                    move_start    = 1;
                    move_stage    = 2;
                    //cnt_plus      = 0;
                end 
            endcase
        end
        encaps:begin
            case(stage_caucl)
                stage_reset:begin
                    jud_mult   = 0;
                    jud_plus_1 = 0;
                    jud_plus_2 = 0;
                    jud_plus_3 = 0;
                    move_start = 0;
                    move_stage = 0;
                    jud_mult_2 = 0;
                    jud_plus_4 = 0;
                end
                stage_mult:begin
                    jud_mult   = 1;

                end
                stage_plus_1:begin
                    jud_plus_1 = 1;
                    move_start = 1;
                    move_stage = 1;

                end
                stage_plus_2:begin
                    jud_plus_2 = 1;
                    move_start = 1;
                    move_stage = 2;

                end
                stage_plus_3:begin
                    jud_plus_3 = 1;
                    move_start = 1;
                    move_stage = 3;

                end
                //修改后的补充状态，用于计算t*y
                stage_mult_2:begin
                    jud_mult_2 = 1;
                end
                stage_plus_4:begin
                    move_start = 1;
                    move_stage = 4;
                    jud_plus_4 = 1;      
                end
            endcase
        end
        decaps:begin
            case(stage_caucl)
                stage_reset:begin
                    
                end
                stage_mult:begin
                    jud_mult   = 1;
                end
                stage_sub:begin
                    jud_sub    = 1;
                    move_start = 1;
                    move_stage = 5;
                end

            endcase
        end
    endcase
    end

//调度模块
        
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            //模式切换
            next_stage <= 0;

            //向量生成调度
            stage_gen <= 0;
            cnt_A     <= 0;
            col_cnt   <= 0;
            row_cnt   <= 0;
            cnt_n     <= 0;
            cnt_A     <= 0;
            cnt_s     <= 0;
            cnt_y     <= 0;
            gen_ing   <= 0; 
            gen_done  <= 0;

            //cnt       <= 0;
            cnt_t     <= 0;
            
            //计算调度
            caucl_ing     <= 0;
            caucl_done    <= 0;
            stage_caucl   <= 0;
            finish_keygen <= 0;
            finish_encaps <= 0;
            finish_decaps <= 0;
            out_vld       <= 0;
            cnt_u         <= 0; 
            count_t       <= 0;
            new_vld       <= 0;

            
        end
        else begin
            //将原先位于其他模块的重复驱动变量移动到本模块中
            finish_keygen <= 0;
            finish_encaps <= 0;
            finish_decaps <= 0;
            out_vld       <= 0;
            //gen_done      <= 0;
            //caucl_done    <= 0;

            case(stage)
                keygen:begin
                    case(stage_gen)
                        stage_reset:begin
                            gen_ing  <= 0;
                            if (start) begin
                                gen_ing   <= 1;  //进入运行模块时，将信号手动拉升，防止switch直接以高电平将状态跳过
                                stage_gen <= stage_A;
                            end
                            //gen_done <= 0;
                        end
                        stage_A:begin
                           if (keccak_done) begin
                                gen_done <= 1;
                                //（row,col）先生成同一列数据，再换列生成
                                if (col_cnt && row_cnt) begin
                                    row_cnt <= 0;
                                    col_cnt <= 0;
                                end
                                else if (row_cnt) begin
                                    col_cnt <= col_cnt + 1;
                                    row_cnt <= 0;
                                end
                                else begin
                                    row_cnt <= row_cnt +1;
                                end    
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;         
                            end
                            if (switch) begin
                                gen_done  <= 0;
                                caucl_done  <= 0;
                                if (!col_cnt && row_cnt) begin 
                                    stage_gen <= stage_A;     //生成A0,0之后跳转生成s0
                                end
                                else if (!row_cnt && col_cnt) begin 
                                    stage_gen   <= stage_e;              //生成A1,0之后跳转生成e1;
                                    cnt_n       <= 3;
                                    stage_caucl <= stage_mult;           //跳转执行A0,1*S0
                                    cnt_t       <= 1;                    //改为求第二行t值
                                end
                                else if (row_cnt && col_cnt) begin
                                    stage_gen   <= stage_s;  //生成A0,1之后跳转生成s1;
                                    cnt_n       <= 1;
                                    cnt_s       <= 1;  
                                    stage_caucl <= stage_reset;  //计算模块暂且停止
                                    caucl_ing   <= 0;

                                end
                                else if (!col_cnt && !row_cnt) begin
                                    stage_gen   <= stage_reset; //生成模块暂时停止
                                    gen_ing     <= 0;
                                    stage_caucl <= stage_mult; //转至A11*s1
                                    cnt_s       <= 1;
                                    //new_vld     <= 1; 
                                end
                                else begin
                                    stage_gen <= 2; 
                                end             
                            end         
                        end 
                        stage_s:begin
                            if (keccak_done) begin
                                //cnt_s    <= cnt_s + 1;
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;
                            end
                            if (switch) begin
                                gen_done  <= 0;
                                caucl_done  <= 0;
                                if (cnt_n == 0) begin  
                                    cnt_n       <= 2;          //n值转至生成e0所需的值     
                                    stage_gen   <= stage_e;    //生成s0之后，跳转生成e0
                                    stage_caucl <= stage_mult; //计算模块转至A00*s0部分
                                    cnt_s       <= 0;          //第一行
                                end
                                else if (cnt_n == 1) begin
                                    stage_gen   <= stage_reset;
                                    gen_ing     <= 0; //暂时停止向量生成 
                                    //cnt_A       <= 2;
                                    stage_caucl <= 1; //转至A0,1*S1
                                    cnt_s       <= 1; //第二行
                                    caucl_ing   <= 1; 
                                end
                            end
                        end
                        stage_e:begin
                            if (keccak_done) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;
                            end
                            if (switch) begin
                                gen_done  <= 0;
                                caucl_done  <= 0;
                                if (cnt_n == 2) begin
                                    stage_gen   <= stage_A; //转至A1,0生成
                                    cnt_A       <= 1;
                                    stage_caucl <= stage_plus_1; //转至第一类加法(A00*s0)
                                    new_vld     <= 1;
                                end
                                else if (cnt_n == 3) begin
                                    stage_gen   <= 1; //转至A0,1生成
                                    cnt_A       <= 2;
                                    stage_caucl <= stage_plus_1; //转至第一类加法(A10*s0)
                                    new_vld     <= 1;
                                end
                            end
                        end 
                    endcase
                    //计算调度
                    case(stage_caucl)
                        stage_reset:begin
                            caucl_ing     <= 0;
                            //caucl_done    <= 0;
                            //stage_caucl   <= 0;
                            //out_vld       <= 0;
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;       
                            end
                            if (switch) begin
                                caucl_done  <= 0;
                                gen_done    <= 0;
                                if (cnt_A == 2) begin
                                    stage_gen   <= stage_A; //生成A11
                                    cnt_A       <= 3;
                                    stage_caucl <= stage_plus_2 //第二类加法(A01*s1)
                                    cnt_t       <= 0; //第一行
                                    new_vld     <= 1;
                                end
                                else if (cnt_A == 3) begin
                                    stage_caucl <= stage_plus_2 //第二类加法(A11*s1)
                                    cnt_t       <= 1; //第二行
                                    new_vld     <= 1;
                                end
                            end

                        end 
                        stage_plus_1:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            /*
                            if (switch && (cnt_A == 3)) begin
                                caucl_done  <= 0;
                                stage_caucl <= 3; //转至第二类加法
                                new_vld     <= 1;
                            end
                            */
                        end
                        stage_plus_2:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            if (switch && (cnt_A == 3)) begin
                                caucl_done    <= 0;
                                stage_caucl   <= stage_reset; //计算完成,恢复至初始状态
                                finish_keygen <= 1;
                                //stage         <= encaps;
                                //new_vld       <= 0;
                                next_stage    <= 1;
                                /////////////////////////////////////////
                                //keygen计算完成
                                ////////////////////////////////////////
                            end
                        end
                    endcase 
                end
                encaps:begin
                    //向量生成调度
                    // [TOP-03][P1][2026-09-25：跨模式请求/状态交接未定义]
                    // stage 已作为外部 input，不再内部赋值；但本模式只在 finish_keygen 的单拍窗口启动，
                    // decaps 同样依赖 finish_encaps。一旦调用方晚一拍切 stage，事件消失，下一模式无法启动。
                    // cnt_y/count_t/行列/nonce 等仅全局复位；重复调用还会继承旧进度。
                    // 修改思路：用明确的新请求启动各模式，在接受请求时初始化本模式上下文，完成保持到确认或产生可捕获脉冲。
                    // stage 的模式值与数据种子应在任务期间稳定/锁存，不应依靠前一模式脉冲恰好与外部 stage 切换重合。
                    case(stage_gen)
                        stage_reset:begin
                            gen_ing     <= 0;
                            cnt_A       <= 0;
                            //caucl_done    <= 0;
                            //stage_caucl   <= 0;
                            //out_vld       <= 0;
                            if (next_stage) begin
                                next_stage <= 0;
                                gen_ing   <= 1;   //进入运行模块时，将信号手动拉升，防止switch直接以高电平将状态跳过
                                stage_gen <= stage_A;

                            end
                        end
                        stage_A:begin
                            if (keccak_done) begin
                                gen_done <= 1;
                                //（row,col）先生成同一列数据，再生成同一行数据，为y腾空间
                                if (row_cnt&&col_cnt) begin
                                    col_cnt <= 0;
                                    row_cnt <= 0;
                                end
                                else if (col_cnt) begin
                                    row_cnt <= row_cnt + 1;
                                    col_cnt <= 0;
                                end
                                else begin
                                    col_cnt <= col_cnt + 1;
                                end
                            end
                            if (switch) begin
                                gen_done  <= 0;
                                caucl_done  <= 0;
                                if (!row_cnt && col_cnt) begin
                                    //gen_ing  <= 1;
                                    stage_gen <= stage_y; 
                                    cnt_n     <= 0;        //生成y0
                                    cnt_A     <= 0;
                                end
                                else if (!col_cnt && row_cnt) begin
                                    //gen_ing     <= 1;
                                    stage_gen   <= 3; //转至生成e1_1
                                    cnt_n       <= 3;
                                    //caucl_ing   <= 1;
                                    stage_caucl <= stage_mult; //转至计算A10*y0
                                    cnt_A       <= 1;
                                end
                                else if (col_cnt && row_cnt) begin
                                    gen_ing   <= 0;
                                    stage_gen <= 0; //暂时暂停向量生成
                                    stage_caucl <= stage_mult_2; //转至计算t0*y0
                                    cnt_A       <= 2;
                                end
                                else begin
                                    gen_ing  <= 0;
                                    stage_gen <= stage_reset; //结束生成
                                    //cnt_n     <= 4;
                                    stage_caucl <= stage_mult; //转至生成A1,1*y
                                    cnt_A       <= 3;
                                end
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;
                            end
                        end
                        stage_y:begin
                            if (keccak_done) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;
                            end
                            if (switch) begin
                                caucl_done  <= 0;
                                gen_done    <= 0;
                                if (cnt_n == 0) begin
                                    stage_gen   <= stage_e; 
                                    cnt_n       <= 2;          //转至生成e1_0
                                    stage_caucl <= stage_mult; //转至A0,0*y0
                                end
                                else if (cnt_n == 1) begin
                                    stage_gen   <= stage_e; //转而生成e2
                                    cnt_n       <= 4;
                                    stage_caucl <= stage_mult; //转至生成A0,1*y1
                                    cnt_t       <= 0;          //第一行
                                end
                            end
                        end
                        stage_e:begin
                            if (keccak_done) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                //gen_done <= 0;
                            end
                            if (switch) begin
                                gen_done  <= 0;
                                caucl_done  <= 0;
                                if (cnt_n == 2) begin
                                    stage_gen   <= stage_A;      //转至生成A1,0
                                    stage_caucl <= stage_plus_1; //转至第一类加法(A00*y0)
                                    new_vld     <= 1;
                                    cnt_t       <= 0; //第一行
                                end
                                else if (cnt_n == 3) begin
                                    stage_gen   <= stage_A; //转至生成A0,1
                                    stage_caucl <= stage_plus_1; //转至第一类加法(A10*y0)
                                    new_vld     <= 1;
                                    cnt_t       <= 1; //第二行
                                end
                                else if ((cnt_n == 4) && cnt_A == 2) begin
                                    stage_gen   <= stage_A; //生成A11
                                    stage_caucl <= stage_plus_2; //转至第二类加法(A01*y1)
                                    new_vld     <= 1;
                                    cnt_t       <= 0; //第一行
                                end
                            end
                        end
                    endcase
                    //计算调度
                    case(stage_caucl)
                        stage_reset:begin
                            caucl_ing     <= 0;
                            //caucl_done    <= 0;
                            //stage_caucl   <= 0;
                            //out_vld       <= 0;
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            //复位输出标志信号
                            finish_keygen <= 0;
                            finish_encaps <= 0;
                            finish_decaps <= 0;
                            //out_vld       <= 0;
                            if (switch && (cnt_n == 4) && (cnt_A == 3)) begin
                                stage_caucl <= stage_plus_2; //转至第二类加法(A11*Y1)
                                cnt_t       <= 1;            //第二行
                            end
                        end
                        stage_plus_1:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                        end
                        stage_plus_2:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            if (switch && (cnt_n == 4)) begin
                                caucl_done  <= 0;
                                gen_ing     <= 0;
                                stage_caucl <= stage_mult_2; //转至t1*y1，开始完成剩余的t*y的计算
                            end

                        end
                        //原先理解有误，现该状态修改为在大部分计算完成以及ramu计算完成后，完成t*y剩余计算的状态
                        stage_plus_3:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            if (switch && (cnt_n == 4)) begin
                                caucl_done  <= 0;
                                stage_caucl   <= stage_reset; //计算完成,恢复至初始状态
                                finish_encaps <= 1;
                                out_vld       <= 1;
                                next_stage    <= 1;
                                //stage         <= decaps;
                                //////////////////////////////////
                                //encaps计算完成
                                /////////////////////////////////
                            end
                        end

                        //修改后的补充状态，用于计算t*y
                        stage_mult_2:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            if (switch) begin
                                caucl_done  <= 0;
                                if (!cnt_y) begin
                                    stage_caucl   <= stage_plus_4;  //计算t0*y0+[q/2]m
                                    new_vld       <= 1;
                                    
                                    gen_ing       <= 0;
                                    stage_gen     <= stage_y;  //转至生成y1
                                    cnt_n         <= 1;

                                    /*
                                    stage_caucl   <= 2;  //转至第一类加法
                                    cnt_t         <= 1;  //第二行
                                    */
                                end
                                else if (cnt_y) begin
                                    stage_caucl <= 4; //计算剩下的加法
                                    new_vld <= 1'b1;
                                end
                            end
                        end
                        stage_plus_4:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                new_vld    <= 0;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            /*
                            if (switch&& !count_t) begin
                                caucl_done  <= 0;
                                count_t     <= 1;   //以t的值作为标志判断t*y执行进度，同时移动t值，第一行y0执行完毕，等待执行第二行y1
                                stage_gen   <= 1;   //转至生成A0,1
                                stage_caucl <= 1;   //转至生成A1,0*y0
                            end
                            */    
                        end
                    endcase
                end
                decaps:begin
                    //无向量生成调度
                    //计算调度
                    case(stage_caucl)
                        stage_reset:begin
                            caucl_ing  <= 0;
                            //caucl_done <= 0;
                            if (next_stage) begin
                                next_stage <= 0;
                                caucl_ing <= 1;  //进入运行模块时，将信号手动拉升，防止switch直接以高电平将状态跳过
                                cnt_s <= 1'b0;
                                cnt_u <= 1'b0;
                                stage_caucl <= stage_mult;
                            end
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                //caucl_done <= 0;
                            end
                            if (switch) begin
                                new_vld <= 1'b1;
                                stage_caucl <= 2;
                            end
                        end
                        stage_sub:begin
                            if (t_finish) begin
                                caucl_done <= 1;
                                caucl_ing  <= 0;
                                new_vld    <= 0;
                            end
                            if (switch) begin
                                if (!cnt_s && !cnt_u) begin
                                    cnt_s       <= 1;
                                    cnt_u       <= 1;
                                    stage_caucl <= stage_mult;
                                end
                                else if (cnt_s && cnt_u) begin
                                    stage_caucl <= stage_reset;
                                    finish_decaps <= 1;
                                    out_vld       <= 1;
                                    finish_decaps <= 1;
                                    ///////////////////////
                                    //decaps完成
                                    //////////////////////
                                end
                            end
                        end
                    endcase
                end
            endcase
        end
    end
 
//keygen t值计算逻辑

    // [TOP-13] 最后一项写入后保持完成；下一搬运类型进入时重新初始化。
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            ram4_addr_a_temp <= 0;
            ram4_addr_b_temp <= 0;
            ramt_addr_a_temp <= 0;
            ramt_addr_b_temp <= 0;
            rame_addr_a_temp <= 0;
            rame_addr_b_temp <= 0;
            ramv_addr_a_temp <= 0;
            ramv_addr_b_temp <= 0;
            t_first          <= 0;
            t_finish         <= 0;
            old_vld          <= 0;
            move_stage_d     <= 0;
            move_done        <= 0;
        end
        else begin 
            t_finish <= 0; // 最后一项实际写入时拉高一拍
            move_stage_d <= move_stage;
            if (!move_start || (move_stage != move_stage_d)) begin
                t_first  <= 0;
                old_vld  <= 0;
                move_done <= 0;
            end
            else if (!move_done) begin
                case(move_stage)
                //将乘法结果+e存入ramt中
                    1'd1: begin
                        //先按照需求复位
                        if (!t_first) begin
                            t_first <= 1;
                            old_vld <= 0;
    
                            ram4_addr_a_temp <= 0;
                            ram4_addr_b_temp <= 1;
                            ramt_addr_a_temp <= 0;
                            ramt_addr_b_temp <= 1;
                            rame_addr_a_temp <= 0;
                            rame_addr_b_temp <= 1;
    
                        end
                        else begin
                            //有新请求，移动ram提前取出数据
                            if (new_vld) begin
                                ram4_addr_a_temp <= ram4_addr_a_temp + 2;
                                ram4_addr_b_temp <= ram4_addr_b_temp + 2;
                                rame_addr_a_temp <= rame_addr_a_temp + 2;
                                rame_addr_b_temp <= rame_addr_b_temp + 2;
                                old_vld          <= 1;     //进行到下一拍后告诉电路上一拍有请求
                            end
                            else begin
                                old_vld <= 0;
                            end
                            //在地址移动到最后一拍，赋值将在当周期内完成时，准备复位，并告诉调度电路计算已完成
                            if (move_write_vld && (ramt_addr_b_temp == 255)) begin
                                t_finish <= 1;
                                old_vld  <= 0;
                                move_done <= 1; // 末项写完后停止，等待调度器切换状态
                            end
                            //上一拍有请求，移动ram准备接受计算完的数据
                            else if (old_vld) begin
                                ramt_addr_a_temp <= ramt_addr_a_temp + 2;
                                ramt_addr_b_temp <= ramt_addr_b_temp + 2;
                            end
                        end
                    end
                //将ramt的结果加上乘法结果存回ramt中
                    3'd2:begin
                    if (!t_first) begin
                        t_first <= 1;
                        old_vld <= 0;
                        
                        ram4_addr_a_temp <= 0;
                        ramt_addr_a_temp <= 0;
                        ramt_addr_b_temp <= 0;
                    end
                    else begin
                        if (new_vld) begin
                            ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                            ramt_addr_a_temp <= ramt_addr_a_temp + 1;
                            old_vld          <= 1;
                        end
                        else begin
                                old_vld <= 0;
                        end
                        //在地址移动到最后一拍，赋值将在当周期内完成时，准备复位，并告诉调度电路计算已完成
                        if (move_write_vld && (ramt_addr_b_temp == 255)) begin
                            t_finish <= 1;
                            old_vld  <= 0;
                            move_done <= 1;
                        end
                        else if (old_vld) begin
                            ramt_addr_b_temp <= ramt_addr_b_temp + 1;
                        end
                    end
                        /*
                        if ((ramt_addr_b_temp == 255) && (stage == keygen)) begin
                               cnt_t <= !cnt_t;
                        end
                        */   
                    end
                    3'd3:begin
                        if (!t_first) begin
                             t_first <= 1;
                             old_vld <= 0;
                             
                             ram4_addr_a_temp <= 0;
                             rame_addr_a_temp <= 0;
                             ramv_addr_a_temp <= 0;
                             ramv_addr_b_temp <= 0;
                         end
                         else begin
                             if (new_vld) begin
                                 ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                                 rame_addr_a_temp <= rame_addr_a_temp + 1;
                                 ramv_addr_a_temp <= ram4_addr_a_temp + 1;
                                 old_vld          <= 1;
                             end
                             else begin
                                old_vld <= 0;
                             end
                             //在地址移动到最后一拍，赋值将在当周期内完成时，准备复位，并告诉调度电路计算已完成
                             if (move_write_vld && (ramv_addr_b_temp == 255)) begin
                                  t_finish <= 1;
                                  old_vld  <= 0;
                                  move_done <= 1;
                             end
                             else if (old_vld) begin
                                 ramv_addr_b_temp <= ramv_addr_b_temp + 1;
                             end 
                         end
                    end
                    3'd4:begin
                        if (!t_first) begin
                            t_first <= 1;
                            old_vld <= 0;
                            
                            ram4_addr_a_temp <= 0;
                            ram4_addr_b_temp <= 1;
                            ramv_addr_a_temp <= 0;
                            ramv_addr_b_temp <= 1;
                        end
                        else begin
                            if (new_vld) begin
                                ram4_addr_a_temp <= ram4_addr_a_temp + 2;
                                ram4_addr_b_temp <= ram4_addr_b_temp + 2;
                                old_vld          <= 1;
                            end
                            else begin
                                old_vld <= 0;
                            end
                            //在地址移动到最后一拍，赋值将在当周期内完成时，准备复位，并告诉调度电路计算已完成
                            if (move_write_vld && (ramv_addr_b_temp == 255)) begin
                                t_finish <= 1;
                                old_vld  <= 0;
                                move_done <= 1;
                            end
                            else if (old_vld) begin
                                ramv_addr_a_temp <= ramv_addr_a_temp + 2;
                                ramv_addr_b_temp <= ramv_addr_b_temp + 2;
                            end
                        end
                    end
                    //调整了减法逻辑，改为单端口读出，减去乘积之后，再写入原地址
                    3'd5:begin
                        if (!t_first) begin
                            t_first <= 1;
                            old_vld <= 0;
                            
                            ram4_addr_a_temp <= 0;
                            ramv_addr_a_temp <= 0;
                            ramv_addr_b_temp <= 0;
                        end
                        else begin
                            if (new_vld) begin
                                ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                                ramv_addr_a_temp <= ramv_addr_a_temp + 1;
                                old_vld          <= 1;
                            end
                            else begin
                                old_vld <= 0;
                            end
                            //在地址移动到最后一拍，赋值将在当周期内完成时，准备复位，并告诉调度电路计算已完成
                            if (move_write_vld && (ramv_addr_b_temp == 255)) begin
                                t_finish <= 1;
                                old_vld  <= 0;
                                move_done <= 1;
                            end
                            else if (old_vld) begin
                                ramv_addr_b_temp <= ramv_addr_b_temp + 1;
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule
