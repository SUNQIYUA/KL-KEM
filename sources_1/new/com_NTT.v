`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/23 23:37:01
// Design Name: 
// Module Name: com_NTT
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

//使多项式进入与离开NTT域的复合模块
module com_NTT#(
    parameter width = 12,
    parameter n     = 256
    )(
    input clk,
    input rst,
    
    input               din_vld,   //输入有效信号，预计在外部增加联动逻辑，当over信号为高电平，外部ram不向本模块输出
    
    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,

    input [width-1:0] zeta_in,     //旋转因子

    input INTT_begin,              //判断该按照NTT逻辑运行还是按照INTT逻辑运行，默认按照NTT逻辑运行

    

    output reg [7:0]    adder_1,
    output reg [7:0]    adder_2,    //输入地址

    output reg [7:0]    zeta_cnt,

    output reg [7:0]       out_cnt_1,  //输出地址
    output reg [7:0]       out_cnt_2,  //输出地址


    output  [width-1:0] post,   //输出
    output  [width-1:0] neg,

    




    output              out_vld,   //NTT进域完成标志信号

    //output reg          which_ram, //0为ram2，1为ram1,初始化为0，stage1是从ram1读数据，写数据至ram2，每个satge计算完成值+1以循环
    //output reg          INTT_which_ram,

    output reg          done,       //标志每一个小阶段计算完成
    output reg          over,       //标志信号，是否处于准备进入下一个阶段时输出未排空的阶段
    output reg          finsh      //n层运算结束信号，前面都是借用外部ram进行分治法计算多项式之积

    

    );
    //wire [13:0]      done;
    //reg  [13:0]      start;
    //reg              first;
//*****************************************************
//暂时作为输入，后面将ram及相关逻辑写好之后，再改为对模块的例化
    
    //reg [width-1:0] ram1 [n-1:0];
    //reg [width-1:0] ram2 [n-1:0];

    wire  [width-1:0] RAM  [n-1:0];
    wire  [width-1:0] zeta [n-1:0];

    //reg  [width-1:0] data_in_1;
    //reg  [width-1:0] data_in_2;

    //reg  [width-1:0] ZETA;

    //wire  [width-1:0] post [13:0];
    //wire  [width-1:0] neg  [13:0];

//**************************************************

    reg INTT_log;   //判断运行逻辑的信号，负责保存外部的状态判断信号输入

    reg  [7:0]       len;
    
    //wire [3:0]       stage_cnt;

    reg  [7:0]       cnt;
    reg  [7:0]       adder_cnt;  //辅助输入定位
    reg  [7:0]       out_temp_1 [4:0];
    reg  [7:0]       out_temp_2 [4:0];

    reg  [7:0]       zeta_index;
    //reg  [width-1:0] data_zeta [13:0];
    //reg  [7:0]       zeta_cnt;
    //reg  [4:0]       start_cnt;
    //reg  [4:0]       out_cnt;    //判断是第几个蝶形模块的输出

    reg  [3:0]       over_cnt;   //等待14个周期，使数据排空，防止数据同时使用ram上的4个端口

    //reg  [7:0]       adder_1 [13:0];
    //reg  [7:0]       adder_2 [13:0];

    reg  [3:0]       stage;



    //assign start = (|cnt)?done:start_in;
    //assign stage_cnt = stage[0];
/*
    //待修改
    // ************************************************
     generate
        genvar i;
          for (i = 0; i < n; i = i + 1)begin:data_block
            assign zeta[i] = zeta_in[width*i +: width];
            assign RAM[i] =  ram[width*i +: width];

        end
     endgenerate
     // *****************************************************
*/



    //新增有效信号，防止数据排空之后由于butterfly的din_vld一直保持为搞，导致无效数据地址传输至顶层之后反馈回来，污染butterfly,进而污染ram
    // reg issue_vld;
    // reg ram_vld;
    reg issue_vld;
    reg ram_vld;
    com_butterfly com_butterfly(.clk(clk), .rst(rst), .data_in_1(data_in_1), .data_in_2(data_in_2), .zeta(zeta_in), .din_vld(ram_vld), .INTT_begin(INTT_log), .post(post), .neg(neg), .done(out_vld));


    always @(posedge clk or negedge rst) begin:control_block
    integer i;
    integer j;
    integer k;

        if (!rst) begin
            adder_1    <= 0;
            adder_2    <= 0;
            zeta_cnt   <= 0;
            out_cnt_1  <= 0;
            out_cnt_2  <= 0;
            //start <= 0;
            cnt        <= 0;
            len        <= 128;
            adder_cnt  <= 0;
            //data_in_1 <= 0;
            //data_in_2 <= 0;
            stage     <= 8;     //直接将状态拉入到安全的等待区
            
            zeta_index <= 1; 
            zeta_cnt   <= 1;     //理论上应提取rom[0]作为第一个值，但是python文件中第一个数据可视为无效数据，需跳过rom[1]
            //start     <= 0;
            //first     <= 0;
            done      <= 0;
            over      <= 0;
            over_cnt  <= 0;
            //which_ram <= 0;
            finsh     <= 0;

            INTT_log  <= 0;

            issue_vld <= 0;
            ram_vld   <= 0;

            
        end
        else begin
            done    <= 0;      //计算未完成时，信号拉低

            issue_vld <= 0;
            ram_vld   <= issue_vld;
            
            if ((stage<7)&din_vld) begin
                if(!over & !done)begin
/*
                        if (!first) begin
                            start <= 1;
                            first <= 1;
                        end
*/
/*
                        else begin
                            start <= {start[0],start[13:1]};
                        end
*/
                        issue_vld <= 1;
                        //增加一个zeta_index作为中间变量缓冲，防止zeta_cnt提前读取下一个zeta
                        zeta_cnt  <= zeta_index;
                        adder_1 <= cnt;
                        adder_2 <= cnt+len;

                        //移位寄存，弥补流水线启动初期所需要的5个计算周期
                        for (i = 4; i > 0; i = i - 1)begin:wait_1_block
                            out_temp_1[i] <= out_temp_1[i-1];
                            out_temp_2[i] <= out_temp_2[i-1];
                        end
                        out_temp_1[0] <= adder_1;
                        out_temp_2[0] <= adder_2;

                        out_cnt_1 <= out_temp_1[4];
                        out_cnt_2 <= out_temp_2[4];

                        //ai_work
                        //通过将边界条件与地址计数器分离，再通过累加信号实现动态移动
                        //很好解决了分治法分组越分越多导致地址变换方式需要频繁在累加与跳变之间改变的问题
                        //神了
                        //*****************************************
                        if (cnt < adder_cnt+len-1) begin
                            cnt      <= cnt+1;
                            //len      <= 128;
                            //stage    <= stage+1;
                            //cnt      <= 0;
                        end
                        else if (adder_cnt + 2*len < 256) begin
                            adder_cnt <= adder_cnt+len*2;
                            cnt       <= adder_cnt +len*2;
                            zeta_index  <= INTT_log? (zeta_index-1) : (zeta_index +1);
                        end
                        else begin
                            len       <= INTT_log? len<<1 : len >>1;
                            // [SIM-20260918-R2-02][P1][仍在使用未声明的zeta_index]
                            // XSim单独编译com_NTT时报告VRFC 10-2989；本模块声明的名称是zeat_index。
                            // 层末还必须推进这个内部索引，因为下一层每次请求执行zeta_cnt<=zeat_index。
                            // 修改后代码（仅建议，未应用）：用下面一行替换紧随其后的赋值：
                            // zeat_index <= INTT_log ? (zeat_index-1'b1) : (zeat_index+1'b1);
                            zeta_index  <= INTT_log? (zeta_cnt-1) : (zeta_index +1);
                            cnt       <= 0;
                            adder_cnt <= 0;
                            over      <= 1;
                        end
/*
                        // ****************************************
                        //data_in_1 <= stage_cnt?ram2[cnt] : ram1[cnt];
                        //data_in_2 <= stage_cnt?ram2[cnt+len] : ram1[cnt+len];

                        //ZETA      <= zeta[zeta_cnt];
                        
                        if (out_vld) begin
                        //赋值代码
                        
                            if (stage_cnt) begin
                                ram1[adder_1[13]] <= post[out_cnt];
                                ram1[adder_2[13]] <= neg[out_cnt];
                            end
                            else if (!stage_cnt)begin
                                ram2[adder_1[13]] <= post[out_cnt];
                                ram2[adder_2[13]] <= neg[out_cnt];
                          
                          end
                        
                            out_cnt<= out_cnt+1;
                            if (out_cnt == 13) begin
                                 out_cnt <= 0;
                             end
                             else begin
                                 out_cnt<= out_cnt+1;
                             end
                        end
*/
                end
                else if (over)begin
                    // out_cnt_1/2 却始终为 122/250；RAM 写入覆盖同一对地址。
                    // 第一层 123..127 和 251..255 在换 RAM 前未被写入，后续读出 X。
                    out_cnt_1 <= out_temp_1[4];
                    out_cnt_2 <= out_temp_2[4];
                    if (over_cnt == 5) begin
                        
                        //清空
                        over      <= 0;
                        over_cnt  <= 0;
                        done      <= 1;   //标志这一小阶段计算完成
                        //which_ram <= which_ram + 1;
                        for (k = 4; k >= 0; k = k - 1)begin:wait_3_block
                            out_temp_1[k] <= 0;
                            out_temp_2[k] <= 0;
                        end
                        adder_1 <= 0;
                        adder_2 <= 0;
                        stage   <= stage+1;

                    end
                    else begin
                        //移位寄存，弥补流水线启动初期所需要的4个计算周期
                        for (j = 4; j > 0; j = j - 1)begin:wait_2_block
                            out_temp_1[j] <= out_temp_1[j-1];
                            out_temp_2[j] <= out_temp_2[j-1];
                        end
                        out_temp_1[0] <= adder_1;
                        out_temp_2[0] <= adder_2;
                        over_cnt <= over_cnt +1;
                     /*
                        //赋值代码
                        for (k_2 = 13; k_2 > 0; k_2 = k_2 - 1)begin:adder_block_2
                            adder_1[k_2] <= adder_1[k_2-1];
                            adder_2[k_2] <= adder_2[k_2-1];
                        end
                        adder_1[0] <= 0;
                        adder_2[0] <= 0; 
                        
                        if (stage_cnt) begin
                                ram2[adder_1[13]] <= post[out_cnt];
                                ram2[adder_2[13]] <= neg[out_cnt];
                        end
                            else if (!stage_cnt)begin
                                ram1[adder_1[13]] <= post[out_cnt];
                                ram1[adder_2[13]] <= neg[out_cnt];
                        end
                     */
                    end
                    
                end
            end
            //缓冲一下，先将完成信号拉高，在进入安全的等待区
            else if (stage == 7) begin
                finsh <= 1;  // 报告外部,可以停止送数据了
                if (!din_vld) begin      //存在信号残留问题，当前模块向外部发送finsh信号时，外部模块需要下一拍开始才会检测，此时准备将din_vld拉低，需要再下一拍开始时，本模块才会检测到din_vld拉低的反馈
                    stage <= 4'd8;
                end
            end
            //进入等待区
            else if (stage == 8) begin
                finsh <= 0; 
                
                //只有当外部开始送数据时，才进行状态初始化
                if (din_vld) begin
                    finsh     <= 0;
                    stage     <= 0; 
                    cnt       <= 0;
                    // [SIM-20260918-07][P1][INTT首个旋转因子地址越界并截断为0]
                    // 参考模型的INTT从zeta[127]倒序；tb只使用zeta_cnt[6:0]访问128深度ROM。
                    // 8'd128的低7位为0，因此当前写法会先取zeta[0]，不是zeta[127]。
                    // 修改后代码（仅建议，未应用）：用以下两句替换紧随其后的两句：
                    // zeta_cnt   <= INTT_begin ? 8'd127 : 8'd1;
                    // zeat_index <= INTT_begin ? 8'd127 : 8'd1;
                    zeta_cnt   <= INTT_begin ? 8'd127 : 8'd1;
                    zeta_index <= INTT_begin ? 8'd127 : 8'd1;
                    adder_cnt <= 0;
                    over      <= 0;
                    over_cnt  <= 0;
                    //which_ram <= 0; // 新任务通常从默认 RAM 方向开始
                    done      <= 0;
                    if (INTT_begin) begin
                        INTT_log <= 1;
                        //zeta_cnt <= 127;
                        len      <= 2;
                        //stage    <= 0;
                    end 
                    else begin
                        INTT_log <= 0;
                        zeta_cnt <= 1;
                        len      <= 128;
                    end
                end
            end
             
        end
    end
endmodule
