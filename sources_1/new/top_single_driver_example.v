/*
 * top_single_driver_example.v -- 基于当前 top.v 的多驱动重写示例
 * 原始 top.v SHA256:
 * 1C6676F28D1845F430E60061D5A6E5408471AF69257C31AC31342A32BEE02FA3
 *
 * 本文件为完整模块副本，模块名改为 top_single_driver_example，
 * 可与原 top 同时存在；没有修改 XPR 或切换工程顶层。
 *
 * [EXAMPLE] 标记处是重写重点：
 * 1. 生成/计算组合译码各自唯一驱动控制量，补齐默认值，统一用 =。
 * 2. 两个调度时序块及地址移动时序块合为 unified_scheduler，统一复位。
 * 3. finish_* / out_vld 移除组合驱动，只在 unified_scheduler 用 <= 更新。
 * 4. 同拍优先级：复位 > 计算调度 > 生成调度 > 地址移动；
 *    完成置位与生成阶段清零同拍时，后执行的完成置位胜出。
 *    这是本示例选定的规则，不代表原代码已定义该优先级。
 * 5. encaps 计算调度的 case(stage_gen) 改为 case(stage_caucl)。
 * 6. 内部 reg/wire/parameter 声明统一前置，原 RAM/算术/子模块连线保留。
 *
 * 验证记录（2026-09-11，Vivado 2018.3）：
 * - xvlog 普通 Verilog 模式：本文件单独语法检查通过。
 * - 提取相同控制逻辑的独立 fixture 经 xelab / xsim：17 项检查通过。
 *   覆盖复位、无效模式默认控制、同拍竞争优先级、计算状态译码、
 *   完成标志置位/保持/同步清零；冲突测试通过测试平台构造内部状态，
 *   不构成这些状态从正常启动可达的证明。
 * - 静态排除注释后检查所有过程写入：未发现跨 always 的重复写入。
 * - 未执行完整模块层级展开、综合、时序分析或 ML-KEM 标准向量验证。
 *
 * 适用范围/保留问题：
 * - 仅演示消除过程多驱动，不是已验证的完整 ML-KEM 实现。
 * - 沿用当前状态跳转、switch 握手和地址计数，未补充完整启动/重启协议。
 *   复位后 stage_gen=stage_reset；原来缺少的启动转移不会凭空产生。
 * - SHAKE 控制字/位宽、NTT 握手、采样器重启、RAM 读写对齐与模运算
 *   等数据路径问题未在此重构中解决。
 * - decaps 的 stage_sub 控制及完成条件按原版保留，需单独修正并验证。
 * - 在 Vivado 中检查本文件时选择 top_single_driver_example；
 *   单文件语法通过不代表所有原子模块能展开或端到端运算正确。
 */
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


module top_single_driver_example#(
    parameter ADDR_WIDTH = 8,
    parameter byte_WIDTH = 8,
    parameter DATA_WIDTH = 12,
    parameter q = 3329,
    parameter k = 2           //规模
    )(
    input                  clk,
    input                  rst,
    input                  din_vld,
    input [DATA_WIDTH-1:0] data_in_A,     //通用种子
    input [DATA_WIDTH-1:0] data_in_r,     //通用种子
    input [255:0]          m_in,          //明文输入
    input [1:0]            stage,         //模式输入
    output reg             out_vld,
    output reg             finish_keygen,
    output reg             finish_encaps,
    output reg             finish_decaps
    );
// [EXAMPLE] 内部常量和线网也统一前置；连接关系保持原样。
    wire [63:0]   keccak_in;
    wire [2:0]    keccak_mod;
    wire          keccak_in_vld;
    wire          keccak_over;
    wire          keccak_start;
    wire [1599:0] keccak_out;
    wire          keccak_out_vld;
    wire                  ntt_din_vld;
    wire [DATA_WIDTH-1:0] ntt_ram1_in_1, ntt_ram1_in_2;
    wire [DATA_WIDTH-1:0] ntt_ram3_in_1, ntt_ram3_in_2;
    wire [DATA_WIDTH-1:0] zeta_in;
    wire [ADDR_WIDTH-1:0] zeta_cnt;
        wire                  ram0_we_a, ram0_we_b;
        wire [ADDR_WIDTH-1:0] ram0_addr_a, ram0_addr_b;
        wire [DATA_WIDTH-1:0] ram0_din_a, ram0_din_b;
        wire [DATA_WIDTH-1:0] ram0_dout_a, ram0_dout_b;
        wire                  ram1_we_a, ram1_we_b;
        wire [ADDR_WIDTH-1:0] ram1_addr_a, ram1_addr_b;
        wire [DATA_WIDTH-1:0] ram1_din_a, ram1_din_b;
        wire [DATA_WIDTH-1:0] ram1_dout_a, ram1_dout_b;
        wire                  ram2_we_a, ram2_we_b;
        wire [ADDR_WIDTH-1:0] ram2_addr_a, ram2_addr_b;
        wire [DATA_WIDTH-1:0] ram2_din_a, ram2_din_b;
        wire [DATA_WIDTH-1:0] ram2_dout_a, ram2_dout_b;
        wire                  ram3_we_a, ram3_we_b;
        wire [ADDR_WIDTH-1:0] ram3_addr_a, ram3_addr_b;
        wire [DATA_WIDTH-1:0] ram3_din_a, ram3_din_b;
        wire [DATA_WIDTH-1:0] ram3_dout_a, ram3_dout_b;
        wire                  ram4_we_a, ram4_we_b;
        wire [ADDR_WIDTH-1:0] ram4_addr_a, ram4_addr_b;
        wire [DATA_WIDTH-1:0] ram4_din_a, ram4_din_b;
        wire [DATA_WIDTH-1:0] ram4_dout_a, ram4_dout_b;
        wire                  ramA_we_a, ramA_we_b;
        wire [ADDR_WIDTH-1:0] ramA_addr_a, ramA_addr_b;
        wire [DATA_WIDTH-1:0] ramA_din_a, ramA_din_b;
        wire [DATA_WIDTH-1:0] ramA_dout_a, ramA_dout_b;
        wire                  rams_we_a   [k-1:0];
        wire                  rams_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] rams_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] rams_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] rams_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] rams_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] rams_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] rams_dout_b [k-1:0];
        wire                  rame_we_a, rame_we_b;
        wire [ADDR_WIDTH-1:0] rame_addr_a, rame_addr_b;
        wire [DATA_WIDTH-1:0] rame_din_a, rame_din_b;
        wire [DATA_WIDTH-1:0] rame_dout_a, rame_dout_b;
        wire                  ramy_we_a, ramy_we_b;
        wire [ADDR_WIDTH-1:0] ramy_addr_a, ramy_addr_b;
        wire [DATA_WIDTH-1:0] ramy_din_a, ramy_din_b;
        wire [DATA_WIDTH-1:0] ramy_dout_a, ramy_dout_b;
        wire                  ramt_we_a   [k-1:0];
        wire                  ramt_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] ramt_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] ramt_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] ramt_dout_b [k-1:0];
        wire                  ramu_we_a   [k-1:0];
        wire                  ramu_we_b   [k-1:0];
        wire [ADDR_WIDTH-1:0] ramu_addr_a [k-1:0];
        wire [ADDR_WIDTH-1:0] ramu_addr_b [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_din_a  [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_din_b  [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_dout_a [k-1:0];
        wire [DATA_WIDTH-1:0] ramu_dout_b [k-1:0];
        wire                  ramv_we_a, ramv_we_b;
        wire [ADDR_WIDTH-1:0] ramv_addr_a, ramv_addr_b;
        wire [DATA_WIDTH-1:0] ramv_din_a, ramv_din_b;
        wire [DATA_WIDTH-1:0] ramv_dout_a, ramv_dout_b;
        wire [ADDR_WIDTH-1:0] ntt_ram1_cnt_1, ntt_ram1_cnt_2;
        wire [ADDR_WIDTH-1:0] ntt_ram3_cnt_1, ntt_ram3_cnt_2;
        wire [DATA_WIDTH-1:0] ntt_ram1_out_1, ntt_ram1_out_2;
        wire [DATA_WIDTH-1:0] ntt_ram3_out_1, ntt_ram3_out_2;
        wire                  ntt_ram1_out_vld, ntt_ram3_out_vld;
        wire                  ntt_finish;
        wire                  ntt_ram4_we_a, ntt_ram4_we_b;
        wire [ADDR_WIDTH-1:0] ntt_ram4_addr_a, ntt_ram4_addr_b;
        wire [DATA_WIDTH-1:0] ntt_ram4_din_a, ntt_ram4_din_b;
        wire [DATA_WIDTH-1:0] ntt_ram4_dout_a, ntt_ram4_dout_b;
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
    wire cbd_in_vld;
    wire [byte_WIDTH-1:0] cbd_in;
    wire [ADDR_WIDTH-1:0] cbd_add_1;
    wire [ADDR_WIDTH-1:0] cbd_add_2;
    wire                  cbd_out_vld;
    wire [DATA_WIDTH-1:0] cbd_out_1;
    wire [DATA_WIDTH-1:0] cbd_out_2;
    wire                  cbd_finish;
    wire [1599:0] squeze_din;
    wire          squeze_din_vld;
    wire [7:0]    squeze_dout_1;     //一字节
    wire [23:0]   squeze_dout_2;     //三字节
    wire          squeze_dout_1_vld;
    wire          squeze_dout_2_vld;
    parameter keygen = 1;
    parameter encaps = 2;
    parameter decaps = 3;
        wire          rej_in_vld_kg, rej_in_vld_enc, rej_in_vld_dec;
        wire [7:0]    rej_in_1_kg,   rej_in_1_enc,   rej_in_1_dec;
        wire [7:0]    rej_in_2_kg,   rej_in_2_enc,   rej_in_2_dec;
        wire [7:0]    rej_in_3_kg,   rej_in_3_enc,   rej_in_3_dec;
        wire          cbd_in_vld_kg, cbd_in_vld_enc, cbd_in_vld_dec;
        wire [7:0]    cbd_in_kg,     cbd_in_enc,     cbd_in_dec;
        wire                  ramA_we_a_kg,   ramA_we_a_enc,   ramA_we_a_dec;
        wire                  ramA_we_b_kg,   ramA_we_b_enc,   ramA_we_b_dec;
        wire [ADDR_WIDTH-1:0] ramA_addr_a_kg, ramA_addr_a_enc, ramA_addr_a_dec;
        wire [ADDR_WIDTH-1:0] ramA_addr_b_kg, ramA_addr_b_enc, ramA_addr_b_dec;
        wire [DATA_WIDTH-1:0] ramA_din_a_kg,  ramA_din_a_enc,  ramA_din_a_dec;
        wire [DATA_WIDTH-1:0] ramA_din_b_kg,  ramA_din_b_enc,  ramA_din_b_dec;
        wire                  rams_we_a_kg_0,   rams_we_a_enc_0,   rams_we_a_dec_0;
        wire                  rams_we_b_kg_0,   rams_we_b_enc_0,   rams_we_b_dec_0;
        wire [ADDR_WIDTH-1:0] rams_addr_a_kg_0, rams_addr_a_enc_0, rams_addr_a_dec_0;
        wire [ADDR_WIDTH-1:0] rams_addr_b_kg_0, rams_addr_b_enc_0, rams_addr_b_dec_0;
        wire [DATA_WIDTH-1:0] rams_din_a_kg_0,  rams_din_a_enc_0,  rams_din_a_dec_0;
        wire [DATA_WIDTH-1:0] rams_din_b_kg_0,  rams_din_b_enc_0,  rams_din_b_dec_0;
        wire                  rams_we_a_kg_1,   rams_we_a_enc_1,   rams_we_a_dec_1;
        wire                  rams_we_b_kg_1,   rams_we_b_enc_1,   rams_we_b_dec_1;
        wire [ADDR_WIDTH-1:0] rams_addr_a_kg_1, rams_addr_a_enc_1, rams_addr_a_dec_1;
        wire [ADDR_WIDTH-1:0] rams_addr_b_kg_1, rams_addr_b_enc_1, rams_addr_b_dec_1;
        wire [DATA_WIDTH-1:0] rams_din_a_kg_1,  rams_din_a_enc_1,  rams_din_a_dec_1;
        wire [DATA_WIDTH-1:0] rams_din_b_kg_1,  rams_din_b_enc_1,  rams_din_b_dec_1;
        wire                  rame_we_a_kg,   rame_we_a_enc, rame_we_a_dec;
        wire                  rame_we_b_kg,   rame_we_b_enc, rame_we_b_dec;
        wire [ADDR_WIDTH-1:0] rame_addr_a_kg, rame_addr_a_enc, rame_addr_a_dec;
        wire [ADDR_WIDTH-1:0] rame_addr_b_kg, rame_addr_b_enc, rame_addr_b_dec;
        wire [DATA_WIDTH-1:0] rame_din_b_kg,  rame_din_b_enc, rame_din_b_dec;
        wire [DATA_WIDTH-1:0] rame_din_a_kg,  rame_din_a_enc, rame_din_a_dec;
        wire                  ram4_we_a_kg,   ram4_we_a_enc, ram4_we_a_dec;
        wire                  ram4_we_b_kg,   ram4_we_b_enc, ram4_we_b_dec;
        wire [ADDR_WIDTH-1:0] ram4_addr_b_kg,  ram4_addr_b_enc, ram4_addr_b_dec;
        wire [ADDR_WIDTH-1:0] ram4_addr_a_kg,  ram4_addr_a_enc, ram4_addr_a_dec;
        wire                  ramt_we_a_kg_0,   ramt_we_a_enc_0,   ramt_we_a_dec_0;
        wire                  ramt_we_b_kg_0,   ramt_we_b_enc_0,   ramt_we_b_dec_0;
        wire [ADDR_WIDTH-1:0] ramt_addr_a_kg_0, ramt_addr_a_enc_0, ramt_addr_a_dec_0;
        wire [ADDR_WIDTH-1:0] ramt_addr_b_kg_0, ramt_addr_b_enc_0, ramt_addr_b_dec_0;
        wire [DATA_WIDTH-1:0] ramt_din_a_kg_0,  ramt_din_a_enc_0,  ramt_din_a_dec_0;
        wire [DATA_WIDTH-1:0] ramt_din_b_kg_0,  ramt_din_b_enc_0,  ramt_din_b_dec_0;
        wire                  ramt_we_a_kg_1,   ramt_we_a_enc_1,   ramt_we_a_dec_1;
        wire                  ramt_we_b_kg_1,   ramt_we_b_enc_1,   ramt_we_b_dec_1;
        wire [ADDR_WIDTH-1:0] ramt_addr_a_kg_1, ramt_addr_a_enc_1, ramt_addr_a_dec_1;
        wire [ADDR_WIDTH-1:0] ramt_addr_b_kg_1, ramt_addr_b_enc_1, ramt_addr_b_dec_1;
        wire [DATA_WIDTH-1:0] ramt_din_a_kg_1,  ramt_din_a_enc_1,  ramt_din_a_dec_1;
        wire [DATA_WIDTH-1:0] ramt_din_b_kg_1,  ramt_din_b_enc_1,  ramt_din_b_dec_1;
        wire                  ntt_din_vld_kg,   ntt_din_vld_enc ,  ntt_din_vld_dec;
        wire [DATA_WIDTH-1:0] ntt_ram1_in_1_kg, ntt_ram1_in_1_enc, ntt_ram1_in_1_dec;
        wire [DATA_WIDTH-1:0] ntt_ram1_in_2_kg, ntt_ram1_in_2_enc, ntt_ram1_in_2_dec;
        wire [DATA_WIDTH-1:0] ntt_ram3_in_1_kg, ntt_ram3_in_1_enc, ntt_ram3_in_1_dec;
        wire [DATA_WIDTH-1:0] ntt_ram3_in_2_kg, ntt_ram3_in_2_enc, ntt_ram3_in_2_dec;
        wire                  ramu_we_a_enc_0  ,ramu_we_a_dec_0;
        wire                  ramu_we_b_enc_0  ,ramu_we_b_dec_0;
        wire [ADDR_WIDTH-1:0] ramu_addr_a_enc_0,ramu_addr_a_dec_0;
        wire [ADDR_WIDTH-1:0] ramu_addr_b_enc_0,ramu_addr_b_dec_0;
        wire [DATA_WIDTH-1:0] ramu_din_a_enc_0 ,ramu_din_a_dec_0;
        wire [DATA_WIDTH-1:0] ramu_din_b_enc_0 ,ramu_din_b_dec_0;
        wire                  ramu_we_a_enc_1  ,ramu_we_a_dec_1;
        wire                  ramu_we_b_enc_1  ,ramu_we_b_dec_1;
        wire [ADDR_WIDTH-1:0] ramu_addr_a_enc_1,ramu_addr_a_dec_1;
        wire [ADDR_WIDTH-1:0] ramu_addr_b_enc_1,ramu_addr_b_dec_1;
        wire [DATA_WIDTH-1:0] ramu_din_a_enc_1 ,ramu_din_a_dec_1;
        wire [DATA_WIDTH-1:0] ramu_din_b_enc_1 ,ramu_din_b_dec_1;
        wire                  ramv_we_a_enc  ,ramv_we_a_dec;
        wire                  ramv_we_b_enc  ,ramv_we_b_dec;
        wire [ADDR_WIDTH-1:0] ramv_addr_a_enc,ramv_addr_a_dec;
        wire [ADDR_WIDTH-1:0] ramv_addr_b_enc,ramv_addr_b_dec;
        wire [DATA_WIDTH-1:0] ramv_din_a_enc ,ramv_din_a_dec;
        wire [DATA_WIDTH-1:0] ramv_din_b_enc ,ramv_din_b_dec;
        wire [13:0] data_a_temp_kg , data_a_temp_enc , data_a_temp_dec;
        wire [13:0] data_b_temp_kg , data_b_temp_enc , data_b_temp_dec;
    wire [DATA_WIDTH-1:0] data_a_temp;
    wire [DATA_WIDTH-1:0] data_b_temp;
    wire [10:0]  data_m_aft;
    wire [DATA_WIDTH-1+16:0] data_A;
    wire [DATA_WIDTH-1+16:0] data_A_t;
    wire [DATA_WIDTH-1+8:0]  data_r;
    wire switch;     //硬掩码，当两边均执行完成之后拉升，告诉电路可以切换了状态了
    parameter stage_reset   = 0;
    parameter stage_keccak  = 1;
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


// [EXAMPLE] 模块寄存器集中声明，避免在表达式中引用尚未声明的变量。
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
reg keygen_done;
reg encaps_done;
reg decaps_done;
    reg [7:0] keccak_op;
    reg       keccak_in_jud;
    reg       move_start;
    reg [2:0] move_stage;
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
    reg  [255:0] data_m;
    reg [DATA_WIDTH-1:0]    pho_A;  //锁存输入的矩阵A种子
    reg [DATA_WIDTH-1:0]    pho_r;  //锁存输入的其余向量r的种子
    reg [1:0] col_cnt;
    reg [1:0] row_cnt;              //矩阵A中每一个元素的行列坐标
    reg [3:0] stage_gen;
    reg [3:0] stage_caucl;
    reg gen_ing;    //生成模块被执行标志信号
    reg gen_done;   //生成模块完成信号
    reg caucl_ing;  //计算模块被执行标志信号
    reg caucl_done; //计算模块完成信号


// [EXAMPLE] 搬移地址寄存器前移声明；仍由统一调度时序块拥有。










 





//keccak模块





    


    
    shake_padder keccak(
        .data_in(keccak_in),
        .mod(keccak_mod),
        .din_vld(keccak_in_vld),
        .over(keccak_over),
        .start(keccak_start),
        .clk(clk),
        .rst(rst),
    
        .data_fin(keccak_out),
        .out_vld(keccak_out_vld));
    
//内部连线声明：NTT 与 RAM 阵列






    //ram
        // RAM 0 连线




    
        // RAM 1 连线




    
        // RAM 2 连线




    
        // RAM 3 连线




    
        // RAM 4 连线





        //ramA





        //rams









        //rame




        
        //ramy





        //ramt









        //ramu








        
        //ramv






    //NTT
        // NTT 输出监控连线






        //ram4 ntt模块连线




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
        .ram4_we_a(ntt_ram4_we_a), .ram4_adder_a(ntt_ram4_addr_a), .ram4_din_a(ram4_din_a), .ram4_dout_a(ntt_ram4_dout_a),
        .ram4_we_b(ntt_ram4_we_b), .ram4_adder_b(ntt_ram4_addr_b), .ram4_din_b(ram4_din_b), .ram4_dout_b(ntt_ram4_dout_b),

        // 状态监控输出
        .zeta_cnt(zeta_cnt),
        .ram1_cnt_1(ntt_ram1_cnt_1), .ram1_cnt_2(ntt_ram1_cnt_2),
        .ram3_cnt_1(ntt_ram3_cnt_1), .ram3_cnt_2(ntt_ram3_cnt_2),
        .ram1_out_1(ntt_ram1_out_1), .ram1_out_2(ntt_ram1_out_2),
        .ram3_out_1(ntt_ram3_out_1), .ram3_out_2(ntt_ram3_out_2),
        .ram1_out_vld(ntt_ram1_out_vld),
        .ram3_out_vld(ntt_ram3_out_vld),
        //.which_ram(which_ram),
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

//squeeze buffer







    assign squeze_din     = keccak_out;
    assign squeze_din_vld = keccak_out_vld;
    
    squeeze_bufer squeeze_bufer(
        .clk(clk),
        .rst(rst),
        .din(squeze_din),
        .din_vld(squeze_din_vld),
        .keccak_mod(keccak_mod),
        .dout_1(squeze_dout_1),
        .dout_2(squeze_dout_2),
        .dout_1_vld(squeze_dout_1_vld),
        .dout_2_vld(squeze_dout_2_vld));

//逻辑信号
    //三个状态



    //MUX控制逻辑
        // --- Squeeze Buffer 虚拟线网 ---
        //wire [1599:0] squeze_din_kg,     squeze_din_enc,     squeze_din_dec;
        //wire          squeze_din_vld_kg, squeze_din_vld_enc, squeze_din_vld_dec;
        
        // --- Reject Sampler 虚拟线网 ---




        
        // --- CBD Sampler 虚拟线网 ---


        
        // --- RAM A 虚拟线网 ---







        // --- RAM S 0 虚拟线网 ---






        
        // --- RAM S 1 虚拟线网 ---






        
        // --- RAM E 虚拟线网 ---






        
        // --- RAM 4 虚拟线网 ---




        
        // --- RAM T 0 虚拟线网 ---






        
        // --- RAM T 1 虚拟线网 ---







        // --- NTT 控制接口虚拟线网 ---






        // --- RAM u 0 虚拟线网 ---






        
        // --- RAM u 1 虚拟线网 ---







        // --- RAM v 虚拟线网 ---







        // --- OTHERS 虚拟线网 ---



//状态编码
    //wire code_state;

    //keccak输入判断



    assign keccak_in     = (jud_s||jud_e) ? data_r : (keccak_in_jud ? ((stage== keygen)? data_A : data_A_t) : 0);
    assign keccak_in_vld = keccak_op[2:0];
    assign keccak_mod    = keccak_op[5:3];
    assign keccak_start  = keccak_op[6];
    assign keccak_over   = keccak_op[7];
    





       //标志信号




















//明文输入


    //寄存明文数据
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            data_m <= 0;            
        end
        else if (din_vld) begin
            data_m <= m_in;
        end
    end
    //[q/2]*m,m=1,为1665.m=0,为0
    assign data_m_aft = data_m[ramv_addr_b_temp] ? 1665 : 0;

//种子输入
    //矩阵A







    assign data_A   = {pho_A,6'd0,col_cnt,6'd0,row_cnt};
    assign data_A_t = {pho_A,6'd0,row_cnt,6'd0,col_cnt};
    assign data_r   = {pho_r,cnt_n};
    
    //锁存输入的种子
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pho_A <= 0;
            pho_r <= 0;
            
        end
        else begin
            pho_A <= data_in_A;
            pho_r <= data_in_r;
        end
    end
         //assign cnt_t         = cnt_plus ? 0 : 1;

//操作编码逻辑
    //reg [2:0] stage;









    assign switch = (gen_done||(!gen_ing))&&(caucl_done||(!caucl_ing)); //单任务可以只看一边，并行双任务两边均输出done才拉升


















       
        // --- Squeeze Buffer MUX ---
        //assign squeze_din     = (stage == keygen) ? squeze_din_kg     :
        //                        (stage == encaps) ? squeze_din_enc    : 
        //                        (stage == decaps) ? squeze_din_dec    : 0;
        //
        //assign squeze_din_vld = (stage == keygen) ? squeze_din_vld_kg :
        //                        (stage == encaps) ? squeze_din_vld_enc: 
        //                        (stage == decaps) ? squeze_din_vld_dec: 0;
        
        // --- Reject Sampler MUX ---
        assign rej_in_vld = (stage == keygen) ? rej_in_vld_kg : (stage == encaps) ? rej_in_vld_enc : (stage == decaps) ? rej_in_vld_dec : 0;
        assign rej_in_1   = (stage == keygen) ? rej_in_1_kg   : (stage == encaps) ? rej_in_1_enc   : (stage == decaps) ? rej_in_1_dec   : 0;
        assign rej_in_2   = (stage == keygen) ? rej_in_2_kg   : (stage == encaps) ? rej_in_2_enc   : (stage == decaps) ? rej_in_2_dec   : 0;
        assign rej_in_3   = (stage == keygen) ? rej_in_3_kg   : (stage == encaps) ? rej_in_3_enc   : (stage == decaps) ? rej_in_3_dec   : 0;
        
        // --- CBD Sampler MUX ---
        assign cbd_in_vld = (stage == keygen) ? cbd_in_vld_kg : (stage == encaps) ? cbd_in_vld_enc : (stage == decaps) ? cbd_in_vld_dec : 0;
        assign cbd_in     = (stage == keygen) ? cbd_in_kg     : (stage == encaps) ? cbd_in_enc     : (stage == decaps) ? cbd_in_dec     : 0;
        
        // --- RAM A MUX ---
        assign ramA_we_a   = (stage == keygen) ? ramA_we_a_kg   : (stage == encaps) ? ramA_we_a_enc   : (stage == decaps) ? ramA_we_a_dec   : 0;
        assign ramA_we_b   = (stage == keygen) ? ramA_we_b_kg   : (stage == encaps) ? ramA_we_b_enc   : (stage == decaps) ? ramA_we_b_dec   : 0;
        assign ramA_addr_a = (stage == keygen) ? ramA_addr_a_kg : (stage == encaps) ? ramA_addr_a_enc : (stage == decaps) ? ramA_addr_a_dec : 0;
        assign ramA_addr_b = (stage == keygen) ? ramA_addr_b_kg : (stage == encaps) ? ramA_addr_b_enc : (stage == decaps) ? ramA_addr_b_dec : 0;
        assign ramA_din_a  = (stage == keygen) ? ramA_din_a_kg  : (stage == encaps) ? ramA_din_a_enc  : (stage == decaps) ? ramA_din_a_dec  : 0;
        assign ramA_din_b  = (stage == keygen) ? ramA_din_b_kg  : (stage == encaps) ? ramA_din_b_enc  : (stage == decaps) ? ramA_din_b_dec  : 0;
        
        // --- RAM S 0 MUX ---
        assign rams_we_a[0]   = (stage == keygen) ? rams_we_a_kg_0   : (stage == encaps) ? rams_we_a_enc_0   : (stage == decaps) ? rams_we_a_dec_0   : 0;
        assign rams_we_b[0]   = (stage == keygen) ? rams_we_b_kg_0   : (stage == encaps) ? rams_we_b_enc_0   : (stage == decaps) ? rams_we_b_dec_0   : 0;
        assign rams_addr_a[0] = (stage == keygen) ? rams_addr_a_kg_0 : (stage == encaps) ? rams_addr_a_enc_0 : (stage == decaps) ? rams_addr_a_dec_0 : 0;
        assign rams_addr_b[0] = (stage == keygen) ? rams_addr_b_kg_0 : (stage == encaps) ? rams_addr_b_enc_0 : (stage == decaps) ? rams_addr_b_dec_0 : 0;
        assign rams_din_a[0]  = (stage == keygen) ? rams_din_a_kg_0  : (stage == encaps) ? rams_din_a_enc_0  : (stage == decaps) ? rams_din_a_dec_0  : 0;
        assign rams_din_b[0]  = (stage == keygen) ? rams_din_b_kg_0  : (stage == encaps) ? rams_din_b_enc_0  : (stage == decaps) ? rams_din_b_dec_0  : 0;
        
        // --- RAM S 1 MUX ---
        assign rams_we_a[1]   = (stage == keygen) ? rams_we_a_kg_1   : (stage == encaps) ? rams_we_a_enc_1   : (stage == decaps) ? rams_we_a_dec_1   : 0;
        assign rams_we_b[1]   = (stage == keygen) ? rams_we_b_kg_1   : (stage == encaps) ? rams_we_b_enc_1   : (stage == decaps) ? rams_we_b_dec_1   : 0;
        assign rams_addr_a[1] = (stage == keygen) ? rams_addr_a_kg_1 : (stage == encaps) ? rams_addr_a_enc_1 : (stage == decaps) ? rams_addr_a_dec_1 : 0;
        assign rams_addr_b[1] = (stage == keygen) ? rams_addr_b_kg_1 : (stage == encaps) ? rams_addr_b_enc_1 : (stage == decaps) ? rams_addr_b_dec_1 : 0;
        assign rams_din_a[1]  = (stage == keygen) ? rams_din_a_kg_1  : (stage == encaps) ? rams_din_a_enc_1  : (stage == decaps) ? rams_din_a_dec_1  : 0;
        assign rams_din_b[1]  = (stage == keygen) ? rams_din_b_kg_1  : (stage == encaps) ? rams_din_b_enc_1  : (stage == decaps) ? rams_din_b_dec_1  : 0;
        
        // --- RAM E MUX ---
        assign rame_we_a   = (stage == keygen) ? rame_we_a_kg   : (stage == encaps) ? rame_we_a_enc   : (stage == decaps) ? rame_we_a_dec   : 0;
        assign rame_we_b   = (stage == keygen) ? rame_we_b_kg   : (stage == encaps) ? rame_we_b_enc   : (stage == decaps) ? rame_we_b_dec   : 0;
        assign rame_addr_a = (stage == keygen) ? rame_addr_a_kg : (stage == encaps) ? rame_addr_a_enc : (stage == decaps) ? rame_addr_a_dec : 0;
        assign rame_addr_b = (stage == keygen) ? rame_addr_b_kg : (stage == encaps) ? rame_addr_b_enc : (stage == decaps) ? rame_addr_b_dec : 0;
        assign rame_din_a  = (stage == keygen) ? rame_din_a_kg  : (stage == encaps) ? rame_din_a_enc  : (stage == decaps) ? rame_din_a_dec  : 0;
        assign rame_din_b  = (stage == keygen) ? rame_din_b_kg  : (stage == encaps) ? rame_din_b_enc  : (stage == decaps) ? rame_din_b_dec  : 0;
        
        // --- RAM 4 MUX ---
        assign ram4_we_a = (stage == keygen) ? ram4_we_a_kg : (stage == encaps) ? ram4_we_a_enc : (stage == decaps) ? ram4_we_a_dec : 0;
        assign ram4_we_b = (stage == keygen) ? ram4_we_b_kg : (stage == encaps) ? ram4_we_b_enc : (stage == decaps) ? ram4_we_b_dec : 0;
        assign ram4_addr_a = (stage == keygen) ? ram4_addr_a_kg : (stage == encaps) ? ram4_addr_a_enc : (stage == decaps) ? ram4_addr_a_dec : 0;
        assign ram4_addr_b = (stage == keygen) ? ram4_addr_b_kg : (stage == encaps) ? ram4_addr_b_enc : (stage == decaps) ? ram4_addr_b_dec : 0;
        
        // --- RAM T 0 MUX ---
        assign ramt_we_a[0]   = (stage == keygen) ? ramt_we_a_kg_0   : (stage == encaps) ? ramt_we_a_enc_0   : (stage == decaps) ? ramt_we_a_dec_0   : 0;
        assign ramt_we_b[0]   = (stage == keygen) ? ramt_we_b_kg_0   : (stage == encaps) ? ramt_we_b_enc_0   : (stage == decaps) ? ramt_we_b_dec_0   : 0;
        assign ramt_addr_a[0] = (stage == keygen) ? ramt_addr_a_kg_0 : (stage == encaps) ? ramt_addr_a_enc_0 : (stage == decaps) ? ramt_addr_a_dec_0 : 0;
        assign ramt_addr_b[0] = (stage == keygen) ? ramt_addr_b_kg_0 : (stage == encaps) ? ramt_addr_b_enc_0 : (stage == decaps) ? ramt_addr_b_dec_0 : 0;
        assign ramt_din_a[0]  = (stage == keygen) ? ramt_din_a_kg_0  : (stage == encaps) ? ramt_din_a_enc_0  : (stage == decaps) ? ramt_din_a_dec_0  : 0;
        assign ramt_din_b[0]  = (stage == keygen) ? ramt_din_b_kg_0  : (stage == encaps) ? ramt_din_b_enc_0  : (stage == decaps) ? ramt_din_b_dec_0  : 0;
        
        // --- RAM T 1 MUX ---
        assign ramt_we_a[1]   = (stage == keygen) ? ramt_we_a_kg_1   : (stage == encaps) ? ramt_we_a_enc_1   : (stage == decaps) ? ramt_we_a_dec_1   : 0;
        assign ramt_we_b[1]   = (stage == keygen) ? ramt_we_b_kg_1   : (stage == encaps) ? ramt_we_b_enc_1   : (stage == decaps) ? ramt_we_b_dec_1   : 0;
        assign ramt_addr_a[1] = (stage == keygen) ? ramt_addr_a_kg_1 : (stage == encaps) ? ramt_addr_a_enc_1 : (stage == decaps) ? ramt_addr_a_dec_1 : 0;
        assign ramt_addr_b[1] = (stage == keygen) ? ramt_addr_b_kg_1 : (stage == encaps) ? ramt_addr_b_enc_1 : (stage == decaps) ? ramt_addr_b_dec_1 : 0;
        assign ramt_din_a[1]  = (stage == keygen) ? ramt_din_a_kg_1  : (stage == encaps) ? ramt_din_a_enc_1  : (stage == decaps) ? ramt_din_a_dec_1  : 0;
        assign ramt_din_b[1]  = (stage == keygen) ? ramt_din_b_kg_1  : (stage == encaps) ? ramt_din_b_enc_1  : (stage == decaps) ? ramt_din_b_dec_1  : 0;

        // --- NTT Core MUX ---
        assign ntt_din_vld   = (stage == keygen) ? ntt_din_vld_kg   : (stage == encaps) ? ntt_din_vld_enc   : (stage == decaps) ? ntt_din_vld_dec   : 0;
        assign ntt_ram1_in_1 = (stage == keygen) ? ntt_ram1_in_1_kg : (stage == encaps) ? ntt_ram1_in_1_enc : (stage == decaps) ? ntt_ram1_in_1_dec : 0;
        assign ntt_ram1_in_2 = (stage == keygen) ? ntt_ram1_in_2_kg : (stage == encaps) ? ntt_ram1_in_2_enc : (stage == decaps) ? ntt_ram1_in_2_dec : 0;
        assign ntt_ram3_in_1 = (stage == keygen) ? ntt_ram3_in_1_kg : (stage == encaps) ? ntt_ram3_in_1_enc : (stage == decaps) ? ntt_ram3_in_1_dec : 0;
        assign ntt_ram3_in_2 = (stage == keygen) ? ntt_ram3_in_2_kg : (stage == encaps) ? ntt_ram3_in_2_enc : (stage == decaps) ? ntt_ram3_in_2_dec : 0;

        //  --- RAM u 0 MUX ---
        assign ramu_we_a[0]   = (stage == encaps)? ramu_we_a_enc_0 : (stage == decaps)? ramu_we_a_dec_0 : 0;
        assign ramu_we_b[0]   = (stage == encaps)? ramu_we_b_enc_0 : (stage == decaps)? ramu_we_b_dec_0 : 0;
        assign ramu_addr_a[0] = (stage == encaps)? ramu_addr_a_enc_0 :(stage == decaps)? ramu_addr_a_dec_0 : 0;
        assign ramu_addr_b[0] = (stage == encaps)? ramu_addr_b_enc_0 :(stage == decaps)? ramu_addr_b_dec_0 : 0;
        assign ramu_din_a[0]  = (stage == encaps)? ramu_din_a_enc_0 : (stage == decaps)? ramu_we_a_dec_0 : 0;
        assign ramu_din_b[0]  = (stage == encaps)? ramu_din_b_enc_0 : (stage == decaps)? ramu_we_b_dec_0 : 0;

        //  --- RAM u 1 MUX ---
        assign ramu_we_a[1]   = (stage == encaps)? ramu_we_a_enc_1 :(stage == decaps)? ramu_we_a_dec_1 : 0; 
        assign ramu_we_b[1]   = (stage == encaps)? ramu_we_b_enc_1 :(stage == decaps)? ramu_we_b_dec_1 : 0;
        assign ramu_addr_a[1] = (stage == encaps)? ramu_addr_a_enc_1 :(stage == decaps)? ramu_addr_a_dec_1 : 0;
        assign ramu_addr_b[1] = (stage == encaps)? ramu_addr_b_enc_1 :(stage == decaps)? ramu_addr_b_dec_1 : 0;
        assign ramu_din_a[1]  = (stage == encaps)? ramu_din_a_enc_1 :(stage == decaps)? ramu_din_a_dec_1 : 0;
        assign ramu_din_b[1]  = (stage == encaps)? ramu_din_b_enc_1 :(stage == decaps)? ramu_din_b_dec_1 : 0;

        //  --- RAM v MUX ---
        assign ramv_we_a   = (stage == encaps)? ramv_we_a_enc : 0; 
        assign ramv_we_b   = (stage == encaps)? ramv_we_b_enc : 0;
        assign ramv_addr_a = (stage == encaps)? ramv_addr_a_enc : 0;
        assign ramv_addr_b = (stage == encaps)? ramv_addr_b_enc : 0;
        assign ramv_din_a  = (stage == encaps)? ramv_din_a_enc : 0;
        assign ramv_din_b  = (stage == encaps)? ramv_din_b_enc : 0;

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
            assign rej_in_vld_kg     = jud_A? squeze_dout_2_vld:0; //一次输入三字节
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
            assign cbd_in_vld_kg        = (jud_s||jud_e) ? squeze_dout_1_vld : 0;    
            assign cbd_in_kg            = (jud_s||jud_e) ? squeze_dout_1 : 0;        //一次输入一字节
            assign rams_we_a_kg_0      = cnt_s? 0 : (jud_s ? cbd_out_vld : 1'b0); 
            assign rams_we_b_kg_0      = cnt_s? 0 : (jud_s ? cbd_out_vld : 1'b0);
            assign rams_addr_a_kg_0    = cnt_s? 0 : (jud_s ? cbd_add_1 : (jud_mult ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}}));
            assign rams_addr_b_kg_0    = cnt_s? 0 : (jud_s ? cbd_add_2 : (jud_mult ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}}));
            assign rams_din_a_kg_0     = cnt_s? 0 : (jud_s ? cbd_out_1 : (jud_mult ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}}));
            assign rams_din_b_kg_0     = cnt_s? 0 : (jud_s ? cbd_out_2 : (jud_mult ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}}));
            assign rams_we_a_kg_1      = cnt_s? (jud_s ? cbd_out_vld : 1'b0) : 0; 
            assign rams_we_b_kg_1      = cnt_s? (jud_s ? cbd_out_vld : 1'b0) : 0;
            assign rams_addr_a_kg_1    = cnt_s? (jud_s ? cbd_add_1 : (jud_mult ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}})) : 0;
            assign rams_addr_b_kg_1    = cnt_s? (jud_s ? cbd_add_2 : (jud_mult ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}})) : 0;
            assign rams_din_a_kg_1     = cnt_s? (jud_s ? cbd_out_1 : (jud_mult ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}})) : 0;
            assign rams_din_b_kg_1     = cnt_s? (jud_s ? cbd_out_2 : (jud_mult ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}})) : 0;
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量e0,向量e0传入rame
            assign rame_we_a_kg         = jud_e ? cbd_out_vld : 0; 
            assign rame_we_b_kg         = jud_e ? cbd_out_vld : 0;
            assign rame_addr_a_kg       = jud_e ? cbd_add_1 : (jud_plus_1 ? rame_addr_a_temp : 0);
            assign rame_addr_b_kg       = jud_e ? cbd_add_2 : (jud_plus_1 ? rame_addr_b_temp : 0);
            assign rame_din_a_kg        = jud_e ? cbd_out_1 : 0;
            assign rame_din_b_kg        = jud_e ? cbd_out_2 : 0;
        //将矩阵A与s相乘
            assign ntt_din_vld_kg    = jud_mult? 1 : 0;
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
            assign ramt_we_a_kg_0 = jud_plus_2? (cnt_t ? 0 : 0) : (jud_plus_1 ? !cnt_t : 0);
            assign ramt_we_b_kg_0 = jud_plus_2? (cnt_t ? 0 : 1) : (jud_plus_1 ? !cnt_t : 0);
            assign ramt_we_a_kg_1 = jud_plus_2? (cnt_t ? 0 : 0) : (jud_plus_1 ? cnt_t : 0);
            assign ramt_we_b_kg_1 = jud_plus_2? (cnt_t ? 1 : 0) : (jud_plus_1 ? cnt_t : 0);
            //assign rame_we_a = 0;
            //assign rame_we_b = 0;
    
            assign ramt_din_a_kg_0 = (jud_plus_1 ? (cnt_t ? 0 : data_a_temp) : 0);
            assign ramt_din_b_kg_0 = (jud_plus_1||jud_plus_2) ? (cnt_t? 0 : data_b_temp) : 0;
            assign ramt_din_a_kg_1 = (jud_plus_1 ? (cnt_t ? data_a_temp : 0) : 0);
            assign ramt_din_b_kg_1 = (jud_plus_1||jud_plus_2) ? (cnt_t? data_b_temp : 0) : 0;

                    
            assign data_a_temp_kg = ram4_dout_a + rame_dout_a;
            assign data_b_temp_kg = jud_plus_2? (ram4_dout_b+ramt_dout_a[cnt_t]) : (ram4_dout_b + rame_dout_b);
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
            assign rej_in_vld_enc     = jud_A? squeze_dout_2_vld:0; //一次输入三字节
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
            assign cbd_in_vld_enc        = (jud_y||jud_e) ? squeze_dout_1_vld : 0;    
            assign cbd_in_enc            = (jud_y||jud_e) ? squeze_dout_1 : 0;        //一次输入一字节
            assign ramy_we_a             = (jud_y ? cbd_out_vld : 1'b0); 
            assign ramy_we_b             = (jud_y ? cbd_out_vld : 1'b0);
            assign ramy_addr_a           = (jud_y ? cbd_add_1 : (jud_mult ? ntt_ram3_cnt_1 : {ADDR_WIDTH{1'b0}}));
            assign ramy_addr_b           = (jud_y ? cbd_add_2 : (jud_mult ? ntt_ram3_cnt_2 : {ADDR_WIDTH{1'b0}}));
            assign ramy_din_a            = (jud_y ? cbd_out_1 : ((jud_mult||jud_mult_2) ? ntt_ram3_in_1 : {DATA_WIDTH{1'b0}}));
            assign ramy_din_b            = (jud_y ? cbd_out_2 : ((jud_mult||jud_mult_2) ? ntt_ram3_in_2 : {DATA_WIDTH{1'b0}}));
        //种子输入keccak,调用shake-256处理种子
        //处理后种子输入buffer，传入cbd_sample生成向量e0,向量e0传入rame
            assign rame_we_a_enc         = jud_e ? cbd_out_vld : 0; 
            assign rame_we_b_enc         = jud_e ? cbd_out_vld : 0;
            assign rame_addr_a_enc       = jud_e ? cbd_add_1 : ((jud_plus_1||jud_plus_3) ? rame_addr_a_temp : 0);
            assign rame_addr_b_enc       = jud_e ? cbd_add_2 : ((jud_plus_1||jud_plus_3) ? rame_addr_b_temp : 0);
            assign rame_din_a_enc        = jud_e ? cbd_out_1 : 0;
            assign rame_din_b_enc        = jud_e ? cbd_out_2 : 0;
        //将矩阵A与y相乘
            assign ntt_din_vld_enc    = jud_mult? 1 : 0;
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
            assign ramu_we_a_enc_0 = jud_plus_2? (cnt_t ? 0 : 0) : (jud_plus_1 ? !cnt_t : 0);
            assign ramu_we_b_enc_0 = jud_plus_2? (cnt_t ? 0 : 1) : (jud_plus_1 ? !cnt_t : 0);
            assign ramu_we_a_enc_1 = jud_plus_2? (cnt_t ? 0 : 0) : (jud_plus_1 ? cnt_t : 0);
            assign ramu_we_b_enc_1 = jud_plus_2? (cnt_t ? 1 : 0) : (jud_plus_1 ? cnt_t : 0);
            //assign rame_we_a = 0;
            //assign rame_we_b = 0;
    
            assign ramu_din_a_enc_0 = (jud_plus_1 ? (cnt_t ? 0 : data_a_temp) : 0);
            assign ramu_din_b_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t? 0 : data_b_temp) : (jud_plus_3? (cnt_t? 0 : data_b_temp) : 0);
            assign ramu_din_a_enc_1 = (jud_plus_1 ? (cnt_t ? data_a_temp : 0) : 0);
            assign ramu_din_b_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t? data_b_temp : 0) : (jud_plus_3? (cnt_t? data_b_temp : 0) : 0);

                    
            assign data_a_temp_enc = jud_plus_4 ? (ram4_dout_a + data_m_aft) : (ram4_dout_a + rame_dout_a);
            assign data_b_temp_enc = jud_plus_4 ? (ram4_dout_b + data_m_aft) : (jud_plus_2? (ram4_dout_b+ramt_dout_a[cnt_t]) : (ram4_dout_b + rame_dout_b));
            assign ram4_addr_a_enc = (jud_plus_1||jud_plus_2||jud_plus_3) ? ram4_addr_a_temp : ntt_ram4_addr_a;
            assign ram4_addr_b_enc = jud_plus_1 ? ram4_addr_b_temp : ntt_ram4_addr_b;
    
            assign ramu_addr_a_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_a_temp) : 0;
            assign ramu_addr_b_enc_0 = (jud_plus_1||jud_plus_2) ? (cnt_t ? 0 :ramt_addr_b_temp) : 0;
            assign ramu_addr_a_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_a_temp : 0) : 0;
            assign ramu_addr_b_enc_1 = (jud_plus_1||jud_plus_2) ? (cnt_t ? ramt_addr_b_temp : 0) : 0;

        //当执行t*y后，将数据+[q/2]m后，存入ramv中
            //assign ram4_we_a_enc = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_a;
            //assign ram4_we_b_enc = (jud_plus_1||jud_plus_2) ? 0 : ntt_ram4_we_b;
            assign ramt_we_a_enc_0 = 0;
            assign ramt_we_a_enc_0 = 0;
            assign ramt_addr_a_dec_0 = (jud_mult_2 && !count_t)? ntt_ram1_cnt_1 : 0;
            assign ramt_addr_b_dec_0 = (jud_mult_2 && !count_t)? ntt_ram1_cnt_2 : 0;
            assign ramt_addr_a_dec_1 = (jud_mult_2 && count_t) ? 0 : ntt_ram1_cnt_1;
            assign ramt_addr_b_dec_1 = (jud_mult_2 && count_t) ? 0 : ntt_ram1_cnt_2;

            assign ramv_we_a_enc   = jud_plus_4 ? 1 : 0;
            assign ramv_we_b_enc   = jud_plus_4 ? 1 : 0;
            assign ramv_addr_a_enc = jud_plus_4 ? ramv_addr_a_temp : 0;
            assign ramv_addr_b_enc = jud_plus_4 ? ramv_addr_b_temp : 0;
            assign ramv_din_a_enc  = jud_plus_4 ? data_a_temp : 0;
            assign ramv_din_b_enc  = jud_plus_4 ? data_b_temp : (jud_plus_3 ? (ramv_dout_a + ram4_dout_a + rame_dout_a)  : 0);
    //decaps
        //矩阵v与t相乘
            assign ntt_din_vld_dec    = jud_mult? 1 : 0;
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
            assign data_a_temp_dec = (ramv_dout_a >= ram4_dout_a)? (ramv_dout_a - ram4_dout_a) : (ramv_dout_a - ram4_dout_a + q);
            assign data_b_temp_dec = (ramv_dout_b >= ram4_dout_b)? (ramv_dout_b - ram4_dout_b) : (ramv_dout_b - ram4_dout_b + q);

            assign ramv_we_a_dec = 0;
            assign ramv_we_a_dec = 0;
            assign ramv_addr_a_dec = ramv_addr_a_temp;
            assign ramv_addr_b_dec = ramv_addr_b_temp;

            assign ram4_we_a_dec = 0;
            assign ram4_we_b_dec = 0;
            assign ram4_addr_a_dec = ram4_addr_a_temp;
            assign ram4_addr_b_dec = ram4_addr_b_temp;
            //借用rame暂存结果
            assign rame_we_a_dec   = jud_sub ? 1 : 0;
            assign rame_we_b_dec   = jud_sub ? 1 : 0;
            assign rame_addr_a_dec = rame_addr_a_temp;
            assign rame_addr_b_dec = rame_addr_b_temp;
            assign rame_din_a_dec  = data_a_temp;
            assign rame_din_b_dec  = data_b_temp;


//向量生成操作
    always @(*) begin
        // [EXAMPLE] 完整默认赋值：本块只拥有生成路径的组合控制。
        keccak_in_jud = 1'b0;
        keccak_op = 8'd0;
        jud_A = 1'b0;
        jud_s = 1'b0;
        jud_y = 1'b0;
        jud_e = 1'b0;
        case(stage)
            keygen:begin
                    case(stage_gen)
                        stage_reset:begin
                            keccak_in_jud = 0;                     //keccak输入接至模块外部输入
                            keccak_op     = 0; 
                            jud_A         = 0;
                            jud_s         = 0;
                            jud_y         = 0;
                            jud_e         = 0;
                            //jud_mult      = 0;
                        end
                        stage_A:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            keccak_op     = {1'b1,3'd1,1'b1,3'b1}; 
                            jud_A         = 1;
                            jud_s         = 0;
                            jud_y         = 0;
                            jud_e         = 0;
                            //jud_mult      = 0;
                            //move_start    = 0;
                            //move_stage    = 0;
                            //cnt_t         = 0;
                            //复位输出标志信号




                        end
                        stage_s:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            keccak_op     = {1'b1,3'd2,1'b1,3'b1}; 
                            jud_A         = 0;
                            jud_s         = 1;
                            jud_y         = 0;
                            jud_e         = 0;
                            //jud_mult      = 0;
                            //move_start    = 0;
                            //move_stage    = 0;
                            //cnt_t         = 0;
                        end
                        stage_e:begin
                            keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                            keccak_op     = {1'b1,3'd2,1'b1,3'b1}; 
                            jud_A         = 0;
                            jud_s         = 0;
                            jud_y         = 0;
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
                    keccak_op     = 0; 
                    jud_A         = 0;
                    jud_s         = 0;
                    jud_y         = 0;
                    jud_e         = 0;
                    //jud_mult      = 0;
                end
                stage_A:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    keccak_op     = {1'b1,3'd1,1'b1,3'b1}; 
                    jud_A         = 1;
                    jud_s         = 0;
                    jud_y         = 0;
                    jud_e         = 0;
                    //jud_mult      = 0;
                    //move_start    = 0;
                    //move_stage    = 0;
                    //复位输出标志信号




                end
                stage_y:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    keccak_op     = {1'b1,3'd2,1'b1,3'b1}; 
                    jud_A         = 0;
                    jud_s         = 0;
                    jud_y         = 1;
                    jud_e         = 0;
                    //jud_mult      = 0;
                end
                stage_e:begin
                    keccak_in_jud = 1;                     //keccak输入接至模块外部输入
                    keccak_op     = {1'b1,3'd2,1'b1,3'b1}; 
                    jud_A         = 0;
                    jud_s         = 0;
                    jud_y         = 0;
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
    always @(*) begin
    // [EXAMPLE] 本块只拥有计算/搬移的组合控制，非法模式默认为不操作。
    jud_mult = 1'b0;
    jud_mult_2 = 1'b0;
    jud_plus_1 = 1'b0;
    jud_plus_2 = 1'b0;
    jud_plus_3 = 1'b0;
    jud_plus_4 = 1'b0;
    jud_sub = 1'b0;
    move_start = 1'b0;
    move_stage = 3'd0;
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
                    //cnt_t         = 0;
                    jud_plus_1    = 0;
                    jud_plus_2    = 0;
                    jud_plus_3    = 0;
                    move_start    = 0;
                    move_stage    = 0;
                    //cnt_t         = 0;
                end 
                stage_plus_1:begin
                    jud_mult      = 0;
                    //cnt_t         = 0;
                    jud_plus_1    = 1;
                    jud_plus_2    = 0;
                    jud_plus_3    = 0;
                    move_start    = 1;
                    move_stage    = 1;
                end
                stage_plus_2:begin
                    jud_mult      = 1;
                    jud_plus_1    = 0;
                    jud_plus_2    = 1;
                    jud_plus_3    = 0;
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
                    jud_plus_1 = 0;
                    jud_plus_2 = 0;
                    jud_plus_3 = 0;
                    move_start = 0;
                    move_stage = 0;
                    jud_mult_2 = 0;
                    jud_plus_4 = 0;
                end
                stage_plus_1:begin
                    jud_mult   = 0;
                    jud_plus_1 = 1;
                    jud_plus_2 = 0;
                    jud_plus_3 = 0;
                    move_start = 1;
                    move_stage = 1;
                    jud_mult_2 = 0;
                    jud_plus_4 = 0;
                end
                stage_plus_2:begin
                    jud_mult   = 1;
                    jud_plus_1 = 0;
                    jud_plus_2 = 1;
                    jud_plus_3 = 0;
                    move_start = 1;
                    move_stage = 2;
                    jud_mult_2 = 0;
                    jud_plus_4 = 0;
                end
                stage_plus_3:begin
                    jud_mult   = 1;
                    jud_plus_1 = 0;
                    jud_plus_2 = 0;
                    jud_plus_3 = 1;
                    move_start = 1;
                    move_stage = 3;
                    jud_mult_2 = 0;
                    jud_plus_4 = 0;
                end
                //修改后的补充状态，用于计算t*y
                stage_mult_2:begin
                    jud_mult   = 0;
                    jud_plus_1 = 0;
                    jud_plus_2 = 0;
                    jud_plus_3 = 0;
                    move_start = 0;
                    move_stage = 0;
                    jud_mult_2 = 1;
                    jud_plus_4 = 0;
                end
                stage_plus_4:begin
                    jud_mult   = 0;
                    jud_plus_1 = 0;
                    jud_plus_2 = 0;
                    jud_plus_3 = 0;
                    move_start = 1;
                    move_stage = 4;
                    jud_mult_2 = 0;
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
                    jud_sub    = 0;
                    move_start = 0;
                    move_stage = 0;
                end
                stage_sub:begin
                    jud_mult   = 1;
                    jud_sub    = 0;
                    move_start = 0;
                    move_stage = 5;
                end

            endcase
        end
    endcase
    end

// [EXAMPLE] 唯一时序所有者：原三个时序 always 合并到这里。
// 优先级（低 -> 高）：地址移动 -> 生成调度 -> 计算调度。
// 同一拍执行多条针对同一寄存器的 <= 时，以本块最后执行的一条为准。
// 三个区域都读取旧状态，不会因文本顺序而多出一个时钟周期。
// 此优先级是示例设计选择，不宣称与原多驱动代码等价。
    always @(posedge clk or negedge rst) begin : unified_scheduler
        if (!rst) begin
            stage_gen <= stage_reset;
            stage_caucl <= stage_reset;
            gen_ing <= 1'b0;
            gen_done <= 1'b0;
            caucl_ing <= 1'b0;
            caucl_done <= 1'b0;
            cnt_A <= 0;
            cnt_n <= 0;
            col_cnt <= 0;
            row_cnt <= 0;
            cnt_s <= 0;
            cnt_t <= 0;
            cnt_y <= 0;
            cnt_u <= 0;
            count_t <= 0;
            finish_keygen <= 0;
            finish_encaps <= 0;
            finish_decaps <= 0;
            out_vld <= 0;
            ram4_addr_a_temp <= 0;
            ram4_addr_b_temp <= 1;
            ramt_addr_a_temp <= 0;
            ramt_addr_b_temp <= 1;
            rame_addr_a_temp <= 0;
            rame_addr_b_temp <= 1;
            ramv_addr_a_temp <= 0;
            ramv_addr_b_temp <= 1;
            ramt_addr_a_temp_delay[0] <= 0;
            ramt_addr_a_temp_delay[1] <= 0;
            ramv_addr_a_temp_delay[0] <= 0;
            ramv_addr_a_temp_delay[1] <= 0;
        end else begin
            // 原组合块中的状态清零移到此处，成为同步清零。
            // 完成标志沿用“保持到清零条件”的语义，不擅自改为单拍脉冲。
            // 本拍完成事件优先于这里的清零。
            if (((stage == keygen) || (stage == encaps)) &&
                (stage_gen == stage_A)) begin
                finish_keygen <= 0;
                finish_encaps <= 0;
                finish_decaps <= 0;
                out_vld <= 0;
            end

            // 1. 地址移动：cnt_t 的自动翻转优先级最低。
            if (move_start) begin
case(move_stage)
                1'd1: begin
                    ram4_addr_a_temp <= ram4_addr_a_temp + 2;
                    ram4_addr_b_temp <= ram4_addr_b_temp + 2;
                    ramt_addr_a_temp <= ramt_addr_a_temp + 2;
                    ramt_addr_b_temp <= ramt_addr_b_temp + 2;
                    rame_addr_a_temp <= rame_addr_a_temp + 2;
                    rame_addr_b_temp <= rame_addr_b_temp + 2;
                end
                3'd2:begin
                    ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                    ramt_addr_a_temp <= ramt_addr_a_temp + 1;
                    ramt_addr_a_temp_delay[0] <= ramt_addr_a_temp;
                    ramt_addr_a_temp_delay[1] <= ramt_addr_a_temp_delay[0];    
                    ramt_addr_b_temp          <= ramt_addr_a_temp_delay[1]; 
                    if ((ramt_addr_b_temp == 255) && (stage == keygen)) begin
                           cnt_t <= !cnt_t;
                       end   
                end
                3'd3:begin
                    rame_addr_a_temp <= rame_addr_a_temp + 1;
                    ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                    ramv_addr_a_temp <= ramv_addr_a_temp + 1;
                    ramv_addr_a_temp_delay[0] <= ramv_addr_a_temp;
                    ramv_addr_a_temp_delay[1] <= ramv_addr_a_temp_delay[0];    
                    ramv_addr_b_temp          <= ramv_addr_a_temp_delay[1]; 
                end
                3'd4:begin
                    ram4_addr_a_temp <= ram4_addr_a_temp + 1;
                    ram4_addr_b_temp <= ram4_addr_b_temp + 1;
                    ramv_addr_a_temp <= ramv_addr_a_temp + 1;
                    ramv_addr_b_temp <= ramv_addr_b_temp + 1;
                end
                3'd5:begin
                    ram4_addr_a_temp <= ram4_addr_a_temp + 2;
                    ram4_addr_b_temp <= ram4_addr_b_temp + 2;
                    ramt_addr_a_temp <= ramt_addr_a_temp + 2;
                    ramt_addr_b_temp <= ramt_addr_b_temp + 2;
                    rame_addr_a_temp <= rame_addr_a_temp + 2;
                    rame_addr_b_temp <= rame_addr_b_temp + 2;
                end
            endcase
            end

            // 2. 生成调度：保留当前源码新增的 stage_reset 嵌套计算跳转。
            // 显式选行覆盖上方 cnt_t 自动翻转。
case(stage)
                keygen:begin
                    case(stage_gen)
                        stage_reset:begin
                            gen_ing  <= 0;
                            gen_done <= 0;
                            case(stage_caucl)
                                stage_plus_1:begin
                                    if (switch && (cnt_A == 3)) begin
                                        stage_caucl <= 3; //转至第二类加法
                                    end
                                end
                                stage_plus_2:begin
                                    if (switch && (cnt_A == 3)) begin
                                        stage_caucl   <= 0; //计算完成,恢复至初始状态
                                        finish_keygen <= 1;
                                        out_vld       <= 1;
                                        /////////////////////////////////////////
                                        //keygen计算完成
                                        ////////////////////////////////////////
                                    end
                                end
                            endcase
                        end
                        stage_A:begin
                           if (ramA_addr_b == 255) begin
                                gen_done <= 1;
                                //（row,col）先生成同一行数据，再换行生成
                                if (col_cnt && row_cnt) begin
                                    row_cnt <= 0;
                                    col_cnt <= 0;
                                end
                                else if (col_cnt) begin
                                    row_cnt <= row_cnt + 1;
                                    col_cnt <= 0;
                                end
                                else begin
                                    col_cnt <= col_cnt +1;
                                end    
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;         
                            end
                            if (switch) begin
                                if (!row_cnt && col_cnt) begin //生成A0,0之后跳转生成s0
                                    stage_gen <= 2;
                                end
                                else if (row_cnt && !col_cnt) begin //生成A0,1之后跳转生成e1;
                                    stage_gen   <= 3;
                                    cnt_n       <= 3;
                                    stage_caucl <= 2;              //跳转执行A0,1*S0
                                end
                                else if (row_cnt && col_cnt) begin
                                    cnt_t       <= 1; //改为求第二行t值
                                    stage_gen   <= 2;  //生成A1,0之后跳转生成s1;
                                    cnt_n       <= 1;
                                    cnt_s       <= 1;  
                                    stage_caucl <= 0;  //计算模块暂且停止

                                end
                                else if (!col_cnt && !row_cnt) begin
                                    stage_gen   <= 0; //生成模块暂时停止
                                    stage_caucl <= 2; //转至第一类加法 
                                end
                                else begin
                                    stage_gen <= 2; 
                                end             
                            end         
                        end 
                        stage_s:begin
                            if (rams_addr_b[cnt_s] == 255) begin
                                cnt_s    <= cnt_s + 1;
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;
                            end
                            if (switch) begin
                                if (cnt_n == 0) begin  
                                    cnt_n       <= 2;    //n值转至生成e0所需的值     
                                    stage_gen   <= 3;    //生成s0之后，跳转生成e0
                                    stage_caucl <= 1;    //计算模块转至A*S部分
                                end
                                else if (cnt_n == 1) begin
                                    stage_gen   <= 1; //转至A1,1
                                    cnt_A       <= 3;
                                    stage_caucl <= 1; //转至A1，0*S1 
                                end
                            end
                        end
                        stage_e:begin
                            if (rame_addr_b == 255) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;
                            end
                            if (switch) begin
                                if (cnt_n == 2) begin
                                    stage_gen   <= 1; //转至A0,1生成
                                    cnt_A       <= 1;
                                    stage_caucl <= 2; //转至第一类加法
                                end
                                else if (cnt_n == 3) begin
                                    stage_gen   <= 1; //转至A1,0生成
                                    cnt_A       <= 2;
                                    stage_caucl <= 3; //转至第二类加法
                                end
                            end
                        end 
                    endcase
                end
                encaps:begin
                    case(stage_gen)
                        stage_reset:begin
                            gen_ing  <= 0;
                            gen_done <= 0;
                            case(stage_caucl)
                                stage_plus_2:begin
                                    if (switch && (cnt_n == 4)) begin
                                        stage_caucl <= 5; //转至t1*y1，开始完成剩余的t*y的计算
                                    end 
                                end
                                stage_plus_3:begin
                                    if (switch && (cnt_n == 4)) begin
                                        stage_caucl   <= 0; //计算完成,恢复至初始状态
                                        finish_encaps <= 1;
                                        out_vld       <= 1;
                                        //////////////////////////////////
                                        //encaps计算完成
                                        /////////////////////////////////
                                    end
                                end
                            endcase
                        end
                        stage_A:begin
                            if (ramA_addr_b == 255) begin
                                gen_done <= 1;
                                //（row,col）先生成同一列数据，再生成同一行数据，为y腾空间
                                if (row_cnt&&col_cnt) begin
                                    col_cnt <= 0;
                                    row_cnt <= 0;
                                end
                                else if (row_cnt) begin
                                    col_cnt <= col_cnt + 1;
                                    row_cnt <= 0;
                                end
                            end
                            if (switch) begin
                                    if (!col_cnt && row_cnt) begin
                                        gen_done  <= 1;
                                        stage_gen <= 2; //生成y0
                                        cnt_n     <= 0;
                                    end
                                    else if (!row_cnt && col_cnt) begin
                                        gen_done  <= 1;
                                        //stage_gen <= 1;   //转至生成A0,1
                                        //stage_caucl <= 1; //转至生成A1,0*y0
                                        stage_gen   <= 0;   //暂时停止生成
                                        stage_caucl <= 1;   //转至t0*y0
                                    end
                                    else if (col_cnt && row_cnt) begin
                                        gen_done    <= 1;
                                        stage_gen   <= 2;  //转至生成y1
                                        cnt_n       <= 1; 
                                        stage_caucl <= 2;  //转至第一类加法
                                        cnt_t       <= 1;  //第二行
                                    end
                                    else begin
                                        gen_done  <= 1;
                                        stage_gen <= 3; //转而生成e2
                                        cnt_n     <= 4;
                                        stage_caucl <= 1; //转至生成A1,1*y
                                    end
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;
                            end
                        end
                        stage_y:begin
                            if (ramy_addr_b == 255) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;
                            end
                            if (switch) begin
                                if (cnt_n == 0) begin
                                    stage_gen   <= 3; //转至生成e1_0
                                    cnt_n       <= 2;
                                    stage_caucl <= 1; //转至A0,0*y0
                                end
                                else if (cnt_n == 1) begin
                                    stage_gen   <= 3; //转至生成e1_1
                                    cnt_n       <= 3;
                                    stage_caucl <= 1; //转至生成A0,1*y1
                                    cnt_y       <= 1; //y1
                                end
                            end
                        end
                        stage_e:begin
                            if (rame_addr_b == 255) begin
                                gen_done <= 1;
                            end
                            else begin
                                gen_ing  <= 1;
                                gen_done <= 0;
                            end
                            if (switch) begin
                                if (cnt_n == 2) begin
                                    stage_gen   <= 1; //转至生成A1,0
                                    stage_caucl <= 2; //转至第一类加法
                                    cnt_t       <= 0; //第一行
                                end
                                else if (cnt_n == 3) begin
                                    stage_gen   <= 1; //转至生成A1,1
                                    stage_caucl <= 3; //转至第二类加法
                                    cnt_t       <= 0; //第一行
                                end
                                else if (cnt_n == 4) begin
                                    stage_gen   <= 0; //后面没有需要生成的了，恢复至初始状态
                                    stage_caucl <= 3; //转至第二类加法
                                    cnt_t       <= 1; //第二行
                                end
                            end
                        end
                    endcase
                end
                decaps:begin
                    
                end
            endcase

            // 3. 计算调度：同时发生时，计算路径的状态跳转优先。
case(stage)
                keygen:begin
                    case(stage_caucl)
                        stage_reset:begin
                            caucl_ing  <= 0;
                            caucl_done <= 0;
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;       
                            end

                        end 
                        stage_plus_1:begin
                            if (ramt_addr_b[cnt_t] == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                        end
                        stage_plus_2:begin
                            if (ramt_addr_b[cnt_t] == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                        end
                    endcase 
                end
                encaps:begin
                    case(stage_caucl) // [EXAMPLE] 计算调度使用计算状态
                        stage_reset:begin
                            caucl_ing  <= 0;
                            caucl_done <= 0;
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                            //复位输出标志信号
                            finish_keygen <= 0;
                            finish_encaps <= 0;
                            finish_decaps <= 0;
                            out_vld       <= 0;
                        end
                        stage_plus_1:begin
                            if (ramt_addr_b[cnt_t] == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                        end
                        stage_plus_2:begin
                            if (ramt_addr_b[cnt_t] == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                        end
                        //原先理解有误，现该状态修改为在大部分计算完成以及ramu计算完成后，完成t*y剩余计算的状态
                        stage_plus_3:begin
                            if (ramt_addr_b[cnt_t] == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                        end

                        //修改后的补充状态，用于计算t*y
                        stage_mult_2:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                            if (switch) begin
                                if (!cnt_y) begin
                                    stage_caucl   <= 6;  //计算t0*y0+[q/2]m
                                    /*
                                    stage_gen     <= 2;  //转至生成y1
                                    cnt_n         <= 1; 
                                    stage_caucl   <= 2;  //转至第一类加法
                                    cnt_t         <= 1;  //第二行
                                    */
                                end
                                else if (cnt_y) begin
                                    stage_caucl <= 4; //计算剩下的加法
                                end
                            end
                        end
                        stage_plus_4:begin
                            if (ramv_addr_b == 255) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                            if (switch&& !count_t) begin
                                count_t     <= 1;   //以t的值作为标志判断t*y执行进度，同时移动t值，第一行y0执行完毕，等待执行第二行y1
                                stage_gen   <= 1;   //转至生成A0,1
                                stage_caucl <= 1;   //转至生成A1,0*y0
                            end    
                        end
                    endcase
                end
                decaps:begin
                    case(stage_caucl)
                        stage_reset:begin
                            caucl_ing  <= 0;
                            caucl_done <= 0;
                        end
                        stage_mult:begin
                            if (ntt_finish) begin
                                caucl_done <= 1;
                            end
                            else begin
                                caucl_ing  <= 1;
                                caucl_done <= 0;
                            end
                            if (switch) begin
                                stage_caucl <= 2;
                            end
                        end
                        stage_sub:begin
                            if (ramv_addr_b_temp == 255) begin
                                caucl_done <= 1;
                                caucl_ing  <= 0;
                            end
                            else begin
                                caucl_done <= 1;
                            end
                            if (switch) begin
                                if (!cnt_s && !cnt_u) begin
                                    cnt_s       <= 1;
                                    cnt_u       <= 1;
                                    stage_caucl <= 2;
                                end
                                else if (cnt_s && cnt_u) begin
                                    finish_decaps <= 1;
                                    out_vld       <= 1;
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

endmodule
