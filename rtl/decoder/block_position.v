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

module block_position
#(
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_SLICE_HEIGHT        = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height,
  input wire [15:0] frame_height,
  
  input wire start_decode, // the first block of the slice
  input wire in_sof,
  input wire in_valid,
  input wire parse_substreams,
  input wire substream0_parsed,
  input wire substreams123_parsed,
  output wire sof,
  output reg soc,
  output reg eoc,
  output reg sos,
  output reg eos,
  output reg early_eos, // pulse once cycle before eos
  output reg eof, // end of frame (before vertical padding)
  output reg eob,
  output reg fbls,
  output reg isFirstParse, // Parse Subsstream 0 one block-time ahead of other subsreams
  output reg isFirstBlock, // First time in slice substreams 1 2 3 are parsed (one block-time after isFirstParse)
  output reg isLastBlock,  // Last time in slice substreams 1 2 3 are parsed 
  output reg nextBlockIsFls,
  output wire neighborsAbove_rd_en,
  output wire block_push,
  output reg resetLeft, // blockPosX == 0
  output wire isEvenChunk // blockPosY[0] == 0
);

reg sticky_in_sof;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sticky_in_sof <= 1'b0;
  else if (flush | start_decode)
    sticky_in_sof <= 1'b0;
  else if (in_sof & in_valid)
    sticky_in_sof <= 1'b1;
assign sof = sticky_in_sof & start_decode; // first start_decode of frame
    

wire [$clog2(MAX_SLICE_WIDTH)-3-1:0] numBlksX;
assign numBlksX = slice_width >> 3;
wire [$clog2(MAX_SLICE_HEIGHT)-3-1:0] numBlksY;
assign numBlksY = slice_height >> 1;

reg [1:0] quad_pix_cnt; // increment by one each 4 pixels (of luma)
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    quad_pix_cnt <= 2'd0;
  else if (flush | sof)
    quad_pix_cnt <= 2'd0;
  else if (start_decode)
    quad_pix_cnt <= 2'd0;
  else
    quad_pix_cnt <= quad_pix_cnt + 1'b1;
  
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eob <= 1'b0;
  else if (flush | sof)
    eob <= 1'b0;
  else if (quad_pix_cnt == 2'd2)
    eob <= 1'b1;
  else
    eob <= 1'b0;
    
reg [2:0] substream0_parsed_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    substream0_parsed_dl <= 3'b0;
  else if (flush | sof)
    substream0_parsed_dl <= 3'b0;
  else
    substream0_parsed_dl <= {substream0_parsed_dl[1:0], substream0_parsed};
    
reg [$clog2(MAX_SLICE_WIDTH)-1:0] blockPosX;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (flush | sof)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (start_decode)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (substreams123_parsed)
    if (blockPosX == numBlksX - 1'b1)
      blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
    else
      blockPosX <= blockPosX + 1'b1;

reg [$clog2(MAX_SLICE_HEIGHT)-1:0] blockPosY;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (flush | sof)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (start_decode)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (substreams123_parsed & (blockPosX == numBlksX - 1'b1))
    if (blockPosY == numBlksY - 1'b1)
      blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
    else
      blockPosY <= blockPosY + 1'b1;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eoc <= 1'b0;
  else if (flush | sof)
    eoc <= 1'b0;
  else if (substreams123_parsed)
    if (blockPosX == numBlksX - 2'd2)
      eoc <= 1'b1;
    else
      eoc <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    soc <= 1'b0;
  else if (flush | sof)
    soc <= 1'b0;
  else if (substreams123_parsed)
    if (blockPosX == numBlksX - 1'b1)
      soc <= 1'b1;
	  else
	    soc <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    nextBlockIsFls <= 1'b1;
  else if (flush | sof)
    nextBlockIsFls <= 1'b1;
  else if (start_decode)
    nextBlockIsFls <= 1'b1;
  else if (substreams123_parsed)
    if ((blockPosX == numBlksX - 1'b1) & (blockPosY == numBlksY - 1'b1))
      nextBlockIsFls <= 1'b1;
    else if ((blockPosX == numBlksX - 2'd2) & (blockPosY == {MAX_SLICE_HEIGHT{1'b0}}))
      nextBlockIsFls <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isFirstBlock <= 1'b0;
  else if (flush | sof)
    isFirstBlock <= 1'b0;
  else if (start_decode | (substream0_parsed & isFirstBlock))
    isFirstBlock <= 1'b0;
  else if (substream0_parsed & isFirstParse)
    isFirstBlock <= 1'b1;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isLastBlock <= 1'b0;
  else if (flush | sof)
    isLastBlock <= 1'b0;
  else if (start_decode | ((quad_pix_cnt == 2'd2) & isLastBlock))
    isLastBlock <= 1'b0;
  else if (substreams123_parsed & (blockPosX == numBlksX - 2'd2) & (blockPosY == numBlksY - 1'b1))
    isLastBlock <= 1'b1;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isFirstParse <= 1'b0;
  else if (flush | in_sof)
    isFirstParse <= 1'b0;
  else if (start_decode)
    isFirstParse <= 1'b1;
  else if (substream0_parsed | substreams123_parsed)
    if ((blockPosX == numBlksX - 1'b1) & (blockPosY == numBlksY - 1'b1))
      isFirstParse <= 1'b1;
    else
      isFirstParse <= 1'b0;

assign isEvenChunk = ~blockPosY[0];

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos <= 1'b0;
  else if (flush | sof)
    sos <= 1'b0;
  else if (substream0_parsed & isFirstParse)
    sos <= 1'b1;
  else if (eob)
    sos <= 1'b0;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eos <= 1'b0;
  else if (flush | sof)
    eos <= 1'b0;
  else if (eob & isLastBlock)
    eos <= 1'b1;
  else if (eob)
    eos <= 1'b0;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    early_eos <= 1'b0;
  else if (flush | sof)
    early_eos <= 1'b0;
  else if (isLastBlock & (quad_pix_cnt == 2'd2))
    early_eos <= 1'b1;
  else
    early_eos <= 1'b0;
    
reg [15:0] line_cnt_until_end_of_frame;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    line_cnt_until_end_of_frame <= 16'b0;
  else if (flush | sof)
    line_cnt_until_end_of_frame <= 16'b0;
  else if (substream0_parsed & (blockPosX == numBlksX - 2'd2))
    line_cnt_until_end_of_frame <= line_cnt_until_end_of_frame + 2'd2;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eof <= 1'b0;
  else if (flush | sof)
    eof <= 1'b0;
  else if (line_cnt_until_end_of_frame >= frame_height)
    eof <= 1'b1;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fbls <= 1'b1;
  else if (flush | isFirstParse)
    fbls <= 1'b1;
  else if (substream0_parsed & (blockPosX == numBlksX - 1'b1))
    fbls <= 1'b0;

  
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    resetLeft <= 1'b1;
  else if (flush)
    resetLeft <= 1'b1;
  else if (start_decode)
    resetLeft <= 1'b1;
  else if (substream0_parsed)
    if (blockPosX == numBlksX - 1'b1)
      resetLeft <= 1'b1;
    else
      resetLeft <= 1'b0;
      
reg enable_above_rd_request;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    enable_above_rd_request <= 1'b0;
  else if (flush)
    enable_above_rd_request <= 1'b0;
  else if (start_decode)
    enable_above_rd_request <= 1'b0;
  else if (early_eos)
    enable_above_rd_request <= 1'b0;
  else if (substreams123_parsed & (blockPosX == numBlksX - 3'd5) & (blockPosY == {MAX_SLICE_HEIGHT{1'b0}}))
    enable_above_rd_request <= 1'b1;
  
assign neighborsAbove_rd_en = enable_above_rd_request & substream0_parsed_dl[2];

assign block_push = (blockPosX <= numBlksX - 3'd4) & (blockPosY == {MAX_SLICE_HEIGHT{1'b0}});
  
endmodule
