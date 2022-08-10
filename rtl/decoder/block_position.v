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
  
  input wire start_decode, // the first block of the frame
  input wire header_parsed,
  output reg eoc,
  output reg sos,
  output reg eos,
  output reg early_eos, // pulse once cycle before eos
  output reg eof, // end of frame (before vertical padding)
  output reg sob,
  output reg eob,
  output reg fbls,
  output reg isLastBlock,
  output reg isFirstBlock,
  output reg nextBlockIsFls,
  output reg enable_above_rd,
  output reg resetLeft, // blockPosX == 0
  output wire isEvenChunk // blockPosY[0] == 0
);

wire [$clog2(MAX_SLICE_WIDTH)-3-1:0] numBlksX;
assign numBlksX = slice_width >> 3;
wire [$clog2(MAX_SLICE_HEIGHT)-3-1:0] numBlksY;
assign numBlksY = slice_height >> 1;

reg [1:0] quad_pix_cnt; // increment by one each 4 pixels (of luma)
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    quad_pix_cnt <= 2'd0;
  else if (flush)
    quad_pix_cnt <= 2'd0;
  else if (start_decode)
    quad_pix_cnt <= 2'd0;
  else
    quad_pix_cnt <= quad_pix_cnt + 1'b1;
  
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eob <= 1'b0;
  else if (flush)
    eob <= 1'b0;
  else if (quad_pix_cnt == 2'd2)
    eob <= 1'b1;
  else
    eob <= 1'b0;
    

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sob <= 1'b1;
  else if (flush)
    sob <= 1'b1;
  else if (quad_pix_cnt == 2'd3)
    sob <= 1'b1;
  else
    sob <= 1'b0;
	    
reg [$clog2(MAX_SLICE_WIDTH)-1:0] blockPosX;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (flush)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (start_decode)
    blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
  else if (header_parsed)
    if (blockPosX == numBlksX - 1'b1)
      blockPosX <= {MAX_SLICE_WIDTH{1'b0}};
    else
      blockPosX <= blockPosX + 1'b1;

reg [$clog2(MAX_SLICE_HEIGHT)-1:0] blockPosY;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (flush)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (start_decode)
    blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
  else if (header_parsed & (blockPosX == numBlksX - 1'b1))
    if (blockPosY == numBlksY - 1'b1)
      blockPosY <= {MAX_SLICE_HEIGHT{1'b0}};
    else
      blockPosY <= blockPosY + 1'b1;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eoc <= 1'b0;
  else if (flush)
    eoc <= 1'b0;
  else if (header_parsed)
    if (blockPosX == numBlksX - 1'b1)
      eoc <= 1'b1;
    else
      eoc <= 1'b0;
      
reg soc;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    soc <= 1'b0;
  else if (flush)
    soc <= 1'b0;
  else if (header_parsed)
    if (~(|blockPosX)) // == 0
      soc <= 1'b1;
	else
	  soc <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    nextBlockIsFls <= 1'b1;
  else if (flush)
    nextBlockIsFls <= 1'b1;
  else if (start_decode)
    nextBlockIsFls <= 1'b1;
  else if (header_parsed)
    if ((blockPosX == numBlksX - 1'b1) & (blockPosY == numBlksY - 1'b1))
      nextBlockIsFls <= 1'b1;
    else if ((blockPosX == numBlksX - 2'd2) & (blockPosY == {MAX_SLICE_HEIGHT{1'b0}}))
      nextBlockIsFls <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isLastBlock <= 1'b0;
  else if (flush)
    isLastBlock <= 1'b0;
  else if (start_decode)
    isLastBlock <= 1'b0;
  else if (header_parsed)
    if ((blockPosX == numBlksX - 2'd2) & (blockPosY == numBlksY - 1'b1))
      isLastBlock <= 1'b1;
    else
      isLastBlock <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isFirstBlock <= 1'b0;
  else if (flush)
    isFirstBlock <= 1'b0;
  else if (start_decode)
    isFirstBlock <= 1'b0;
  else if (header_parsed)
    if ((blockPosX == numBlksX - 1'b1) & (blockPosY == numBlksY - 1'b1))
      isFirstBlock <= 1'b1;
    else
      isFirstBlock <= 1'b0;

  
assign isEvenChunk = ~blockPosY[0];

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos <= 1'b0;
  else if (header_parsed &  (~(|blockPosX)) & (~(|blockPosY)))
    sos <= 1'b1;
  else if (eob)
    sos <= 1'b0;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eos <= 1'b0;
  else if (eob & isLastBlock)
    eos <= 1'b1;
  else if (eob)
    eos <= 1'b0;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    early_eos <= 1'b0;
  else if (isLastBlock & (quad_pix_cnt == 2'd2))
    early_eos <= 1'b1;
  else
    early_eos <= 1'b0;
    
reg [15:0] line_cnt_until_end_of_frame;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    line_cnt_until_end_of_frame <= 16'b0;
  else if (flush | start_decode)
    line_cnt_until_end_of_frame <= 16'b0;
  else if (header_parsed & (blockPosX == numBlksX - 2'd2))
    line_cnt_until_end_of_frame <= line_cnt_until_end_of_frame + 2'd2;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eof <= 1'b0;
  else if (flush | start_decode)
    eof <= 1'b0;
  else if (line_cnt_until_end_of_frame == frame_height)
    eof <= 1'b1;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fbls <= 1'b1;
  else if (flush)
    fbls <= 1'b1;
  else if (header_parsed)
    if ((blockPosX == numBlksX - 1'b1) & (blockPosY == numBlksY - 1'b1))
      fbls <= 1'b1;
    else if (blockPosX == numBlksX - 1'b1)
      fbls <= 1'b0;

  
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    resetLeft <= 1'b1;
  else if (flush)
    resetLeft <= 1'b1;
  else if (start_decode)
    resetLeft <= 1'b1;
  else if (header_parsed)
    if (blockPosX == numBlksX - 1'b1)
      resetLeft <= 1'b1;
    else
      resetLeft <= 1'b0;
      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    enable_above_rd <= 1'b0;
  else if (flush)
    enable_above_rd <= 1'b0;
  else if (start_decode)
    enable_above_rd <= 1'b0;
  else if (early_eos)
    enable_above_rd <= 1'b0;
  else if (header_parsed & (blockPosX == numBlksX - 3'd4))
    enable_above_rd <= 1'b1;
  
  
endmodule
