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

module ssmFunnelShifter
#(
  parameter MAX_FUNNEL_SHIFTER_SIZE = 2*248 - 1
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [7:0] ssm_max_se_size,
  
  input wire en_funnel_shifter,
  // Interface to RC
  output wire mux_word_request,
  input wire mux_word_valid,
  input wire [255:0] mux_word,
  // Interface to Parser
  output reg [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed,
  output reg ready,
  input wire [8:0] size_to_remove,
  input wire size_to_remove_valid

);

reg [8:0] fullness;
reg [8:0] fullness_r;
always @ (*)
  if (flush)
    fullness = 9'd0;
  else if (en_funnel_shifter)
    if (mux_word_valid & (fullness_r < MAX_FUNNEL_SHIFTER_SIZE - 9'd128) & ~size_to_remove_valid) // Push
      fullness = fullness_r + ssm_max_se_size;
    else if (~mux_word_valid & size_to_remove_valid) // Pull
      fullness = fullness_r - size_to_remove;
    else if (mux_word_valid & (fullness_r < MAX_FUNNEL_SHIFTER_SIZE - 9'd128) & size_to_remove_valid) // Push and pull
      fullness = fullness_r + ssm_max_se_size - size_to_remove;
    else
      fullness = fullness_r;
  else
    fullness = fullness_r;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fullness_r <= 9'd0;
  else if (flush)
    fullness_r <= 9'd0;
  else
    fullness_r <= fullness;

assign mux_word_request = en_funnel_shifter & (fullness < ssm_max_se_size) & ~flush;
always @ (posedge clk)
  ready <= (fullness_r >= ssm_max_se_size);

integer i;
reg [MAX_FUNNEL_SHIFTER_SIZE-1:0] bit_shifter;
always @ (posedge clk)
  if (mux_word_valid)
    for (i=0; i<MAX_FUNNEL_SHIFTER_SIZE; i=i+1)
      if (i<ssm_max_se_size)
        bit_shifter[i] <= mux_word[i];
      else
        bit_shifter[i] <= bit_shifter[i-ssm_max_se_size];

reg flush_dl;
always @ (posedge clk)
  flush_dl <= flush;

reg [1:0] mux_word_valid_dl;        
always @ (posedge clk)
  if ((mux_word_valid_dl[0] | size_to_remove_valid) & ~(flush | flush_dl)) // leave data inside for the last block of slice - so do not flush
    for (i=0; i<MAX_FUNNEL_SHIFTER_SIZE; i=i+1)
      if (i<fullness)
        data_to_be_parsed[i] <= bit_shifter[fullness-i-1];
      else
        data_to_be_parsed[i] <= 1'bx;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    mux_word_valid_dl <= 2'b0;
  else
    mux_word_valid_dl <= {mux_word_valid_dl[0], mux_word_valid};

endmodule
