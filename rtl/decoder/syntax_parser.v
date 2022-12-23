`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module syntax_parser
#(
  parameter MAX_FUNNEL_SHIFTER_SIZE = 2*248 - 1
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [3*5-1:0] compNumSamples_p,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [7:0] rc_stuffing_bits,
  input wire [11:0] rcStuffingBitsX9,
  input wire [1:0] bits_per_component_coded,
  input wire [1:0] source_color_space, // Image original color space 0: RGB, 1: YCoCg, 2: YCbCr (YCoCg is impossible)
  input wire [3:0] mppf_bits_per_comp_R_Y,
  input wire [3:0] mppf_bits_per_comp_G_Cb,
  input wire [3:0] mppf_bits_per_comp_B_Cr,
  input wire [3:0] mppf_bits_per_comp_Y,
  input wire [3:0] mppf_bits_per_comp_Co,
  input wire [3:0] mppf_bits_per_comp_Cg,

  input wire [4*MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_p,
  input wire [3:0] fs_ready,
  input wire nextBlockIsFls,
  input wire isFirstParse,
  input wire isLastBlock,
  input wire ssm_sof,
  input wire sos,
  input wire [1:0] sos_fsm,
  input wire [1:0] eos_fsm,
  input wire eos,
  
  output wire [9*4-1:0] size_to_remove_p,
  output wire size_to_remove_valid,
  
  input wire enableUnderflowPrevention,
  
  output reg [2:0] blockMode,
  output reg [2:0] prevBlockMode_r,
  output reg flatnessFlag_r,
  output reg [1:0] flatnessType_r, // 0: very flat; 1: somewhat flat; 2: complex to flat; 3: flat to complex
  output reg [2:0] nextBlockBestIntraPredIdx_r,
  output reg [3:0] bpvTable,
  output wire [6*4-1:0] bpv2x2_p,
  output wire [6*4*2-1:0] bpv2x1_p,
  output wire substream0_parsed,
  output wire substreams123_parsed,
  input wire stall_pull,
  output wire parse_substreams,
  
  output wire [16*3*17-1:0] pQuant_r_p,
  output wire pQuant_r_valid,
  
  output reg [12:0] blockBits,
  output reg blockBits_valid,
  
  output reg [12:0] prevBlockBitsWithoutPadding,
  output wire prevBlockBitsWithoutPadding_valid,
  
  output reg [1:0] blockCsc_r,
  output reg [3:0] blockStepSize_r,
  output reg mppfIndex_r,
  output wire mpp_ctrl_valid // indicates that blockCsc_r & blockStepSize_r are valid

);

wire [2:0] transformEcgMappingLastSigPos_444 [15:0][3:0];
assign  transformEcgMappingLastSigPos_444[0][0] = 3'd0;
assign  transformEcgMappingLastSigPos_444[0][1] = 3'd0;
assign  transformEcgMappingLastSigPos_444[0][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[0][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[1][0] = 3'd0;
assign  transformEcgMappingLastSigPos_444[1][1] = 3'd1;
assign  transformEcgMappingLastSigPos_444[1][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[1][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[2][0] = 3'd0;
assign  transformEcgMappingLastSigPos_444[2][1] = 3'd2;
assign  transformEcgMappingLastSigPos_444[2][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[2][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[3][0] = 3'd0;
assign  transformEcgMappingLastSigPos_444[3][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[3][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[3][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[4][0] = 3'd1;
assign  transformEcgMappingLastSigPos_444[4][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[4][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[4][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[5][0] = 3'd2;
assign  transformEcgMappingLastSigPos_444[5][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[5][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[5][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[6][0] = 3'd3;
assign  transformEcgMappingLastSigPos_444[6][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[6][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[6][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[7][0] = 3'd4;
assign  transformEcgMappingLastSigPos_444[7][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[7][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[7][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[8][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[8][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[8][2] = 3'd0;
assign  transformEcgMappingLastSigPos_444[8][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[9][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[9][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[9][2] = 3'd1;
assign  transformEcgMappingLastSigPos_444[9][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[10][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[10][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[10][2] = 3'd2;
assign  transformEcgMappingLastSigPos_444[10][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[11][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[11][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[11][2] = 3'd3;
assign  transformEcgMappingLastSigPos_444[11][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[12][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[12][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[12][2] = 3'd4;
assign  transformEcgMappingLastSigPos_444[12][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[13][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[13][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[13][2] = 3'd5;
assign  transformEcgMappingLastSigPos_444[13][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[14][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[14][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[14][2] = 3'd6;
assign  transformEcgMappingLastSigPos_444[14][3] = 3'd1;
  
assign  transformEcgMappingLastSigPos_444[15][0] = 3'd5;
assign  transformEcgMappingLastSigPos_444[15][1] = 3'd3;
assign  transformEcgMappingLastSigPos_444[15][2] = 3'd7;
assign  transformEcgMappingLastSigPos_444[15][3] = 3'd1;

// Big constant look up tables

wire [2:0] transformEcgMappingLastSigPos_422 [7:0][3:0];
assign  transformEcgMappingLastSigPos_422[0][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[0][1] = 3'd0;
assign  transformEcgMappingLastSigPos_422[0][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[0][3] = 3'd0;
  
assign  transformEcgMappingLastSigPos_422[1][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[1][1] = 3'd1;
assign  transformEcgMappingLastSigPos_422[1][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[1][3] = 3'd0;
  
assign  transformEcgMappingLastSigPos_422[2][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[2][1] = 3'd2;
assign  transformEcgMappingLastSigPos_422[2][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[2][3] = 3'd0;
        
assign  transformEcgMappingLastSigPos_422[3][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[3][1] = 3'd3;
assign  transformEcgMappingLastSigPos_422[3][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[3][3] = 3'd0;
  
assign  transformEcgMappingLastSigPos_422[4][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[4][1] = 3'd4;
assign  transformEcgMappingLastSigPos_422[4][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[4][3] = 3'd0;
        
assign  transformEcgMappingLastSigPos_422[5][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[5][1] = 3'd5;
assign  transformEcgMappingLastSigPos_422[5][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[5][3] = 3'd0;
        
assign  transformEcgMappingLastSigPos_422[6][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[6][1] = 3'd6;
assign  transformEcgMappingLastSigPos_422[6][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[6][3] = 3'd0;
        
assign  transformEcgMappingLastSigPos_422[7][0] = 3'd1;
assign  transformEcgMappingLastSigPos_422[7][1] = 3'd7;
assign  transformEcgMappingLastSigPos_422[7][2] = 3'd0;
assign  transformEcgMappingLastSigPos_422[7][3] = 3'd0;

wire [2:0] transformEcgMappingLastSigPos_420 [3:0][3:0];
assign  transformEcgMappingLastSigPos_420[0][0] = 3'd1;
assign  transformEcgMappingLastSigPos_420[0][1] = 3'd0;
assign  transformEcgMappingLastSigPos_420[0][2] = 3'd0;
assign  transformEcgMappingLastSigPos_420[0][3] = 3'd0;
  
assign  transformEcgMappingLastSigPos_420[1][0] = 3'd2;
assign  transformEcgMappingLastSigPos_420[1][1] = 3'd0;
assign  transformEcgMappingLastSigPos_420[1][2] = 3'd0;
assign  transformEcgMappingLastSigPos_420[1][3] = 3'd0;
  
assign  transformEcgMappingLastSigPos_420[2][0] = 3'd3;
assign  transformEcgMappingLastSigPos_420[2][1] = 3'd2;
assign  transformEcgMappingLastSigPos_420[2][2] = 3'd0;
assign  transformEcgMappingLastSigPos_420[2][3] = 3'd0;
        
assign  transformEcgMappingLastSigPos_420[3][0] = 3'd4;
assign  transformEcgMappingLastSigPos_420[3][1] = 3'd0;
assign  transformEcgMappingLastSigPos_420[3][2] = 3'd0;
assign  transformEcgMappingLastSigPos_420[3][3] = 3'd0;


wire [3:0] ecIndexMapping_Transform_8x2[15:0];
assign  ecIndexMapping_Transform_8x2[0] = 4'd0;
assign  ecIndexMapping_Transform_8x2[1] = 4'd1;
assign  ecIndexMapping_Transform_8x2[2] = 4'd2;
assign  ecIndexMapping_Transform_8x2[3] = 4'd4;
assign  ecIndexMapping_Transform_8x2[4] = 4'd5;
assign  ecIndexMapping_Transform_8x2[5] = 4'd9;
assign  ecIndexMapping_Transform_8x2[6] = 4'd10;
assign  ecIndexMapping_Transform_8x2[7] = 4'd11;
assign  ecIndexMapping_Transform_8x2[8] = 4'd3;
assign  ecIndexMapping_Transform_8x2[9] = 4'd6;
assign  ecIndexMapping_Transform_8x2[10] = 4'd7;
assign  ecIndexMapping_Transform_8x2[11] = 4'd8;
assign  ecIndexMapping_Transform_8x2[12] = 4'd12;
assign  ecIndexMapping_Transform_8x2[13] = 4'd13;
assign  ecIndexMapping_Transform_8x2[14] = 4'd14;
assign  ecIndexMapping_Transform_8x2[15] = 4'd15;

wire [3:0] ecIndexMapping_BP_8x2[15:0];
assign ecIndexMapping_BP_8x2[0] = 4'd0;
assign ecIndexMapping_BP_8x2[1] = 4'd1;
assign ecIndexMapping_BP_8x2[2] = 4'd4;
assign ecIndexMapping_BP_8x2[3] = 4'd5;
assign ecIndexMapping_BP_8x2[4] = 4'd8;
assign ecIndexMapping_BP_8x2[5] = 4'd9;
assign ecIndexMapping_BP_8x2[6] = 4'd12;
assign ecIndexMapping_BP_8x2[7] = 4'd13;
assign ecIndexMapping_BP_8x2[8] = 4'd2;
assign ecIndexMapping_BP_8x2[9] = 4'd3;
assign ecIndexMapping_BP_8x2[10] = 4'd6;
assign ecIndexMapping_BP_8x2[11] = 4'd7;
assign ecIndexMapping_BP_8x2[12] = 4'd10;
assign ecIndexMapping_BP_8x2[13] = 4'd11;
assign ecIndexMapping_BP_8x2[14] = 4'd14;
assign ecIndexMapping_BP_8x2[15] = 4'd15;

wire [2:0] ecIndexMapping_BP_4x2[7:0];
assign ecIndexMapping_BP_4x2[0] = 3'd0;
assign ecIndexMapping_BP_4x2[1] = 3'd1;
assign ecIndexMapping_BP_4x2[2] = 3'd4;
assign ecIndexMapping_BP_4x2[3] = 3'd5;
assign ecIndexMapping_BP_4x2[4] = 3'd2;
assign ecIndexMapping_BP_4x2[5] = 3'd3;
assign ecIndexMapping_BP_4x2[6] = 3'd6;
assign ecIndexMapping_BP_4x2[7] = 3'd7;

wire [3:0] vec_2c_bitsReq_1_luma_inv [15:0];
assign vec_2c_bitsReq_1_luma_inv[0] = 4'd2;
assign vec_2c_bitsReq_1_luma_inv[1] = 4'd1;
assign vec_2c_bitsReq_1_luma_inv[2] = 4'd8;
assign vec_2c_bitsReq_1_luma_inv[3] = 4'd4;
assign vec_2c_bitsReq_1_luma_inv[4] = 4'd3;
assign vec_2c_bitsReq_1_luma_inv[5] = 4'd5;
assign vec_2c_bitsReq_1_luma_inv[6] = 4'd10;
assign vec_2c_bitsReq_1_luma_inv[7] = 4'd12;
assign vec_2c_bitsReq_1_luma_inv[8] = 4'd9;
assign vec_2c_bitsReq_1_luma_inv[9] = 4'd6;
assign vec_2c_bitsReq_1_luma_inv[10]= 4'd7;
assign vec_2c_bitsReq_1_luma_inv[11]= 4'd11;
assign vec_2c_bitsReq_1_luma_inv[12]= 4'd14;
assign vec_2c_bitsReq_1_luma_inv[13]= 4'd13;
assign vec_2c_bitsReq_1_luma_inv[14]= 4'd15;
assign vec_2c_bitsReq_1_luma_inv[15]= 4'd0;

wire [3:0] vec_2c_bitsReq_1_chroma_inv [15:0]; 
assign vec_2c_bitsReq_1_chroma_inv[0] = 4'd2;
assign vec_2c_bitsReq_1_chroma_inv[1] = 4'd1;
assign vec_2c_bitsReq_1_chroma_inv[2] = 4'd4;
assign vec_2c_bitsReq_1_chroma_inv[3] = 4'd8;
assign vec_2c_bitsReq_1_chroma_inv[4] = 4'd3;
assign vec_2c_bitsReq_1_chroma_inv[5] = 4'd12;
assign vec_2c_bitsReq_1_chroma_inv[6] = 4'd5;
assign vec_2c_bitsReq_1_chroma_inv[7] = 4'd10;
assign vec_2c_bitsReq_1_chroma_inv[8] = 4'd6;
assign vec_2c_bitsReq_1_chroma_inv[9] = 4'd9;
assign vec_2c_bitsReq_1_chroma_inv[10]= 4'd15;
assign vec_2c_bitsReq_1_chroma_inv[11]= 4'd7;
assign vec_2c_bitsReq_1_chroma_inv[12]= 4'd11;
assign vec_2c_bitsReq_1_chroma_inv[13]= 4'd13;
assign vec_2c_bitsReq_1_chroma_inv[14]= 4'd14;
assign vec_2c_bitsReq_1_chroma_inv[15]= 4'd0;

wire [7:0] vec_2c_bitsReq_2_luma_inv [0:255];
assign vec_2c_bitsReq_2_luma_inv[0] =   8'd1;
assign vec_2c_bitsReq_2_luma_inv[1] =   8'd4;
assign vec_2c_bitsReq_2_luma_inv[2] =   8'd64;
assign vec_2c_bitsReq_2_luma_inv[3] =   8'd16;
assign vec_2c_bitsReq_2_luma_inv[4] =   8'd68;
assign vec_2c_bitsReq_2_luma_inv[5] =   8'd17;
assign vec_2c_bitsReq_2_luma_inv[6] =   8'd5;
assign vec_2c_bitsReq_2_luma_inv[7] =   8'd80;
assign vec_2c_bitsReq_2_luma_inv[8] =   8'd65;
assign vec_2c_bitsReq_2_luma_inv[9] =   8'd20;
assign vec_2c_bitsReq_2_luma_inv[10]=  8'd193;
assign vec_2c_bitsReq_2_luma_inv[11]=  8'd67;
assign vec_2c_bitsReq_2_luma_inv[12]=  8'd52;
assign vec_2c_bitsReq_2_luma_inv[13]=  8'd28;
assign vec_2c_bitsReq_2_luma_inv[14]=  8'd49;
assign vec_2c_bitsReq_2_luma_inv[15]=  8'd19;
assign vec_2c_bitsReq_2_luma_inv[16]=  8'd196;
assign vec_2c_bitsReq_2_luma_inv[17]=  8'd76;
assign vec_2c_bitsReq_2_luma_inv[18]=  8'd7;
assign vec_2c_bitsReq_2_luma_inv[19]=  8'd13;
assign vec_2c_bitsReq_2_luma_inv[20]=  8'd8;
assign vec_2c_bitsReq_2_luma_inv[21]=  8'd2;
assign vec_2c_bitsReq_2_luma_inv[22]=  8'd208;
assign vec_2c_bitsReq_2_luma_inv[23]=  8'd112;
assign vec_2c_bitsReq_2_luma_inv[24]=  8'd32;
assign vec_2c_bitsReq_2_luma_inv[25]=  8'd128;
assign vec_2c_bitsReq_2_luma_inv[26]=  8'd69;
assign vec_2c_bitsReq_2_luma_inv[27]=  8'd21;
assign vec_2c_bitsReq_2_luma_inv[28]=  8'd84;
assign vec_2c_bitsReq_2_luma_inv[29]=  8'd81;
assign vec_2c_bitsReq_2_luma_inv[30]=  8'd71;
assign vec_2c_bitsReq_2_luma_inv[31]=  8'd14;
assign vec_2c_bitsReq_2_luma_inv[32]=  8'd31;
assign vec_2c_bitsReq_2_luma_inv[33]=  8'd50;
assign vec_2c_bitsReq_2_luma_inv[34]=  8'd53;
assign vec_2c_bitsReq_2_luma_inv[35]=  8'd241;
assign vec_2c_bitsReq_2_luma_inv[36]=  8'd23;
assign vec_2c_bitsReq_2_luma_inv[37]=  8'd92;
assign vec_2c_bitsReq_2_luma_inv[38]=  8'd79;
assign vec_2c_bitsReq_2_luma_inv[39]=  8'd29;
assign vec_2c_bitsReq_2_luma_inv[40]=  8'd244;
assign vec_2c_bitsReq_2_luma_inv[41]=  8'd83;
assign vec_2c_bitsReq_2_luma_inv[42]=  8'd11;
assign vec_2c_bitsReq_2_luma_inv[43]=  8'd197;
assign vec_2c_bitsReq_2_luma_inv[44]=  8'd209;
assign vec_2c_bitsReq_2_luma_inv[45]=  8'd200;
assign vec_2c_bitsReq_2_luma_inv[46]=  8'd115;
assign vec_2c_bitsReq_2_luma_inv[47]=  8'd212;
assign vec_2c_bitsReq_2_luma_inv[48]=  8'd205;
assign vec_2c_bitsReq_2_luma_inv[49]=  8'd116;
assign vec_2c_bitsReq_2_luma_inv[50]=  8'd113;
assign vec_2c_bitsReq_2_luma_inv[51]=  8'd140;
assign vec_2c_bitsReq_2_luma_inv[52]=  8'd66;
assign vec_2c_bitsReq_2_luma_inv[53]=  8'd224;
assign vec_2c_bitsReq_2_luma_inv[54]=  8'd61;
assign vec_2c_bitsReq_2_luma_inv[55]=  8'd35;
assign vec_2c_bitsReq_2_luma_inv[56]=  8'd124;
assign vec_2c_bitsReq_2_luma_inv[57]=  8'd55;
assign vec_2c_bitsReq_2_luma_inv[58]=  8'd77;
assign vec_2c_bitsReq_2_luma_inv[59]=  8'd220;
assign vec_2c_bitsReq_2_luma_inv[60]=  8'd72;
assign vec_2c_bitsReq_2_luma_inv[61]=  8'd176;
assign vec_2c_bitsReq_2_luma_inv[62]=  8'd199;
assign vec_2c_bitsReq_2_luma_inv[63]=  8'd132;
assign vec_2c_bitsReq_2_luma_inv[64]=  8'd129;
assign vec_2c_bitsReq_2_luma_inv[65]=  8'd36;
assign vec_2c_bitsReq_2_luma_inv[66]=  8'd33;
assign vec_2c_bitsReq_2_luma_inv[67]=  8'd18;
assign vec_2c_bitsReq_2_luma_inv[68]=  8'd211;
assign vec_2c_bitsReq_2_luma_inv[69]=  8'd24;
assign vec_2c_bitsReq_2_luma_inv[70]=  8'd9;
assign vec_2c_bitsReq_2_luma_inv[71]=  8'd6;
assign vec_2c_bitsReq_2_luma_inv[72]=  8'd85;
assign vec_2c_bitsReq_2_luma_inv[73]=  8'd96;
assign vec_2c_bitsReq_2_luma_inv[74]=  8'd44;
assign vec_2c_bitsReq_2_luma_inv[75]=  8'd56;
assign vec_2c_bitsReq_2_luma_inv[76]=  8'd144;
assign vec_2c_bitsReq_2_luma_inv[77]=  8'd194;
assign vec_2c_bitsReq_2_luma_inv[78]=  8'd131;
assign vec_2c_bitsReq_2_luma_inv[79]=  8'd10;
assign vec_2c_bitsReq_2_luma_inv[80]=  8'd34;
assign vec_2c_bitsReq_2_luma_inv[81]=  8'd136;
assign vec_2c_bitsReq_2_luma_inv[82]=  8'd245;
assign vec_2c_bitsReq_2_luma_inv[83]=  8'd95;
assign vec_2c_bitsReq_2_luma_inv[84]=  8'd203;
assign vec_2c_bitsReq_2_luma_inv[85]=  8'd62;
assign vec_2c_bitsReq_2_luma_inv[86]=  8'd160;
assign vec_2c_bitsReq_2_luma_inv[87]=  8'd119;
assign vec_2c_bitsReq_2_luma_inv[88]=  8'd215;
assign vec_2c_bitsReq_2_luma_inv[89]=  8'd125;
assign vec_2c_bitsReq_2_luma_inv[90]=  8'd221;
assign vec_2c_bitsReq_2_luma_inv[91]=  8'd78;
assign vec_2c_bitsReq_2_luma_inv[92]=  8'd188;
assign vec_2c_bitsReq_2_luma_inv[93]=  8'd73;
assign vec_2c_bitsReq_2_luma_inv[94]=  8'd27;
assign vec_2c_bitsReq_2_luma_inv[95]=  8'd114;
assign vec_2c_bitsReq_2_luma_inv[96]=  8'd87;
assign vec_2c_bitsReq_2_luma_inv[97]=  8'd30;
assign vec_2c_bitsReq_2_luma_inv[98]=  8'd47;
assign vec_2c_bitsReq_2_luma_inv[99]=  8'd117;
assign vec_2c_bitsReq_2_luma_inv[100]= 8'd97;
assign vec_2c_bitsReq_2_luma_inv[101]= 8'd228;
assign vec_2c_bitsReq_2_luma_inv[102]= 8'd75;
assign vec_2c_bitsReq_2_luma_inv[103]= 8'd227;
assign vec_2c_bitsReq_2_luma_inv[104]= 8'd177;
assign vec_2c_bitsReq_2_luma_inv[105]= 8'd206;
assign vec_2c_bitsReq_2_luma_inv[106]= 8'd133;
assign vec_2c_bitsReq_2_luma_inv[107]= 8'd93;
assign vec_2c_bitsReq_2_luma_inv[108]= 8'd248;
assign vec_2c_bitsReq_2_luma_inv[109]= 8'd59;
assign vec_2c_bitsReq_2_luma_inv[110]= 8'd37;
assign vec_2c_bitsReq_2_luma_inv[111]= 8'd88;
assign vec_2c_bitsReq_2_luma_inv[112]= 8'd127;
assign vec_2c_bitsReq_2_luma_inv[113]= 8'd180;
assign vec_2c_bitsReq_2_luma_inv[114]= 8'd225;
assign vec_2c_bitsReq_2_luma_inv[115]= 8'd213;
assign vec_2c_bitsReq_2_luma_inv[116]= 8'd70;
assign vec_2c_bitsReq_2_luma_inv[117]= 8'd148;
assign vec_2c_bitsReq_2_luma_inv[118]= 8'd242;
assign vec_2c_bitsReq_2_luma_inv[119]= 8'd223;
assign vec_2c_bitsReq_2_luma_inv[120]= 8'd82;
assign vec_2c_bitsReq_2_luma_inv[121]= 8'd25;
assign vec_2c_bitsReq_2_luma_inv[122]= 8'd236;
assign vec_2c_bitsReq_2_luma_inv[123]= 8'd247;
assign vec_2c_bitsReq_2_luma_inv[124]= 8'd179;
assign vec_2c_bitsReq_2_luma_inv[125]= 8'd141;
assign vec_2c_bitsReq_2_luma_inv[126]= 8'd216;
assign vec_2c_bitsReq_2_luma_inv[127]= 8'd22;
assign vec_2c_bitsReq_2_luma_inv[128]= 8'd99;
assign vec_2c_bitsReq_2_luma_inv[129]= 8'd45;
assign vec_2c_bitsReq_2_luma_inv[130]= 8'd210;
assign vec_2c_bitsReq_2_luma_inv[131]= 8'd120;
assign vec_2c_bitsReq_2_luma_inv[132]= 8'd57;
assign vec_2c_bitsReq_2_luma_inv[133]= 8'd201;
assign vec_2c_bitsReq_2_luma_inv[134]= 8'd135;
assign vec_2c_bitsReq_2_luma_inv[135]= 8'd39;
assign vec_2c_bitsReq_2_luma_inv[136]= 8'd100;
assign vec_2c_bitsReq_2_luma_inv[137]= 8'd147;
assign vec_2c_bitsReq_2_luma_inv[138]= 8'd253;
assign vec_2c_bitsReq_2_luma_inv[139]= 8'd143;
assign vec_2c_bitsReq_2_luma_inv[140]= 8'd40;
assign vec_2c_bitsReq_2_luma_inv[141]= 8'd145;
assign vec_2c_bitsReq_2_luma_inv[142]= 8'd156;
assign vec_2c_bitsReq_2_luma_inv[143]= 8'd54;
assign vec_2c_bitsReq_2_luma_inv[144]= 8'd198;
assign vec_2c_bitsReq_2_luma_inv[145]= 8'd108;
assign vec_2c_bitsReq_2_luma_inv[146]= 8'd130;
assign vec_2c_bitsReq_2_luma_inv[147]= 8'd254;
assign vec_2c_bitsReq_2_luma_inv[148]= 8'd251;
assign vec_2c_bitsReq_2_luma_inv[149]= 8'd202;
assign vec_2c_bitsReq_2_luma_inv[150]= 8'd250;
assign vec_2c_bitsReq_2_luma_inv[151]= 8'd239;
assign vec_2c_bitsReq_2_luma_inv[152]= 8'd191;
assign vec_2c_bitsReq_2_luma_inv[153]= 8'd184;
assign vec_2c_bitsReq_2_luma_inv[154]= 8'd58;
assign vec_2c_bitsReq_2_luma_inv[155]= 8'd161;
assign vec_2c_bitsReq_2_luma_inv[156]= 8'd229;
assign vec_2c_bitsReq_2_luma_inv[157]= 8'd91;
assign vec_2c_bitsReq_2_luma_inv[158]= 8'd121;
assign vec_2c_bitsReq_2_luma_inv[159]= 8'd109;
assign vec_2c_bitsReq_2_luma_inv[160]= 8'd26;
assign vec_2c_bitsReq_2_luma_inv[161]= 8'd94;
assign vec_2c_bitsReq_2_luma_inv[162]= 8'd46;
assign vec_2c_bitsReq_2_luma_inv[163]= 8'd163;
assign vec_2c_bitsReq_2_luma_inv[164]= 8'd74;
assign vec_2c_bitsReq_2_luma_inv[165]= 8'd118;
assign vec_2c_bitsReq_2_luma_inv[166]= 8'd181;
assign vec_2c_bitsReq_2_luma_inv[167]= 8'd226;
assign vec_2c_bitsReq_2_luma_inv[168]= 8'd172;
assign vec_2c_bitsReq_2_luma_inv[169]= 8'd139;
assign vec_2c_bitsReq_2_luma_inv[170]= 8'd164;
assign vec_2c_bitsReq_2_luma_inv[171]= 8'd86;
assign vec_2c_bitsReq_2_luma_inv[172]= 8'd217;
assign vec_2c_bitsReq_2_luma_inv[173]= 8'd151;
assign vec_2c_bitsReq_2_luma_inv[174]= 8'd43;
assign vec_2c_bitsReq_2_luma_inv[175]= 8'd214;
assign vec_2c_bitsReq_2_luma_inv[176]= 8'd103;
assign vec_2c_bitsReq_2_luma_inv[177]= 8'd137;
assign vec_2c_bitsReq_2_luma_inv[178]= 8'd157;
assign vec_2c_bitsReq_2_luma_inv[179]= 8'd38;
assign vec_2c_bitsReq_2_luma_inv[180]= 8'd98;
assign vec_2c_bitsReq_2_luma_inv[181]= 8'd101;
assign vec_2c_bitsReq_2_luma_inv[182]= 8'd232;
assign vec_2c_bitsReq_2_luma_inv[183]= 8'd104;
assign vec_2c_bitsReq_2_luma_inv[184]= 8'd89;
assign vec_2c_bitsReq_2_luma_inv[185]= 8'd149;
assign vec_2c_bitsReq_2_luma_inv[186]= 8'd134;
assign vec_2c_bitsReq_2_luma_inv[187]= 8'd231;
assign vec_2c_bitsReq_2_luma_inv[188]= 8'd123;
assign vec_2c_bitsReq_2_luma_inv[189]= 8'd189;
assign vec_2c_bitsReq_2_luma_inv[190]= 8'd126;
assign vec_2c_bitsReq_2_luma_inv[191]= 8'd178;
assign vec_2c_bitsReq_2_luma_inv[192]= 8'd222;
assign vec_2c_bitsReq_2_luma_inv[193]= 8'd183;
assign vec_2c_bitsReq_2_luma_inv[194]= 8'd187;
assign vec_2c_bitsReq_2_luma_inv[195]= 8'd152;
assign vec_2c_bitsReq_2_luma_inv[196]= 8'd41;
assign vec_2c_bitsReq_2_luma_inv[197]= 8'd142;
assign vec_2c_bitsReq_2_luma_inv[198]= 8'd146;
assign vec_2c_bitsReq_2_luma_inv[199]= 8'd246;
assign vec_2c_bitsReq_2_luma_inv[200]= 8'd219;
assign vec_2c_bitsReq_2_luma_inv[201]= 8'd111;
assign vec_2c_bitsReq_2_luma_inv[202]= 8'd238;
assign vec_2c_bitsReq_2_luma_inv[203]= 8'd249;
assign vec_2c_bitsReq_2_luma_inv[204]= 8'd237;
assign vec_2c_bitsReq_2_luma_inv[205]= 8'd175;
assign vec_2c_bitsReq_2_luma_inv[206]= 8'd90;
assign vec_2c_bitsReq_2_luma_inv[207]= 8'd159;
assign vec_2c_bitsReq_2_luma_inv[208]= 8'd165;
assign vec_2c_bitsReq_2_luma_inv[209]= 8'd42;
assign vec_2c_bitsReq_2_luma_inv[210]= 8'd138;
assign vec_2c_bitsReq_2_luma_inv[211]= 8'd190;
assign vec_2c_bitsReq_2_luma_inv[212]= 8'd235;
assign vec_2c_bitsReq_2_luma_inv[213]= 8'd153;
assign vec_2c_bitsReq_2_luma_inv[214]= 8'd186;
assign vec_2c_bitsReq_2_luma_inv[215]= 8'd168;
assign vec_2c_bitsReq_2_luma_inv[216]= 8'd162;
assign vec_2c_bitsReq_2_luma_inv[217]= 8'd170;
assign vec_2c_bitsReq_2_luma_inv[218]= 8'd102;
assign vec_2c_bitsReq_2_luma_inv[219]= 8'd230;
assign vec_2c_bitsReq_2_luma_inv[220]= 8'd234;
assign vec_2c_bitsReq_2_luma_inv[221]= 8'd167;
assign vec_2c_bitsReq_2_luma_inv[222]= 8'd150;
assign vec_2c_bitsReq_2_luma_inv[223]= 8'd105;
assign vec_2c_bitsReq_2_luma_inv[224]= 8'd185;
assign vec_2c_bitsReq_2_luma_inv[225]= 8'd218;
assign vec_2c_bitsReq_2_luma_inv[226]= 8'd174;
assign vec_2c_bitsReq_2_luma_inv[227]= 8'd155;
assign vec_2c_bitsReq_2_luma_inv[228]= 8'd110;
assign vec_2c_bitsReq_2_luma_inv[229]= 8'd171;
assign vec_2c_bitsReq_2_luma_inv[230]= 8'd173;
assign vec_2c_bitsReq_2_luma_inv[231]= 8'd122;
assign vec_2c_bitsReq_2_luma_inv[232]= 8'd158;
assign vec_2c_bitsReq_2_luma_inv[233]= 8'd182;
assign vec_2c_bitsReq_2_luma_inv[234]= 8'd233;
assign vec_2c_bitsReq_2_luma_inv[235]= 8'd107;
assign vec_2c_bitsReq_2_luma_inv[236]= 8'd154;
assign vec_2c_bitsReq_2_luma_inv[237]= 8'd106;
assign vec_2c_bitsReq_2_luma_inv[238]= 8'd166;
assign vec_2c_bitsReq_2_luma_inv[239]= 8'd169;
assign vec_2c_bitsReq_2_luma_inv[240]= 8'd255;
assign vec_2c_bitsReq_2_luma_inv[241]= 8'd63;
assign vec_2c_bitsReq_2_luma_inv[242]= 8'd207;
assign vec_2c_bitsReq_2_luma_inv[243]= 8'd15;
assign vec_2c_bitsReq_2_luma_inv[244]= 8'd243;
assign vec_2c_bitsReq_2_luma_inv[245]= 8'd51;
assign vec_2c_bitsReq_2_luma_inv[246]= 8'd195;
assign vec_2c_bitsReq_2_luma_inv[247]= 8'd3;
assign vec_2c_bitsReq_2_luma_inv[248]= 8'd252;
assign vec_2c_bitsReq_2_luma_inv[249]= 8'd60;
assign vec_2c_bitsReq_2_luma_inv[250]= 8'd204;
assign vec_2c_bitsReq_2_luma_inv[251]= 8'd12;
assign vec_2c_bitsReq_2_luma_inv[252]= 8'd240;
assign vec_2c_bitsReq_2_luma_inv[253]= 8'd48;
assign vec_2c_bitsReq_2_luma_inv[254]= 8'd192;
assign vec_2c_bitsReq_2_luma_inv[255]= 8'd0;

wire [7:0] vec_2c_bitsReq_2_chroma_inv [0:255];
assign vec_2c_bitsReq_2_chroma_inv[0]   = 8'd4;
assign vec_2c_bitsReq_2_chroma_inv[1]   = 8'd1;
assign vec_2c_bitsReq_2_chroma_inv[2]   = 8'd64;
assign vec_2c_bitsReq_2_chroma_inv[3]   = 8'd16;
assign vec_2c_bitsReq_2_chroma_inv[4]   = 8'd5;
assign vec_2c_bitsReq_2_chroma_inv[5]   = 8'd80;
assign vec_2c_bitsReq_2_chroma_inv[6]   = 8'd17;
assign vec_2c_bitsReq_2_chroma_inv[7]   = 8'd68;
assign vec_2c_bitsReq_2_chroma_inv[8]   = 8'd65;
assign vec_2c_bitsReq_2_chroma_inv[9]   = 8'd20;
assign vec_2c_bitsReq_2_chroma_inv[10]  = 8'd67;
assign vec_2c_bitsReq_2_chroma_inv[11]  = 8'd52;
assign vec_2c_bitsReq_2_chroma_inv[12]  = 8'd28;
assign vec_2c_bitsReq_2_chroma_inv[13]  = 8'd193;
assign vec_2c_bitsReq_2_chroma_inv[14]  = 8'd13;
assign vec_2c_bitsReq_2_chroma_inv[15]  = 8'd76;
assign vec_2c_bitsReq_2_chroma_inv[16]  = 8'd7;
assign vec_2c_bitsReq_2_chroma_inv[17]  = 8'd112;
assign vec_2c_bitsReq_2_chroma_inv[18]  = 8'd208;
assign vec_2c_bitsReq_2_chroma_inv[19]  = 8'd49;
assign vec_2c_bitsReq_2_chroma_inv[20]  = 8'd19;
assign vec_2c_bitsReq_2_chroma_inv[21]  = 8'd196;
assign vec_2c_bitsReq_2_chroma_inv[22]  = 8'd2;
assign vec_2c_bitsReq_2_chroma_inv[23]  = 8'd8;
assign vec_2c_bitsReq_2_chroma_inv[24]  = 8'd128;
assign vec_2c_bitsReq_2_chroma_inv[25]  = 8'd32;
assign vec_2c_bitsReq_2_chroma_inv[26]  = 8'd85;
assign vec_2c_bitsReq_2_chroma_inv[27]  = 8'd21;
assign vec_2c_bitsReq_2_chroma_inv[28]  = 8'd69;
assign vec_2c_bitsReq_2_chroma_inv[29]  = 8'd81;
assign vec_2c_bitsReq_2_chroma_inv[30]  = 8'd84;
assign vec_2c_bitsReq_2_chroma_inv[31]  = 8'd10;
assign vec_2c_bitsReq_2_chroma_inv[32]  = 8'd14;
assign vec_2c_bitsReq_2_chroma_inv[33]  = 8'd11;
assign vec_2c_bitsReq_2_chroma_inv[34]  = 8'd79;
assign vec_2c_bitsReq_2_chroma_inv[35]  = 8'd53;
assign vec_2c_bitsReq_2_chroma_inv[36]  = 8'd224;
assign vec_2c_bitsReq_2_chroma_inv[37]  = 8'd176;
assign vec_2c_bitsReq_2_chroma_inv[38]  = 8'd50;
assign vec_2c_bitsReq_2_chroma_inv[39]  = 8'd241;
assign vec_2c_bitsReq_2_chroma_inv[40]  = 8'd244;
assign vec_2c_bitsReq_2_chroma_inv[41]  = 8'd31;
assign vec_2c_bitsReq_2_chroma_inv[42]  = 8'd200;
assign vec_2c_bitsReq_2_chroma_inv[43]  = 8'd29;
assign vec_2c_bitsReq_2_chroma_inv[44]  = 8'd83;
assign vec_2c_bitsReq_2_chroma_inv[45]  = 8'd197;
assign vec_2c_bitsReq_2_chroma_inv[46]  = 8'd92;
assign vec_2c_bitsReq_2_chroma_inv[47]  = 8'd160;
assign vec_2c_bitsReq_2_chroma_inv[48]  = 8'd209;
assign vec_2c_bitsReq_2_chroma_inv[49]  = 8'd71;
assign vec_2c_bitsReq_2_chroma_inv[50]  = 8'd115;
assign vec_2c_bitsReq_2_chroma_inv[51]  = 8'd205;
assign vec_2c_bitsReq_2_chroma_inv[52]  = 8'd116;
assign vec_2c_bitsReq_2_chroma_inv[53]  = 8'd55;
assign vec_2c_bitsReq_2_chroma_inv[54]  = 8'd140;
assign vec_2c_bitsReq_2_chroma_inv[55]  = 8'd35;
assign vec_2c_bitsReq_2_chroma_inv[56]  = 8'd220;
assign vec_2c_bitsReq_2_chroma_inv[57]  = 8'd95;
assign vec_2c_bitsReq_2_chroma_inv[58]  = 8'd245;
assign vec_2c_bitsReq_2_chroma_inv[59]  = 8'd77;
assign vec_2c_bitsReq_2_chroma_inv[60]  = 8'd113;
assign vec_2c_bitsReq_2_chroma_inv[61]  = 8'd66;
assign vec_2c_bitsReq_2_chroma_inv[62]  = 8'd24;
assign vec_2c_bitsReq_2_chroma_inv[63]  = 8'd36;
assign vec_2c_bitsReq_2_chroma_inv[64]  = 8'd6;
assign vec_2c_bitsReq_2_chroma_inv[65]  = 8'd129;
assign vec_2c_bitsReq_2_chroma_inv[66]  = 8'd211;
assign vec_2c_bitsReq_2_chroma_inv[67]  = 8'd124;
assign vec_2c_bitsReq_2_chroma_inv[68]  = 8'd23;
assign vec_2c_bitsReq_2_chroma_inv[69]  = 8'd212;
assign vec_2c_bitsReq_2_chroma_inv[70]  = 8'd199;
assign vec_2c_bitsReq_2_chroma_inv[71]  = 8'd56;
assign vec_2c_bitsReq_2_chroma_inv[72]  = 8'd194;
assign vec_2c_bitsReq_2_chroma_inv[73]  = 8'd61;
assign vec_2c_bitsReq_2_chroma_inv[74]  = 8'd34;
assign vec_2c_bitsReq_2_chroma_inv[75]  = 8'd9;
assign vec_2c_bitsReq_2_chroma_inv[76]  = 8'd203;
assign vec_2c_bitsReq_2_chroma_inv[77]  = 8'd144;
assign vec_2c_bitsReq_2_chroma_inv[78]  = 8'd96;
assign vec_2c_bitsReq_2_chroma_inv[79]  = 8'd18;
assign vec_2c_bitsReq_2_chroma_inv[80]  = 8'd136;
assign vec_2c_bitsReq_2_chroma_inv[81]  = 8'd62;
assign vec_2c_bitsReq_2_chroma_inv[82]  = 8'd44;
assign vec_2c_bitsReq_2_chroma_inv[83]  = 8'd132;
assign vec_2c_bitsReq_2_chroma_inv[84]  = 8'd131;
assign vec_2c_bitsReq_2_chroma_inv[85]  = 8'd33;
assign vec_2c_bitsReq_2_chroma_inv[86]  = 8'd72;
assign vec_2c_bitsReq_2_chroma_inv[87]  = 8'd250;
assign vec_2c_bitsReq_2_chroma_inv[88]  = 8'd227;
assign vec_2c_bitsReq_2_chroma_inv[89]  = 8'd221;
assign vec_2c_bitsReq_2_chroma_inv[90]  = 8'd119;
assign vec_2c_bitsReq_2_chroma_inv[91]  = 8'd188;
assign vec_2c_bitsReq_2_chroma_inv[92]  = 8'd175;
assign vec_2c_bitsReq_2_chroma_inv[93]  = 8'd254;
assign vec_2c_bitsReq_2_chroma_inv[94]  = 8'd251;
assign vec_2c_bitsReq_2_chroma_inv[95]  = 8'd59;
assign vec_2c_bitsReq_2_chroma_inv[96]  = 8'd78;
assign vec_2c_bitsReq_2_chroma_inv[97]  = 8'd206;
assign vec_2c_bitsReq_2_chroma_inv[98]  = 8'd248;
assign vec_2c_bitsReq_2_chroma_inv[99]  = 8'd239;
assign vec_2c_bitsReq_2_chroma_inv[100] = 8'd27;
assign vec_2c_bitsReq_2_chroma_inv[101] = 8'd228;
assign vec_2c_bitsReq_2_chroma_inv[102] = 8'd191;
assign vec_2c_bitsReq_2_chroma_inv[103] = 8'd47;
assign vec_2c_bitsReq_2_chroma_inv[104] = 8'd177;
assign vec_2c_bitsReq_2_chroma_inv[105] = 8'd236;
assign vec_2c_bitsReq_2_chroma_inv[106] = 8'd143;
assign vec_2c_bitsReq_2_chroma_inv[107] = 8'd242;
assign vec_2c_bitsReq_2_chroma_inv[108] = 8'd58;
assign vec_2c_bitsReq_2_chroma_inv[109] = 8'd202;
assign vec_2c_bitsReq_2_chroma_inv[110] = 8'd179;
assign vec_2c_bitsReq_2_chroma_inv[111] = 8'd114;
assign vec_2c_bitsReq_2_chroma_inv[112] = 8'd93;
assign vec_2c_bitsReq_2_chroma_inv[113] = 8'd223;
assign vec_2c_bitsReq_2_chroma_inv[114] = 8'd39;
assign vec_2c_bitsReq_2_chroma_inv[115] = 8'd170;
assign vec_2c_bitsReq_2_chroma_inv[116] = 8'd117;
assign vec_2c_bitsReq_2_chroma_inv[117] = 8'd30;
assign vec_2c_bitsReq_2_chroma_inv[118] = 8'd141;
assign vec_2c_bitsReq_2_chroma_inv[119] = 8'd247;
assign vec_2c_bitsReq_2_chroma_inv[120] = 8'd225;
assign vec_2c_bitsReq_2_chroma_inv[121] = 8'd213;
assign vec_2c_bitsReq_2_chroma_inv[122] = 8'd127;
assign vec_2c_bitsReq_2_chroma_inv[123] = 8'd253;
assign vec_2c_bitsReq_2_chroma_inv[124] = 8'd216;
assign vec_2c_bitsReq_2_chroma_inv[125] = 8'd54;
assign vec_2c_bitsReq_2_chroma_inv[126] = 8'd70;
assign vec_2c_bitsReq_2_chroma_inv[127] = 8'd75;
assign vec_2c_bitsReq_2_chroma_inv[128] = 8'd87;
assign vec_2c_bitsReq_2_chroma_inv[129] = 8'd180;
assign vec_2c_bitsReq_2_chroma_inv[130] = 8'd172;
assign vec_2c_bitsReq_2_chroma_inv[131] = 8'd133;
assign vec_2c_bitsReq_2_chroma_inv[132] = 8'd99;
assign vec_2c_bitsReq_2_chroma_inv[133] = 8'd90;
assign vec_2c_bitsReq_2_chroma_inv[134] = 8'd165;
assign vec_2c_bitsReq_2_chroma_inv[135] = 8'd37;
assign vec_2c_bitsReq_2_chroma_inv[136] = 8'd201;
assign vec_2c_bitsReq_2_chroma_inv[137] = 8'd82;
assign vec_2c_bitsReq_2_chroma_inv[138] = 8'd163;
assign vec_2c_bitsReq_2_chroma_inv[139] = 8'd238;
assign vec_2c_bitsReq_2_chroma_inv[140] = 8'd88;
assign vec_2c_bitsReq_2_chroma_inv[141] = 8'd145;
assign vec_2c_bitsReq_2_chroma_inv[142] = 8'd46;
assign vec_2c_bitsReq_2_chroma_inv[143] = 8'd26;
assign vec_2c_bitsReq_2_chroma_inv[144] = 8'd74;
assign vec_2c_bitsReq_2_chroma_inv[145] = 8'd156;
assign vec_2c_bitsReq_2_chroma_inv[146] = 8'd100;
assign vec_2c_bitsReq_2_chroma_inv[147] = 8'd187;
assign vec_2c_bitsReq_2_chroma_inv[148] = 8'd226;
assign vec_2c_bitsReq_2_chroma_inv[149] = 8'd215;
assign vec_2c_bitsReq_2_chroma_inv[150] = 8'd25;
assign vec_2c_bitsReq_2_chroma_inv[151] = 8'd161;
assign vec_2c_bitsReq_2_chroma_inv[152] = 8'd184;
assign vec_2c_bitsReq_2_chroma_inv[153] = 8'd125;
assign vec_2c_bitsReq_2_chroma_inv[154] = 8'd91;
assign vec_2c_bitsReq_2_chroma_inv[155] = 8'd94;
assign vec_2c_bitsReq_2_chroma_inv[156] = 8'd139;
assign vec_2c_bitsReq_2_chroma_inv[157] = 8'd97;
assign vec_2c_bitsReq_2_chroma_inv[158] = 8'd164;
assign vec_2c_bitsReq_2_chroma_inv[159] = 8'd181;
assign vec_2c_bitsReq_2_chroma_inv[160] = 8'd40;
assign vec_2c_bitsReq_2_chroma_inv[161] = 8'd229;
assign vec_2c_bitsReq_2_chroma_inv[162] = 8'd130;
assign vec_2c_bitsReq_2_chroma_inv[163] = 8'd135;
assign vec_2c_bitsReq_2_chroma_inv[164] = 8'd120;
assign vec_2c_bitsReq_2_chroma_inv[165] = 8'd57;
assign vec_2c_bitsReq_2_chroma_inv[166] = 8'd108;
assign vec_2c_bitsReq_2_chroma_inv[167] = 8'd148;
assign vec_2c_bitsReq_2_chroma_inv[168] = 8'd73;
assign vec_2c_bitsReq_2_chroma_inv[169] = 8'd22;
assign vec_2c_bitsReq_2_chroma_inv[170] = 8'd234;
assign vec_2c_bitsReq_2_chroma_inv[171] = 8'd198;
assign vec_2c_bitsReq_2_chroma_inv[172] = 8'd45;
assign vec_2c_bitsReq_2_chroma_inv[173] = 8'd210;
assign vec_2c_bitsReq_2_chroma_inv[174] = 8'd171;
assign vec_2c_bitsReq_2_chroma_inv[175] = 8'd147;
assign vec_2c_bitsReq_2_chroma_inv[176] = 8'd217;
assign vec_2c_bitsReq_2_chroma_inv[177] = 8'd174;
assign vec_2c_bitsReq_2_chroma_inv[178] = 8'd118;
assign vec_2c_bitsReq_2_chroma_inv[179] = 8'd38;
assign vec_2c_bitsReq_2_chroma_inv[180] = 8'd186;
assign vec_2c_bitsReq_2_chroma_inv[181] = 8'd137;
assign vec_2c_bitsReq_2_chroma_inv[182] = 8'd98;
assign vec_2c_bitsReq_2_chroma_inv[183] = 8'd157;
assign vec_2c_bitsReq_2_chroma_inv[184] = 8'd235;
assign vec_2c_bitsReq_2_chroma_inv[185] = 8'd152;
assign vec_2c_bitsReq_2_chroma_inv[186] = 8'd219;
assign vec_2c_bitsReq_2_chroma_inv[187] = 8'd190;
assign vec_2c_bitsReq_2_chroma_inv[188] = 8'd231;
assign vec_2c_bitsReq_2_chroma_inv[189] = 8'd178;
assign vec_2c_bitsReq_2_chroma_inv[190] = 8'd103;
assign vec_2c_bitsReq_2_chroma_inv[191] = 8'd232;
assign vec_2c_bitsReq_2_chroma_inv[192] = 8'd237;
assign vec_2c_bitsReq_2_chroma_inv[193] = 8'd142;
assign vec_2c_bitsReq_2_chroma_inv[194] = 8'd189;
assign vec_2c_bitsReq_2_chroma_inv[195] = 8'd138;
assign vec_2c_bitsReq_2_chroma_inv[196] = 8'd89;
assign vec_2c_bitsReq_2_chroma_inv[197] = 8'd43;
assign vec_2c_bitsReq_2_chroma_inv[198] = 8'd249;
assign vec_2c_bitsReq_2_chroma_inv[199] = 8'd126;
assign vec_2c_bitsReq_2_chroma_inv[200] = 8'd153;
assign vec_2c_bitsReq_2_chroma_inv[201] = 8'd149;
assign vec_2c_bitsReq_2_chroma_inv[202] = 8'd162;
assign vec_2c_bitsReq_2_chroma_inv[203] = 8'd42;
assign vec_2c_bitsReq_2_chroma_inv[204] = 8'd101;
assign vec_2c_bitsReq_2_chroma_inv[205] = 8'd102;
assign vec_2c_bitsReq_2_chroma_inv[206] = 8'd183;
assign vec_2c_bitsReq_2_chroma_inv[207] = 8'd111;
assign vec_2c_bitsReq_2_chroma_inv[208] = 8'd86;
assign vec_2c_bitsReq_2_chroma_inv[209] = 8'd246;
assign vec_2c_bitsReq_2_chroma_inv[210] = 8'd222;
assign vec_2c_bitsReq_2_chroma_inv[211] = 8'd123;
assign vec_2c_bitsReq_2_chroma_inv[212] = 8'd168;
assign vec_2c_bitsReq_2_chroma_inv[213] = 8'd159;
assign vec_2c_bitsReq_2_chroma_inv[214] = 8'd109;
assign vec_2c_bitsReq_2_chroma_inv[215] = 8'd151;
assign vec_2c_bitsReq_2_chroma_inv[216] = 8'd121;
assign vec_2c_bitsReq_2_chroma_inv[217] = 8'd134;
assign vec_2c_bitsReq_2_chroma_inv[218] = 8'd214;
assign vec_2c_bitsReq_2_chroma_inv[219] = 8'd218;
assign vec_2c_bitsReq_2_chroma_inv[220] = 8'd104;
assign vec_2c_bitsReq_2_chroma_inv[221] = 8'd41;
assign vec_2c_bitsReq_2_chroma_inv[222] = 8'd122;
assign vec_2c_bitsReq_2_chroma_inv[223] = 8'd146;
assign vec_2c_bitsReq_2_chroma_inv[224] = 8'd230;
assign vec_2c_bitsReq_2_chroma_inv[225] = 8'd155;
assign vec_2c_bitsReq_2_chroma_inv[226] = 8'd105;
assign vec_2c_bitsReq_2_chroma_inv[227] = 8'd150;
assign vec_2c_bitsReq_2_chroma_inv[228] = 8'd167;
assign vec_2c_bitsReq_2_chroma_inv[229] = 8'd173;
assign vec_2c_bitsReq_2_chroma_inv[230] = 8'd233;
assign vec_2c_bitsReq_2_chroma_inv[231] = 8'd185;
assign vec_2c_bitsReq_2_chroma_inv[232] = 8'd110;
assign vec_2c_bitsReq_2_chroma_inv[233] = 8'd158;
assign vec_2c_bitsReq_2_chroma_inv[234] = 8'd182;
assign vec_2c_bitsReq_2_chroma_inv[235] = 8'd107;
assign vec_2c_bitsReq_2_chroma_inv[236] = 8'd169;
assign vec_2c_bitsReq_2_chroma_inv[237] = 8'd154;
assign vec_2c_bitsReq_2_chroma_inv[238] = 8'd106;
assign vec_2c_bitsReq_2_chroma_inv[239] = 8'd166;
assign vec_2c_bitsReq_2_chroma_inv[240] = 8'd255;
assign vec_2c_bitsReq_2_chroma_inv[241] = 8'd63;
assign vec_2c_bitsReq_2_chroma_inv[242] = 8'd207;
assign vec_2c_bitsReq_2_chroma_inv[243] = 8'd15;
assign vec_2c_bitsReq_2_chroma_inv[244] = 8'd243;
assign vec_2c_bitsReq_2_chroma_inv[245] = 8'd51;
assign vec_2c_bitsReq_2_chroma_inv[246] = 8'd195;
assign vec_2c_bitsReq_2_chroma_inv[247] = 8'd3;
assign vec_2c_bitsReq_2_chroma_inv[248] = 8'd252;
assign vec_2c_bitsReq_2_chroma_inv[249] = 8'd60;
assign vec_2c_bitsReq_2_chroma_inv[250] = 8'd204;
assign vec_2c_bitsReq_2_chroma_inv[251] = 8'd12;
assign vec_2c_bitsReq_2_chroma_inv[252] = 8'd240;
assign vec_2c_bitsReq_2_chroma_inv[253] = 8'd48;
assign vec_2c_bitsReq_2_chroma_inv[254] = 8'd192;
assign vec_2c_bitsReq_2_chroma_inv[255] = 8'd0;

wire [3:0] vec_sm_bitsReq_1_luma_inv[0:15];
assign vec_sm_bitsReq_1_luma_inv[0]  = 4'd2;
assign vec_sm_bitsReq_1_luma_inv[1]  = 4'd1;
assign vec_sm_bitsReq_1_luma_inv[2]  = 4'd8;
assign vec_sm_bitsReq_1_luma_inv[3]  = 4'd4;
assign vec_sm_bitsReq_1_luma_inv[4]  = 4'd10;
assign vec_sm_bitsReq_1_luma_inv[5]  = 4'd5;
assign vec_sm_bitsReq_1_luma_inv[6]  = 4'd3;
assign vec_sm_bitsReq_1_luma_inv[7]  = 4'd9;
assign vec_sm_bitsReq_1_luma_inv[8]  = 4'd6;
assign vec_sm_bitsReq_1_luma_inv[9]  = 4'd12;
assign vec_sm_bitsReq_1_luma_inv[10] = 4'd7;
assign vec_sm_bitsReq_1_luma_inv[11] = 4'd11;
assign vec_sm_bitsReq_1_luma_inv[12] = 4'd14;
assign vec_sm_bitsReq_1_luma_inv[13] = 4'd13;
assign vec_sm_bitsReq_1_luma_inv[14] = 4'd15;
assign vec_sm_bitsReq_1_luma_inv[15] = 4'd0;

wire [3:0] vec_sm_bitsReq_1_chroma_inv[0:15];
assign vec_sm_bitsReq_1_chroma_inv[0]  = 4'd2;
assign vec_sm_bitsReq_1_chroma_inv[1]  = 4'd1;
assign vec_sm_bitsReq_1_chroma_inv[2]  = 4'd4;
assign vec_sm_bitsReq_1_chroma_inv[3]  = 4'd8;
assign vec_sm_bitsReq_1_chroma_inv[4]  = 4'd3;
assign vec_sm_bitsReq_1_chroma_inv[5]  = 4'd12;
assign vec_sm_bitsReq_1_chroma_inv[6]  = 4'd10;
assign vec_sm_bitsReq_1_chroma_inv[7]  = 4'd5;
assign vec_sm_bitsReq_1_chroma_inv[8]  = 4'd6;
assign vec_sm_bitsReq_1_chroma_inv[9]  = 4'd9;
assign vec_sm_bitsReq_1_chroma_inv[10] = 4'd11;
assign vec_sm_bitsReq_1_chroma_inv[11] = 4'd7;
assign vec_sm_bitsReq_1_chroma_inv[12] = 4'd13;
assign vec_sm_bitsReq_1_chroma_inv[13] = 4'd14;
assign vec_sm_bitsReq_1_chroma_inv[14] = 4'd15;
assign vec_sm_bitsReq_1_chroma_inv[15] = 4'd0;

wire [7:0] vec_sm_bitsReq_2_luma_inv[0:255];
assign vec_sm_bitsReq_2_luma_inv[0]   = 8'd8;
assign vec_sm_bitsReq_2_luma_inv[1]   = 8'd2;
assign vec_sm_bitsReq_2_luma_inv[2]   = 8'd128;
assign vec_sm_bitsReq_2_luma_inv[3]   = 8'd32;
assign vec_sm_bitsReq_2_luma_inv[4]   = 8'd6;
assign vec_sm_bitsReq_2_luma_inv[5]   = 8'd9;
assign vec_sm_bitsReq_2_luma_inv[6]   = 8'd18;
assign vec_sm_bitsReq_2_luma_inv[7]   = 8'd72;
assign vec_sm_bitsReq_2_luma_inv[8]   = 8'd132;
assign vec_sm_bitsReq_2_luma_inv[9]   = 8'd33;
assign vec_sm_bitsReq_2_luma_inv[10]  = 8'd66;
assign vec_sm_bitsReq_2_luma_inv[11]  = 8'd24;
assign vec_sm_bitsReq_2_luma_inv[12]  = 8'd129;
assign vec_sm_bitsReq_2_luma_inv[13]  = 8'd36;
assign vec_sm_bitsReq_2_luma_inv[14]  = 8'd144;
assign vec_sm_bitsReq_2_luma_inv[15]  = 8'd96;
assign vec_sm_bitsReq_2_luma_inv[16]  = 8'd22;
assign vec_sm_bitsReq_2_luma_inv[17]  = 8'd73;
assign vec_sm_bitsReq_2_luma_inv[18]  = 8'd12;
assign vec_sm_bitsReq_2_luma_inv[19]  = 8'd3;
assign vec_sm_bitsReq_2_luma_inv[20]  = 8'd25;
assign vec_sm_bitsReq_2_luma_inv[21]  = 8'd70;
assign vec_sm_bitsReq_2_luma_inv[22]  = 8'd88;
assign vec_sm_bitsReq_2_luma_inv[23]  = 8'd82;
assign vec_sm_bitsReq_2_luma_inv[24]  = 8'd37;
assign vec_sm_bitsReq_2_luma_inv[25]  = 8'd133;
assign vec_sm_bitsReq_2_luma_inv[26]  = 8'd148;
assign vec_sm_bitsReq_2_luma_inv[27]  = 8'd97;
assign vec_sm_bitsReq_2_luma_inv[28]  = 8'd192;
assign vec_sm_bitsReq_2_luma_inv[29]  = 8'd48;
assign vec_sm_bitsReq_2_luma_inv[30]  = 8'd145;
assign vec_sm_bitsReq_2_luma_inv[31]  = 8'd100;
assign vec_sm_bitsReq_2_luma_inv[32]  = 8'd86;
assign vec_sm_bitsReq_2_luma_inv[33]  = 8'd89;
assign vec_sm_bitsReq_2_luma_inv[34]  = 8'd10;
assign vec_sm_bitsReq_2_luma_inv[35]  = 8'd34;
assign vec_sm_bitsReq_2_luma_inv[36]  = 8'd136;
assign vec_sm_bitsReq_2_luma_inv[37]  = 8'd149;
assign vec_sm_bitsReq_2_luma_inv[38]  = 8'd101;
assign vec_sm_bitsReq_2_luma_inv[39]  = 8'd13;
assign vec_sm_bitsReq_2_luma_inv[40]  = 8'd7;
assign vec_sm_bitsReq_2_luma_inv[41]  = 8'd76;
assign vec_sm_bitsReq_2_luma_inv[42]  = 8'd19;
assign vec_sm_bitsReq_2_luma_inv[43]  = 8'd160;
assign vec_sm_bitsReq_2_luma_inv[44]  = 8'd40;
assign vec_sm_bitsReq_2_luma_inv[45]  = 8'd49;
assign vec_sm_bitsReq_2_luma_inv[46]  = 8'd28;
assign vec_sm_bitsReq_2_luma_inv[47]  = 8'd67;
assign vec_sm_bitsReq_2_luma_inv[48]  = 8'd130;
assign vec_sm_bitsReq_2_luma_inv[49]  = 8'd196;
assign vec_sm_bitsReq_2_luma_inv[50]  = 8'd112;
assign vec_sm_bitsReq_2_luma_inv[51]  = 8'd208;
assign vec_sm_bitsReq_2_luma_inv[52]  = 8'd52;
assign vec_sm_bitsReq_2_luma_inv[53]  = 8'd193;
assign vec_sm_bitsReq_2_luma_inv[54]  = 8'd74;
assign vec_sm_bitsReq_2_luma_inv[55]  = 8'd38;
assign vec_sm_bitsReq_2_luma_inv[56]  = 8'd26;
assign vec_sm_bitsReq_2_luma_inv[57]  = 8'd137;
assign vec_sm_bitsReq_2_luma_inv[58]  = 8'd98;
assign vec_sm_bitsReq_2_luma_inv[59]  = 8'd152;
assign vec_sm_bitsReq_2_luma_inv[60]  = 8'd77;
assign vec_sm_bitsReq_2_luma_inv[61]  = 8'd41;
assign vec_sm_bitsReq_2_luma_inv[62]  = 8'd23;
assign vec_sm_bitsReq_2_luma_inv[63]  = 8'd83;
assign vec_sm_bitsReq_2_luma_inv[64]  = 8'd71;
assign vec_sm_bitsReq_2_luma_inv[65]  = 8'd29;
assign vec_sm_bitsReq_2_luma_inv[66]  = 8'd92;
assign vec_sm_bitsReq_2_luma_inv[67]  = 8'd90;
assign vec_sm_bitsReq_2_luma_inv[68]  = 8'd134;
assign vec_sm_bitsReq_2_luma_inv[69]  = 8'd164;
assign vec_sm_bitsReq_2_luma_inv[70]  = 8'd153;
assign vec_sm_bitsReq_2_luma_inv[71]  = 8'd146;
assign vec_sm_bitsReq_2_luma_inv[72]  = 8'd104;
assign vec_sm_bitsReq_2_luma_inv[73]  = 8'd161;
assign vec_sm_bitsReq_2_luma_inv[74]  = 8'd113;
assign vec_sm_bitsReq_2_luma_inv[75]  = 8'd102;
assign vec_sm_bitsReq_2_luma_inv[76]  = 8'd53;
assign vec_sm_bitsReq_2_luma_inv[77]  = 8'd197;
assign vec_sm_bitsReq_2_luma_inv[78]  = 8'd212;
assign vec_sm_bitsReq_2_luma_inv[79]  = 8'd209;
assign vec_sm_bitsReq_2_luma_inv[80]  = 8'd116;
assign vec_sm_bitsReq_2_luma_inv[81]  = 8'd165;
assign vec_sm_bitsReq_2_luma_inv[82]  = 8'd14;
assign vec_sm_bitsReq_2_luma_inv[83]  = 8'd150;
assign vec_sm_bitsReq_2_luma_inv[84]  = 8'd11;
assign vec_sm_bitsReq_2_luma_inv[85]  = 8'd35;
assign vec_sm_bitsReq_2_luma_inv[86]  = 8'd93;
assign vec_sm_bitsReq_2_luma_inv[87]  = 8'd105;
assign vec_sm_bitsReq_2_luma_inv[88]  = 8'd50;
assign vec_sm_bitsReq_2_luma_inv[89]  = 8'd87;
assign vec_sm_bitsReq_2_luma_inv[90]  = 8'd140;
assign vec_sm_bitsReq_2_luma_inv[91]  = 8'd200;
assign vec_sm_bitsReq_2_luma_inv[92]  = 8'd117;
assign vec_sm_bitsReq_2_luma_inv[93]  = 8'd213;
assign vec_sm_bitsReq_2_luma_inv[94]  = 8'd176;
assign vec_sm_bitsReq_2_luma_inv[95]  = 8'd224;
assign vec_sm_bitsReq_2_luma_inv[96]  = 8'd131;
assign vec_sm_bitsReq_2_luma_inv[97]  = 8'd44;
assign vec_sm_bitsReq_2_luma_inv[98]  = 8'd194;
assign vec_sm_bitsReq_2_luma_inv[99]  = 8'd56;
assign vec_sm_bitsReq_2_luma_inv[100] = 8'd39;
assign vec_sm_bitsReq_2_luma_inv[101] = 8'd138;
assign vec_sm_bitsReq_2_luma_inv[102] = 8'd27;
assign vec_sm_bitsReq_2_luma_inv[103] = 8'd42;
assign vec_sm_bitsReq_2_luma_inv[104] = 8'd201;
assign vec_sm_bitsReq_2_luma_inv[105] = 8'd162;
assign vec_sm_bitsReq_2_luma_inv[106] = 8'd78;
assign vec_sm_bitsReq_2_luma_inv[107] = 8'd168;
assign vec_sm_bitsReq_2_luma_inv[108] = 8'd141;
assign vec_sm_bitsReq_2_luma_inv[109] = 8'd30;
assign vec_sm_bitsReq_2_luma_inv[110] = 8'd75;
assign vec_sm_bitsReq_2_luma_inv[111] = 8'd106;
assign vec_sm_bitsReq_2_luma_inv[112] = 8'd114;
assign vec_sm_bitsReq_2_luma_inv[113] = 8'd54;
assign vec_sm_bitsReq_2_luma_inv[114] = 8'd156;
assign vec_sm_bitsReq_2_luma_inv[115] = 8'd99;
assign vec_sm_bitsReq_2_luma_inv[116] = 8'd166;
assign vec_sm_bitsReq_2_luma_inv[117] = 8'd154;
assign vec_sm_bitsReq_2_luma_inv[118] = 8'd216;
assign vec_sm_bitsReq_2_luma_inv[119] = 8'd169;
assign vec_sm_bitsReq_2_luma_inv[120] = 8'd15;
assign vec_sm_bitsReq_2_luma_inv[121] = 8'd198;
assign vec_sm_bitsReq_2_luma_inv[122] = 8'd177;
assign vec_sm_bitsReq_2_luma_inv[123] = 8'd170;
assign vec_sm_bitsReq_2_luma_inv[124] = 8'd210;
assign vec_sm_bitsReq_2_luma_inv[125] = 8'd45;
assign vec_sm_bitsReq_2_luma_inv[126] = 8'd57;
assign vec_sm_bitsReq_2_luma_inv[127] = 8'd217;
assign vec_sm_bitsReq_2_luma_inv[128] = 8'd108;
assign vec_sm_bitsReq_2_luma_inv[129] = 8'd228;
assign vec_sm_bitsReq_2_luma_inv[130] = 8'd204;
assign vec_sm_bitsReq_2_luma_inv[131] = 8'd103;
assign vec_sm_bitsReq_2_luma_inv[132] = 8'd147;
assign vec_sm_bitsReq_2_luma_inv[133] = 8'd120;
assign vec_sm_bitsReq_2_luma_inv[134] = 8'd135;
assign vec_sm_bitsReq_2_luma_inv[135] = 8'd51;
assign vec_sm_bitsReq_2_luma_inv[136] = 8'd91;
assign vec_sm_bitsReq_2_luma_inv[137] = 8'd225;
assign vec_sm_bitsReq_2_luma_inv[138] = 8'd180;
assign vec_sm_bitsReq_2_luma_inv[139] = 8'd94;
assign vec_sm_bitsReq_2_luma_inv[140] = 8'd157;
assign vec_sm_bitsReq_2_luma_inv[141] = 8'd151;
assign vec_sm_bitsReq_2_luma_inv[142] = 8'd229;
assign vec_sm_bitsReq_2_luma_inv[143] = 8'd121;
assign vec_sm_bitsReq_2_luma_inv[144] = 8'd118;
assign vec_sm_bitsReq_2_luma_inv[145] = 8'd109;
assign vec_sm_bitsReq_2_luma_inv[146] = 8'd181;
assign vec_sm_bitsReq_2_luma_inv[147] = 8'd240;
assign vec_sm_bitsReq_2_luma_inv[148] = 8'd214;
assign vec_sm_bitsReq_2_luma_inv[149] = 8'd195;
assign vec_sm_bitsReq_2_luma_inv[150] = 8'd79;
assign vec_sm_bitsReq_2_luma_inv[151] = 8'd60;
assign vec_sm_bitsReq_2_luma_inv[152] = 8'd205;
assign vec_sm_bitsReq_2_luma_inv[153] = 8'd55;
assign vec_sm_bitsReq_2_luma_inv[154] = 8'd31;
assign vec_sm_bitsReq_2_luma_inv[155] = 8'd220;
assign vec_sm_bitsReq_2_luma_inv[156] = 8'd43;
assign vec_sm_bitsReq_2_luma_inv[157] = 8'd115;
assign vec_sm_bitsReq_2_luma_inv[158] = 8'd119;
assign vec_sm_bitsReq_2_luma_inv[159] = 8'd142;
assign vec_sm_bitsReq_2_luma_inv[160] = 8'd163;
assign vec_sm_bitsReq_2_luma_inv[161] = 8'd178;
assign vec_sm_bitsReq_2_luma_inv[162] = 8'd221;
assign vec_sm_bitsReq_2_luma_inv[163] = 8'd139;
assign vec_sm_bitsReq_2_luma_inv[164] = 8'd202;
assign vec_sm_bitsReq_2_luma_inv[165] = 8'd107;
assign vec_sm_bitsReq_2_luma_inv[166] = 8'd232;
assign vec_sm_bitsReq_2_luma_inv[167] = 8'd58;
assign vec_sm_bitsReq_2_luma_inv[168] = 8'd244;
assign vec_sm_bitsReq_2_luma_inv[169] = 8'd199;
assign vec_sm_bitsReq_2_luma_inv[170] = 8'd158;
assign vec_sm_bitsReq_2_luma_inv[171] = 8'd46;
assign vec_sm_bitsReq_2_luma_inv[172] = 8'd155;
assign vec_sm_bitsReq_2_luma_inv[173] = 8'd241;
assign vec_sm_bitsReq_2_luma_inv[174] = 8'd95;
assign vec_sm_bitsReq_2_luma_inv[175] = 8'd184;
assign vec_sm_bitsReq_2_luma_inv[176] = 8'd172;
assign vec_sm_bitsReq_2_luma_inv[177] = 8'd226;
assign vec_sm_bitsReq_2_luma_inv[178] = 8'd122;
assign vec_sm_bitsReq_2_luma_inv[179] = 8'd124;
assign vec_sm_bitsReq_2_luma_inv[180] = 8'd61;
assign vec_sm_bitsReq_2_luma_inv[181] = 8'd211;
assign vec_sm_bitsReq_2_luma_inv[182] = 8'd182;
assign vec_sm_bitsReq_2_luma_inv[183] = 8'd233;
assign vec_sm_bitsReq_2_luma_inv[184] = 8'd245;
assign vec_sm_bitsReq_2_luma_inv[185] = 8'd185;
assign vec_sm_bitsReq_2_luma_inv[186] = 8'd173;
assign vec_sm_bitsReq_2_luma_inv[187] = 8'd110;
assign vec_sm_bitsReq_2_luma_inv[188] = 8'd167;
assign vec_sm_bitsReq_2_luma_inv[189] = 8'd218;
assign vec_sm_bitsReq_2_luma_inv[190] = 8'd230;
assign vec_sm_bitsReq_2_luma_inv[191] = 8'd215;
assign vec_sm_bitsReq_2_luma_inv[192] = 8'd125;
assign vec_sm_bitsReq_2_luma_inv[193] = 8'd47;
assign vec_sm_bitsReq_2_luma_inv[194] = 8'd186;
assign vec_sm_bitsReq_2_luma_inv[195] = 8'd174;
assign vec_sm_bitsReq_2_luma_inv[196] = 8'd206;
assign vec_sm_bitsReq_2_luma_inv[197] = 8'd143;
assign vec_sm_bitsReq_2_luma_inv[198] = 8'd171;
assign vec_sm_bitsReq_2_luma_inv[199] = 8'd203;
assign vec_sm_bitsReq_2_luma_inv[200] = 8'd234;
assign vec_sm_bitsReq_2_luma_inv[201] = 8'd111;
assign vec_sm_bitsReq_2_luma_inv[202] = 8'd179;
assign vec_sm_bitsReq_2_luma_inv[203] = 8'd59;
assign vec_sm_bitsReq_2_luma_inv[204] = 8'd62;
assign vec_sm_bitsReq_2_luma_inv[205] = 8'd246;
assign vec_sm_bitsReq_2_luma_inv[206] = 8'd236;
assign vec_sm_bitsReq_2_luma_inv[207] = 8'd242;
assign vec_sm_bitsReq_2_luma_inv[208] = 8'd222;
assign vec_sm_bitsReq_2_luma_inv[209] = 8'd237;
assign vec_sm_bitsReq_2_luma_inv[210] = 8'd183;
assign vec_sm_bitsReq_2_luma_inv[211] = 8'd126;
assign vec_sm_bitsReq_2_luma_inv[212] = 8'd248;
assign vec_sm_bitsReq_2_luma_inv[213] = 8'd123;
assign vec_sm_bitsReq_2_luma_inv[214] = 8'd249;
assign vec_sm_bitsReq_2_luma_inv[215] = 8'd231;
assign vec_sm_bitsReq_2_luma_inv[216] = 8'd159;
assign vec_sm_bitsReq_2_luma_inv[217] = 8'd219;
assign vec_sm_bitsReq_2_luma_inv[218] = 8'd227;
assign vec_sm_bitsReq_2_luma_inv[219] = 8'd188;
assign vec_sm_bitsReq_2_luma_inv[220] = 8'd189;
assign vec_sm_bitsReq_2_luma_inv[221] = 8'd187;
assign vec_sm_bitsReq_2_luma_inv[222] = 8'd250;
assign vec_sm_bitsReq_2_luma_inv[223] = 8'd63;
assign vec_sm_bitsReq_2_luma_inv[224] = 8'd207;
assign vec_sm_bitsReq_2_luma_inv[225] = 8'd175;
assign vec_sm_bitsReq_2_luma_inv[226] = 8'd223;
assign vec_sm_bitsReq_2_luma_inv[227] = 8'd238;
assign vec_sm_bitsReq_2_luma_inv[228] = 8'd247;
assign vec_sm_bitsReq_2_luma_inv[229] = 8'd235;
assign vec_sm_bitsReq_2_luma_inv[230] = 8'd253;
assign vec_sm_bitsReq_2_luma_inv[231] = 8'd127;
assign vec_sm_bitsReq_2_luma_inv[232] = 8'd252;
assign vec_sm_bitsReq_2_luma_inv[233] = 8'd190;
assign vec_sm_bitsReq_2_luma_inv[234] = 8'd243;
assign vec_sm_bitsReq_2_luma_inv[235] = 8'd239;
assign vec_sm_bitsReq_2_luma_inv[236] = 8'd191;
assign vec_sm_bitsReq_2_luma_inv[237] = 8'd254;
assign vec_sm_bitsReq_2_luma_inv[238] = 8'd255;
assign vec_sm_bitsReq_2_luma_inv[239] = 8'd251;
assign vec_sm_bitsReq_2_luma_inv[240] = 8'd85;
assign vec_sm_bitsReq_2_luma_inv[241] = 8'd21;
assign vec_sm_bitsReq_2_luma_inv[242] = 8'd69;
assign vec_sm_bitsReq_2_luma_inv[243] = 8'd5;
assign vec_sm_bitsReq_2_luma_inv[244] = 8'd81;
assign vec_sm_bitsReq_2_luma_inv[245] = 8'd17;
assign vec_sm_bitsReq_2_luma_inv[246] = 8'd65;
assign vec_sm_bitsReq_2_luma_inv[247] = 8'd1;
assign vec_sm_bitsReq_2_luma_inv[248] = 8'd84;
assign vec_sm_bitsReq_2_luma_inv[249] = 8'd20;
assign vec_sm_bitsReq_2_luma_inv[250] = 8'd68;
assign vec_sm_bitsReq_2_luma_inv[251] = 8'd4;
assign vec_sm_bitsReq_2_luma_inv[252] = 8'd80;
assign vec_sm_bitsReq_2_luma_inv[253] = 8'd16;
assign vec_sm_bitsReq_2_luma_inv[254] = 8'd64;
assign vec_sm_bitsReq_2_luma_inv[255] = 8'd0;

wire [15:0] vec_sm_bitsReq_2_chroma_inv[0:255];
assign vec_sm_bitsReq_2_chroma_inv[0]   = 8'd2;
assign vec_sm_bitsReq_2_chroma_inv[1]   = 8'd8;
assign vec_sm_bitsReq_2_chroma_inv[2]   = 8'd128;
assign vec_sm_bitsReq_2_chroma_inv[3]   = 8'd32;
assign vec_sm_bitsReq_2_chroma_inv[4]   = 8'd6;
assign vec_sm_bitsReq_2_chroma_inv[5]   = 8'd9;
assign vec_sm_bitsReq_2_chroma_inv[6]   = 8'd18;
assign vec_sm_bitsReq_2_chroma_inv[7]   = 8'd72;
assign vec_sm_bitsReq_2_chroma_inv[8]   = 8'd96;
assign vec_sm_bitsReq_2_chroma_inv[9]   = 8'd144;
assign vec_sm_bitsReq_2_chroma_inv[10]  = 8'd33;
assign vec_sm_bitsReq_2_chroma_inv[11]  = 8'd132;
assign vec_sm_bitsReq_2_chroma_inv[12]  = 8'd10;
assign vec_sm_bitsReq_2_chroma_inv[13]  = 8'd24;
assign vec_sm_bitsReq_2_chroma_inv[14]  = 8'd66;
assign vec_sm_bitsReq_2_chroma_inv[15]  = 8'd129;
assign vec_sm_bitsReq_2_chroma_inv[16]  = 8'd22;
assign vec_sm_bitsReq_2_chroma_inv[17]  = 8'd36;
assign vec_sm_bitsReq_2_chroma_inv[18]  = 8'd73;
assign vec_sm_bitsReq_2_chroma_inv[19]  = 8'd160;
assign vec_sm_bitsReq_2_chroma_inv[20]  = 8'd25;
assign vec_sm_bitsReq_2_chroma_inv[21]  = 8'd70;
assign vec_sm_bitsReq_2_chroma_inv[22]  = 8'd97;
assign vec_sm_bitsReq_2_chroma_inv[23]  = 8'd82;
assign vec_sm_bitsReq_2_chroma_inv[24]  = 8'd88;
assign vec_sm_bitsReq_2_chroma_inv[25]  = 8'd148;
assign vec_sm_bitsReq_2_chroma_inv[26]  = 8'd86;
assign vec_sm_bitsReq_2_chroma_inv[27]  = 8'd37;
assign vec_sm_bitsReq_2_chroma_inv[28]  = 8'd89;
assign vec_sm_bitsReq_2_chroma_inv[29]  = 8'd12;
assign vec_sm_bitsReq_2_chroma_inv[30]  = 8'd3;
assign vec_sm_bitsReq_2_chroma_inv[31]  = 8'd133;
assign vec_sm_bitsReq_2_chroma_inv[32]  = 8'd100;
assign vec_sm_bitsReq_2_chroma_inv[33]  = 8'd145;
assign vec_sm_bitsReq_2_chroma_inv[34]  = 8'd34;
assign vec_sm_bitsReq_2_chroma_inv[35]  = 8'd101;
assign vec_sm_bitsReq_2_chroma_inv[36]  = 8'd149;
assign vec_sm_bitsReq_2_chroma_inv[37]  = 8'd136;
assign vec_sm_bitsReq_2_chroma_inv[38]  = 8'd90;
assign vec_sm_bitsReq_2_chroma_inv[39]  = 8'd192;
assign vec_sm_bitsReq_2_chroma_inv[40]  = 8'd48;
assign vec_sm_bitsReq_2_chroma_inv[41]  = 8'd165;
assign vec_sm_bitsReq_2_chroma_inv[42]  = 8'd74;
assign vec_sm_bitsReq_2_chroma_inv[43]  = 8'd7;
assign vec_sm_bitsReq_2_chroma_inv[44]  = 8'd26;
assign vec_sm_bitsReq_2_chroma_inv[45]  = 8'd13;
assign vec_sm_bitsReq_2_chroma_inv[46]  = 8'd19;
assign vec_sm_bitsReq_2_chroma_inv[47]  = 8'd76;
assign vec_sm_bitsReq_2_chroma_inv[48]  = 8'd15;
assign vec_sm_bitsReq_2_chroma_inv[49]  = 8'd112;
assign vec_sm_bitsReq_2_chroma_inv[50]  = 8'd102;
assign vec_sm_bitsReq_2_chroma_inv[51]  = 8'd153;
assign vec_sm_bitsReq_2_chroma_inv[52]  = 8'd196;
assign vec_sm_bitsReq_2_chroma_inv[53]  = 8'd161;
assign vec_sm_bitsReq_2_chroma_inv[54]  = 8'd49;
assign vec_sm_bitsReq_2_chroma_inv[55]  = 8'd98;
assign vec_sm_bitsReq_2_chroma_inv[56]  = 8'd130;
assign vec_sm_bitsReq_2_chroma_inv[57]  = 8'd164;
assign vec_sm_bitsReq_2_chroma_inv[58]  = 8'd208;
assign vec_sm_bitsReq_2_chroma_inv[59]  = 8'd38;
assign vec_sm_bitsReq_2_chroma_inv[60]  = 8'd137;
assign vec_sm_bitsReq_2_chroma_inv[61]  = 8'd40;
assign vec_sm_bitsReq_2_chroma_inv[62]  = 8'd67;
assign vec_sm_bitsReq_2_chroma_inv[63]  = 8'd28;
assign vec_sm_bitsReq_2_chroma_inv[64]  = 8'd11;
assign vec_sm_bitsReq_2_chroma_inv[65]  = 8'd152;
assign vec_sm_bitsReq_2_chroma_inv[66]  = 8'd14;
assign vec_sm_bitsReq_2_chroma_inv[67]  = 8'd23;
assign vec_sm_bitsReq_2_chroma_inv[68]  = 8'd41;
assign vec_sm_bitsReq_2_chroma_inv[69]  = 8'd134;
assign vec_sm_bitsReq_2_chroma_inv[70]  = 8'd193;
assign vec_sm_bitsReq_2_chroma_inv[71]  = 8'd77;
assign vec_sm_bitsReq_2_chroma_inv[72]  = 8'd52;
assign vec_sm_bitsReq_2_chroma_inv[73]  = 8'd240;
assign vec_sm_bitsReq_2_chroma_inv[74]  = 8'd104;
assign vec_sm_bitsReq_2_chroma_inv[75]  = 8'd224;
assign vec_sm_bitsReq_2_chroma_inv[76]  = 8'd150;
assign vec_sm_bitsReq_2_chroma_inv[77]  = 8'd71;
assign vec_sm_bitsReq_2_chroma_inv[78]  = 8'd146;
assign vec_sm_bitsReq_2_chroma_inv[79]  = 8'd29;
assign vec_sm_bitsReq_2_chroma_inv[80]  = 8'd83;
assign vec_sm_bitsReq_2_chroma_inv[81]  = 8'd170;
assign vec_sm_bitsReq_2_chroma_inv[82]  = 8'd105;
assign vec_sm_bitsReq_2_chroma_inv[83]  = 8'd92;
assign vec_sm_bitsReq_2_chroma_inv[84]  = 8'd176;
assign vec_sm_bitsReq_2_chroma_inv[85]  = 8'd35;
assign vec_sm_bitsReq_2_chroma_inv[86]  = 8'd113;
assign vec_sm_bitsReq_2_chroma_inv[87]  = 8'd87;
assign vec_sm_bitsReq_2_chroma_inv[88]  = 8'd197;
assign vec_sm_bitsReq_2_chroma_inv[89]  = 8'd53;
assign vec_sm_bitsReq_2_chroma_inv[90]  = 8'd209;
assign vec_sm_bitsReq_2_chroma_inv[91]  = 8'd212;
assign vec_sm_bitsReq_2_chroma_inv[92]  = 8'd200;
assign vec_sm_bitsReq_2_chroma_inv[93]  = 8'd93;
assign vec_sm_bitsReq_2_chroma_inv[94]  = 8'd95;
assign vec_sm_bitsReq_2_chroma_inv[95]  = 8'd50;
assign vec_sm_bitsReq_2_chroma_inv[96]  = 8'd140;
assign vec_sm_bitsReq_2_chroma_inv[97]  = 8'd116;
assign vec_sm_bitsReq_2_chroma_inv[98]  = 8'd154;
assign vec_sm_bitsReq_2_chroma_inv[99]  = 8'd106;
assign vec_sm_bitsReq_2_chroma_inv[100] = 8'd117;
assign vec_sm_bitsReq_2_chroma_inv[101] = 8'd166;
assign vec_sm_bitsReq_2_chroma_inv[102] = 8'd94;
assign vec_sm_bitsReq_2_chroma_inv[103] = 8'd169;
assign vec_sm_bitsReq_2_chroma_inv[104] = 8'd245;
assign vec_sm_bitsReq_2_chroma_inv[105] = 8'd213;
assign vec_sm_bitsReq_2_chroma_inv[106] = 8'd91;
assign vec_sm_bitsReq_2_chroma_inv[107] = 8'd51;
assign vec_sm_bitsReq_2_chroma_inv[108] = 8'd27;
assign vec_sm_bitsReq_2_chroma_inv[109] = 8'd30;
assign vec_sm_bitsReq_2_chroma_inv[110] = 8'd78;
assign vec_sm_bitsReq_2_chroma_inv[111] = 8'd138;
assign vec_sm_bitsReq_2_chroma_inv[112] = 8'd39;
assign vec_sm_bitsReq_2_chroma_inv[113] = 8'd75;
assign vec_sm_bitsReq_2_chroma_inv[114] = 8'd42;
assign vec_sm_bitsReq_2_chroma_inv[115] = 8'd204;
assign vec_sm_bitsReq_2_chroma_inv[116] = 8'd229;
assign vec_sm_bitsReq_2_chroma_inv[117] = 8'd141;
assign vec_sm_bitsReq_2_chroma_inv[118] = 8'd168;
assign vec_sm_bitsReq_2_chroma_inv[119] = 8'd99;
assign vec_sm_bitsReq_2_chroma_inv[120] = 8'd162;
assign vec_sm_bitsReq_2_chroma_inv[121] = 8'd114;
assign vec_sm_bitsReq_2_chroma_inv[122] = 8'd103;
assign vec_sm_bitsReq_2_chroma_inv[123] = 8'd177;
assign vec_sm_bitsReq_2_chroma_inv[124] = 8'd31;
assign vec_sm_bitsReq_2_chroma_inv[125] = 8'd225;
assign vec_sm_bitsReq_2_chroma_inv[126] = 8'd54;
assign vec_sm_bitsReq_2_chroma_inv[127] = 8'd181;
assign vec_sm_bitsReq_2_chroma_inv[128] = 8'd157;
assign vec_sm_bitsReq_2_chroma_inv[129] = 8'd201;
assign vec_sm_bitsReq_2_chroma_inv[130] = 8'd228;
assign vec_sm_bitsReq_2_chroma_inv[131] = 8'd216;
assign vec_sm_bitsReq_2_chroma_inv[132] = 8'd156;
assign vec_sm_bitsReq_2_chroma_inv[133] = 8'd118;
assign vec_sm_bitsReq_2_chroma_inv[134] = 8'd79;
assign vec_sm_bitsReq_2_chroma_inv[135] = 8'd180;
assign vec_sm_bitsReq_2_chroma_inv[136] = 8'd194;
assign vec_sm_bitsReq_2_chroma_inv[137] = 8'd56;
assign vec_sm_bitsReq_2_chroma_inv[138] = 8'd131;
assign vec_sm_bitsReq_2_chroma_inv[139] = 8'd217;
assign vec_sm_bitsReq_2_chroma_inv[140] = 8'd44;
assign vec_sm_bitsReq_2_chroma_inv[141] = 8'd244;
assign vec_sm_bitsReq_2_chroma_inv[142] = 8'd158;
assign vec_sm_bitsReq_2_chroma_inv[143] = 8'd210;
assign vec_sm_bitsReq_2_chroma_inv[144] = 8'd57;
assign vec_sm_bitsReq_2_chroma_inv[145] = 8'd108;
assign vec_sm_bitsReq_2_chroma_inv[146] = 8'd45;
assign vec_sm_bitsReq_2_chroma_inv[147] = 8'd175;
assign vec_sm_bitsReq_2_chroma_inv[148] = 8'd147;
assign vec_sm_bitsReq_2_chroma_inv[149] = 8'd109;
assign vec_sm_bitsReq_2_chroma_inv[150] = 8'd241;
assign vec_sm_bitsReq_2_chroma_inv[151] = 8'd135;
assign vec_sm_bitsReq_2_chroma_inv[152] = 8'd198;
assign vec_sm_bitsReq_2_chroma_inv[153] = 8'd151;
assign vec_sm_bitsReq_2_chroma_inv[154] = 8'd119;
assign vec_sm_bitsReq_2_chroma_inv[155] = 8'd120;
assign vec_sm_bitsReq_2_chroma_inv[156] = 8'd214;
assign vec_sm_bitsReq_2_chroma_inv[157] = 8'd107;
assign vec_sm_bitsReq_2_chroma_inv[158] = 8'd121;
assign vec_sm_bitsReq_2_chroma_inv[159] = 8'd250;
assign vec_sm_bitsReq_2_chroma_inv[160] = 8'd233;
assign vec_sm_bitsReq_2_chroma_inv[161] = 8'd142;
assign vec_sm_bitsReq_2_chroma_inv[162] = 8'd182;
assign vec_sm_bitsReq_2_chroma_inv[163] = 8'd221;
assign vec_sm_bitsReq_2_chroma_inv[164] = 8'd55;
assign vec_sm_bitsReq_2_chroma_inv[165] = 8'd220;
assign vec_sm_bitsReq_2_chroma_inv[166] = 8'd43;
assign vec_sm_bitsReq_2_chroma_inv[167] = 8'd255;
assign vec_sm_bitsReq_2_chroma_inv[168] = 8'd115;
assign vec_sm_bitsReq_2_chroma_inv[169] = 8'd171;
assign vec_sm_bitsReq_2_chroma_inv[170] = 8'd155;
assign vec_sm_bitsReq_2_chroma_inv[171] = 8'd110;
assign vec_sm_bitsReq_2_chroma_inv[172] = 8'd205;
assign vec_sm_bitsReq_2_chroma_inv[173] = 8'd186;
assign vec_sm_bitsReq_2_chroma_inv[174] = 8'd173;
assign vec_sm_bitsReq_2_chroma_inv[175] = 8'd122;
assign vec_sm_bitsReq_2_chroma_inv[176] = 8'd202;
assign vec_sm_bitsReq_2_chroma_inv[177] = 8'd218;
assign vec_sm_bitsReq_2_chroma_inv[178] = 8'd58;
assign vec_sm_bitsReq_2_chroma_inv[179] = 8'd230;
assign vec_sm_bitsReq_2_chroma_inv[180] = 8'd46;
assign vec_sm_bitsReq_2_chroma_inv[181] = 8'd174;
assign vec_sm_bitsReq_2_chroma_inv[182] = 8'd195;
assign vec_sm_bitsReq_2_chroma_inv[183] = 8'd167;
assign vec_sm_bitsReq_2_chroma_inv[184] = 8'd139;
assign vec_sm_bitsReq_2_chroma_inv[185] = 8'd178;
assign vec_sm_bitsReq_2_chroma_inv[186] = 8'd185;
assign vec_sm_bitsReq_2_chroma_inv[187] = 8'd232;
assign vec_sm_bitsReq_2_chroma_inv[188] = 8'd111;
assign vec_sm_bitsReq_2_chroma_inv[189] = 8'd60;
assign vec_sm_bitsReq_2_chroma_inv[190] = 8'd234;
assign vec_sm_bitsReq_2_chroma_inv[191] = 8'd159;
assign vec_sm_bitsReq_2_chroma_inv[192] = 8'd226;
assign vec_sm_bitsReq_2_chroma_inv[193] = 8'd246;
assign vec_sm_bitsReq_2_chroma_inv[194] = 8'd184;
assign vec_sm_bitsReq_2_chroma_inv[195] = 8'd211;
assign vec_sm_bitsReq_2_chroma_inv[196] = 8'd163;
assign vec_sm_bitsReq_2_chroma_inv[197] = 8'd61;
assign vec_sm_bitsReq_2_chroma_inv[198] = 8'd123;
assign vec_sm_bitsReq_2_chroma_inv[199] = 8'd172;
assign vec_sm_bitsReq_2_chroma_inv[200] = 8'd187;
assign vec_sm_bitsReq_2_chroma_inv[201] = 8'd238;
assign vec_sm_bitsReq_2_chroma_inv[202] = 8'd249;
assign vec_sm_bitsReq_2_chroma_inv[203] = 8'd125;
assign vec_sm_bitsReq_2_chroma_inv[204] = 8'd183;
assign vec_sm_bitsReq_2_chroma_inv[205] = 8'd47;
assign vec_sm_bitsReq_2_chroma_inv[206] = 8'd143;
assign vec_sm_bitsReq_2_chroma_inv[207] = 8'd199;
assign vec_sm_bitsReq_2_chroma_inv[208] = 8'd179;
assign vec_sm_bitsReq_2_chroma_inv[209] = 8'd248;
assign vec_sm_bitsReq_2_chroma_inv[210] = 8'd124;
assign vec_sm_bitsReq_2_chroma_inv[211] = 8'd206;
assign vec_sm_bitsReq_2_chroma_inv[212] = 8'd237;
assign vec_sm_bitsReq_2_chroma_inv[213] = 8'd59;
assign vec_sm_bitsReq_2_chroma_inv[214] = 8'd239;
assign vec_sm_bitsReq_2_chroma_inv[215] = 8'd126;
assign vec_sm_bitsReq_2_chroma_inv[216] = 8'd215;
assign vec_sm_bitsReq_2_chroma_inv[217] = 8'd222;
assign vec_sm_bitsReq_2_chroma_inv[218] = 8'd251;
assign vec_sm_bitsReq_2_chroma_inv[219] = 8'd189;
assign vec_sm_bitsReq_2_chroma_inv[220] = 8'd62;
assign vec_sm_bitsReq_2_chroma_inv[221] = 8'd219;
assign vec_sm_bitsReq_2_chroma_inv[222] = 8'd254;
assign vec_sm_bitsReq_2_chroma_inv[223] = 8'd191;
assign vec_sm_bitsReq_2_chroma_inv[224] = 8'd203;
assign vec_sm_bitsReq_2_chroma_inv[225] = 8'd242;
assign vec_sm_bitsReq_2_chroma_inv[226] = 8'd231;
assign vec_sm_bitsReq_2_chroma_inv[227] = 8'd190;
assign vec_sm_bitsReq_2_chroma_inv[228] = 8'd127;
assign vec_sm_bitsReq_2_chroma_inv[229] = 8'd235;
assign vec_sm_bitsReq_2_chroma_inv[230] = 8'd236;
assign vec_sm_bitsReq_2_chroma_inv[231] = 8'd188;
assign vec_sm_bitsReq_2_chroma_inv[232] = 8'd253;
assign vec_sm_bitsReq_2_chroma_inv[233] = 8'd243;
assign vec_sm_bitsReq_2_chroma_inv[234] = 8'd227;
assign vec_sm_bitsReq_2_chroma_inv[235] = 8'd207;
assign vec_sm_bitsReq_2_chroma_inv[236] = 8'd63;
assign vec_sm_bitsReq_2_chroma_inv[237] = 8'd247;
assign vec_sm_bitsReq_2_chroma_inv[238] = 8'd223;
assign vec_sm_bitsReq_2_chroma_inv[239] = 8'd252;
assign vec_sm_bitsReq_2_chroma_inv[240] = 8'd85;
assign vec_sm_bitsReq_2_chroma_inv[241] = 8'd21;
assign vec_sm_bitsReq_2_chroma_inv[242] = 8'd69;
assign vec_sm_bitsReq_2_chroma_inv[243] = 8'd5;
assign vec_sm_bitsReq_2_chroma_inv[244] = 8'd81;
assign vec_sm_bitsReq_2_chroma_inv[245] = 8'd17;
assign vec_sm_bitsReq_2_chroma_inv[246] = 8'd65;
assign vec_sm_bitsReq_2_chroma_inv[247] = 8'd1;
assign vec_sm_bitsReq_2_chroma_inv[248] = 8'd84;
assign vec_sm_bitsReq_2_chroma_inv[249] = 8'd20;
assign vec_sm_bitsReq_2_chroma_inv[250] = 8'd68;
assign vec_sm_bitsReq_2_chroma_inv[251] = 8'd4;
assign vec_sm_bitsReq_2_chroma_inv[252] = 8'd80;
assign vec_sm_bitsReq_2_chroma_inv[253] = 8'd16;
assign vec_sm_bitsReq_2_chroma_inv[254] = 8'd64;
assign vec_sm_bitsReq_2_chroma_inv[255] = 8'd0;

wire [3:0] stepSizeMapCo [11:0];
assign stepSizeMapCo[0]  = 4'd1;
assign stepSizeMapCo[1]  = 4'd3;
assign stepSizeMapCo[2]  = 4'd4;
assign stepSizeMapCo[3]  = 4'd5;
assign stepSizeMapCo[4]  = 4'd6;
assign stepSizeMapCo[5]  = 4'd7;
assign stepSizeMapCo[6]  = 4'd7;
assign stepSizeMapCo[7]  = 4'd7;
assign stepSizeMapCo[8]  = 4'd8;
assign stepSizeMapCo[9]  = 4'd9;
assign stepSizeMapCo[10] = 4'd10;
assign stepSizeMapCo[11] = 4'd11;

wire [3:0] stepSizeMapCg [11:0];
assign stepSizeMapCg[0]  = 4'd1;
assign stepSizeMapCg[1]  = 4'd2;
assign stepSizeMapCg[2]  = 4'd3;
assign stepSizeMapCg[3]  = 4'd4;
assign stepSizeMapCg[4]  = 4'd5;
assign stepSizeMapCg[5]  = 4'd6;
assign stepSizeMapCg[6]  = 4'd7;
assign stepSizeMapCg[7]  = 4'd7;
assign stepSizeMapCg[8]  = 4'd8;
assign stepSizeMapCg[9]  = 4'd9;
assign stepSizeMapCg[10] = 4'd10;
assign stepSizeMapCg[11] = 4'd11;

integer i;
integer c;
reg [3:0] indexMappingTransform [2:0][15:0];
reg [3:0] indexMappingBp [2:0][15:0];

always @ (*) begin
  for (i=0; i<16; i=i+1) begin
    indexMappingTransform[0][i] = ecIndexMapping_Transform_8x2[i];
    indexMappingBp[0][i] = ecIndexMapping_BP_8x2[i];
  end
  for (c=1; c<3; c=c+1) begin
    for (i=0; i<16; i=i+1) begin // Default to avoid inferred latches
      indexMappingTransform[c][i] = 4'b0;
      indexMappingBp[c][i] = 4'b0;
    end
    case (chroma_format)
      2'd0: // 4:4:4
        for (i=0; i<16; i=i+1) begin
          indexMappingTransform[c][i] = ecIndexMapping_Transform_8x2[i];
          indexMappingBp[c][i] = ecIndexMapping_BP_8x2[i];
        end
      2'd1: // 4:2:2
        for (i=0; i<8; i=i+1) begin
          indexMappingTransform[c][i] = i;
          indexMappingBp[c][i] = ecIndexMapping_BP_4x2[i];
        end
      2'd2: // 4:2:0
        for (i=0; i<4; i=i+1) begin
          indexMappingTransform[c][i] = i;
          indexMappingBp[c][i] = i;
        end
      default:
        for (i=0; i<16; i=i+1) begin
          indexMappingTransform[c][i] = ecIndexMapping_Transform_8x2[i];
          indexMappingBp[c][i] = ecIndexMapping_BP_8x2[i];
        end
    endcase
  end
end 
  
// Table 4-80 in spec
localparam MODE_TRANSFORM = 3'd0;
localparam MODE_BP        = 3'd1;
localparam MODE_MPP       = 3'd2;
localparam MODE_MPPF      = 3'd3;
localparam MODE_BP_SKIP   = 3'd4;

// Table 4-81 in spec
localparam FLATNESS_VERY_FLAT     = 2'b00;
localparam FLATNESS_SOMEWHAT_FLAT = 2'b01;
localparam FLATNESS_COMP2FLAT     = 2'b10;
localparam FLATNESS_FLAT2COMP     = 2'b11;

// modeType
localparam EC_TRANSFORM = 1'b0;
localparam EC_BP        = 1'b1;

localparam mtkQcomVectorEcThreshold = 5'd2;

wire [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_i [3:0];
wire [4:0] compNumSamples [2:0];
reg [5:0] bpv2x2_r [3:0];
reg [5:0] bpv2x1_r [3:0][1:0];
genvar gi;
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_data_to_be_parsed_i
    assign data_to_be_parsed_i[gi] = data_to_be_parsed_p[gi*MAX_FUNNEL_SHIFTER_SIZE+:MAX_FUNNEL_SHIFTER_SIZE];
  end
  for (gi=0; gi<3; gi=gi+1) begin : gen_compNumSamples
    assign compNumSamples[gi] = compNumSamples_p[gi*5+:5];
  end
  for (gi=0; gi<4; gi=gi+1) begin : gen_bpv2x2_bpv2x1
    assign bpv2x2_p[gi*6+:6] = bpv2x2_r[gi];
    assign bpv2x1_p[gi*2*6+:6] = bpv2x1_r[gi][0];
    assign bpv2x1_p[(gi*2+1)*6+:6] = bpv2x1_r[gi][1];
  end
endgenerate

localparam SOS_FSM_IDLE = 2'd0;
localparam SOS_FSM_FETCH_SSM0 = 2'd1;
localparam SOS_FSM_PARSE_SSM0 = 2'd2;
localparam SOS_FSM_RUNTIME = 2'd3;

reg [1:0] clk_cnt;
reg parse_substreams_i;
always @ (*)
  if (isFirstParse)
    parse_substreams_i = ~stall_pull & (clk_cnt == 2'd2) & fs_ready[0] & (sos_fsm >= SOS_FSM_PARSE_SSM0);
  else
    parse_substreams_i = ~stall_pull & (clk_cnt == 2'd2) & ((eos_fsm == 2'b0) ? (&fs_ready) : (&fs_ready[3:1]));
    
reg [4:0] parse_substreams_i_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    parse_substreams_i_dl <= 5'b0;
  else
    parse_substreams_i_dl <= {parse_substreams_i_dl[3:0], parse_substreams_i};
assign parse_substreams = parse_substreams_i & ~parse_substreams_i_dl[0];

reg parse_substreams_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    parse_substreams_dl <= 1'b0;
  else if (flush | sos)
    parse_substreams_dl <= 1'b0;
  else
    parse_substreams_dl <= parse_substreams;

reg [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_r [3:0];
always @ (posedge clk)
  for (i=0; i<4; i=i+1)
    if (parse_substreams)
      data_to_be_parsed_r[i] <= data_to_be_parsed_i[i];
wire [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed [3:0];
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_data_to_be_parsed
    assign data_to_be_parsed[gi] = parse_substreams ? data_to_be_parsed_i[gi] : data_to_be_parsed_r[gi];
  end
endgenerate

function [15:0] BitReverse;
  input [15:0] x;
  input integer n;
  integer i;
  begin
    BitReverse = 16'b0;
    for (i=0; i<n; i=i+1)
      BitReverse[i] = x[n-1-i];
  end
endfunction

reg [1:0] nextBlockIsFls_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    nextBlockIsFls_dl <= 2'b11;
  else if (blockBits_valid)
    nextBlockIsFls_dl <= {nextBlockIsFls_dl[0], nextBlockIsFls};

integer k;
integer s;
integer sb; // sub-block index

integer maxChromaEcgIdx;
always @ (*)
  case (chroma_format)
    2'd0: maxChromaEcgIdx = 4;
    2'd1: maxChromaEcgIdx = 2;
    2'd2: maxChromaEcgIdx = 1;
    default: maxChromaEcgIdx = 4;
  endcase

wire [2:0] bitsPerBpv;
assign bitsPerBpv = nextBlockIsFls/*_dl[0]*/ ? 3'd5 : 3'd6;

reg [8:0] bit_pointer [3:0];
reg modeSameFlag;
reg [2:0] curBlockMode;
reg [2:0] curBlockMode_r;
reg flatnessFlag;
reg [1:0] flatnessType;
reg [2:0] nextBlockBestIntraPredIdx;
reg [3:0] use2x2;
reg [5:0] bpv2x2_i_0; // subblock 0
reg [5:0] bpv2x1_i_0[1:0]; // Two vectors for subblock 0
reg [1:0] nextBlockCsc; // 0: RGB, 1: YCoCg
reg [3:0] nextBlockStepSize;
reg [3:0] stepSizeSsm0 [2:0];
reg [4:0] mppQuantBits_0 [2:0];
reg signed [16:0] mppNextBlockQuant [2:0][15:0];
reg [15:0] val;
reg mppfIndexNextBlock;
reg [3:0] compBits [2:0];

// Ssm 0 parser
// ------------
always @ (*) begin : proc_parser_0
  bit_pointer[0] = 9'd0; // init
  nextBlockBestIntraPredIdx = 3'd0; // init
  use2x2 = 4'b0000; // init
  bpv2x2_i_0 = 6'd0; // init
  bpv2x1_i_0[0] = 6'd0; // init
  bpv2x1_i_0[1] = 6'd0; // init
  curBlockMode = curBlockMode_r; // default
  modeSameFlag = 1'b0; // default
  flatnessFlag = 1'b0; // default
  flatnessType = 2'b0; // default
  nextBlockCsc = 2'b0; // default
  nextBlockStepSize = 4'd0; // default
  val = 16'd0; // default
  mppfIndexNextBlock = 1'b0;
  for (c = 0; c < 3; c = c + 1) begin
    mppQuantBits_0[c] = 5'd0; // default
    stepSizeSsm0[c] = 4'd0; // default
    compBits[c] = 4'd0;
    for (s = 0; s < 16; s = s + 1) begin
      mppNextBlockQuant[c][s] = 17'b0;
    end
  end
  
  if (~eos) begin
    modeSameFlag = data_to_be_parsed[0][bit_pointer[0]];
    bit_pointer[0] = bit_pointer[0] + 1'b1;
    // DecodeModeHeader in C
    if (~modeSameFlag) begin
      bit_pointer[0] = bit_pointer[0] + 2'd2;
      case ({data_to_be_parsed[0][1], data_to_be_parsed[0][2]})
        2'b00: curBlockMode = MODE_TRANSFORM;
        2'b01: curBlockMode = MODE_BP;
        2'b10: curBlockMode = MODE_MPP;
        2'b11:
          begin 
            bit_pointer[0] = bit_pointer[0] + 1'b1;
            if (data_to_be_parsed[0][3])
              curBlockMode = MODE_BP_SKIP;
            else
              curBlockMode = MODE_MPPF;
          end
      endcase
    end
    else
      curBlockMode = curBlockMode_r;
    // DecodeFlatnessType in C
    flatnessFlag = data_to_be_parsed[0][bit_pointer[0]];
    bit_pointer[0] = bit_pointer[0] + 1'b1;
    if (flatnessFlag) begin
      flatnessType = {data_to_be_parsed[0][bit_pointer[0]], data_to_be_parsed[0][bit_pointer[0]+1]};
      bit_pointer[0] = bit_pointer[0] + 2'd2;
    end
  
    case (curBlockMode) // Line #262 in DecTop.cpp - switch (modeNext) { ... }
      MODE_TRANSFORM: // DecodeBestIntraPredictor in C
        if (~nextBlockIsFls) begin
          nextBlockBestIntraPredIdx = {data_to_be_parsed[0][bit_pointer[0]], data_to_be_parsed[0][bit_pointer[0]+1], data_to_be_parsed[0][bit_pointer[0]+2]};
          bit_pointer[0] = bit_pointer[0] + 2'd3;
        end
      MODE_MPP, MODE_MPPF:
        begin
          if (curBlockMode == MODE_MPP) begin
            // ParseCsc in C
            if (source_color_space == 2'd2)
              nextBlockCsc = 2'd2;
            else begin
              nextBlockCsc = {1'b0, data_to_be_parsed[0][bit_pointer[0]]};
              bit_pointer[0] = bit_pointer[0] + 1'b1;
            end
            // ParseStepSize in C
            if (bits_per_component_coded == 2'd0) begin
              nextBlockStepSize = {1'b0, BitReverse(data_to_be_parsed[0][bit_pointer[0]+:3], 3)};
              bit_pointer[0] = bit_pointer[0] + 9'd3;
            end
            else begin
              nextBlockStepSize = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:4], 4);
              bit_pointer[0] = bit_pointer[0] + 9'd4;
            end
          end
          else begin // curBlockMode == MODE_MPPF
            if (source_color_space == 2'd2) begin // YCbCr
              mppfIndexNextBlock = 2'd0;
              nextBlockCsc = 2'd2; // m_mppfAdaptiveCsc[m_mppfIndexNext] in C
            end
            else begin
              mppfIndexNextBlock = data_to_be_parsed[0][bit_pointer[0]];
              bit_pointer[0] = bit_pointer[0] + 1'b1;
              nextBlockCsc = {1'b0, mppfIndexNextBlock}; // m_mppfAdaptiveCsc[m_mppfIndexNext] in C
            end
            
          end          
          // DecodeMppSuffixBits in C for ssmIdx 0
          for (c = 0; c < 3; c = c + 1) begin
            if (curBlockMode == MODE_MPP) begin
              if ((nextBlockCsc == 2'd1) & (c > 0)) begin
                if (c == 1)
                  stepSizeSsm0[c] = stepSizeMapCo[nextBlockStepSize];
                else // c==2
                  stepSizeSsm0[c] = stepSizeMapCg[nextBlockStepSize];
              end
              else
                stepSizeSsm0[c] = nextBlockStepSize;
            end
            else begin // curBlockMode == MODE_MPPF
              case(c)
                4'd0: compBits[c] = (~mppfIndexNextBlock | (nextBlockCsc == 2'd2)) ? mppf_bits_per_comp_R_Y : mppf_bits_per_comp_Y;
                4'd1: compBits[c] = (~mppfIndexNextBlock | (nextBlockCsc == 2'd2)) ? mppf_bits_per_comp_G_Cb : mppf_bits_per_comp_Co;
                4'd2: compBits[c] = (~mppfIndexNextBlock | (nextBlockCsc == 2'd2)) ? mppf_bits_per_comp_B_Cr : mppf_bits_per_comp_Cg;
                default: compBits[c] = (~mppfIndexNextBlock | (nextBlockCsc == 2'd2)) ? mppf_bits_per_comp_R_Y : mppf_bits_per_comp_Y;
              endcase
              case (bits_per_component_coded)
                2'd0: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
                2'd1: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd11 - compBits[c] : 4'd10 - compBits[c];
                2'd2: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd13 - compBits[c] : 4'd12 - compBits[c];
                default: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
              endcase
            end
            case (bits_per_component_coded)
              2'd0: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsm0[c] : 4'd8 - stepSizeSsm0[c];
              2'd1: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd11 - stepSizeSsm0[c] : 4'd10 - stepSizeSsm0[c];
              2'd2: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd13 - stepSizeSsm0[c] : 4'd12 - stepSizeSsm0[c];
              default: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsm0[c] : 4'd8 - stepSizeSsm0[c];
            endcase
            case(chroma_format)
              // 4:4:4
              2'd0:
                for (s = 0; s < 4; s = s + 1) begin // See g_mppSsmMapping_444 in C
                  case(mppQuantBits_0[c])
                    4'd1: val = data_to_be_parsed[0][bit_pointer[0]];
                    4'd2: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:2], 2);
                    4'd3: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:3], 3);
                    4'd4: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:4], 4);
                    4'd5: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
                    4'd6: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
                    4'd7: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:7], 7);
                    4'd8: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:8], 8);
                    4'd9: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:9], 9);
                    4'd10: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:10], 10);
                    4'd11: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:11], 11);
                    4'd12: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:12], 12);
                    4'd13: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:13], 13);
                    4'd14: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:14], 14);
                    4'd15: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:15], 15);
                    5'd16: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:16], 16);
                    default: val = data_to_be_parsed[0][bit_pointer[0]];
                  endcase
                  bit_pointer[0] = bit_pointer[0] + mppQuantBits_0[c];
                  mppNextBlockQuant[c][s] = $signed({1'b0, val}) - (16'sd1 << (mppQuantBits_0[c] - 1'b1));
                end
              // 4:2:2
              2'd1:
                if (c == 0)
                  for (s = 0; s < 8; s = s + 1) begin // See g_mppSsmMapping_422 in C
                    case(mppQuantBits_0[c])
                      4'd1: val = data_to_be_parsed[0][bit_pointer[0]];
                      4'd2: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:2], 2);
                      4'd3: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:3], 3);
                      4'd4: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:4], 4);
                      4'd5: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
                      4'd6: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
                      4'd7: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:7], 7);
                      4'd8: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:8], 8);
                      4'd9: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:9], 9);
                      4'd10: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:10], 10);
                      4'd11: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:11], 11);
                      4'd12: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:12], 12);
                      4'd13: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:13], 13);
                      4'd14: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:14], 14);
                      4'd15: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:15], 15);
                      5'd16: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:16], 16);
                      default: val = data_to_be_parsed[0][bit_pointer[0]];
                    endcase
                    bit_pointer[0] = bit_pointer[0] + mppQuantBits_0[c];
                    mppNextBlockQuant[c][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_0[c] - 1'b1));
                  end
              // 4:2:0
              2'd2:
                if (c == 0)
                  for (s = 0; s < 6; s = s + 1) begin // See g_mppSsmMapping_420 in C
                    case(mppQuantBits_0[c])
                      4'd1: val = data_to_be_parsed[0][bit_pointer[0]];
                      4'd2: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:2], 2);
                      4'd3: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:3], 3);
                      4'd4: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:4], 4);
                      4'd5: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
                      4'd6: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
                      4'd7: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:7], 7);
                      4'd8: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:8], 8);
                      4'd9: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:9], 9);
                      4'd10: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:10], 10);
                      4'd11: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:11], 11);
                      4'd12: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:12], 12);
                      4'd13: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:13], 13);
                      4'd14: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:14], 14);
                      4'd15: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:15], 15);
                      5'd16: val = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:16], 16);
                      default: val = data_to_be_parsed[0][bit_pointer[0]];
                    endcase
                    bit_pointer[0] = bit_pointer[0] + mppQuantBits_0[c];
                    mppNextBlockQuant[c][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_0[c] - 1'b1));
                  end
              default: bit_pointer[0] = 9'd0;
            endcase
          end
        end
      MODE_BP_SKIP, MODE_BP: // DecodeBpvNextBlock in C
        begin
          for (sb = 0; sb < 4; sb = sb + 1) begin
            use2x2[sb] = data_to_be_parsed[0][bit_pointer[0]];
            bit_pointer[0] = bit_pointer[0] + 1'b1;
          end
          if (use2x2[0]) begin
            if (bitsPerBpv == 3'd5)
              bpv2x2_i_0 = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
            else
              bpv2x2_i_0 = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
            bit_pointer[0] = bit_pointer[0] + bitsPerBpv;
            if (nextBlockIsFls)
              bpv2x2_i_0 = bpv2x2_i_0 + 6'd32;
          end
          else begin // bpv2x1
            if (bitsPerBpv == 3'd5) begin
              bpv2x1_i_0[0] = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
              //$display("time: %0t, bpv2x1_i[0][0] = %d", $realtime, bpv2x1_i_0[0]);
              bit_pointer[0] = bit_pointer[0] + 9'd5;
              bpv2x1_i_0[1] = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:5], 5);
              //$display("time: %0t, bpv2x1_i[0][1] = %d", $realtime, bpv2x1_i_0[1]);
              bit_pointer[0] = bit_pointer[0] + 9'd5;
            end
            else begin
              bpv2x1_i_0[0] = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
              bit_pointer[0] = bit_pointer[0] + 9'd6;
              bpv2x1_i_0[1] = BitReverse(data_to_be_parsed[0][bit_pointer[0]+:6], 6);
              bit_pointer[0] = bit_pointer[0] + 9'd6;
            end
            if (nextBlockIsFls) begin
              bpv2x1_i_0[0] = bpv2x1_i_0[0] + 7'd32;
              bpv2x1_i_0[1] = bpv2x1_i_0[1] + 7'd32;
            end
            //$display("time: %0t, bpv2x1_i[0][0] = %d", $realtime, bpv2x1_i_0[0]);
            //$display("time: %0t, bpv2x1_i[0][1] = %d", $realtime, bpv2x1_i_0[1]);
          end
        end
      default: bit_pointer[0] = 9'd0;
    endcase
  end
end

reg [2:0] numBitsLastSigPos [2:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    numBitsLastSigPos[c] = ((compNumSamples[c] == 16) ? 3'd4 : ((compNumSamples[c] == 8) ? 3'd3 : 3'd2));
    
function [3:0] GetBitsReqFromCodeWord_0;
  input [3:0] codeWord;
  begin
    case (codeWord)
      4'd0: GetBitsReqFromCodeWord_0 = 4'd1;
      4'd1: GetBitsReqFromCodeWord_0 = 4'd2;
      4'd2: GetBitsReqFromCodeWord_0 = 4'd3;
      4'd3: GetBitsReqFromCodeWord_0 = 4'd4;
      4'd4: GetBitsReqFromCodeWord_0 = 4'd0;
      default: GetBitsReqFromCodeWord_0 = codeWord;
    endcase
  end
endfunction

function [3:0] GetBitsReqFromCodeWord_other;
  input [3:0] codeWord;
  begin
    case (codeWord)
      4'd0: GetBitsReqFromCodeWord_other = 4'd1;
      4'd1: GetBitsReqFromCodeWord_other = 4'd0;
      default: GetBitsReqFromCodeWord_other = codeWord;
    endcase
  end
endfunction

// Ssm 1 to 3
// ----------
wire [2:0] bitsPerBpv_dl;
assign bitsPerBpv_dl = nextBlockIsFls_dl[0] ? 3'd5 : 3'd6;

reg [2:0] isCompSkip;
reg [3:0] lastSigPos [2:0];
reg [49:0] ecg [3:0];
reg [3:0] ecgDataActive [2:0];
reg [3:0] curEcgStart [2:0][3:0];
reg [5:0] curEcgEnd [2:0][3:0]; // Different per component, one per ECG
reg [15:0] coeffSign [2:0];
reg signed [16:0] compEcgCoeff [2:0][15:0]; // TBD bit width of each element of the array
reg [3:0] signSigPos;
reg [15:0] signBitValid [2:0];
localparam [4*4-1:0] ecTransformEcgStart_444 = 16'h0914;
localparam [4*4-1:0] ecTransformEcgStart_422 = 16'h0010;
localparam [4*4-1:0] ecTransformEcgStart_420 = 16'h0000;
reg [3:0] groupSkipActive [2:0]; // boolean per ECG (4) and per ssm, excluding ssm 0 (3)
reg [3:0] prefix [2:0][3:0];
reg uiBits;
reg [4:0] bitsReq [2:0][3:0];
integer ecgIdx;
reg useSignMag;
reg signed [16:0] pQuant [2:0][15:0];
integer curSubstream;
reg [3:0] bitsReqFromCodeWord [2:0][3:0];
reg [3:0] use2x2_r;
reg [7:0] symbol [2:0];
reg [5:0] bpv2x2_i [2:0]; // One vector per subblock cmpnt 0 is sb 1
reg [5:0] bpv2x1_i [2:0][1:0]; // Two vectors per subblock
reg [3:0] stepSizeSsmX [2:0];
reg [4:0] mppQuantBits_X [2:0];
reg [1:0] blockCsc;

// in C, DecTop.cpp line #329 - codingModes[mode]->Decode ()
always @ (*) begin : proc_parser_123
  reg [15:0] th;
  reg [15:0] pos;
  reg signed [16:0] neg;
  reg [3:0] ecgIdx_s;
  integer vecGrK;
  reg [3:0] maxPrefix;
  reg [4:0] suffix;
  reg [7:0] vecCodeNumber;
  reg [1:0] mask;
  reg [14:0] thresh;
  reg [14:0] offset;
  reg [5:0]  shift;
  reg [1:0] field;
  integer cnt_in_while;
  
  for (c = 0; c < 3; c = c + 1) begin
    // Default values to avoid latches
    curSubstream = c + 1;
    coeffSign[c] = 16'b0; // Default
    groupSkipActive[c] = 4'b0; // Default
    bit_pointer[curSubstream] = 9'd0; // Init
    signBitValid[c] = 16'b0;
    bpv2x2_i[c] = 6'd0;
    bpv2x1_i[c][0] = 6'd0;
    bpv2x1_i[c][1] = 6'd0;
    symbol[c] = 8'd0;
    maxPrefix[3:0] = 4'b0;
    vecGrK = 0;
    vecCodeNumber = 8'b0;
    mppQuantBits_X[c] = 5'd0; // default
    cnt_in_while = 0;
    for (ecgIdx = 0; ecgIdx < 4; ecgIdx = ecgIdx + 1) begin
      bitsReq[c][ecgIdx] = 5'd0;
      prefix[c][ecgIdx] = 4'd0;
    end
    for (s = 0; s < 16; s = s + 1) begin
      compEcgCoeff[c][s] = 17'sd0;
      pQuant[c][s] = 17'b0;
    end
    ecgIdx_s = 4'd0;
    stepSizeSsmX[c] = 4'd0;
    compBits[c] = 4'd0;
    blockCsc = 2'd0;
            
    // Parse differently in each mode
    if ((curBlockMode_r == MODE_BP_SKIP) | (curBlockMode_r == MODE_BP)) begin // DecodeBpvCurBlock in C
      if (use2x2_r[c+1]) begin// bpv2x2
        if (bitsPerBpv_dl == 3'd5) begin
          bpv2x2_i[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd5;
        end
        else begin
          bpv2x2_i[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd6;
        end
        if (nextBlockIsFls_dl[0])
          bpv2x2_i[c] = bpv2x2_i[c] + 6'd32;
      end
      else begin // bpv2x1
        if (bitsPerBpv_dl == 3'd5) begin
          bpv2x1_i[c][0] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd5;
          bpv2x1_i[c][1] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd5;
        end
        else begin
          bpv2x1_i[c][0] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd6;
          bpv2x1_i[c][1] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 9'd6;
        end
        if (nextBlockIsFls_dl[0]) begin
          bpv2x1_i[c][0] = bpv2x1_i[c][0] + 6'd32;
          bpv2x1_i[c][1] = bpv2x1_i[c][1] + 6'd32;
        end
      end
    end
    else if ((curBlockMode_r == MODE_MPP) | (curBlockMode_r == MODE_MPPF)) begin // MppMode::Decode in C
      if (curBlockMode_r == MODE_MPP) begin
        // DecodeMppSuffixBits for ssmIdx != 0
        if ((blockCsc_r == 2'd1) & (c > 0)) begin
          if (c == 1)
            stepSizeSsmX[c] = stepSizeMapCo[blockStepSize_r];
          else // c==2
            stepSizeSsmX[c] = stepSizeMapCg[blockStepSize_r];
        end
        else
          stepSizeSsmX[c] = blockStepSize_r;
      end
      else begin // curBlockMode_r == MODE_MPPF
        case(c)
          4'd0: compBits[c] = (~mppfIndex_r | (blockCsc_r == 2'd2)) ? mppf_bits_per_comp_R_Y : mppf_bits_per_comp_Y;
          4'd1: compBits[c] = (~mppfIndex_r | (blockCsc_r == 2'd2)) ? mppf_bits_per_comp_G_Cb : mppf_bits_per_comp_Co;
          4'd2: compBits[c] = (~mppfIndex_r | (blockCsc_r == 2'd2)) ? mppf_bits_per_comp_B_Cr : mppf_bits_per_comp_Cg;
          default: compBits[c] = (~mppfIndex_r | (blockCsc_r == 2'd2)) ? mppf_bits_per_comp_R_Y : mppf_bits_per_comp_Y;
        endcase
        case (bits_per_component_coded)
          2'd0: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
          2'd1: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd11 - compBits[c] : 4'd10 - compBits[c];
          2'd2: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd13 - compBits[c] : 4'd12 - compBits[c];
          default: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
        endcase
      end
      case (bits_per_component_coded)
        2'd0: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsmX[c] : 4'd8 - stepSizeSsmX[c];
        2'd1: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd11 - stepSizeSsmX[c] : 4'd10 - stepSizeSsmX[c];
        2'd2: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd13 - stepSizeSsmX[c] : 4'd12 - stepSizeSsmX[c];
        default: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsmX[c] : 4'd8 - stepSizeSsmX[c];
      endcase
      case(chroma_format)
        // 4:4:4
        2'd0:
          for (s = 4; s < 16; s = s + 1) begin // See g_mppSsmMapping_444 in C
            case(mppQuantBits_X[c])
              4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
              4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
              4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
              4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
              4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
              4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
              4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
              4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
              4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
              4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
              4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
              4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
              4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
              4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
              5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
              default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
            endcase
            bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[c];
            pQuant[c][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[c] - 1'b1));
          end
        // 4:2:2
        2'd1:
          for (s = 0; s < 16; s = s + 1) begin // See g_mppSsmMapping_422 in C
            if ((s >= ((curSubstream == 1) ? 8 : 0)) & (s < ((curSubstream == 1) ? 16 : 8))) begin
              case(mppQuantBits_X[c])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[c];
              pQuant[c][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[c] - 1'b1));
            end
          end
        // 4:2:0
        2'd2:
          if (curSubstream == 1) // See g_mppSsmMapping_420 in C
            for (s = 6; s < 12; s = s + 1) begin // component 0
              case(mppQuantBits_X[0])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[0];
              pQuant[0][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[0] - 1'b1));
            end
          else if (curSubstream == 2) begin // See g_mppSsmMapping_420 in C
            for (s = 12; s < 16; s = s + 1) begin // component 0
              case(mppQuantBits_X[0])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[0];
              pQuant[0][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[0] - 1'b1));
            end
            for (s = 0; s < 2; s = s + 1) begin // component 1
              case(mppQuantBits_X[1])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[1];
              pQuant[1][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[1] - 1'b1));
            end
          end
          else begin // curSubstream = 3. See g_mppSsmMapping_420 in C
            for (s = 2; s < 4; s = s + 1) begin // component 1
              case(mppQuantBits_X[1])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[1];
              pQuant[1][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[1] - 1'b1));
            end
            for (s = 0; s < 4; s = s + 1) begin // component 2
              case(mppQuantBits_X[2])
                4'd1: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                4'd2: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                4'd3: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                4'd4: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                4'd5: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                4'd6: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                4'd7: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                4'd8: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                4'd9: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                4'd10: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                4'd11: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                4'd12: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                4'd13: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                4'd14: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                4'd15: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                5'd16: val = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                default: val = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              endcase
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[2];
              pQuant[2][s] = $signed({1'b0, val}) - (17'sd1 << (mppQuantBits_X[2] - 1'b1));
            end
          end
        default: bit_pointer[curSubstream] = 9'd0;
      endcase
    end
    if ((curBlockMode_r == MODE_TRANSFORM) | (curBlockMode_r == MODE_BP)) begin // DecodeResiduals in C
      for (ecgIdx = 0; ecgIdx < 4; ecgIdx = ecgIdx + 1) begin
        bitsReq[c][ecgIdx] = 5'd0;
        prefix[c][ecgIdx] = 4'd0;
      end
      for (s = 0; s < 16; s = s + 1)
        compEcgCoeff[c][s] = 17'sd0;
      // DecodeAllGroups	
      if (c > 0) begin
        isCompSkip[c] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
        bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
      end
      else
        isCompSkip[c] = 1'b0;
      if (isCompSkip[c]) begin
        // read one more bit for 2-bit component skip flag
        if (curBlockMode_r == MODE_TRANSFORM) 
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
        // set all samples to zero
        for (s = 0; s < 16; s = s + 1) 
          compEcgCoeff[c][s] = 17'sd0; 
      end
      // lastSigPos
      if ((curBlockMode_r == MODE_TRANSFORM) & ~isCompSkip[c]) begin
        case (numBitsLastSigPos[c])
          3'd4: lastSigPos[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
          3'd3: lastSigPos[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
          3'd2: lastSigPos[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
          default: lastSigPos[c] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
        endcase
        bit_pointer[curSubstream] = bit_pointer[curSubstream] + numBitsLastSigPos[c];
      end
      else
        lastSigPos[c] = compNumSamples[c] - 1'b1;
      
      // Process ECGs
      for (ecgIdx = 0; ecgIdx < 4; ecgIdx = ecgIdx + 1) begin
        maxPrefix[3:0] = 4'b0;
        vecGrK = 0;
        vecCodeNumber = 8'b0; // Default
        curEcgStart[c][ecgIdx] = 4'd0; // Default
        curEcgEnd[c][ecgIdx] = 6'd0; // Default
        ecgIdx_s = ecgIdx;
        // GetEcgInfo
        if (isCompSkip[c])
          ecgDataActive[c][ecgIdx] = 1'b0;
        else
          case (curBlockMode_r)
            MODE_BP: 
              begin
                if ((c==0) | (ecgIdx < maxChromaEcgIdx)) begin
                  ecgDataActive[c][ecgIdx] = 1'b1;                      
                  curEcgStart[c][ecgIdx] = ecgIdx_s << 2;
                  curEcgEnd[c][ecgIdx] = curEcgStart[c][ecgIdx] + 3'd4;
                end
                else
                  ecgDataActive[c][ecgIdx] = 1'b0;
              end
            MODE_TRANSFORM:
              begin
                if ((chroma_format == 2'd0) | (c==0)) begin
                  curEcgStart[c][ecgIdx] = ecTransformEcgStart_444[ecgIdx*4+:4];
                  curEcgEnd[c][ecgIdx] = curEcgStart[c][ecgIdx] + transformEcgMappingLastSigPos_444[lastSigPos[c]][ecgIdx];
                end
                else if (chroma_format == 2'd1) begin // 4:2:2
                  curEcgStart[c][ecgIdx] = ecTransformEcgStart_422[ecgIdx*4+:4];
                  curEcgEnd[c][ecgIdx] = curEcgStart[c][ecgIdx] + transformEcgMappingLastSigPos_422[lastSigPos[c]][ecgIdx];
                end
                else begin // 4:2:0
                  curEcgStart[c][ecgIdx] = ecTransformEcgStart_420[ecgIdx*4+:4];
                  curEcgEnd[c][ecgIdx] = curEcgStart[c][ecgIdx] + transformEcgMappingLastSigPos_420[lastSigPos[c]][ecgIdx];
                end
                ecgDataActive[c][ecgIdx] = ((c==0) | (ecgIdx < maxChromaEcgIdx)) ? (curEcgEnd[c][ecgIdx] != {2'b0, curEcgStart[c][ecgIdx]}) : 1'b0;
              end
            default: ecgDataActive[c][ecgIdx] = 1'b0; 
          endcase
        // ecg: data
        if (ecgDataActive[c][ecgIdx]) begin
          // DecodeOneGroup
          // group skip active
          groupSkipActive[c][ecgIdx] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
          if (groupSkipActive[c][ecgIdx]) begin
            for (s = 0; s < 16; s = s + 1)
              if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx]))
                compEcgCoeff[c][s] = 17'sd0; 
          end
          else begin        
          // bitsReq = DecodePrefix
            /*
            prefix[c][ecgIdx] = 4'd0;
            uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
            bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
            while (uiBits) begin
              uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
              prefix[c][ecgIdx] = prefix[c][ecgIdx] + 1'b1;
            end
            */
            if (~data_to_be_parsed[curSubstream][bit_pointer[curSubstream]]) begin
              prefix[c][ecgIdx] = 4'd0;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2] == 2'b01) begin
              prefix[c][ecgIdx] = 4'd1;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd2;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3] == 3'b011) begin
              prefix[c][ecgIdx] = 4'd2;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd3;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4] == 4'b0111) begin
              prefix[c][ecgIdx] = 4'd3;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd4;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5] == 5'b01111) begin
              prefix[c][ecgIdx] = 4'd4;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd5;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6] == 6'b011111) begin
              prefix[c][ecgIdx] = 4'd5;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd6;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7] == 7'b0111111) begin
              prefix[c][ecgIdx] = 4'd6;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd7;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8] == 8'b01111111) begin
              prefix[c][ecgIdx] = 4'd7;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd8;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9] == 9'b011111111) begin
              prefix[c][ecgIdx] = 4'd8;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd9;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10] == 10'b0111111111) begin
              prefix[c][ecgIdx] = 4'd9;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd10;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11] == 11'b01111111111) begin
              prefix[c][ecgIdx] = 4'd10;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd11;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12] == 12'b011111111111) begin
              prefix[c][ecgIdx] = 4'd11;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd12;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13] == 13'b0111111111111) begin
              prefix[c][ecgIdx] = 4'd12;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd13;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14] == 14'b01111111111111) begin
              prefix[c][ecgIdx] = 4'd13;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd14;
            end
            else if (data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15] == 15'b011111111111111) begin
              prefix[c][ecgIdx] = 4'd14;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 4'd15;
            end
            else begin
              prefix[c][ecgIdx] = 4'd15;
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 5'd16;
            end
            
            bitsReqFromCodeWord[c][ecgIdx] = (c==0) ? GetBitsReqFromCodeWord_0(prefix[c][ecgIdx]) : GetBitsReqFromCodeWord_other(prefix[c][ecgIdx]);            
            bitsReq[c][ecgIdx] = (curBlockMode_r == MODE_TRANSFORM) ? (bitsReqFromCodeWord[c][ecgIdx] + 1'b1) : (prefix[c][ecgIdx] + 1'b1);
            //bit representation for group
            useSignMag = (ecgIdx < 3 ? 1'b1 : 1'b0);
            if (useSignMag) begin
              if ((bitsReq[c][ecgIdx] <= mtkQcomVectorEcThreshold) && (curBlockMode_r == MODE_BP)) begin
                // decode VEC ECG (SM)
                // DecodeVecEcSymbolSM in C
                vecGrK = ((bitsReq[c][ecgIdx] - 1'b1) == 1'b0) ? 2 : 5;
                //$display("vecGrK[%0d][%0d] = %d", c, ecgIdx, vecGrK);
                maxPrefix = ((8'b1 << (bitsReq[c][ecgIdx] << 2)) - 1'b1) >> vecGrK;
                //$display("maxPrefix[%0d][%0d] = %d", c, ecgIdx, maxPrefix);
                
                cnt_in_while = 0;
                uiBits = 1'b1;
                prefix[c][ecgIdx] = 4'd0;
                while (uiBits & (cnt_in_while <= 16)) begin
                  uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                  bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
                  prefix[c][ecgIdx] = prefix[c][ecgIdx] + uiBits;
                  if (prefix[c][ecgIdx] == maxPrefix)
                    uiBits = 1'b0;
                  cnt_in_while = cnt_in_while + 1;
                end
                
                //$display("prefix[%0d][%0d] = %d", c, ecgIdx, prefix[c][ecgIdx]);
                suffix = (vecGrK == 5) ? BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5) : 
                                         BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                bit_pointer[curSubstream] = bit_pointer[curSubstream] + ((vecGrK == 5) ? 3'd5 : 2'd2);
                //$display("suffix[%0d][%0d] = %d", c, ecgIdx, suffix);
                
                vecCodeNumber = (({4'b0, prefix[c][ecgIdx]} << vecGrK) | {3'b0, suffix});
                //$display("vecCodeNumber[%0d][%0d] = %d", c, ecgIdx, vecCodeNumber);
                if (bitsReq[c][ecgIdx] == 5'd1)
                  symbol[c] = (c == 0) ? {4'b0, vec_sm_bitsReq_1_luma_inv[vecCodeNumber]} : vec_sm_bitsReq_1_chroma_inv[vecCodeNumber];
                else
                  symbol[c] = (c == 0) ? {4'b0, vec_sm_bitsReq_2_luma_inv[vecCodeNumber]} : vec_sm_bitsReq_2_chroma_inv[vecCodeNumber];
                //$display("symbol[%0d][%0d] = %d", c, ecgIdx, symbol[c]);
                mask = (bitsReq[c][ecgIdx] == 5'd1) ? 2'b01 : 2'b11;
                // VecCodeSymbolToSamplesSM
                shift = 3*bitsReq[c][ecgIdx];
                for (s = 0; s < 16; s = s + 1) begin
                  if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx])) begin
                    compEcgCoeff[c][s] = $signed({1'b0, (symbol[c] >> shift) & mask});
                    //$display("compEcgCoeff[%0d][%0d] = %d", c, s, compEcgCoeff[c][s]);
                    shift = shift - bitsReq[c][ecgIdx];
                  end
                end
              end
              else begin
                // decode CPEC ECG (SM)
                for (s = 0; s < 16; s = s + 1) begin
                  if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx])) begin
                    case (bitsReq[c][ecgIdx])
                      5'd1: compEcgCoeff[c][s] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                      5'd2: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                      5'd3: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                      5'd4: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                      5'd5: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                      5'd6: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                      5'd7: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                      5'd8: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                      5'd9: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                      5'd10: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                      5'd11: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                      5'd12: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                      5'd13: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                      5'd14: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                      5'd15: compEcgCoeff[c][s] = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                      5'd16: compEcgCoeff[c][s] = $signed({1'b0, BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16)});
                      default: compEcgCoeff[c][s] = 17'sd0;
                    endcase
                    //$display("time: %0t, CPEC ECG (SM) compEcgCoeff[%0d][%0d] = %d", $realtime, c, s, compEcgCoeff[c][s]);
                    bit_pointer[curSubstream] = bit_pointer[curSubstream] + bitsReq[c][ecgIdx];
                  end
                end
              end
		          // set flag for valid sign bit
		          for (s = 0; s < 16; s = s + 1)
                if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx]))
		              if (compEcgCoeff[c][s] != 17'sd0)
		  	            signBitValid[c][s] = 1'b1;
		  	          else
		  	            signBitValid[c][s] = 1'b0;
	          end
            else begin
              if ((bitsReq[c][ecgIdx] <= mtkQcomVectorEcThreshold) && (curBlockMode_r == MODE_BP)) begin
                // decode VEC ECG (2C)
                // DecodeVecEcSymbol2C in C
                vecGrK = ((bitsReq[c][ecgIdx] - 1'b1) == 1'b0) ? 1 : 5;
                //$display("vecGrK[%0d][%0d] = %d", c, ecgIdx, vecGrK);
                maxPrefix = ((8'b1 << (bitsReq[c][ecgIdx] << 2)) - 1'b1) >> vecGrK;
                //$display("maxPrefix[%0d][%0d] = %d", c, ecgIdx, maxPrefix);
                uiBits = 1'b1;
                prefix[c][ecgIdx] = 4'd0;
                cnt_in_while = 0;
                while (uiBits & (cnt_in_while <= 16)) begin
                  uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                  bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
                  prefix[c][ecgIdx] = prefix[c][ecgIdx] + uiBits;
                  if (prefix[c][ecgIdx] == maxPrefix)
                    uiBits = 1'b0;
                  cnt_in_while = cnt_in_while + 1;
                end
                //$display("prefix[%0d][%0d] = %d", c, ecgIdx, prefix[c][ecgIdx]);
                suffix = (vecGrK == 5) ? BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5) : data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                bit_pointer[curSubstream] = bit_pointer[curSubstream] + ((vecGrK == 5) ? 3'd5 : 1'b1);
                vecCodeNumber = ((prefix[c][ecgIdx] << vecGrK) | suffix);
                if (bitsReq[c][ecgIdx] == 5'd1)
                  symbol[c] = (c == 0) ? {4'b0, vec_2c_bitsReq_1_luma_inv[vecCodeNumber]} : vec_2c_bitsReq_1_chroma_inv[vecCodeNumber];
                else
                  symbol[c] = (c == 0) ? {4'b0, vec_2c_bitsReq_2_luma_inv[vecCodeNumber]} : vec_2c_bitsReq_2_chroma_inv[vecCodeNumber];
                // VecCodeSymbolToSamples2C in C
                mask = (bitsReq[c][ecgIdx] == 5'd1) ? 2'b01 : 2'b11;
                thresh = 1'b1 << (bitsReq[c][ecgIdx] - 1'b1);
                offset = 1'b1 << bitsReq[c][ecgIdx];
                shift =  2'd3 * bitsReq[c][ecgIdx];
                for (s = 0; s < 16; s = s + 1) 
                  if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx])) begin
                    field = (symbol[c] >> shift) & mask;
                    compEcgCoeff[c][s] = (field < thresh) ? field : field - offset;
                    shift = shift - bitsReq[c][ecgIdx];
                  end
              end
              else begin
                // decode CPEC ECG (2C)
                th = (1'b1 << (bitsReq[c][ecgIdx] - 1'b1)) - 1'b1;
                //$display("th = %d", th);
                for (s = 0; s < 16; s = s + 1) begin
                  if ((s >= curEcgStart[c][ecgIdx]) & (s < curEcgEnd[c][ecgIdx])) begin
                    case (bitsReq[c][ecgIdx])
                      5'd1: pos = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:1];
                      5'd2: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:2], 2);
                      5'd3: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:3], 3);
                      5'd4: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:4], 4);
                      5'd5: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:5], 5);
                      5'd6: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:6], 6);
                      5'd7: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:7], 7);
                      5'd8: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:8], 8);
                      5'd9: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:9], 9);
                      5'd10: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:10], 10);
                      5'd11: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:11], 11);
                      5'd12: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:12], 12);
                      5'd13: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:13], 13);
                      5'd14: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:14], 14);
                      5'd15: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:15], 15);
                      5'd16: pos = BitReverse(data_to_be_parsed[curSubstream][bit_pointer[curSubstream]+:16], 16);
                      default: pos = 16'd0;
                    endcase
                    //$display("time: %0t, pos = %d", $realtime, pos);
		  	            bit_pointer[curSubstream] = bit_pointer[curSubstream] + bitsReq[c][ecgIdx];
                    neg = $signed({1'b0, pos}) - $signed({1'b0, 16'b1 << bitsReq[c][ecgIdx]});
                    //$display("neg = %d", neg);
                    compEcgCoeff[c][s] = (pos > th) ? neg : $signed({1'b0, pos});
                    //$display("CPEC ECG (2C) compEcgCoeff[%0d][%0d] = %d", c, s, compEcgCoeff[c][s]);
                  end
                end
              end
            end
          end          
        end
      
        // ecg: padding in substreams 1-3
        if (enableUnderflowPrevention & (ecgIdx >= 1))
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + rc_stuffing_bits;
        // ecg: sign bits in substream 3
        if ((ecgIdx == 3) & ~isCompSkip[c]) begin
          for (s = 0; s < 16; s = s + 1)
            if (signBitValid[c][s]) begin
              coeffSign[c][s] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
              compEcgCoeff[c][s] = (coeffSign[c][s]) ? -compEcgCoeff[c][s] : compEcgCoeff[c][s];
            end
          // signLastSigPos
          if (curBlockMode_r == MODE_TRANSFORM)
            if (~((lastSigPos[c] == 4'd0) & (c == 0))) begin
              if (compEcgCoeff[c][lastSigPos[c]] == 17'sd0) begin
                signSigPos[ecgIdx] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
              end
              else
                signSigPos[ecgIdx] = (compEcgCoeff[c][lastSigPos[c]] < 16'sd0) ? 1'b1 : 1'b0;
              // modify compEcgCoeff[lastSigPos]
              compEcgCoeff[c][lastSigPos[c]] = signSigPos[ecgIdx] ? (compEcgCoeff[c][lastSigPos[c]] - 1'b1) : (compEcgCoeff[c][lastSigPos[c]] + 1'b1);
            end
        end
      end
      // Remap pQuant coefficients
      for (s = 0; s < 16; s = s + 1)
        if (curBlockMode_r == MODE_TRANSFORM)
          pQuant[c][s] = compEcgCoeff[c][indexMappingTransform[c][s]];
        else
          pQuant[c][s] = compEcgCoeff[c][indexMappingBp[c][s]];
    end
  end
end      

reg [8:0] bit_pointer_r [3:0];
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    for (c = 0; c < 4; c = c + 1)
      bit_pointer_r[c] <= 9'd0;
  else if (flush)
    for (c = 0; c < 4; c = c + 1)
      bit_pointer_r[c] <= 9'd0;
  else
    for (c = 0; c < 4; c = c + 1)
      if (parse_substreams)
        bit_pointer_r[c] <= bit_pointer[c];
		
reg signed [16:0] mppBlockQuant_r [2:0][15:0]; // TBD bit width of each element of the array
reg signed [16:0] pQuant_r [2:0][15:0]; // TBD bit width of each element of the array
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    for (c = 0; c < 3; c = c + 1)
      for (s = 0; s < 16; s = s + 1)
        pQuant_r[c][s] <= 17'b0;
  else if (flush)
    for (c = 0; c < 3; c = c + 1)
      for (s = 0; s < 16; s = s + 1)
        pQuant_r[c][s] <= 17'b0;
  else
    if (parse_substreams)
      for (c = 0; c < 3; c = c + 1)
        for (s = 0; s < 16; s = s + 1)
          if ((curBlockMode_r == MODE_MPP) | (curBlockMode_r == MODE_MPPF))
            case (chroma_format)
              // 4:4:4
              2'd0: 
                if (s < 4) // See g_mppSsmMapping_444 in C
                  pQuant_r[c][s] <= mppBlockQuant_r[c][s];
                else
                  pQuant_r[c][s] <= pQuant[c][s];
              // 4:2:2
              2'd1:
                if (c == 0) // See g_mppSsmMapping_422 in C
                  if (s < 8)
                    pQuant_r[c][s] <= mppBlockQuant_r[c][s];
                  else
                    pQuant_r[c][s] <= pQuant[c][s];
                else
                  pQuant_r[c][s] <= pQuant[c][s];
              // 4:2:0
              2'd2:
                if (c == 0) // See g_mppSsmMapping_420 in C
                  if (s < 6)
                    pQuant_r[c][s] <= mppBlockQuant_r[0][s];
                  else
                    pQuant_r[c][s] <= pQuant[0][s];
                else
                  pQuant_r[c][s] <= pQuant[c][s];
              default: pQuant_r[c][s] <= pQuant[c][s];
            endcase
          else
            pQuant_r[c][s] <= pQuant[c][s];

reg [5:0] bpv2x2_0_r;
reg [5:0] bpv2x2 [3:0];
reg [5:0] bpv2x1_0_r [1:0];
reg [5:0] bpv2x1 [3:0][1:0];
always @ (*) begin
  bpv2x2[0] = bpv2x2_0_r;
  bpv2x1[0][0] = bpv2x1_0_r[0];
  bpv2x1[0][1] = bpv2x1_0_r[1];
  for (sb = 1; sb < 4; sb = sb + 1) begin
    bpv2x2[sb] = bpv2x2_i[sb-1];
    bpv2x1[sb][0] = bpv2x1_i[sb-1][0];
    bpv2x1[sb][1] = bpv2x1_i[sb-1][1];
  end
end

always @ (posedge clk) begin
  if (parse_substreams) begin
    curBlockMode_r <= curBlockMode;
    prevBlockMode_r <= curBlockMode_r;
    flatnessFlag_r <= flatnessFlag;
    flatnessType_r <= flatnessType;
    nextBlockBestIntraPredIdx_r <= nextBlockBestIntraPredIdx;
    use2x2_r <= use2x2;
    bpv2x2_0_r <= bpv2x2_i_0;
    bpv2x1_0_r[0] <= bpv2x1_i_0[0];
    bpv2x1_0_r[1] <= bpv2x1_i_0[1];
    for (sb = 0; sb < 4; sb = sb + 1) begin
      bpv2x2_r[sb] <= bpv2x2[sb];
      bpv2x1_r[sb][0] <= bpv2x1[sb][0];
      bpv2x1_r[sb][1] <= bpv2x1[sb][1];
    end
    blockCsc_r <= nextBlockCsc;
    blockStepSize_r <= nextBlockStepSize;
    for (c = 0; c < 3; c = c + 1)
      for (s = 0; s < 16; s = s + 1)
        mppBlockQuant_r[c][s] <= mppNextBlockQuant[c][s];
    mppfIndex_r <= mppfIndexNextBlock;
  end
end


always @ (posedge clk)
  if (pQuant_r_valid | sos) begin
    bpvTable <= use2x2_r;
    blockMode <= curBlockMode_r;
  end

reg substream0_parsed_i;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    substream0_parsed_i <= 1'b0;
  else if (substream0_parsed_i)
    substream0_parsed_i <= 1'b0;
  else if (isFirstParse)
    substream0_parsed_i <= fs_ready[0];
  else if (isLastBlock)
    substream0_parsed_i <= 1'b0;
  else
    substream0_parsed_i <= (&fs_ready) & (clk_cnt == 2'd2);
assign substream0_parsed = substream0_parsed_i & parse_substreams_dl & (sos_fsm >= 2'd2);
    
reg [2:0] substream_parsed;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    substream_parsed <= 3'b0;
  else 
    for (c = 0; c < 3; c = c + 1)
      if (substream_parsed[c])
        substream_parsed[c] <= 1'b0;
      else if ((fs_ready[c+1] | isLastBlock) & (clk_cnt == 2'd2) & parse_substreams)
        substream_parsed[c] <= 1'b1;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    clk_cnt <= 2'd0;
  else if (substream0_parsed)
    clk_cnt <= 2'd0;
  else if (clk_cnt < 2'd2)
    clk_cnt <= clk_cnt + 1'b1;
    
assign size_to_remove_valid = (&substream_parsed) & substream0_parsed;

assign substreams123_parsed = isLastBlock ? |substream_parsed : &substream_parsed;
    
genvar si;    
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_pack_outputs
    assign size_to_remove_p[gi*9+:9] = bit_pointer_r[gi];
    if (gi>0)
      for (si=0; si<16; si=si+1) begin : gen_pack_pQuant_r
        assign pQuant_r_p[((gi-1)*16+si)*17+:17] = pQuant_r[gi-1][si];
      end
  end
endgenerate

assign pQuant_r_valid = blockBits_valid;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockBits_valid <= 1'b0;
  else if (flush)
    blockBits_valid <= 1'b0;
  else
    blockBits_valid <= parse_substreams & ~isFirstParse; // There is no data available to parse in the beginning of the slice.

reg [8:0] curBlockBits0_dl; // extra delay for ssm 0 because it arrives one block before the other ssms
always @ (posedge clk)
  if (substream0_parsed) 
    curBlockBits0_dl <= bit_pointer_r[0];
    
reg [12:0] curBlockBits_d;
always @ (*) begin
  curBlockBits_d = curBlockBits0_dl;
  for (c = 1; c < 4; c = c + 1)
      curBlockBits_d = curBlockBits_d + bit_pointer[c];
end
always @ (posedge clk)
  if (parse_substreams)
    blockBits <= curBlockBits_d;

reg blockBits_valid_dl;    
always @ (posedge clk)
  if (sos & substream0_parsed)
    blockBits_valid_dl <= 1'b0;
  else
    blockBits_valid_dl <= blockBits_valid;

reg [2:0] curBlockMode_rr;
always @ (posedge clk)
  if (parse_substreams)
    curBlockMode_rr <= curBlockMode_r;

always @ (posedge clk)
  if (|substream_parsed) begin
    if (enableUnderflowPrevention & ((curBlockMode_rr == MODE_TRANSFORM) | (curBlockMode_rr == MODE_BP)))
      prevBlockBitsWithoutPadding <= blockBits - rcStuffingBitsX9; 
    else
      prevBlockBitsWithoutPadding <= blockBits;
  end
assign prevBlockBitsWithoutPadding_valid = blockBits_valid_dl;

assign mpp_ctrl_valid = parse_substreams;

endmodule
