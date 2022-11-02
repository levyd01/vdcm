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
  output wire [7*4-1:0] bpv2x2_p,
  output wire [7*4*2-1:0] bpv2x1_p,
  output wire substream0_parsed,
  output wire substreams123_parsed,
  input wire stall_pull,
  output wire parse_substreams,
  
  output wire [16*3*16-1:0] pQuant_r_p,
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

`include "../../rtl/decoder/syntax_parser_tables.v"
integer i;
integer c;
reg [3:0] indexMappingTransform [2:0][15:0];
reg [3:0] indexMappingBp [2:0][15:0];

always @ (*) begin
  for (i=0; i<16; i=i+1) begin
    indexMappingTransform[0][i] = ecIndexMapping_Transform_8x2[i];
    indexMappingBp[0][i] = ecIndexMapping_BP_8x2[i];
  end
  for (c=1; c<3; c=c+1)
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
    endcase
end 
  
// Table 4-80 in spec
parameter MODE_TRANSFORM = 3'd0;
parameter MODE_BP        = 3'd1;
parameter MODE_MPP       = 3'd2;
parameter MODE_MPPF      = 3'd3;
parameter MODE_BP_SKIP   = 3'd4;

// Table 4-81 in spec
parameter FLATNESS_VERY_FLAT     = 2'b00;
parameter FLATNESS_SOMEWHAT_FLAT = 2'b01;
parameter FLATNESS_COMP2FLAT     = 2'b10;
parameter FLATNESS_FLAT2COMP     = 2'b11;

// modeType
parameter EC_TRANSFORM = 1'b0;
parameter EC_BP        = 1'b1;

parameter mtkQcomVectorEcThreshold = 5'd2;

wire [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_i [3:0];
wire [4:0] compNumSamples [2:0];
reg [6:0] bpv2x2_r [3:0];
reg [6:0] bpv2x1_r [3:0][1:0];
genvar gi;
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_data_to_be_parsed_i
    assign data_to_be_parsed_i[gi] = data_to_be_parsed_p[gi*MAX_FUNNEL_SHIFTER_SIZE+:MAX_FUNNEL_SHIFTER_SIZE];
  end
  for (gi=0; gi<3; gi=gi+1) begin : gen_compNumSamples
    assign compNumSamples[gi] = compNumSamples_p[gi*5+:5];
  end
  for (gi=0; gi<4; gi=gi+1) begin : gen_bpv2x2_bpv2x1
    assign bpv2x2_p[gi*7+:7] = bpv2x2_r[gi];
    assign bpv2x1_p[gi*2*7+:7] = bpv2x1_r[gi][0];
    assign bpv2x1_p[(gi*2+1)*7+:7] = bpv2x1_r[gi][1];
  end
endgenerate

reg eos_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eos_dl <= 1'b0;
  else if (sos)
    eos_dl <= 1'b0;
  else if (blockBits_valid)
    eos_dl <= eos;

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
    parse_substreams_i = ~stall_pull & (clk_cnt == 2'd2) & (isLastBlock | (&fs_ready));

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
reg [6:0] bpv2x2_i_0; // subblock 0
reg [6:0] bpv2x1_i_0[1:0]; // Two vectors for subblock 0
reg [1:0] nextBlockCsc; // 0: RGB, 1: YCoCg
reg [3:0] nextBlockStepSize;
reg [3:0] stepSizeSsm0 [2:0];
reg [3:0] mppQuantBits_0 [2:0];
reg signed [15:0] mppNextBlockQuant [2:0][15:0];
reg [15:0] val;
reg mppfIndexNextBlock;
reg [3:0] compBits [2:0];

// Ssm 0 parser
// ------------
always @ (*) begin : proc_parser_0
  bit_pointer[0] = 9'd0; // init
  nextBlockBestIntraPredIdx = 3'd0; // init
  use2x2 = 4'b0000; // init
  bpv2x2_i_0 = 7'd0; // init
  bpv2x1_i_0[0] = 7'd0; // init
  bpv2x1_i_0[1] = 7'd0; // init
  curBlockMode = curBlockMode_r; // default
  modeSameFlag = 1'b0; // default
  flatnessFlag = 1'b0; // default
  flatnessType = 2'b0; // default
  nextBlockCsc = 2'b0; // default
  nextBlockStepSize = 4'd0; // default
  val = 16'd0; // default
  mppfIndexNextBlock = 1'b0;
  for (c = 0; c < 3; c = c + 1) begin
    mppQuantBits_0[c] = 4'd0; // default
    stepSizeSsm0[c] = 4'd0; // default
    compBits[c] = 4'd0;
    for (s = 0; s < compNumSamples[c]; s = s + 1) begin
      mppNextBlockQuant[c][s] = 16'b0;
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
              endcase
              case (bits_per_component_coded)
                2'd0: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
                2'd1: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd11 - compBits[c] : 4'd10 - compBits[c];
                2'd2: stepSizeSsm0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd13 - compBits[c] : 4'd12 - compBits[c];
              endcase
            end
            case (bits_per_component_coded)
              2'd0: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsm0[c] : 4'd8 - stepSizeSsm0[c];
              2'd1: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd11 - stepSizeSsm0[c] : 4'd10 - stepSizeSsm0[c];
              2'd2: mppQuantBits_0[c] = ((nextBlockCsc == 2'd1) & (c > 0)) ? 4'd13 - stepSizeSsm0[c] : 4'd12 - stepSizeSsm0[c];
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
                    endcase
                    bit_pointer[0] = bit_pointer[0] + mppQuantBits_0[c];
                    mppNextBlockQuant[c][s] = $signed({1'b0, val}) - (16'sd1 << (mppQuantBits_0[c] - 1'b1));
                  end
              // 4:2:0 TBD              
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
reg [3:0] curEcgStart [3:0]; // Same for all components, one per ECG
reg [5:0] curEcgEnd [2:0][3:0]; // Different per component, one per ECG
reg [15:0] coeffSign [2:0];
reg signed [15:0] compEcgCoeff [2:0][15:0]; // TBD bit width of each element of the array
reg [3:0] signSigPos;
reg [15:0] signBitValid [2:0];
parameter [4*4-1:0] ecTransformEcgStart_444 = 16'h0914;
parameter [4*4-1:0] ecTransformEcgStart_420 = 16'h0010;
reg [3:0] groupSkipActive [2:0]; // boolean per ECG (4) and per ssm, excluding ssm 0 (3)
reg [3:0] prefix [2:0][3:0];
reg uiBits;
reg [4:0] bitsReq [2:0][3:0];
integer ecgIdx;
reg useSignMag;
reg signed [15:0] pQuant [2:0][15:0];
integer curSubstream;
reg [3:0] bitsReqFromCodeWord [2:0][3:0];
reg [3:0] use2x2_r;
reg [7:0] symbol [2:0];
reg [6:0] bpv2x2_i [2:0]; // One vector per subblock cmpnt 0 is sb 1
reg [6:0] bpv2x1_i [2:0][1:0]; // Two vectors per subblock
reg [3:0] stepSizeSsmX [2:0];
reg [3:0] mppQuantBits_X [2:0];
reg [1:0] blockCsc;

// in C, DecTop.cpp line #329 - codingModes[mode]->Decode ()
always @ (*) begin : proc_parser_123
  reg [15:0] th;
  reg [14:0] pos;
  reg signed [15:0] neg;
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
  
  for (c = 0; c < 3; c = c + 1) begin
    // Default values to avoid latches
    curSubstream = c + 1;
    coeffSign[c] = 16'b0; // Default
    groupSkipActive[c] = 4'b0; // Default
    bit_pointer[curSubstream] = 9'd0; // Init
    signBitValid[c] = 16'b0;
    bpv2x2_i[c] = 7'd0;
    bpv2x1_i[c][0] = 7'd0;
    bpv2x1_i[c][1] = 7'd0;
    symbol[c] = 8'd0;
    maxPrefix[3:0] = 4'b0;
    vecGrK = 0;
    vecCodeNumber = 8'b0;
    mppQuantBits_X[c] = 4'd0; // default
    for (ecgIdx = 0; ecgIdx < 4; ecgIdx = ecgIdx + 1) begin
      bitsReq[c][ecgIdx] = 5'd0;
      prefix[c][ecgIdx] = 4'd0;
    end
    for (s = 0; s < compNumSamples[c]; s = s + 1) begin
      compEcgCoeff[c][s] = 16'sd0;
      pQuant[c][s] = 16'b0;
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
        endcase
        case (bits_per_component_coded)
          2'd0: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
          2'd1: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd11 - compBits[c] : 4'd10 - compBits[c];
          2'd2: stepSizeSsmX[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd13 - compBits[c] : 4'd12 - compBits[c];
        endcase
      end
      case (bits_per_component_coded)
        2'd0: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd9 - stepSizeSsmX[c] : 4'd8 - stepSizeSsmX[c];
        2'd1: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd11 - stepSizeSsmX[c] : 4'd10 - stepSizeSsmX[c];
        2'd2: mppQuantBits_X[c] = ((blockCsc_r == 2'd1) & (c > 0)) ? 4'd13 - stepSizeSsmX[c] : 4'd12 - stepSizeSsmX[c];
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
            endcase
            bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[c];
            pQuant[c][s] = $signed({1'b0, val}) - (16'sd1 << (mppQuantBits_X[c] - 1'b1));
          end
        // 4:2:2
        2'd1:
          for (s = ((curSubstream == 1) ? 8 : 0); s < ((curSubstream == 1) ? 16 : 8); s = s + 1) begin // See g_mppSsmMapping_422 in C
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
            endcase
            bit_pointer[curSubstream] = bit_pointer[curSubstream] + mppQuantBits_X[c];
            pQuant[c][s] = $signed({1'b0, val}) - (16'sd1 << (mppQuantBits_X[c] - 1'b1));
          end
        // 4:2:0 TBD              
      endcase
    end
    if ((curBlockMode_r == MODE_TRANSFORM) | (curBlockMode_r == MODE_BP)) begin // DecodeResiduals in C
      for (ecgIdx = 0; ecgIdx < 4; ecgIdx = ecgIdx + 1) begin
        bitsReq[c][ecgIdx] = 5'd0;
        prefix[c][ecgIdx] = 4'd0;
      end
      for (s = 0; s < compNumSamples[c]; s = s + 1)
        compEcgCoeff[c][s] = 16'sd0;
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
        for (s = 0; s < compNumSamples[c]; s = s + 1) 
          compEcgCoeff[c][s] = 16'sd0; 
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
        curEcgStart[ecgIdx] = 4'd0; // Default
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
                  curEcgStart[ecgIdx] = ecgIdx_s << 2;
                  curEcgEnd[c][ecgIdx] = curEcgStart[ecgIdx] + 3'd4;
                end
                else
                  ecgDataActive[c][ecgIdx] = 1'b0;
              end
            MODE_TRANSFORM:
              begin
                if ((chroma_format == 2'd0) | (c==0)) begin
                  curEcgStart[ecgIdx] = ecTransformEcgStart_444[ecgIdx*4+:4];
                  curEcgEnd[c][ecgIdx] = curEcgStart[ecgIdx] + transformEcgMappingLastSigPos_444[lastSigPos[c]][ecgIdx];
                end
                else if (chroma_format == 2'd1) begin // 4:2:2
                  curEcgStart[ecgIdx] = ecTransformEcgStart_420[ecgIdx*4+:4];
                  curEcgEnd[c][ecgIdx] = curEcgStart[ecgIdx] + transformEcgMappingLastSigPos_422[lastSigPos[c]][ecgIdx];
                end
                // else 4:2:0 TBD
                if (curEcgEnd[c][ecgIdx] > {2'b0, curEcgStart[ecgIdx]})
                  ecgDataActive[c][ecgIdx] = 1'b1;
                else
                  ecgDataActive[c][ecgIdx] = 1'b0;
              end
          endcase
        // ecg: data
        if (ecgDataActive[c][ecgIdx]) begin
          // DecodeOneGroup
          // group skip active
          groupSkipActive[c][ecgIdx] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
          bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
          if (groupSkipActive[c][ecgIdx]) begin
            for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1) 
              compEcgCoeff[c][s] = 16'sd0; 
          end
          else begin        
          // bitsReq = DecodePrefix
            prefix[c][ecgIdx] = 4'd0;
            uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
            bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
            while (uiBits) begin
              uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
              prefix[c][ecgIdx] = prefix[c][ecgIdx] + 1'b1;
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
                uiBits = 1'b1;
                prefix[c][ecgIdx] = 4'd0;
                while (uiBits) begin
                  uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                  bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
                  prefix[c][ecgIdx] = prefix[c][ecgIdx] + uiBits;
                  if (prefix[c][ecgIdx] == maxPrefix)
                    uiBits = 1'b0;
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
                for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1) begin
                  compEcgCoeff[c][s] = $signed({1'b0, (symbol[c] >> shift) & mask});
                  //$display("compEcgCoeff[%0d][%0d] = %d", c, s, compEcgCoeff[c][s]);
                  shift = shift - bitsReq[c][ecgIdx];
                end
              end
              else begin
                // decode CPEC ECG (SM)
                for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1) begin
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
                    default: compEcgCoeff[c][s] = 16'sd0;
                  endcase
                  //$display("time: %0t, CPEC ECG (SM) compEcgCoeff[%0d][%0d] = %d", $realtime, c, s, compEcgCoeff[c][s]);
                  bit_pointer[curSubstream] = bit_pointer[curSubstream] + bitsReq[c][ecgIdx];
                end
              end
		          // set flag for valid sign bit
		          for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1)
		            if (compEcgCoeff[c][s] != 16'd0)
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
                while (uiBits) begin
                  uiBits = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
                  bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
                  prefix[c][ecgIdx] = prefix[c][ecgIdx] + uiBits;
                  if (prefix[c][ecgIdx] == maxPrefix)
                    uiBits = 1'b0;
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
                for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1) begin
                  field = (symbol[c] >> shift) & mask;
                  compEcgCoeff[c][s] = (field < thresh) ? field : field - offset;
                  shift = shift - bitsReq[c][ecgIdx];
                end
              end
              else begin
                // decode CPEC ECG (2C)
                th = (1'b1 << (bitsReq[c][ecgIdx] - 1'b1)) - 1'b1;
                //$display("th = %d", th);
                for (s = curEcgStart[ecgIdx]; s < curEcgEnd[c][ecgIdx]; s = s + 1) begin
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
                    default: pos = 15'd0;
                  endcase
                  //$display("pos = %d", pos);
		  	          bit_pointer[curSubstream] = bit_pointer[curSubstream] + bitsReq[c][ecgIdx];
                  neg = $signed({1'b0, pos}) - $signed({1'b0, 15'b1 << bitsReq[c][ecgIdx]});
                  //$display("neg = %d", neg);
                  compEcgCoeff[c][s] = (pos > th) ? neg : $signed({1'b0, pos});
                  //$display("CPEC ECG (2C) compEcgCoeff[%d][%d] = %d", c, s, compEcgCoeff[c][s]);
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
          for (s = 0; s < compNumSamples[c]; s = s + 1)
            if (signBitValid[c][s]) begin
              coeffSign[c][s] = data_to_be_parsed[curSubstream][bit_pointer[curSubstream]];
              bit_pointer[curSubstream] = bit_pointer[curSubstream] + 1'b1;
              compEcgCoeff[c][s] = (coeffSign[c][s]) ? -compEcgCoeff[c][s] : compEcgCoeff[c][s];
            end
          // signLastSigPos
          if (curBlockMode_r == MODE_TRANSFORM)
            if (~((lastSigPos[c] == 4'd0) & (c == 0))) begin
              if (compEcgCoeff[c][lastSigPos[c]] == 4'd0) begin
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
      for (s = 0; s < compNumSamples[c]; s = s + 1)
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
		
reg signed [15:0] mppBlockQuant_r [2:0][15:0]; // TBD bit width of each element of the array
reg signed [15:0] pQuant_r [2:0][15:0]; // TBD bit width of each element of the array
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    for (c = 0; c < 3; c = c + 1)
      for (s = 0; s < 16; s = s + 1)
        pQuant_r[c][s] <= 16'sd0;
  else if (flush)
    for (c = 0; c < 3; c = c + 1)
      for (s = 0; s < 16; s = s + 1)
        pQuant_r[c][s] <= 16'sd0;
  else
    if (parse_substreams)
      for (c = 0; c < 3; c = c + 1)
        for (s = 0; s < compNumSamples[c]; s = s + 1)
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
              // 4:2:0 TBD
            endcase
          else
            pQuant_r[c][s] <= pQuant[c][s];

reg [6:0] bpv2x2_0_r;
reg [6:0] bpv2x2 [3:0];
reg [6:0] bpv2x1_0_r [1:0];
reg [6:0] bpv2x1 [3:0][1:0];
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
      for (s = 0; s < compNumSamples[c]; s = s + 1)
        mppBlockQuant_r[c][s] <= mppNextBlockQuant[c][s];
    mppfIndex_r <= mppfIndexNextBlock;
  end
end


always @ (posedge clk or negedge rst_n)
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
      for (si=0; si<16; si=si+1)
        assign pQuant_r_p[((gi-1)*16+si)*16+:16] = pQuant_r[gi-1][si];
  end
endgenerate

assign pQuant_r_valid = blockBits_valid;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockBits_valid <= 1'b0;
  else if (flush | (sos_fsm == SOS_FSM_IDLE))
    blockBits_valid <= 1'b0;
  else
    blockBits_valid <= parse_substreams & ~isFirstParse; // There is no data available to parse in the beginning of the slice.

reg [8:0] curBlockBits0_dl; // extra delay for ssm 0 because it arrives one block before the other ssms
always @ (posedge clk)
  if (substream0_parsed) 
    curBlockBits0_dl <= bit_pointer_r[0];
    
reg [13:0] curBlockBits_d;
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
