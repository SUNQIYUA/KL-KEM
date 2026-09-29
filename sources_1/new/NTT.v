`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 23:29:09
// Design Name: 
// Module Name: NTT
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



//多项式系数与旋转因子仍采用四处调用寄存器的方式，等待改为ram


module NTT#(
    parameter width = 12,
    parameter n     = 256
    )(
    input clk,
    input rst,
    
    input               din_vld,   //输入有效信号，预计在外部增加联动逻辑，当over信号为高电平，外部ram不向本模块输出
    
    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,

    input [width-1:0] zeta_in,     //旋转因子

    
    output reg [7:0]    adder_1,
    output reg [7:0]    adder_2,    //输入地址

    output reg [7:0]    zeta_cnt,

    output reg [7:0]       out_cnt_1,  //输出地址
    output reg [7:0]       out_cnt_2,  //输出地址


    output  [width-1:0] post,   //输出
    output  [width-1:0] neg,

    output              out_vld,   //NTT进域完成标志信号

    //output reg          which_ram, //0为ram2，1为ram1,初始化为0，stage1是从ram1读数据，写数据至ram2，每个satge计算完成值+1以循环

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

    reg [7:0] zeta_index;

    //reg  [width-1:0] data_in_1;
    //reg  [width-1:0] data_in_2;

    //reg  [width-1:0] ZETA;

    //wire  [width-1:0] post [13:0];
    //wire  [width-1:0] neg  [13:0];

//**************************************************

    reg  [7:0]       len;
    
    //wire [3:0]       stage_cnt;

    reg  [7:0]       cnt;
    reg  [7:0]       adder_cnt;  //辅助输入定位
    reg  [7:0]       out_temp_1 [4:0];
    reg  [7:0]       out_temp_2 [4:0];

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
    // [SIM-20260918-R2-01][P1][使用了中文全角分号]
    // 下一行末尾是U+FF1B“；”（UTF-8字节EF BC 9B），不是Verilog使用的ASCII分号“;”。
    // XSim因此在本行报“non-printable character 0xef”，并导致ram_vld声明失效。
    // 修改后代码（仅建议，未应用）：用下面一行替换紧随其后的声明：
    // reg issue_vld;
    reg issue_vld;
    reg ram_vld;
    
    butterfly butterfly(.clk(clk), .rst(rst), .data_in_1(data_in_1), .data_in_2(data_in_2), .zeta(zeta_in), .din_vld(ram_vld), .post(post), .neg(neg), .done(out_vld));


    always @(posedge clk or negedge rst) begin:control_block
    integer i;
    integer j;
    integer k;

        if (!rst) begin
            adder_1    <= 0;
            adder_2    <= 0;
            zeta_index <= 1;
            zeta_cnt   <= 1; //理论上应提取rom[0]作为第一个值，但是python文件中第一个数据可视为无效数据，需跳过rom[1]
            out_cnt_1  <= 0;
            out_cnt_2  <= 0;
            //start <= 0;
            cnt        <= 0;
            len        <= 128;
            adder_cnt  <= 0;
            issue_vld  <= 0; 
            ram_vld    <= 0;
            //data_in_1 <= 0;
            //data_in_2 <= 0;
            stage      <= 8;
            //zeta_cnt  <= 0;
            //start     <= 0;
            //first     <= 0;
            done      <= 0;
            over      <= 0;
            over_cnt  <= 0;
            //which_ram <= 0;
            finsh     <= 0;

            
        end
        else begin
            done <= 0; //依旧常驻清0，利用同一 always 块后赋值优先的特性，使得finsh完成分支再置1
            issue_vld <= 0;
            // [SIM-20260918-02][P1][RAM返回有效信号被每拍清零]
            // 本拍issue_vld表示上一拍是否发布了同步RAM读请求；ram_vld必须把它延迟一拍。
            // 当前固定赋0会使butterfly.din_vld始终为0，即使修好语法也不会产生有效结果。
            // 修改后代码（仅建议，未应用）：用下一句替换紧随其后的原赋值：
            // ram_vld <= issue_vld;
            ram_vld   <= issue_vld;
            if ((stage<7)&din_vld) begin
                if(!over && !done)begin
                        issue_vld <= 1;
/*
                        if (!first) begin
                            start <= 1;
                            first <= 1;
                        end

                        else begin
                            start <= {start[0],start[13:1]};
                        end
*/
                        //增加一个zeta_index作为中间变量缓冲，防止zeta_cnt提前读取下一个zeta
                        // 修改后代码（仅建议，未应用）：替换下一句：
                        // zeta_cnt <= zeta_index;
                        zeta_cnt <= zeta_index;
                        
                        adder_1 <= cnt;
                        adder_2 <= cnt+len;

                        //移位寄存，弥补流水线启动初期所需要的4个计算周期
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
                            zeta_index  <= zeta_index +1;
                        end
                        else begin
                            len       <= len >>1;
                            //stage     <= stage+1;
                            zeta_index  <= zeta_index +1;
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
                    // 写地址停在 122/250，输出数据仍在更新，尾部五对地址未写入。
                    // 包括 over_cnt==4 的终止拍都应推进输出地址：
                    out_cnt_1 <= out_temp_1[4];
                    out_cnt_2 <= out_temp_2[4];
                    if (over_cnt == 5) begin
                        
                        //清空
                        over      <= 0;
                        over_cnt  <= 0;
                        done      <= 1;   //标志这一小阶段计算完成
                        stage     <= stage +1;

                        //which_ram <= which_ram + 1;
                        for (k = 4; k >= 0; k = k - 1)begin:wait_3_block
                            out_temp_1[k] <= 0;
                            out_temp_2[k] <= 0;
                        end
                        adder_1 <= 0;
                        adder_2 <= 0;

                    end
                    else begin
                        //移位寄存，弥补流水线启动初期所需要的4个计算周期
                        // [SIM-20260918-04][P1][for初始化与条件之间缺少分号]
                        // XSim在j附近报VRFC 10-1412；Verilog for必须包含两个分号。
                        // 修改后代码（仅建议，未应用）：替换下一行循环头：
                        // for (j = 4; j > 0; j = j - 1) begin:wait_2_block
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
                if (!din_vld) begin
                    stage <= 4'd8;
                end
                //stage <= stage +1;
            end
            //进入等待区
            else if (stage == 8)begin
                finsh <= 0;
                if (din_vld) begin
                    finsh     <= 0;
                    stage     <= 0; 
                    cnt       <= 0;
                    adder_cnt <= 0;
                    over      <= 0;
                    over_cnt  <= 0;
                    //which_ram <= 0; // 新任务通常从默认 RAM 方向开始
                    done      <= 0;
                    len       <= 128;
                    zeta_index <= 1;
                    zeta_cnt   <= 1;   //len 和 zeta_cnt未重置（已修改）
               end 
            end  
        end
    end
endmodule
