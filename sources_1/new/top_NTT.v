`timescale 1ns / 1ps

module top_NTT#(
    parameter width = 12,
    parameter n     = 256)(
    input clk,
    input rst,
    input din_vld,

    input [width-1:0] ram1_in_1,
    input [width-1:0] ram1_in_2,
    input [width-1:0] ram3_in_1,
    input [width-1:0] ram3_in_2,
    input [width-1:0] zeta_in,


    input             first_NTT,// 经过keccak处理后的种子再拒绝采样后，直接规定为进入NTT域的多项式A的系数
                                 // 因此需要外部信号告诉是否需要先进NTT域

    // 外部 RAM 0 接口
    output              ram0_we_a,
    output [7:0]        ram0_adder_a,
    output [width-1:0]  ram0_din_a,
    input  [width-1:0]  ram0_dout_a,
    output              ram0_we_b,
    output [7:0]        ram0_adder_b,
    output [width-1:0]  ram0_din_b,
    input  [width-1:0]  ram0_dout_b,

    // 外部 RAM 1 接口
    output              ram1_we_a,
    output [7:0]        ram1_adder_a,
    output [width-1:0]  ram1_din_a,
    input  [width-1:0]  ram1_dout_a,
    output              ram1_we_b,
    output [7:0]        ram1_adder_b,
    output [width-1:0]  ram1_din_b,
    input  [width-1:0]  ram1_dout_b,

    // 外部 RAM 2 接口
    output              ram2_we_a,
    output [7:0]        ram2_adder_a,
    output [width-1:0]  ram2_din_a,
    input  [width-1:0]  ram2_dout_a,
    output              ram2_we_b,
    output [7:0]        ram2_adder_b,
    output [width-1:0]  ram2_din_b,
    input  [width-1:0]  ram2_dout_b,

    // 外部 RAM 3 接口
    output              ram3_we_a,
    output [7:0]        ram3_adder_a,
    output [width-1:0]  ram3_din_a,
    input  [width-1:0]  ram3_dout_a,
    output              ram3_we_b,
    output [7:0]        ram3_adder_b,
    output [width-1:0]  ram3_din_b,
    input  [width-1:0]  ram3_dout_b,

    // 外部 RAM 4 接口
    output              ram4_we_a,
    output [7:0]        ram4_adder_a,
    output [width-1:0]  ram4_din_a,
    input  [width-1:0]  ram4_dout_a,
    output              ram4_we_b,
    output [7:0]        ram4_adder_b,
    output [width-1:0]  ram4_din_b,
    input  [width-1:0]  ram4_dout_b,

    output     [7:0] zeta_cnt,
    output reg [7:0] ram1_cnt_1,
    output reg [7:0] ram1_cnt_2,
    output reg [7:0] ram3_cnt_1,
    output reg [7:0] ram3_cnt_2,
    //output reg [1:0] which_ram,

    //output [width-1:0] ram1_out_1,
    //output [width-1:0] ram1_out_2,
    //output [width-1:0] ram3_out_1,
    //output [width-1:0] ram3_out_2,
    // output             ram1_out_vld,
    // output             ram3_out_vld,
    output reg         import_finish, // 连接外部top模块的信号，告诉外部模块可以终止输入了
    output reg         finsh
    );

// 端口声明与内部线网
    wire [width-1:0] NTT1_in_1;
    wire [width-1:0] NTT1_in_2;
    wire [width-1:0] NTT2_in_1;
    wire [width-1:0] NTT2_in_2;
    
    wire [7:0]       NTT1_adder_1;
    wire [7:0]       NTT1_adder_2;
    wire [7:0]       NTT2_adder_1;
    wire [7:0]       NTT2_adder_2;
    
    wire [7:0]       NTT1_cnt_1;
    wire [7:0]       NTT1_cnt_2;
    wire [7:0]       NTT2_cnt_1;
    wire [7:0]       NTT2_cnt_2;
    
    wire             NTT1_out_vld;
    wire             NTT2_out_vld;
    wire [width-1:0] NTT1_out_1;
    wire [width-1:0] NTT1_out_2;
    wire [width-1:0] NTT2_out_1;
    wire [width-1:0] NTT2_out_2;
    
    wire [7:0] NTT1_zeta_cnt;
    wire [7:0] NTT2_zeta_cnt;
    wire [7:0] p2p_zeta_cnt;
    
    wire done_NTT1;
    wire done_NTT2;
    wire done_p2p;
    wire finsh_NTT1;
    wire finsh_NTT2;
    
    reg vld_NTT;
    reg NTT_start;
    wire NTT_start_1,NTT_start_2;
    reg vld_p2p;
    
    wire [4:0] we_a, we_b;
    wire [7:0] adder_a [4:0];
    wire [7:0] adder_b [4:0];
     
    wire [11:0] din_a [4:0];
    wire [11:0] din_b [4:0];
    
    wire [11:0] dout_a [4:0];
    wire [11:0] dout_b [4:0];
    
    reg         which_ram[1:0];
    
    reg [7:0] ram1_adder_1;
    reg [7:0] ram1_adder_2;
    reg [7:0] ram3_adder_1;
    reg [7:0] ram3_adder_2;
    
    reg  INTT_start;
    wire INTT_begin;
    assign INTT_begin = INTT_start;
    
    wire [7:0] ramA_adder_1;
    wire [7:0] ramA_adder_2;
    wire [7:0] ramB_adder_1;
    wire [7:0] ramB_adder_2;
    
    wire [7:0] out_adder_1;
    wire [7:0] out_adder_2;
    
    wire [width-1:0] ram_data_1;
    wire [width-1:0] ram_data_2;
    
    wire out_vld_p2p;

// 外部 RAM 信号映射
    assign ram0_we_a    = we_a[0];
    assign ram0_adder_a = adder_a[0];
    assign ram0_din_a   = din_a[0];
    assign dout_a[0]    = ram0_dout_a;
    assign ram0_we_b    = we_b[0];
    assign ram0_adder_b = adder_b[0];
    assign ram0_din_b   = din_b[0];
    assign dout_b[0]    = ram0_dout_b;

    assign ram1_we_a    = we_a[1];
    assign ram1_adder_a = adder_a[1];
    assign ram1_din_a   = din_a[1];
    assign dout_a[1]    = ram1_dout_a;
    assign ram1_we_b    = we_b[1];
    assign ram1_adder_b = adder_b[1];
    assign ram1_din_b   = din_b[1];
    assign dout_b[1]    = ram1_dout_b;

    assign ram2_we_a    = we_a[2];
    assign ram2_adder_a = adder_a[2];
    assign ram2_din_a   = din_a[2];
    assign dout_a[2]    = ram2_dout_a;
    assign ram2_we_b    = we_b[2];
    assign ram2_adder_b = adder_b[2];
    assign ram2_din_b   = din_b[2];
    assign dout_b[2]    = ram2_dout_b;

    assign ram3_we_a    = we_a[3];
    assign ram3_adder_a = adder_a[3];
    assign ram3_din_a   = din_a[3];
    assign dout_a[3]    = ram3_dout_a;
    assign ram3_we_b    = we_b[3];
    assign ram3_adder_b = adder_b[3];
    assign ram3_din_b   = din_b[3];
    assign dout_b[3]    = ram3_dout_b;

    assign ram4_we_a    = we_a[4];
    assign ram4_adder_a = adder_a[4];
    assign ram4_din_a   = din_a[4];
    assign dout_a[4]    = ram4_dout_a;
    assign ram4_we_b    = we_b[4];
    assign ram4_adder_b = adder_b[4];
    assign ram4_din_b   = din_b[4];
    assign dout_b[4]    = ram4_dout_b;

// ram5写使能与地址/数据赋值
    assign we_a[4] = INTT_begin ? (which_ram[0] & NTT1_out_vld) : out_vld_p2p;
    assign we_b[4] = INTT_begin ? (which_ram[0] & NTT1_out_vld) : out_vld_p2p;

    assign adder_a[4] = INTT_begin? (which_ram[0]? NTT1_cnt_1 : NTT1_adder_1) : out_adder_1;
    assign adder_b[4] = INTT_begin? (which_ram[0]? NTT1_cnt_2 : NTT1_adder_2) : out_adder_2;

    assign din_a[4] = INTT_begin ? NTT1_out_1 : ram_data_1;
    assign din_b[4] = INTT_begin ? NTT1_out_2 : ram_data_2;

// zeta调用逻辑
    //旁路第一路 NTT 时不能继续用第一路旋转因子地址
    // 否则第一路不运行、地址不推进，第二路会读错 zeta；本候选未做完整旁路 NTT 数值验证。
    assign zeta_cnt = NTT_start ? ((first_NTT && !INTT_begin) ? NTT2_zeta_cnt : NTT1_zeta_cnt) : (vld_p2p ? p2p_zeta_cnt : 8'd0);
    //assign zeta_cnt = NTT_start? NTT1_zeta_cnt : (vld_p2p? p2p_zeta_cnt : 0);



// ram 写入与读出 使能信号判断逻辑
    // [DEEP-03][P1][无效周期仍写 RAM]
    // 现有RAM0..3写使能只看bank，NTT_start=0或结果无效时也可能写入。
    // cycle 134 的 valid地址为X；cycle264换bank后仍写0/0；cycle269写入有效标记的X。
    // 修改后代码（仅建议，未应用）：须先在NTT/com_NTT生成逐请求有效信号，
    // 再用以下八句替换本节八句 we 赋值。单加 out_vld 不能修复“假有效”。
    // INTT写目标是RAM1/4；B路和RAM0/2/3不应继续写。RAM4原有有效门控保留。
    // 当不处于点乘或输入加载阶段时，为了使得ram不处于写出状态，向其他模块或寄存器输出错误数据，加上一些约束条件，使得在特定情况下ram为0
    assign we_a[0] = din_vld ? 1'b1 : (NTT_start && !INTT_begin && which_ram[0] && NTT1_out_vld);
    assign we_b[0] = we_a[0];
    assign we_a[1] = !din_vld && NTT_start && !which_ram[0] && NTT1_out_vld;
    assign we_b[1] = we_a[1];
    assign we_a[2] = din_vld ? 1'b1 : (NTT_start && !INTT_begin && which_ram[1] && NTT2_out_vld);
    assign we_b[2] = we_a[2];
    assign we_a[3] = !din_vld && NTT_start && !INTT_begin && !which_ram[1] && NTT2_out_vld;
    assign we_b[3] = we_a[3];
    // INTT写目标是RAM1/4；B路和RAM0/2/3不应继续写。RAM4原有有效门控保留。
    //assign we_a[0] = din_vld ? 1 : (vld_p2p ? 0 : which_ram[0]);
    //assign we_b[0] = din_vld ? 1 : (vld_p2p ? 0 : which_ram[0]);
    //assign we_a[2] = din_vld ? 1 : (vld_p2p ? 0 : which_ram[1]);
    //assign we_b[2] = din_vld ? 1 : (vld_p2p ? 0 : which_ram[1]);
    //
    //assign we_a[1] = din_vld ? 0 : (vld_p2p ? 0 : !which_ram[0]);
    //assign we_b[1] = din_vld ? 0 : (vld_p2p ? 0 : !which_ram[0]);
    //assign we_a[3] = din_vld ? 0 : (vld_p2p ? 0 : !which_ram[1]);
    //assign we_b[3] = din_vld ? 0 : (vld_p2p ? 0 : !which_ram[1]);

// ram 输入数据来源与地址移动判断逻辑
    assign adder_a[0] = din_vld? ram1_adder_1 : (vld_p2p? ramA_adder_1 : (which_ram[0]? NTT1_cnt_1 : NTT1_adder_1));
    assign adder_b[0] = din_vld? ram1_adder_2 : (vld_p2p? ramA_adder_2 : (which_ram[0]? NTT1_cnt_2 : NTT1_adder_2));
    assign adder_a[2] = din_vld? ram3_adder_1 : (vld_p2p? ramB_adder_1 : (which_ram[1]? NTT2_cnt_1 : NTT2_adder_1));
    assign adder_b[2] = din_vld? ram3_adder_2 : (vld_p2p? ramB_adder_2 : (which_ram[1]? NTT2_cnt_2 : NTT2_adder_2));
    // [DEEP-04][P1][点乘读地址未接到当前数据所在RAM]
    // 七层正变换后bankA=bankB=1，点乘数据来自RAM1/3，而本处仍给NTT读地址。
    // 实测cycle1064..1068请求2/3、4/5等，RAM1/3实际地址一直为0/0；
    // 点乘一直读到A=379/379、B=2697/2697，造成奇数输出重复为320。
    // 当前数据选择NTT1_in/NTT2_in按bank选择可保留；点乘开始须等同步读返回
    // 再送有效信号，见p2p_mult的DEEP-05。此连接修复不保证上游NTT结果正确。
     assign adder_a[1] = vld_p2p ? ramA_adder_1 : (which_ram[0] ? NTT1_adder_1 : NTT1_cnt_1);
     assign adder_b[1] = vld_p2p ? ramA_adder_2 : (which_ram[0] ? NTT1_adder_2 : NTT1_cnt_2);
     assign adder_a[3] = vld_p2p ? ramB_adder_1 : (which_ram[1] ? NTT2_adder_1 : NTT2_cnt_1);
     assign adder_b[3] = vld_p2p ? ramB_adder_2 : (which_ram[1] ? NTT2_adder_2 : NTT2_cnt_2);
    
    //assign adder_a[1] = which_ram[0]? NTT1_adder_1 : NTT1_cnt_1;
    //assign adder_b[1] = which_ram[0]? NTT1_adder_2 : NTT1_cnt_2;
    //assign adder_a[3] = which_ram[1]? NTT2_adder_1 : NTT2_cnt_1;
    //assign adder_b[3] = which_ram[1]? NTT2_adder_2 : NTT2_cnt_2;

//主控制逻辑
    // 各步骤状态控制逻辑
    localparam state_wait = 0;
    localparam state_in   = 1;
    localparam state_NTT  = 2;
    localparam state_p2p  = 3;
    localparam state_INTT = 4;

    assign NTT_start_1 = NTT_start && (INTT_begin || !first_NTT);
    assign NTT_start_2 = NTT_start;
    
    reg [3:0] stage;
    reg strat_reg; //缓冲器，使得输入地址移动比输出地址移动慢一拍

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            stage        <= 0;
            ram1_adder_1 <= 0;
            ram1_adder_2 <= 1;
            ram3_adder_1 <= 0;
            ram3_adder_2 <= 1;   //两个端口都从 0 开始且都 +2，同时写同一偶数地址(已修改)
            
            //控制外部ram地址
            ram1_cnt_1 <= 0;
            ram1_cnt_2 <= 1;
            ram3_cnt_1 <= 0;
            ram3_cnt_2 <= 1;
            
            vld_NTT      <= 0;
            vld_p2p      <= 0;
            NTT_start    <= 0;
            INTT_start   <= 0;
            which_ram[0] <= 0;
            which_ram[1] <= 0;
            finsh        <= 0;
            
            strat_reg <= 0;

            import_finish <= 0;
        end
        else begin
            finsh <= 0; //利用同一 always 块后赋值优先的特性，使得finsh完成分支再置1
            strat_reg <= 0; //默认为0，state_in阶段拉高   
            case (stage)
            state_wait: begin
                if (din_vld) begin
                    stage <= 1;
                end
                ram1_cnt_1 <= 0;
                ram1_cnt_2 <= 1;
                ram3_cnt_1 <= 0;
                ram3_cnt_2 <= 1;

                ram1_adder_1 <= 0;
                ram1_adder_2 <= 1;
                ram3_adder_1 <= 0;
                ram3_adder_2 <= 1; //两个端口都从 0 开始且都 +2，同时写同一偶数地址(已修改)
                
                NTT_start    <= 0;
                vld_p2p      <= 0;
                INTT_start   <= 0;
                which_ram[0] <= 0;
                which_ram[1] <= 0;
                import_finish <= 0; //当外部开始后续轮次输入前，将填充完成标志信号归零
            end
            state_in: begin
                ram1_cnt_1 <= ram1_cnt_1 + 2;
                ram1_cnt_2 <= ram1_cnt_2 + 2;
                ram3_cnt_1 <= ram3_cnt_1 + 2;
                ram3_cnt_2 <= ram3_cnt_2 + 2;
                strat_reg  <= 1;
                if (strat_reg) begin
                    ram1_adder_1 <= ram1_adder_1 + 2;
                    ram1_adder_2 <= ram1_adder_2 + 2;
                    ram3_adder_1 <= ram3_adder_1 + 2;
                    ram3_adder_2 <= ram3_adder_2 + 2;
                    // stage <= (ram1_adder_1 == 8'd254) ? state_NTT : stage;
                    stage        <= (ram1_adder_1 == 254)?  state_NTT : stage;
                    NTT_start    <= (ram1_adder_1 == 254)?  1 : 0;
                    import_finish <= (ram1_adder_1 == 254)? 1 : 0; // 连接外部top模块的信号，告诉外部模块可以终止输入了
                end
            end
            state_NTT: begin
                if (done_NTT1) begin
                    which_ram[0] <= !which_ram[0];
                end
                if (done_NTT2) begin
                    which_ram[1] <= !which_ram[1];
                end
                if (finsh_NTT2) begin
                    stage   <= state_p2p; //将原先的stage+1赋值改为直接赋值常数，节约一个加法电路
                    vld_p2p <= 1;
                    NTT_start <= 1'b0;  //vld_p2p 拉高后 NTT_start 仍保持1(已修改)
                end
            end 
            state_p2p: begin
                NTT_start <= 0;
                if (done_p2p) begin
                    vld_p2p      <= 0;
                    which_ram[0] <= 0;
                    stage        <= state_INTT;
                    INTT_start   <= 1;
                    NTT_start    <= 1;
                end
            end 
            state_INTT: begin
                if (done_NTT1) begin
                    which_ram[0] <= !which_ram[0];
                end
                if (finsh_NTT1) begin
                    NTT_start  <= 0;
                    INTT_start <= 0;
                    finsh      <= 1;
                    if (din_vld) begin
                        stage  <= 1;
                    end
                    else begin
                        stage <= 0;
                        //finsh <= 0; //将finsh置0的逻辑移至逻辑块最开头
                    end
                end
            end
            endcase
        end
    end

// 输入数据切换逻辑
    assign NTT1_in_1 = which_ram[0]? dout_a[1] : (INTT_begin? dout_a[4] : dout_a[0]);
    assign NTT1_in_2 = which_ram[0]? dout_b[1] : (INTT_begin? dout_b[4] : dout_b[0]);
    assign NTT2_in_1 = which_ram[1]? dout_a[3] : dout_a[2];
    assign NTT2_in_2 = which_ram[1]? dout_b[3] : dout_b[2];

// 输出数据逻辑
    assign din_a[0] = din_vld? ram1_in_1 : NTT1_out_1;
    assign din_b[0] = din_vld? ram1_in_2 : NTT1_out_2;
    assign din_a[1] = NTT1_out_1;
    assign din_b[1] = NTT1_out_2;
    
    assign din_a[2] = din_vld? ram3_in_1 : NTT2_out_1;
    assign din_b[2] = din_vld? ram3_in_2 : NTT2_out_2;
    assign din_a[3] = NTT2_out_1;
    assign din_b[3] = NTT2_out_2;

// 子模块实例化
    com_NTT com_NTT(
        .clk(clk),
        .rst(rst),
        .din_vld(NTT_start_1),
        .data_in_1(NTT1_in_1),
        .data_in_2(NTT1_in_2),
        .zeta_in(zeta_in),
        .INTT_begin(INTT_begin),

        .adder_1(NTT1_adder_1),
        .adder_2(NTT1_adder_2),
        .zeta_cnt(NTT1_zeta_cnt),
        .out_cnt_1(NTT1_cnt_1),
        .out_cnt_2(NTT1_cnt_2),
        .post(NTT1_out_1),
        .neg(NTT1_out_2),
        .out_vld(NTT1_out_vld),
        .done(done_NTT1),
        .over(),
        .finsh(finsh_NTT1)
    );

    NTT NTT_2(
        .clk(clk),
        .rst(rst),
        .din_vld(NTT_start_2),
        .data_in_1(NTT2_in_1),
        .data_in_2(NTT2_in_2),
        .zeta_in(zeta_in),

        .adder_1(NTT2_adder_1),
        .adder_2(NTT2_adder_2),
        .zeta_cnt(NTT2_zeta_cnt),
        .out_cnt_1(NTT2_cnt_1),
        .out_cnt_2(NTT2_cnt_2),
        .post(NTT2_out_1),
        .neg(NTT2_out_2),
        .out_vld(NTT2_out_vld),
        .done(done_NTT2),                 
        .over(),
        .finsh(finsh_NTT2)
    );

    p2p_mult p2p_mult(
        .clk(clk),
        .rst(rst), 
        .RAM_a_1(NTT1_in_1),
        .RAM_a_2(NTT1_in_2),
        .RAM_b_1(NTT2_in_1),
        .RAM_b_2(NTT2_in_2),
        .zeta_in(zeta_in),
        .din_vld(vld_p2p), 

        .zeta_cnt(p2p_zeta_cnt),
        .ramA_adder_1(ramA_adder_1),
        .ramA_adder_2(ramA_adder_2),
        .ramB_adder_1(ramB_adder_1),
        .ramB_adder_2(ramB_adder_2),
        .out_adder_1(out_adder_1),
        .out_adder_2(out_adder_2),
        .ram_data_1(ram_data_1),
        .ram_data_2(ram_data_2),
        .out_vld(out_vld_p2p),
        .done(done_p2p)
    );

endmodule
