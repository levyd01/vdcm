// *********************************************************************
//
// Property of Vicip.
// Restricted rights to use, duplicate or disclose this code are
// granted through contract.
//
// (C) Copyright Vicip 2022
//
// Author         : David Levy
// Contact        : david.levy@vic-ip.com
// *********************************************************************

`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module mpp_mode
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [1:0] csc, // decoding color space 0: RGB, 1: YCoCg, 2: YCbCr (RGB impossible)
  input wire [1:0] bits_per_component_coded,
  input wire [12:0] midPoint,
  input wire [12:0] maxPoint,
  input wire [3*2-1:0] blkHeight_p,
  input wire [3*4-1:0] blkWidth_p,
  input wire [3:0] mppf_bits_per_comp_R_Y,
  input wire [3:0] mppf_bits_per_comp_G_Cb,
  input wire [3:0] mppf_bits_per_comp_B_Cr,
  input wire [3:0] mppf_bits_per_comp_Y,
  input wire [3:0] mppf_bits_per_comp_Co,
  input wire [3:0] mppf_bits_per_comp_Cg,

  input wire sos,
  input wire fbls, // First line of slice

  input wire [2:0] blockMode,
  input wire [1:0] blockCsc,
  input wire [3:0] blockStepSize,
  input wire mppfIndex,
  input wire mpp_ctrl_valid, // indicates that blockCsc & blockStepSize are valid
  
  input wire [16*3*17-1:0] pQuant_p,
  input wire pQuant_valid,
  
  input wire pReconLeftBlk_valid,
  input wire [2*8*3*14-1:0] pReconLeftBlk_p,
  input wire [8*3*14-1:0] pReconAboveBlk_p,
  input wire pReconAboveBlk_valid,
  
  output wire [2*8*3*14-1:0] pReconBlk_p,
  output wire pReconBlk_valid
  
);

// Unpack inputs
genvar ci, si;
genvar rowi, coli;
wire [1:0] blkHeight [2:0];
wire [4:0] blkWidth [2:0];
wire signed [16:0] pQuant [2:0][15:0];
wire signed [13:0] pReconLeftBlk [2:0][1:0][7:0];
generate
  for (ci =0; ci < 3; ci = ci + 1) begin : gen_unpack_inputs
    assign blkHeight[ci] = blkHeight_p[2*ci+:2];
    assign blkWidth[ci] = blkWidth_p[4*ci+:4];
    for (si=0; si<16; si=si+1) begin : gen_unpack_pquant
      assign pQuant[ci][si] = pQuant_p[ci*16*17+si*17+:17];
    end
    for (coli=0; coli<8; coli=coli+1) begin : gen_in_coli
      for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_in_coli
        assign pReconLeftBlk[ci][rowi][coli] = pReconLeftBlk_p[(ci*8*2 + rowi*8 + coli)*14+:14];
      end
    end
  end
endgenerate

integer c;
integer col;
reg signed [13:0] pReconAboveBlk [2:0][7:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1) begin
    for (col = 0; col < 8; col = col + 1)
      pReconAboveBlk[c][col] = 14'b0; // Default
    if ((chroma_format > 2'd0) & (c > 0)) 
      for (col = 0; col < 2; col = col + 1) begin
        pReconAboveBlk[c][col<<1] = pReconAboveBlk_p[(c*8 + (col<<2))*14+:14];
        pReconAboveBlk[c][(col<<1) + 1] = pReconAboveBlk_p[(c*8 + (col<<2) + 1)*14+:14];
      end
    else
      for (col = 0; col < 8; col = col + 1)
        pReconAboveBlk[c][col] = pReconAboveBlk_p[(c*8 + col)*14+:14];
  end

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

function signed [15:0] min;
  input signed [15:0] x;
  input signed [15:0] y;
  begin
    if (x < y)
      min = x;
    else
      min = y;
  end
endfunction

function signed [13:0] clip3;
  input signed [13:0] min;
  input signed [13:0] max;
  input signed [15:0] unclipped;
  begin
    if (unclipped > $signed({max[13], max[13], max}))
      clip3 = max;
    else if (unclipped < $signed({min[13], min[13], min}))
      clip3 = min;
    else
      clip3 = unclipped[13:0];
  end
endfunction


integer sb;

wire [2:0] numSubBlocksChroma;
assign numSubBlocksChroma = (chroma_format == 2'd0) ? 3'd4 : 3'd2;

// Middle
reg signed [13:0] middle [2:0][3:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (sb = 0; sb < 4; sb = sb + 1)
      if ((chroma_format != 2'd0) & (c > 0) & (sb >= numSubBlocksChroma))
        middle[c][sb] = 14'd0;
      else
        middle[c][sb] = ((blockCsc == 2'd1) & (c > 0)) ? 14'sd0 : $signed({1'b0, midPoint});

reg [3:0] mpp_ctrl_valid_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    mpp_ctrl_valid_dl <= 4'b0;
  else if (flush)
    mpp_ctrl_valid_dl <= 4'b0;
  else
    mpp_ctrl_valid_dl <= {mpp_ctrl_valid_dl[2:0], mpp_ctrl_valid};

parameter MODE_MPP       = 3'd2;
parameter MODE_MPPF      = 3'd3;

reg [3:0] stepSize [2:0];
reg [3:0] compBits [2:0];

wire [1:0] bitsPerCompA [2:0];
assign bitsPerCompA[0] = 2'd1;
assign bitsPerCompA[1] = 2'd2;
assign bitsPerCompA[2] = 2'd1;

wire [1:0] bitsPerCompB [2:0];
assign bitsPerCompB[0] = 2'd2;
assign bitsPerCompB[1] = 2'd1;
assign bitsPerCompB[2] = 2'd1;

always @ (*)
  for (c = 0; c < 3; c = c + 1) begin
    compBits[c] = 4'd0; // default
    if (blockMode == MODE_MPP) begin
      if ((blockCsc == 2'd1) & (c > 0)) begin
        if (c == 1)
          stepSize[c] = stepSizeMapCo[blockStepSize];
        else // c==2
          stepSize[c] = stepSizeMapCg[blockStepSize];
      end
      else
        stepSize[c] = blockStepSize;
    end
    else begin // blockMode == MODE_MPPF
      //compBits[c] = ~mppfIndex ? bitsPerCompA[c] : bitsPerCompB[c];
      case(c)
        4'd0: compBits[c] = (~mppfIndex | (blockCsc == 2'd2)) ? mppf_bits_per_comp_R_Y : mppf_bits_per_comp_Y;
        4'd1: compBits[c] = (~mppfIndex | (blockCsc == 2'd2)) ? mppf_bits_per_comp_G_Cb : mppf_bits_per_comp_Co;
        4'd2: compBits[c] = (~mppfIndex | (blockCsc == 2'd2)) ? mppf_bits_per_comp_B_Cr : mppf_bits_per_comp_Cg;
        default: compBits[c] = 4'd0;
      endcase
      case (bits_per_component_coded)
        2'd0: stepSize[c] = ((blockCsc == 2'd1) & (c > 0)) ? 4'd9 - compBits[c] : 4'd8 - compBits[c];
        2'd1: stepSize[c] = ((blockCsc == 2'd1) & (c > 0)) ? 4'd11 - compBits[c] : 4'd10 - compBits[c];
        2'd2: stepSize[c] = ((blockCsc == 2'd1) & (c > 0)) ? 4'd13 - compBits[c] : 4'd12 - compBits[c];
        default: stepSize[c] = 4'd0;
      endcase
    end
  end
      
// sos streched until first mpp_ctrl_valid of slice
reg sos_r;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos_r <= 1'b0;
  else if (flush)
    sos_r <= 1'b0;
  else if (sos)
    sos_r <= 1'b1;
  else if (mpp_ctrl_valid)
    sos_r <= 1'b0;
wire sos_streched;
assign sos_streched = sos | sos_r;

reg [1:0] blockCsc_dl;
always @ (posedge clk)
  if (mpp_ctrl_valid)
    blockCsc_dl <= blockCsc; 
    
reg [2:0] blockMode_dl;
always @ (posedge clk)
  if (mpp_ctrl_valid)
    blockMode_dl <= blockMode;
    
// If current block CSC is RGB, convert reconstructed block to RGB
wire [11:0] pReconLeftBlk_rgb [2:0][1:0][7:0];
generate
  for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_reconleft_rgb_rowi
    for (coli=0; coli<8; coli=coli+1) begin : gen_reconleft_rgb_coli
      ycocg2rgb ycocg2rgb_u
        (
          .maxPoint         (maxPoint),
          .src_y            (pReconLeftBlk[0][rowi][coli]),
          .src_co           (pReconLeftBlk[1][rowi][coli]),
          .src_cg           (pReconLeftBlk[2][rowi][coli]),
          .dst_r            (pReconLeftBlk_rgb[0][rowi][coli]),
          .dst_g            (pReconLeftBlk_rgb[1][rowi][coli]),
          .dst_b            (pReconLeftBlk_rgb[2][rowi][coli])
        );
    end
  end
endgenerate
integer row;
reg signed [13:0] pReconLeftBlk_converted [2:0][1:0][7:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (row = 0; row < 2; row = row + 1)
      for (col = 0; col < 8; col = col + 1)
        pReconLeftBlk_converted[c][row][col] = ((blockCsc == 2'd0) & ~sos_streched) ? $signed({2'b0, pReconLeftBlk_rgb[c][row][col]}) : pReconLeftBlk[c][row][col];

wire [11:0] pReconAboveBlk_rgb [2:0][7:0];
generate
  for (coli=0; coli<8; coli=coli+1) begin : gen_reconabove_rgb_coli
    ycocg2rgb ycocg2rgb_u
      (
        .maxPoint         (maxPoint),
        .src_y            (pReconAboveBlk[0][coli]),
        .src_co           (pReconAboveBlk[1][coli]),
        .src_cg           (pReconAboveBlk[2][coli]),
        .dst_r            (pReconAboveBlk_rgb[0][coli]),
        .dst_g            (pReconAboveBlk_rgb[1][coli]),
        .dst_b            (pReconAboveBlk_rgb[2][coli])
      );
  end
endgenerate
reg signed [13:0] pReconAboveBlk_converted [2:0][7:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (col = 0; col < 8; col = col + 1)
      pReconAboveBlk_converted[c][col] = $signed({2'b0, pReconAboveBlk_rgb[c][col]});
    
// Mean before color space conversion
reg signed [15:0] sumReconLeftBlk [2:0][3:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (sb = 0; sb < 4; sb = sb + 1)
      sumReconLeftBlk[c][sb] = pReconLeftBlk_converted[c][0][sb<<1] + pReconLeftBlk_converted[c][0][(sb<<1)+1] + 
                                               pReconLeftBlk_converted[c][1][sb<<1] + pReconLeftBlk_converted[c][1][(sb<<1)+1];
                                               
reg signed [13:0] mean [2:0][3:0];
always @ (posedge clk)
  if (mpp_ctrl_valid)
    for (c = 0; c < 3; c = c + 1)
      for (sb = 0; sb < 4; sb = sb + 1) begin
        if (sos_streched) // First block of slice 
          if ((chroma_format != 2'd0) & (c > 0) & (sb >= numSubBlocksChroma))
            mean[c][sb] <= 14'd0;
          else
            mean[c][sb] <= middle[c][sb];
        else if (fbls) // Use left reconstructed pixels (see page 126 of spec)
          if ((chroma_format != 2'd0) & (c > 0) & (sb >= numSubBlocksChroma))
            mean[c][sb] <= 14'd0;
          else if ((chroma_format == 2'd2) & (c > 0)) // 4:2:0 average of only two pixels of row 0
            mean[c][sb] <= (pReconLeftBlk_converted[c][0][sb<<1] + pReconLeftBlk_converted[c][0][(sb<<1)+1]) >>> 1;
          else// Average over all pixels of sub block
            mean[c][sb] <= sumReconLeftBlk[c][sb] >>> 2; 
        else begin // Use above reconstructed pixels (see page 126 of spec)
          if ((chroma_format != 2'd0) & (c > 0) & (sb >= numSubBlocksChroma))
            mean[c][sb] <= 14'd0;
          else if (chroma_format != 2'd0)
            mean[c][sb] <= (pReconAboveBlk[c][sb<<1] + pReconAboveBlk[c][(sb<<1)+1]) >>> 1 ;
          else
            mean[c][sb] <= (pReconAboveBlk_converted[c][sb<<1] + pReconAboveBlk_converted[c][(sb<<1)+1]) >>> 1 ;
        end
      end
      
// If current block CSC is RGB, convert mean to YCoCg
genvar sbi;
wire [13:0] mean_ycocg [2:0][3:0];
generate
  for (sbi=0; sbi<4; sbi=sbi+1) begin : gen_mean_ycocg_sb
    rgb2ycocg rgb2ycocg_u
      (
        .src_r            (mean[0][sbi][11:0]),
        .src_g            (mean[1][sbi][11:0]),
        .src_b            (mean[2][sbi][11:0]),
        .dst_y            (mean_ycocg[0][sbi]),
        .dst_co           (mean_ycocg[1][sbi]),
        .dst_cg           (mean_ycocg[2][sbi])
      );
  end
endgenerate

reg signed [13:0] mean_converted [2:0][3:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (sb = 0; sb < 4; sb = sb + 1)
      mean_converted[c][sb] = ((blockCsc_dl == 2'd1) & ~fbls) ? $signed(mean_ycocg[c][sb]) : mean[c][sb];

reg signed [15:0] curBias [2:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    curBias[c] = (stepSize[c] == 4'd0) ? 16'sd0 : 16'sd1 << (stepSize[c] - 1'b1);
    
reg [3:0] stepSize_dl [2:0];
always @ (posedge clk)
  if (mpp_ctrl_valid)
    for (c = 0; c < 3; c = c + 1)
      stepSize_dl[c] <= stepSize[c];
    
reg signed [13:0] maxClip [2:0][3:0];
always @ (posedge clk)
  if (mpp_ctrl_valid)
    for (c = 0; c < 3; c = c + 1)
      for (sb = 0; sb < 4; sb = sb + 1)
        maxClip[c][sb] <= min({1'b0, maxPoint}, middle[c][sb] + (curBias[c]<<1));
      
reg signed [15:0] curBias_dl [2:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    curBias_dl[c] = (stepSize_dl[c] == 4'd0) ? 16'sd0 : 16'sd1 << (stepSize_dl[c] - 1'b1);
    
reg signed [13:0] middle_dl [2:0][3:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (sb = 0; sb < 4; sb = sb + 1)
      middle_dl[c][sb] = ((blockCsc_dl == 2'd1) & (c > 0)) ? 14'sd0 : $signed({1'b0, midPoint});


// Midpoint      
reg signed [13:0] midpoint [2:0][3:0];
always @ (posedge clk)
  if (mpp_ctrl_valid_dl[0])
    for (c = 0; c < 3; c = c + 1)
      for (sb = 0; sb < 4; sb = sb + 1)
        midpoint[c][sb] <= clip3(middle_dl[c][sb], maxClip[c][sb], mean_converted[c][sb] + (curBias_dl[c]<<1));

// Reconstruct
reg signed [15:0] pDequant [2:0][1:0][7:0];
always @ (posedge clk)
  if (mpp_ctrl_valid_dl[0])
    for (c = 0; c < 3; c = c + 1)
      for (row = 0; row < 2; row = row + 1)
        if (row < blkHeight[c]) begin
          for (col = 0; col < 8; col = col + 1)
            if (col < blkWidth[c]) begin
              if ((chroma_format == 2'd0) | (c == 0))
                pDequant[c][row][col] <= pQuant[c][row*8+col] << stepSize_dl[c];
              else
                pDequant[c][row][col] <= pQuant[c][row*4+col] << stepSize_dl[c];
            end
        end
          
reg signed [13:0] clipMin [2:0];
always @ (posedge clk)
  if (mpp_ctrl_valid_dl[0])
    for (c = 0; c < 3; c = c + 1)
      case (bits_per_component_coded)
        2'd0: clipMin[c] <= ((blockCsc_dl == 2'd1) & (c > 0)) ? -14'sd256  : 14'sd0;
        2'd1: clipMin[c] <= ((blockCsc_dl == 2'd1) & (c > 0)) ? -14'sd1024 : 14'sd0;
        2'd2: clipMin[c] <= ((blockCsc_dl == 2'd1) & (c > 0)) ? -14'sd4096 : 14'sd0;
        default: clipMin[c] <= ((blockCsc_dl == 2'd1) & (c > 0)) ? -14'sd256  : 14'sd0;
      endcase
      
reg signed [13:0] pReconBlk [2:0][1:0][7:0];
always @ (posedge clk)
  if (mpp_ctrl_valid_dl[1])
    for (c = 0; c < 3; c = c + 1)
      for (row = 0; row < 2; row = row + 1)
        if (row < blkHeight[c]) begin
          for (col = 0; col < 8; col = col + 1)
            if (col < blkWidth[c]) begin
              if ((chroma_format == 2'd0) | (c == 0)) begin
                //$display("midpoint[%0d][%0d] = %d     pDequant[%0d][%0d][%0d] = %d", c, col>>1, midpoint[c][col>>1], c, row, col, pDequant[c][row][col]);
                pReconBlk[c][row][col] <= clip3(clipMin[c], {1'b0, maxPoint}, midpoint[c][col>>1] + pDequant[c][row][col]);
              end
              else begin
                //$display("midpoint[%0d][%0d] = %d     pDequant[%0d][%0d][%0d] = %d", c, col>>(blockMode_dl == MODE_MPPF), midpoint[c][col>>(blockMode_dl == MODE_MPPF)], c, row, col, pDequant[c][row][col]);
                if (blockMode_dl == MODE_MPPF)
                  pReconBlk[c][row][col] <= clip3(clipMin[c], {1'b0, maxPoint}, midpoint[c][col>>1] + pDequant[c][row][col]);
                else
                  pReconBlk[c][row][col] <= clip3(clipMin[c], {1'b0, maxPoint}, midpoint[c][col&2'b11] + pDequant[c][row][col]);
              end
            end
        end
        
reg signed [14:0] Co;
reg signed [14:0] Cg;
reg signed [14:0] tmp;
reg signed [13:0] pReconBlk_colorConverted [2:0][1:0][7:0];
always @ (*)
  for (row = 0; row < 2; row = row + 1)
    for (col = 0; col < 8; col = col + 1) begin
      Co = pReconBlk[0][row][col] - pReconBlk[2][row][col];
      tmp = pReconBlk[2][row][col] + (Co >>> 1);
      Cg = pReconBlk[1][row][col] - tmp;
      pReconBlk_colorConverted[0][row][col] = tmp + (Cg >>> 1);
      pReconBlk_colorConverted[1][row][col] = Co;
      pReconBlk_colorConverted[2][row][col] = Cg;
    end
  
reg signed [13:0] pReconBlk_colorConverted_r [2:0][1:0][7:0];
always @ (posedge clk)
  if (mpp_ctrl_valid_dl[2])
    for (c = 0; c < 3; c = c + 1)
      for (row = 0; row < 2; row = row + 1)
        for (col = 0; col < 8; col = col + 1)
          if (blockCsc_dl == 2'd0) // RGB -> convert to YCoCg
            pReconBlk_colorConverted_r[c][row][col] <= pReconBlk_colorConverted[c][row][col];
          else
            pReconBlk_colorConverted_r[c][row][col] <= pReconBlk[c][row][col];

// Pack output
generate
  for (ci=0; ci<3; ci=ci+1) begin : gen_out_comp
    for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_out_rowi
      for (coli=0; coli<8; coli=coli+1) begin : gen_out_coli
        assign pReconBlk_p[(ci*8*2+rowi*8+coli)*14+:14] = pReconBlk_colorConverted_r[ci][rowi][coli];
      end
    end
  end
endgenerate

assign pReconBlk_valid = mpp_ctrl_valid_dl[3];


endmodule
