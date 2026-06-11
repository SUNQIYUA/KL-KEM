`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/25 20:36:24
// Design Name: 
// Module Name: mod_mult
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


module mod_mult#(
    parameter width   =16,
    parameter r_mod_q = 2988  //Q=3329
    )(
    input             clk,
    input             rst,
    input [width-1:0] data_in_1,
    input [width-1:0] data_in_2,
    input [22:0]      q,
    input             start,
    output reg        done,
    output reg [22:0] data_out
    );

    
    wire [2*width:0]   result;
    wire [2*width:0]   buff  ;
/*
    wire [width+21:0] s21 = data_in_1 << 21;
    wire [width+21:0] s18 = data_in_1 << 18;
    wire [width+21:0] s12 = data_in_1 << 12;
    wire [width+21:0] s11 = data_in_1 << 11;
    wire [width+21:0] s9  = data_in_1 << 9;

    (* keep = "true" *) wire [width+21:0] sum1 = s21 + s18;
    (* keep = "true" *) wire [width+21:0] sum2 = sum1 + s12;
    (* keep = "true" *) wire [width+21:0] sum3 = sum2 + s11;
    (* keep = "true" *) wire [width+21:0] sum4 = sum3 + s9;

    (* keep = "true" *) wire [2*width:0]data_tran = sum4 - data_in_1;
*/
    (* use_dsp = "no" *)reg [width:0]      data1;
    reg [width-1:0]    data2;

    reg [8:0]          cnt;
    reg [width-1:0]    Q;
    reg [2*width:0]    temp;
    //reg [2*width:0]    out;

    assign result =  temp+(data2[0]?data1:0);
    assign buff   =  (result+(result[0]?Q:0))>>1;



    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            Q        <= 0;
            data1    <= 0;
            data2    <= 0;

            cnt      <= 0;

            temp     <= 0;
            done     <= 0;
            data_out <= 0;
            
        end
        else if (start&!done) begin
            if (cnt == 0) begin
                data1 <= data_in_1*r_mod_q;
                data2 <= data_in_2;
                cnt   <= cnt +1;
                Q     <= q;

            end
            else if (cnt < width+1)begin
                temp   <= buff;

                data2  <=  data2 >> 1;
                
                cnt    <=  cnt+1;

            end
            else begin
                if (result>=Q) begin
                    temp <= temp - Q;
                end
                else begin
                    done     <= 1;
                    data_out <= temp;
                end
            end
            
        end
    end

endmodule
