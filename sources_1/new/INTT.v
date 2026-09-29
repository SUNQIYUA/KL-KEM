`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/07 22:18:21
// Design Name: 
// Module Name: INTT
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


module INTT#(
    parameter width = 12,
    parameter n     = 256
    )(
    input clk,
    input rst,

    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,

    input [width-1:0] zeta_in,     //旋转因子

    input               din_vld,   //输入有效信号，预计在外部增加联动逻辑，当over信号为高电平，外部ram不向本模块输出

    output reg [7:0]    adder_1,
    output reg [7:0]    adder_2,    //输入地址

    output reg [7:0]    zeta_cnt,


    output  [width-1:0] post,   //输出
    output  [width-1:0] neg,

    output reg [7:0]       out_cnt_1,  //输出地址
    output reg [7:0]       out_cnt_2,  //输出地址




    output              out_vld,   //NTT进域完成标志信号

    //output reg          which_ram, //0为ram2，1为ram1,初始化为0，stage1是从ram1读数据，写数据至ram2，每个satge计算完成值+1以循环

    output reg          over,       //标志信号，是否处于准备进入下一个阶段时输出未排空的阶段
    output reg          finsh      //n层运算结束信号，前面都是借用外部ram进行分治法计算多项式之积

    

    );


    wire [13:0]      done;
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

    reg  [7:0]       len;
    
    //wire [3:0]       stage_cnt;

    reg  [7:0]       cnt;
    reg  [7:0]       adder_cnt;  //辅助输入定位
    reg  [7:0]       out_temp_1 [3:0];
    reg  [7:0]       out_temp_2 [3:0];
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


    butterfly_neg butterfly_neg(.clk(clk), .rst(rst), .data_in_1(data_in_1), .data_in_2(data_in_2), .zeta(zeta_in), .din_vld(din_vld), .post(post), .neg(neg), .done(out_vld));


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
            len        <= 1;
            adder_cnt  <= 0;
            //data_in_1 <= 0;
            //data_in_2 <= 0;
            stage     <= 0;
            zeta_cnt  <= 127;    //由于是逆NTT，需要乘上旋转因子的逆元，由于模意义下的特性，乘逆元等效于倒着乘乘对应的旋转因子
            //start     <= 0;
            //first     <= 0;
            over      <= 0;
            over_cnt  <= 0;
            //which_ram <= 0;
            finsh     <= 0;

            
        end
        else begin
            if ((stage<8)&din_vld) begin
                if(!over)begin
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
                        adder_1 <= cnt;
                        adder_2 <= cnt+len;

                        //移位寄存，弥补流水线启动初期所需要的4个计算周期
                        for (i = 3; i > 0; i = i - 1)begin:wait_1_block
                            out_temp_1[i] <= out_temp_1[i-1];
                            out_temp_2[i] <= out_temp_2[i-1];
                        end
                        out_temp_1[0] <= adder_1;
                        out_temp_2[0] <= adder_2;

                        out_cnt_1 <= out_temp_1[3];
                        out_cnt_2 <= out_temp_2[3];

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
                            zeta_cnt  <= zeta_cnt -1;         //旋转因子倒序移动
                        end
                        else begin
                            len       <= len <<1;
                            stage     <= stage+1;
                            zeta_cnt  <= zeta_cnt -1;
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
                    if (over_cnt == 4) begin
                        
                        //清空
                        over      <= 0;
                        over_cnt  <= 0;
                        //which_ram <= which_ram + 1;
                        for (k = 3; k >= 0; k = k - 1)begin:wait_3_block
                            out_temp_1[k] <= 0;
                            out_temp_2[k] <= 0;
                        end
                        adder_1 <= 0;
                        adder_2 <= 0;

                    end
                    else begin
                        //移位寄存，弥补流水线启动初期所需要的4个计算周期
                        for (j = 3; j > 0; j = j - 1)begin:wait_2_block
                            out_temp_1[j] <= out_temp_1[j-1];
                            out_temp_2[j] <= out_temp_2[j-1];
                        end
                        out_temp_1[0] <= adder_1;
                        out_temp_2[0] <= adder_2;
                        over_cnt      <= over_cnt +1;
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
            else if (stage == 8)begin
                   
                   finsh <= 1;
               end   
        end
    end
endmodule

