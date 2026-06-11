`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/29 00:11:53
// Design Name: 
// Module Name: absorb
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


module absorb(
    input [1599:0] data_in,
    //input          ready,
    //input          clk,
    //input          rst,
    input [64:0]   rc,
    //input [1599:0] data_mid,

    output [1599:0] data_out

    );


parameter  r1 = 168;                //SHAKE-128
parameter  r2 = 136;                //SHAKE-256
parameter  r3 = 136;                //SHA-256
parameter  r4 = 72 ;                //SHA-512


wire [63:0]theta[24:0];
wire [63:0]theta_y[4:0];

wire [63:0]rho[24:0];

wire [63:0] pi [24:0];

wire [63:0] chi [24:0];

wire lota [63:0];

wire [63:0]data[24:0];
//wire [63:0]data_mid[24:0];


/*
always @(posedge clk or negedge rst) begin
    integer i;
    if (!rst) begin
        // reset
        
    end
    else if (clk) begin
        for (i = 0; i < 25; i = i + 1)begin:data_block
            data[i] <= data_mid[i] ^ data_in[i*64 +: 64];
        end
    end
end
*/

genvar m;
generate
    for (m=0; m<25; m=m+1) begin: unpack
        assign data[m] = data_in[m*64 +: 64];
    end
endgenerate

//theta
generate
    genvar i;
    genvar j;
//计算奇偶校验值
        for (j = 0; j < 5; j = j + 1)begin:theta_slice_block
            assign theta_y[j] = data[j] ^ data[j+5] ^ data[j+10] ^ data[j+15] ^ data[j+20];
        end
//执行theta操作
        for (i = 0; i < 21; i = i + 5)begin:theta__block
            assign theta[i] = theta_y[4]^theta_y[1]^data[i];
            assign theta[i+1] = theta_y[0]^theta_y[2]^data[i+1];
            assign theta[i+2] = theta_y[1]^theta_y[3]^data[i+2];
            assign theta[i+3] = theta_y[2]^theta_y[4]^data[i+3];
            assign theta[i+4] = theta_y[3]^theta_y[0]^data[i+4];
        end
endgenerate

//rho
assign rho[0]  = theta[0]; 
assign rho[1]  = {theta[1][62:0], theta[1][63]}; 
assign rho[2]  = {theta[2][1:0], theta[2][63:2]}; 
assign rho[3]  = {theta[3][35:0], theta[3][63:36]}; 
assign rho[4]  = {theta[4][36:0], theta[4][63:37]}; 

assign rho[5]  = {theta[5][27:0], theta[5][63:28]}; 
assign rho[6]  = {theta[6][19:0], theta[6][63:20]}; 
assign rho[7]  = {theta[7][57:0], theta[7][63:58]}; 
assign rho[8]  = {theta[8][8:0], theta[8][63:9]}; 
assign rho[9]  = {theta[9][43:0], theta[9][63:44]}; 

assign rho[10] = {theta[10][60:0], theta[10][63:61]}; 
assign rho[11] = {theta[11][53:0], theta[11][63:54]}; 
assign rho[12] = {theta[12][20:0], theta[12][63:21]}; 
assign rho[13] = {theta[13][38:0], theta[13][63:39]}; 
assign rho[14] = {theta[14][24:0], theta[14][63:25]}; 

assign rho[15] = {theta[15][22:0], theta[15][63:23]}; 
assign rho[16] = {theta[16][18:0], theta[16][63:19]}; 
assign rho[17] = {theta[17][48:0], theta[17][63:49]}; 
assign rho[18] = {theta[18][42:0], theta[18][63:43]}; 
assign rho[19] = {theta[19][55:0], theta[19][63:56]}; 

assign rho[20] = {theta[20][45:0], theta[20][63:46]}; 
assign rho[21] = {theta[21][61:0], theta[21][63:62]}; 
assign rho[22] = {theta[22][2:0], theta[22][63:3]}; 
assign rho[23] = {theta[23][7:0], theta[23][63:8]}; 
assign rho[24] = {theta[24][49:0], theta[24][63:50]};


//pi
assign pi[0]  = rho[0];   
assign pi[1]  = rho[6];   
assign pi[2]  = rho[12];  
assign pi[3]  = rho[18];  
assign pi[4]  = rho[24];  

assign pi[5]  = rho[3];   
assign pi[6]  = rho[9];   
assign pi[7]  = rho[10];  
assign pi[8]  = rho[16];  
assign pi[9]  = rho[22];  

assign pi[10] = rho[1];   
assign pi[11] = rho[7];   
assign pi[12] = rho[13];  
assign pi[13] = rho[19];  
assign pi[14] = rho[20];  


assign pi[15] = rho[4];   
assign pi[16] = rho[5];   
assign pi[17] = rho[11];  
assign pi[18] = rho[17];  
assign pi[19] = rho[23];  

assign pi[20] = rho[2];   
assign pi[21] = rho[8];   
assign pi[22] = rho[14];  
assign pi[23] = rho[15];  
assign pi[24] = rho[21];  

//xchi
generate
    genvar k;
    for (k = 0; k < 21; k = k + 5)begin:chi_block
        assign chi[k] = pi[k]^(~pi[k+1]&pi[k+2]);
        assign chi[k+1] = pi[0]^(~pi[k+1]&pi[k+2]);
        assign chi[k+2] = pi[k+2]^(~pi[k+3]&pi[k+4]);
        assign chi[k+3] = pi[k+3]^(~pi[k+4]&pi[k]);
        assign chi[k+4] = pi[k+4]^(~pi[k]&pi[k+1]);
    end
endgenerate

//lota
assign lata = chi[0]^rc;


assign data_out[63:0] = lata;

generate
    genvar l;
     for (l = 1; l < 24; l = l + +1)begin:out_block
        assign data_out[64*l +: 64] = chi[l];
    end
endgenerate
endmodule
