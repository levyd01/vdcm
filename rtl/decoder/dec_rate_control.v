
`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module dec_rate_control
#(
  parameter MAX_SLICE_HEIGHT        = 2560,
  parameter MAX_SLICE_WIDTH         = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire sof,
  input wire sos,
  input wire eoc,
  input wire isLastBlock,
  input wire fbls,
  input wire isEvenChunk,
  input wire sos_for_rc,
  input wire [1:0] sos_fsm,
  
  input wire [15:0] rc_buffer_max_size,
  input wire [15:0] chunk_size,
  input wire [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height,
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] slice_num_px,
  input wire [$clog2(MAX_SLICE_HEIGHT)+16-1:0] b0,
  input wire [15:0] num_extra_mux_bits,
  input wire [31:0] rc_target_rate_threshold,
  input wire [7:0] rc_target_rate_scale,
  input wire [3:0] rc_target_rate_extra_fbls,
  input wire [7:0] rc_fullness_scale,
  input wire [23:0] rc_fullness_offset_slope,
  input wire [7:0] rc_init_tx_delay,
  input wire [8+9-1:0] rcOffsetInitAtSos,
  input wire [16*8-1:0] target_rate_delta_lut_p,
  input wire [3:0] chunk_adj_bits,
  input wire [3:0] maxAdjBits,
  input wire [9:0] bits_per_pixel,
  input wire isSliceWidthMultipleOf16,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [8*8-1:0] max_qp_lut_p,
  input wire signed [5:0] minQp,
  input wire [15:0] rc_buffer_init_size,
  input wire [7:0] flatness_qp_very_flat_fbls,
  input wire [7:0] flatness_qp_very_flat_nfbls,
  input wire [7:0] flatness_qp_somewhat_flat_fbls,
  input wire [7:0] flatness_qp_somewhat_flat_nfbls,
  input wire [8*8-1:0] flatness_qp_lut_p,
  input wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] rcOffsetThreshold,
  
  input wire flatnessFlag,
  input wire [1:0] flatnessType, // 0: very flat; 1: somewhat flat; 2: complex to flat; 3: flat to complex
  
  input wire [12:0] blockBits,
  input wire blockBits_valid,
  input wire [12:0] prevBlockBitsWithoutPadding,
  input wire prevBlockBitsWithoutPadding_valid,

  
  output reg [6:0] qp,
  output wire qp_valid,
  output reg [8:0] maxQp,
  output reg enableUnderflowPrevention
);

// Constant look up tables
wire [6:0] qpIndexThresholdPositive [0:2][0:4];
assign qpIndexThresholdPositive[0][0] = 7'd10;
assign qpIndexThresholdPositive[0][1] = 7'd29;
assign qpIndexThresholdPositive[0][2] = 7'd50;
assign qpIndexThresholdPositive[0][3] = 7'd60;
assign qpIndexThresholdPositive[0][4] = 7'd70;
assign qpIndexThresholdPositive[1][0] = 7'd9;
assign qpIndexThresholdPositive[1][1] = 7'd26;
assign qpIndexThresholdPositive[1][2] = 7'd45;
assign qpIndexThresholdPositive[1][3] = 7'd54;
assign qpIndexThresholdPositive[1][4] = 7'd63;
assign qpIndexThresholdPositive[2][0] = 7'd8;
assign qpIndexThresholdPositive[2][1] = 7'd23;
assign qpIndexThresholdPositive[2][2] = 7'd40;
assign qpIndexThresholdPositive[2][3] = 7'd48;
assign qpIndexThresholdPositive[2][4] = 7'd55;
wire [6:0] qpIndexThresholdNegative [0:2][0:3];
assign qpIndexThresholdNegative[0][0] = 7'd10;
assign qpIndexThresholdNegative[0][1] = 7'd20;
assign qpIndexThresholdNegative[0][2] = 7'd35;
assign qpIndexThresholdNegative[0][3] = 7'd65;
assign qpIndexThresholdNegative[1][0] = 7'd9;
assign qpIndexThresholdNegative[1][1] = 7'd18;
assign qpIndexThresholdNegative[1][2] = 7'd31;
assign qpIndexThresholdNegative[1][3] = 7'd58;
assign qpIndexThresholdNegative[2][0] = 7'd8;
assign qpIndexThresholdNegative[2][1] = 7'd16;
assign qpIndexThresholdNegative[2][2] = 7'd28;
assign qpIndexThresholdNegative[2][3] = 7'd51;

wire signed [3:0] QpIncrementTable [0:4][0:5];
assign QpIncrementTable[0][0] = 4'sd0;
assign QpIncrementTable[0][1] = 4'sd1;
assign QpIncrementTable[0][2] = 4'sd2;
assign QpIncrementTable[0][3] = 4'sd3;
assign QpIncrementTable[0][4] = 4'sd4;
assign QpIncrementTable[0][5] = 4'sd5;
assign QpIncrementTable[1][0] = 4'sd1;
assign QpIncrementTable[1][1] = 4'sd2;
assign QpIncrementTable[1][2] = 4'sd3;
assign QpIncrementTable[1][3] = 4'sd5;
assign QpIncrementTable[1][4] = 4'sd5;
assign QpIncrementTable[1][5] = 4'sd6;
assign QpIncrementTable[2][0] = 4'sd2;
assign QpIncrementTable[2][1] = 4'sd3;
assign QpIncrementTable[2][2] = 4'sd4;
assign QpIncrementTable[2][3] = 4'sd6;
assign QpIncrementTable[2][4] = 4'sd6;
assign QpIncrementTable[2][5] = 4'sd7;
assign QpIncrementTable[3][0] = -4'sd1;
assign QpIncrementTable[3][1] = 4'sd0;
assign QpIncrementTable[3][2] = 4'sd1;
assign QpIncrementTable[3][3] = 4'sd1;
assign QpIncrementTable[3][4] = 4'sd2;
assign QpIncrementTable[3][5] = 4'sd2;
assign QpIncrementTable[4][0] = -4'sd2;
assign QpIncrementTable[4][1] = -4'sd1;
assign QpIncrementTable[4][2] = -4'sd1;
assign QpIncrementTable[4][3] = 4'sd0;
assign QpIncrementTable[4][4] = 4'sd1;
assign QpIncrementTable[4][5] = 4'sd1;
wire signed [3:0] QpDecrementTable [0:4][0:4];
assign QpDecrementTable[0][0] = 4'sd0;
assign QpDecrementTable[0][1] = 4'sd1;
assign QpDecrementTable[0][2] = 4'sd2;
assign QpDecrementTable[0][3] = 4'sd3;
assign QpDecrementTable[0][4] = 4'sd4;
assign QpDecrementTable[1][0] = -4'sd1;
assign QpDecrementTable[1][1] = 4'sd0;
assign QpDecrementTable[1][2] = 4'sd0;
assign QpDecrementTable[1][3] = 4'sd1;
assign QpDecrementTable[1][4] = 4'sd1;
assign QpDecrementTable[2][0] = -4'sd2;
assign QpDecrementTable[2][1] = -4'sd2;
assign QpDecrementTable[2][2] = 4'sd0;
assign QpDecrementTable[2][3] = 4'sd1;
assign QpDecrementTable[2][4] = 4'sd1;
assign QpDecrementTable[3][0] = 4'sd1;
assign QpDecrementTable[3][1] = 4'sd1;
assign QpDecrementTable[3][2] = 4'sd2;
assign QpDecrementTable[3][3] = 4'sd4;
assign QpDecrementTable[3][4] = 4'sd4;
assign QpDecrementTable[4][0] = 4'sd2;
assign QpDecrementTable[4][1] = 4'sd2;
assign QpDecrementTable[4][2] = 4'sd4;
assign QpDecrementTable[4][3] = 4'sd5;
assign QpDecrementTable[4][4] = 4'sd5;


// unpack inputs
wire [7:0] target_rate_delta_lut [15:0];
wire [7:0] max_qp_lut [7:0];
wire [7:0] flatness_qp_lut [7:0];
genvar gi;
generate
  for (gi = 0; gi < 16 ; gi = gi + 1) begin : gen_target_rate_delta_lut
    assign target_rate_delta_lut[gi] = target_rate_delta_lut_p[gi*8+:8];
  end
  for (gi = 0; gi < 8 ; gi = gi + 1) begin : gen_max_qp_lut
    assign max_qp_lut[gi] = max_qp_lut_p[gi*8+:8];
    assign flatness_qp_lut[gi] = flatness_qp_lut_p[gi*8+:8];
  end
endgenerate

reg [6:0] blockBits_valid_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    blockBits_valid_dl <= 7'b0;
  else
    blockBits_valid_dl <= {blockBits_valid_dl[5:0], blockBits_valid};
	
reg isLastBlock_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    isLastBlock_dl <= 1'b0;
  else if (blockBits_valid)
    isLastBlock_dl <= isLastBlock;
    
reg fbls_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fbls_dl <= 1'b1;
  else if (blockBits_valid)
    fbls_dl <= fbls;
    
reg [3:0] sos_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos_dl <= 4'b0;
  else
    sos_dl <= {sos_dl[2:0], sos};
    
wire sos_pulse;
assign sos_pulse = sos & ~sos_dl[0];
wire [2:0] sos_pulse_dl;
assign sos_pulse_dl = {sos_dl[2] & ~sos_dl[3], sos_dl[1] & ~sos_dl[2], sos_dl[0] & ~sos_dl[1]};

    
reg [$clog2(MAX_SLICE_HEIGHT)+16-1:0] sliceBitsRemaining;
always @ (posedge clk)
  if (sof | (blockBits_valid & isLastBlock_dl))
    sliceBitsRemaining <= b0 - num_extra_mux_bits;
  else if (blockBits_valid)
    sliceBitsRemaining <= sliceBitsRemaining - blockBits;

reg signed [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT):0] slicePixelsRemaining;
always @ (posedge clk)
  if (sof | (blockBits_valid & isLastBlock_dl))
    slicePixelsRemaining <= $signed({1'b0, slice_num_px});
  else if (blockBits_valid)
    slicePixelsRemaining <= slicePixelsRemaining - 6'sd16;

parameter rcFullnessScaleApproxBits = 4; // Defined in Table 4-12 in spec. Called g_rc_BFScaleApprox in C model
wire [8+8+9-3-1:0] rcFullnessInit;
assign rcFullnessInit = (rc_fullness_scale * rcOffsetInitAtSos) >> rcFullnessScaleApproxBits;
parameter [4:0] rcFullnessRangeBits = 5'd16; // Defined in Table 4-12 in spec. Called g_rc_BFRangeBits in C model
reg [15:0] rcFullness;
  
reg [9:0] prevBlockBits;
always @ (posedge clk)
  if (sos)
    prevBlockBits <= 10'd0;
  else if (blockBits_valid)
    prevBlockBits <= blockBits;

reg [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] numBlocksCoded;
always @ (posedge clk)
  if (sos_pulse)
    numBlocksCoded <= 13'd0;
  else if (blockBits_valid)
    numBlocksCoded <= numBlocksCoded + 1'b1;
    
reg [$clog2((MAX_SLICE_WIDTH>>4)+1)-1:0] numChunkBlks;
always @ (posedge clk)
  if (numBlocksCoded + 1'b1 <= rc_init_tx_delay)
    numChunkBlks <= {$clog2((MAX_SLICE_WIDTH>>4)+1){1'b0}};
  // else TBD


// chunk byte-alignment adjustment bits TBD
  // if (numChunkBlks >= slice_width) TBD
reg [7:0] chunkAdjBits = 0;

reg [15:0] bufferFullness_i;
reg [15:0] bufferFullness_r;
always @ (*) begin
  if (numBlocksCoded + 1'b1 <= rc_init_tx_delay) //if (m_numPixelsCoded <= 16 * m_initTxDelay)
    bufferFullness_i = bufferFullness_r + blockBits;
  else
    bufferFullness_i = bufferFullness_r + blockBits - bits_per_pixel - chunkAdjBits;
end

always @ (posedge clk)
  if (sos_pulse)
    bufferFullness_r <= 16'd0;
  else if (blockBits_valid)
    bufferFullness_r <= bufferFullness_i;
	
// Check overflow or underflow of bufferFullness_r
reg bufferFullnessOverflow;
reg bufferFullnessUnderflow;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    bufferFullnessOverflow <= 1'b0;
	bufferFullnessUnderflow <= 1'b0;
  end
  else begin
    if (bufferFullness_r[15]) // It means that there was a wrap around
	  bufferFullnessUnderflow <= 1'b1;
	if (bufferFullness_r > rc_buffer_max_size)
	  bufferFullnessOverflow <= 1'b1;
  end

// UpdateRcOffsets
// update rcOffsetInit
reg signed [15:0] rcOffsetInit;
always @ (posedge clk)
  if (sos_pulse)
    rcOffsetInit <= rcOffsetInitAtSos;
  else if (blockBits_valid & (numBlocksCoded + 1'b1 <= rc_init_tx_delay))
    rcOffsetInit <= rcOffsetInit - {1'b0, bits_per_pixel};
// update rcOffset
reg signed [15:0] rcOffset;
reg signed [15:0] rcOffset_d;
reg [23:0] slope;
reg [16:0] bufferFracBitsAccum_d;
reg [15:0] bufferFracBitsAccum;
reg [8:0] tmp_offset;
always @ (*) begin
  slope = rc_fullness_offset_slope;
  bufferFracBitsAccum_d = bufferFracBitsAccum + (slope & 16'hFFFF);
  tmp_offset = (slope >> 16) + (bufferFracBitsAccum_d >> 16);
  bufferFracBitsAccum_d = bufferFracBitsAccum_d & 17'h0FFFF;
  // special case for last block in slice
  if (isLastBlock & (bufferFracBitsAccum_d >= (1'b1 << 15)))
    tmp_offset = tmp_offset + 1'b1;
  rcOffset_d = rcOffset + tmp_offset;
end
always @ (posedge clk)
  if (sos) begin
    rcOffset <= 16'sd0;
    bufferFracBitsAccum <= 16'd0;
  end
  else if (blockBits_valid & ~sos & (numBlocksCoded + 1'b1 >= rcOffsetThreshold)) begin
    rcOffset <= rcOffset_d;
    bufferFracBitsAccum <= bufferFracBitsAccum_d[15:0];
  end
  
// unscaled rcFullness = rc_fullness_scale * (bufferFullness_r + rcOffset + rcOffsetInit)
wire signed [1+8+16+1+1-1:0] unscaledRcFullness;
assign unscaledRcFullness = $signed({1'b0, rc_fullness_scale}) * ($signed({1'b0, bufferFullness_r}) + rcOffset + rcOffsetInit);
wire signed [1+8+16+1+1-4-1:0] unscaledRcFullnessShifted;
assign unscaledRcFullnessShifted = unscaledRcFullness >>> 4;

parameter [15:0] max_rcFullness = (1'b1 << 16) - 1'b1;
reg [15:0] rcFullness_d;
always @ (*)
  if (sos_pulse) begin
    if (rcFullnessInit > ((1'b1 << rcFullnessRangeBits) - 1'b1))
      rcFullness_d = (1'b1 << rcFullnessRangeBits) - 1'b1;
    else
      rcFullness_d = rcFullnessInit;
  end
  else if (unscaledRcFullnessShifted > $signed({1'b0, max_rcFullness}))
    rcFullness_d = $signed({1'b0, max_rcFullness});
  else if (unscaledRcFullnessShifted[1+8+16+1+1-4-1])
    rcFullness_d = 16'b0;
  else
    rcFullness_d = unscaledRcFullnessShifted[15:0];
      
always @ (posedge clk)
  if (sos_pulse | blockBits_valid_dl[0])
    rcFullness <= rcFullness_d;    
    
    

// CalcTargetRate
/////////////////
reg [1:0] sof_dl;
always @ (posedge clk)
  sof_dl <= {sof_dl[0], sof};
reg [7:0] targetRateScale;
reg [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] targetRateThreshold;
always @ (posedge clk)
  if (sof | (~blockBits_valid & isLastBlock_dl)) begin
    targetRateScale <= rc_target_rate_scale;
    targetRateThreshold <= rc_target_rate_threshold;
  end
  else if (sof_dl[0] | blockBits_valid)
    if ((slicePixelsRemaining - 6'sd16) < $signed({1'b0, targetRateThreshold})) begin
      targetRateScale <= targetRateScale - 1'b1;
      targetRateThreshold <= 1'b1 << (targetRateScale - 2'd2);
    end

wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] pOffset;
assign pOffset = 1'b1 << (targetRateScale - 1'b1);

parameter [2:0] targetRateBaseBits = 3'd6; // Table 4.17 of spec. Called g_rc_targetRateLutScaleBits in C model
wire  [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)+6-1:0] pTemp;
assign pTemp = slicePixelsRemaining << targetRateBaseBits;

parameter [5:0] pMax = (1'b1 << targetRateBaseBits) - 1'b1;
reg [5:0] p;
reg [$clog2(MAX_SLICE_HEIGHT)+16+8+4-1:0] baseTargetRateTemp;

always @ (*) begin 
  if (((pTemp+pOffset) >> targetRateScale) > pMax)
    p = pMax;
  else
    p = (pTemp+pOffset) >> targetRateScale;
  case (p) // baseTargetRateTemp = (sliceBitsRemaining * targetRateInverseLut[(31-(p-6'd32))*8+:8]) << 4;
    6'd32: baseTargetRateTemp = (sliceBitsRemaining * 8'd126) << 4;
    6'd33: baseTargetRateTemp = (sliceBitsRemaining * 8'd122) << 4;
    6'd34: baseTargetRateTemp = (sliceBitsRemaining * 8'd119) << 4;
    6'd35: baseTargetRateTemp = (sliceBitsRemaining * 8'd115) << 4;
    6'd36: baseTargetRateTemp = (sliceBitsRemaining * 8'd112) << 4;
    6'd37: baseTargetRateTemp = (sliceBitsRemaining * 8'd109) << 4;
    6'd38: baseTargetRateTemp = (sliceBitsRemaining * 8'd106) << 4;
    6'd39: baseTargetRateTemp = (sliceBitsRemaining * 8'd103) << 4;
    6'd40: baseTargetRateTemp = (sliceBitsRemaining * 8'd101) << 4;
    6'd41: baseTargetRateTemp = (sliceBitsRemaining *  8'd98) << 4;
    6'd42: baseTargetRateTemp = (sliceBitsRemaining *  8'd96) << 4;
    6'd43: baseTargetRateTemp = (sliceBitsRemaining *  8'd94) << 4;
    6'd44: baseTargetRateTemp = (sliceBitsRemaining *  8'd92) << 4;
    6'd45: baseTargetRateTemp = (sliceBitsRemaining *  8'd90) << 4;
    6'd46: baseTargetRateTemp = (sliceBitsRemaining *  8'd88) << 4;
    6'd47: baseTargetRateTemp = (sliceBitsRemaining *  8'd86) << 4;
    6'd48: baseTargetRateTemp = (sliceBitsRemaining *  8'd84) << 4;
    6'd49: baseTargetRateTemp = (sliceBitsRemaining *  8'd82) << 4;
    6'd50: baseTargetRateTemp = (sliceBitsRemaining *  8'd81) << 4;
    6'd51: baseTargetRateTemp = (sliceBitsRemaining *  8'd79) << 4;
    6'd52: baseTargetRateTemp = (sliceBitsRemaining *  8'd78) << 4;
    6'd53: baseTargetRateTemp = (sliceBitsRemaining *  8'd76) << 4;
    6'd54: baseTargetRateTemp = (sliceBitsRemaining *  8'd75) << 4;
    6'd55: baseTargetRateTemp = (sliceBitsRemaining *  8'd73) << 4;
    6'd56: baseTargetRateTemp = (sliceBitsRemaining *  8'd72) << 4;
    6'd57: baseTargetRateTemp = (sliceBitsRemaining *  8'd71) << 4;
    6'd58: baseTargetRateTemp = (sliceBitsRemaining *  8'd70) << 4;
    6'd59: baseTargetRateTemp = (sliceBitsRemaining *  8'd68) << 4;
    6'd60: baseTargetRateTemp = (sliceBitsRemaining *  8'd67) << 4;
    6'd61: baseTargetRateTemp = (sliceBitsRemaining *  8'd66) << 4;
    6'd62: baseTargetRateTemp = (sliceBitsRemaining *  8'd65) << 4;
    6'd63: baseTargetRateTemp = (sliceBitsRemaining *  8'd64) << 4;
  endcase
end

wire [8:0] scale; // Called a in the spec and scale in the C model
assign scale = targetRateScale + targetRateBaseBits;

wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)+6-1:0] offset;
assign offset = 1'b1 << (scale - 1'b1);

reg [14:0] baseTargetRate;

always @ (*)
  if (fbls_dl /*& !(isLastBlock_dl & blockBits_valid_dl[0])*/)
    baseTargetRate = ((baseTargetRateTemp + offset) >> scale) + (rc_target_rate_extra_fbls << 4);
  else
    baseTargetRate = (baseTargetRateTemp + offset) >> scale;

parameter [2:0] targetRateLutBits = 3'd4; // Defined in Table 4-17 in spec. Called g_rc_targetRateBits in C model
parameter [4:0] targetRateShift = rcFullnessRangeBits - targetRateLutBits; // Called shift in spec Table 4-18.
wire [4:0] LutTargetRateDeltaIndexTemp;
assign LutTargetRateDeltaIndexTemp = (rcFullness_d + (1'b1 << (targetRateShift - 1'b1))) >> targetRateShift;

parameter [3:0] clipMax = (1'b1 << targetRateLutBits) - 1'b1;
reg [3:0] LutTargetRateDeltaIndex;
always @ (*) 
  if (LutTargetRateDeltaIndexTemp > clipMax)
    LutTargetRateDeltaIndex = clipMax;
  else
    LutTargetRateDeltaIndex = LutTargetRateDeltaIndexTemp;

reg [15:0] targetRate;
always @ (posedge clk) 
  if (blockBits_valid_dl[0] | sos_for_rc)
    targetRate <= baseTargetRate + target_rate_delta_lut[LutTargetRateDeltaIndex];

reg [6:0] prevQp;
always @ (posedge clk) 
  if (sos)
    prevQp = 7'd36;
  else if (qp_valid)
    prevQp = qp;
      
always @ (posedge clk or negedge rst_n) 
  if (~rst_n)
    enableUnderflowPrevention <= 1'b1;
  else if (sos)
    enableUnderflowPrevention <= 1'b1;
  else if (blockBits_valid_dl[0])
    enableUnderflowPrevention <= bufferFullness_r < ((bits_per_pixel<<1) + maxAdjBits);

reg [12:0] prevBlockBitsWithoutPadding_r;
always @ (posedge clk or negedge rst_n) 
  if (~rst_n)
    prevBlockBitsWithoutPadding_r <= 13'd0;
  else if (flush | sos_dl[1])
    prevBlockBitsWithoutPadding_r <= 13'd0;
  else if (prevBlockBitsWithoutPadding_valid)
    prevBlockBitsWithoutPadding_r <= prevBlockBitsWithoutPadding;

wire signed [13:0] diffBits;
assign diffBits = $signed({1'b0, prevBlockBitsWithoutPadding_r}) - $signed({1'b0, targetRate});

reg [2:0] qpUpdateMode;
always @ (*) begin
  qpUpdateMode = 3'd0;
  if (rcFullness >= 16'd57672) //88%
        qpUpdateMode = 3'd2;
  else if (rcFullness >= 16'd49807)  //76%
        qpUpdateMode = 3'd1;
  if (rcFullness <= 16'd7864) //12%
        qpUpdateMode = 3'd4;
  else if (rcFullness <= 16'd15729)  //24%
        qpUpdateMode = 3'd3;
end
wire signed [13:0] negDiff;
assign negDiff = ~diffBits + 1'b1;
wire [12:0] absDiff;
assign absDiff = diffBits[13] ? negDiff[12:0] : diffBits[12:0];
reg [3:0] qpIndex;
always @ (*)
  if (~diffBits[13]) begin // diffBits > 0 
    if (absDiff < qpIndexThresholdPositive[chroma_format][2]) begin
      if (absDiff < qpIndexThresholdPositive[chroma_format][1])
        if (absDiff < qpIndexThresholdPositive[chroma_format][0])
          qpIndex = 3'd0;
        else
          qpIndex = 3'd1;
      else
        qpIndex = 3'd2;
    end
    else begin
      if (absDiff < qpIndexThresholdPositive[chroma_format][3])
        qpIndex = 3'd3;
      else
        if (absDiff < qpIndexThresholdPositive[chroma_format][4])
          qpIndex = 3'd4;
        else
          qpIndex = 3'd5;
    end
  end
  else begin// diffBits <= 0 
    if (absDiff < qpIndexThresholdNegative[chroma_format][1]) begin
      if (absDiff < qpIndexThresholdNegative[chroma_format][0])
        qpIndex = 3'd0;
      else
        qpIndex = 3'd1;
    end
    else begin
      if (absDiff < qpIndexThresholdNegative[chroma_format][3])
        if (absDiff < qpIndexThresholdNegative[chroma_format][2])
          qpIndex = 3'd2;
        else
          qpIndex = 3'd3;
      else
        qpIndex = 3'd4;
    end
  end
  
reg signed [3:0] deltaQp;
always @ (posedge clk)
  if (blockBits_valid_dl[1])
    if (~diffBits[13])
      deltaQp <= QpIncrementTable[qpUpdateMode][qpIndex];
    else
      deltaQp <= -QpDecrementTable[qpUpdateMode][qpIndex];
      
always @ (posedge clk)
  if (blockBits_valid_dl[1])
    if (rcFullness > 16'd62259) // buffer fullness >95%
      maxQp <= 3'd4 + max_qp_lut[7];
    else
      maxQp <= max_qp_lut[rcFullness >> 13];
      
reg [3:0] minQpOffset;
always @ (posedge clk)
  if (blockBits_valid_dl[1])
    if ((bufferFullness_r <= (rc_buffer_init_size >> 2)) | (rcFullness < 16'd9830))
      minQpOffset <= 4'd0;
    else
      minQpOffset <= 4'd8;

wire signed [9:0] qpUnclamped;  
assign qpUnclamped = $signed({1'b0, qp}) + deltaQp;
reg [7:0] qpClamped;
always @ (*)
  if (qpUnclamped < $signed(minQp + minQpOffset))
    qpClamped = minQp + minQpOffset;
  else if (qpUnclamped > $signed({1'b0, maxQp}))
    qpClamped = maxQp;
  else 
    qpClamped = qpUnclamped[8:0];

wire [7:0] flatness_qp_very_flat;
assign flatness_qp_very_flat = fbls_dl ? flatness_qp_very_flat_fbls : flatness_qp_very_flat_nfbls;
wire [7:0] flatness_qp_somewhat_flat;
assign flatness_qp_somewhat_flat = fbls_dl ? flatness_qp_somewhat_flat_fbls : flatness_qp_somewhat_flat_nfbls;
wire [2:0] lutFlatnessQpIndex;
assign lutFlatnessQpIndex = (rcFullness >> 13);
wire [7:0] lutFlatnessQpSelected;
assign lutFlatnessQpSelected = flatness_qp_lut[lutFlatnessQpIndex];

reg [7:0] qpFlatnessAdjusted;
always @ (*)
  case (flatnessType)
    2'd0: if (flatness_qp_very_flat < qpClamped) qpFlatnessAdjusted = flatness_qp_very_flat; else qpFlatnessAdjusted = qpClamped;
    2'd1: if (flatness_qp_somewhat_flat < qpClamped) qpFlatnessAdjusted = flatness_qp_somewhat_flat; else qpFlatnessAdjusted = qpClamped;
    2'd2: if (lutFlatnessQpSelected < qpClamped) qpFlatnessAdjusted = lutFlatnessQpSelected; else qpFlatnessAdjusted = qpClamped;
    2'd3: if (lutFlatnessQpSelected > qpClamped) qpFlatnessAdjusted = lutFlatnessQpSelected; else qpFlatnessAdjusted = qpClamped;
  endcase

reg rcFullnessLorE96Percent;
always @ (posedge clk) 
  if (blockBits_valid_dl[0])
    rcFullnessLorE96Percent <= (rcFullness <= 16'd62915);
  
reg [7:0] qpFirstLineAdjusted;
always @ (*)
  if (fbls_dl & rcFullnessLorE96Percent & (qpFlatnessAdjusted > maxQp))
    qpFirstLineAdjusted = maxQp;
  else
    qpFirstLineAdjusted = qpFlatnessAdjusted;
      
    
// UpdateQp
always @ (posedge clk) 
  if (sos_fsm == 2'd2)
    qp <= 7'd36;
  else if (blockBits_valid_dl[2])
    qp <= qpFirstLineAdjusted;
    
  
assign qp_valid = blockBits_valid;//(blockBits_valid_dl[3] & ~sos) | (sos_dl[3] & blockBits_valid);



endmodule

