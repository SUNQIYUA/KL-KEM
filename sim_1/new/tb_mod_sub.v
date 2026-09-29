`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/27 01:32:50
// Design Name: 
// Module Name: tb_mod_sub
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


`timescale 1ns / 1ps

module tb_mod_sub;
    
    parameter width =64;
    
    reg             clk;
    reg             rst;
    reg [width-1:0] data_in_1;
    reg [width-1:0] data_in_2;
    reg [22:0]      q;
    reg             start;
    
    wire [22:0]     data_out1;
    wire [22:0]     data_out2;

    wire            done1;
    wire            done2;

    //例化
    mod_mult  test(.clk(clk), .rst(rst), .data_in_1(data_in_1), .data_in_2(data_in_2), .q(q), .start(start), .data_out(data_out2), .done(done2));


    // 时钟
    always #5 clk = ~clk;

    initial begin
        clk      = 0;
        rst      = 0;

        data_in_1  = 0;
        data_in_2  = 0;
        q          = 0;
        
        start      = 0;


        // 复位
        #100;
        rst = 0;

        #20;
        rst = 1;

        #20
        start   = 1;
        q       = 3329;
        data_in_1 = 52501;
        data_in_2 = 26801;
    end


    initial begin
        wait(done2 == 1);
        
        #500

        $display("Simulation finished.result is ",data_out1,data_out2);
        $stop;
    end


endmodule
