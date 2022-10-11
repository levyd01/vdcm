`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module bp_mode
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [3*2-1:0] partitionSize_p,
  input wire [3*4-1:0] blkWidth_p,
  input wire [3*2-1:0] blkHeight_p,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [1:0] bits_per_component_coded,
  
  input wire fbls, // First line of slice
  input wire substreams123_parsed,
  input wire sos,
  input wire [6:0] masterQp,
  input wire masterQp_valid,
  input wire [5:0] minQp,
  input wire [8:0] maxQp,
  input wire [12:0] maxPoint,
  input wire [12:0] midPoint,
  input wire [3*14-1:0] minPoint_p,
  
  input wire pReconLeftBlk_valid,
  input wire [2*8*3*14-1:0] pReconLeftBlk_p,
  
  input wire [33*3*14-1:0] neighborsAbove_rd_p,
  input wire neighborsAbove_valid,
  
  input wire [2:0] blockMode,
  input wire [7*4*2-1:0] bpv2x1_sel_p,
  input wire [7*4-1:0] bpv2x2_sel_p,
  input wire [3:0] bpvTable,
  
  input wire [16*3*16-1:0] pQuant_p,
  input wire pQuant_valid,
  
  output reg [6:0] masterQpForBp,
  input wire [3*7-1:0] qp_p,
  input wire qp_valid,
  
  output wire pReconBlk_valid,
  output wire [2*8*3*14-1:0] pReconBlk_p

);

// Tables for BP
wire [7:0] bpInvQuantScales [7:0];
assign bpInvQuantScales[0] = 8'd128;
assign bpInvQuantScales[1] = 8'd140;
assign bpInvQuantScales[2] = 8'd152;
assign bpInvQuantScales[3] = 8'd164;
assign bpInvQuantScales[4] = 8'd180;
assign bpInvQuantScales[5] = 8'd196;
assign bpInvQuantScales[6] = 8'd216;
assign bpInvQuantScales[7] = 8'd236;

genvar ci;
genvar bi;
genvar coli;
genvar rowi;
wire [13:0] pReconLeftPix [2:0][1:0][7:0];
wire [13:0] searchRangeA [2:0][7:0];
wire [13:0] searchRangeB [2:0][24:0];
wire [6:0] bpv2x2_sel [3:0];
wire [6:0] bpv2x1_sel [3:0][1:0];
wire [1:0] partitionSize [2:0];
wire [4:0] blkWidth [2:0];
wire [1:0] blkHeight [2:0];
wire [6:0] qp [2:0];
wire signed [15:0] pQuant [2:0][1:0][7:0];
wire signed [13:0] minPoint [2:0];
reg fbls_dl;
reg [12:0] meanValue [2:0];

generate
  for (ci=0; ci<3; ci=ci+1) begin : gen_in_comp
    for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_in_coli
      for (coli=0; coli<8; coli=coli+1) begin : gen_in_coli
        assign pReconLeftPix[ci][rowi][coli] = pReconLeftBlk_p[(ci*8*2 + rowi*8 + coli)*14+:14];
        assign pQuant[ci][rowi][coli] = pQuant_p[(ci*8*2 + rowi*8 + coli)*16+:16];
      end
    end
    for (coli=0; coli<8; coli=coli+1) begin : gen_searchRangeA_coli
      assign searchRangeA[ci][coli] = fbls_dl ? meanValue[ci] : neighborsAbove_rd_p[(33*ci+ 32-coli)*14+:14];
    end
    for (coli=0; coli<25; coli=coli+1) begin : gen_searchRangeB_coli
      assign searchRangeB[ci][coli] = neighborsAbove_rd_p[(33*ci + 24-coli)*14+:14];
    end
    assign partitionSize[ci] = partitionSize_p[2*ci+:2];
    assign blkWidth[ci] = blkWidth_p[4*ci+:4];
    assign blkHeight[ci] = blkHeight_p[2*ci+:2];
    assign qp[ci] = qp_p[7*ci+:7];
    assign minPoint[ci] = minPoint_p[14*ci+:14];
  end
  for (bi = 0; bi < 4; bi = bi + 1) begin : gen_bpv2x2_sel
    assign bpv2x2_sel[bi] = bpv2x2_sel_p[7*bi+:7];
    assign bpv2x1_sel[bi][0] = bpv2x1_sel_p[7*bi*2+:7];
    assign bpv2x1_sel[bi][1] = bpv2x1_sel_p[7*(bi*2+1)+:7];
  end
endgenerate

reg [2:0] blockMode_dl [1:0];
always @ (posedge clk) begin
  blockMode_dl[0] <= blockMode;
  blockMode_dl[1] <= blockMode_dl[0];
end

reg [3:0] bpvTable_dl [1:0];
always @ (posedge clk) begin
  bpvTable_dl[0] <= bpvTable;
  bpvTable_dl[1] <= bpvTable_dl[0];
end

reg [3:0] substreams123_parsed_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    substreams123_parsed_dl <= 4'b0;
  else if (flush)
    substreams123_parsed_dl <= 4'b0;
  else
    substreams123_parsed_dl <= {substreams123_parsed_dl[2:0], substreams123_parsed};
  
localparam SOS_FSM_IDLE     = 3'd0;
localparam SOS_FSM_SOS      = 3'd1;
localparam SOS_FSM_1ST_BLK  = 3'd2;
localparam SOS_FSM_2ND_BLK  = 3'd3;
localparam SOS_FSM_3RD_BLK  = 3'd4;
localparam SOS_FSM_4TH_BLK  = 3'd5;
localparam SOS_FSM_RUN      = 3'd6;

// In the first blocks of the slice, replace the unavailable pixels by mean value for searchRangeC
reg [2:0] sos_fsm; 
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos_fsm <= SOS_FSM_IDLE;
  else if (flush)
    sos_fsm <= SOS_FSM_IDLE;
  else
    case (sos_fsm)
      SOS_FSM_IDLE: if (sos) sos_fsm <= SOS_FSM_SOS;
      SOS_FSM_SOS: if (pReconLeftBlk_valid) sos_fsm <= SOS_FSM_1ST_BLK;
      SOS_FSM_1ST_BLK: if (pReconLeftBlk_valid) sos_fsm <= SOS_FSM_2ND_BLK;
      SOS_FSM_2ND_BLK: if (pReconLeftBlk_valid) sos_fsm <= SOS_FSM_3RD_BLK;
      SOS_FSM_3RD_BLK: if (pReconLeftBlk_valid) sos_fsm <= SOS_FSM_4TH_BLK;
      SOS_FSM_4TH_BLK: if (pReconLeftBlk_valid) sos_fsm <= SOS_FSM_RUN;
      SOS_FSM_RUN: if (sos) sos_fsm <= SOS_FSM_SOS;
    endcase
    

integer c;
always @ (*)
  for (c=0; c<3; c=c+1)
    meanValue[c] = ((csc == 2'd1) & (c > 0)) ? 12'd0 : midPoint;

integer col;
integer row;
integer i;
reg [13:0] pReconLeftPix_r [2:0][1:0][7:0]; // C25 to C32 and C58 to C65
reg [13:0]  pReconLeftPix_r_dl [2:0][2:0][1:0][7:0]; // 0: C1 to C8 and C34 to C41; 1: and C9 to C16 and C42 to C49; 2: C17 to C24 and C50 to C57
reg [13:0]  pReconLeftPix_r_last [2:0][1:0]; // C0 and C33
always @ (posedge clk)
  for (c=0; c<3; c=c+1)
    for (row=0; row<2; row=row+1) 
      if (pReconLeftBlk_valid) begin
        for (col=0; col<8; col=col+1) begin
          pReconLeftPix_r[c][row][col] <= pReconLeftPix[c][row][col];
          pReconLeftPix_r_dl[c][2][row][col] <= pReconLeftPix_r[c][row][col];
          pReconLeftPix_r_dl[c][1][row][col] <= pReconLeftPix_r_dl[c][2][row][col];
          pReconLeftPix_r_dl[c][0][row][col] <= pReconLeftPix_r_dl[c][1][row][col];
        end
        pReconLeftPix_r_last[c][row] <= pReconLeftPix_r_dl[c][0][row][7];
      end
      
integer s;
reg [13:0] searchRangeC [2:0][65:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    for (row=0; row<2; row=row+1)
      for (col=0; col<33; col=col+1)
        if (col == 0)
          searchRangeC[c][col+33*row] = (sos_fsm == SOS_FSM_RUN) ? pReconLeftPix_r_last[c][row] : meanValue[c];
        else if ((col >= 1) & (col <= 8))
          searchRangeC[c][col+33*row] = (sos_fsm >= SOS_FSM_4TH_BLK) ? pReconLeftPix_r_dl[c][0][row][col-1] : meanValue[c];
        else if ((col >= 9) & (col <= 16))
          searchRangeC[c][col+33*row] = (sos_fsm >= SOS_FSM_3RD_BLK) ? pReconLeftPix_r_dl[c][1][row][col-9] : meanValue[c];
        else if ((col >= 17) & (col <= 24))
          searchRangeC[c][col+33*row] = (sos_fsm >= SOS_FSM_2ND_BLK) ? pReconLeftPix_r_dl[c][2][row][col-17] : meanValue[c];
        else // ((col >= 25) & (col <= 32))
          searchRangeC[c][col+33*row] = (sos_fsm >= SOS_FSM_1ST_BLK) ? pReconLeftPix_r[c][row][col-25] : meanValue[c];
          
// Build BPVs 2x2
reg [13:0] bpv2x2 [2:0][63:0][1:0][1:0];
integer b;
always @ (*)
  for (c=0; c<3; c=c+1) begin
    // BPV0 to BPV6
    for (b=0; b<7; b=b+1) 
      for (col=0; col<2; col=col+1) begin
        bpv2x2[c][b][0][col] = searchRangeA[c][b+col];
        bpv2x2[c][b][1][col] = searchRangeC[c][25+b+col];
      end
    // BPV7
    bpv2x2[c][7][0][0] = searchRangeA[c][7];
    bpv2x2[c][7][0][1] = searchRangeB[c][0];
    bpv2x2[c][7][1][0] = searchRangeC[c][32];
    bpv2x2[c][7][1][1] = searchRangeC[c][32];
    // BPV8 to BPV32
    for (b=8; b<32; b=b+1) 
      for (row=0; row<2; row=row+1) begin
        bpv2x2[c][b][row][0] = searchRangeB[c][b-8];
        bpv2x2[c][b][row][1] = searchRangeB[c][b+1-8];
      end
    // BPV32 to BPV63
    for (b=32; b<64; b=b+1)
      for (col=0; col<2; col=col+1) begin
        bpv2x2[c][b][0][col] = searchRangeC[c][b-32+col];
        bpv2x2[c][b][1][col] = searchRangeC[c][b+1+col];
      end
  end
  
// Build BPVs 2x1
reg [13:0] bpv2x1 [2:0][1:0][63:0][1:0];
always @ (*)
  for (c=0; c<3; c=c+1) begin
    // First line of Subblock
    // bpv0 to bpv6
    for (b=0; b<7; b=b+1) 
      for (col=0; col<2; col=col+1)
        bpv2x1[c][0][b][col] = searchRangeA[c][b+col];
    // bpv7
    bpv2x1[c][0][7][0] = searchRangeA[c][7];
    bpv2x1[c][0][7][1] = searchRangeB[c][0];
    // bpv8 to bpv31
    for (b=8; b<32; b=b+1)
      for (col=0; col<2; col=col+1)
        bpv2x1[c][0][b][col] = searchRangeB[c][b-8+col];
    // bpv32 to bpv63
    for (b=32; b<64; b=b+1)
      for (col=0; col<2; col=col+1)
        bpv2x1[c][0][b][col] = searchRangeC[c][b-32+col];
    // Second line of Subblock
    // bpv0 to bpv6
    for (b=0; b<7; b=b+1) 
      for (col=0; col<2; col=col+1)
        bpv2x1[c][1][b][col] = searchRangeC[c][b+25+col];
    // bpv7
    bpv2x1[c][1][7][0] = searchRangeC[c][32];
    bpv2x1[c][1][7][1] = searchRangeC[c][32];
    // bpv8 to bpv31
    for (b=8; b<32; b=b+1)
      for (col=0; col<2; col=col+1)
        bpv2x1[c][1][b][col] = searchRangeB[c][b-8+col];
    // bpv32 to bpv63
    for (b=32; b<64; b=b+1)
      for (col=0; col<2; col=col+1)
        bpv2x1[c][1][b][col] = searchRangeC[c][b+1+col];
  end

parameter MODE_BP        = 3'd1;
parameter MODE_BP_SKIP   = 3'd4;

reg [3:0] pReconLeftBlk_valid_dl;
always @ (posedge clk)
  pReconLeftBlk_valid_dl <= {pReconLeftBlk_valid_dl[2:0], pReconLeftBlk_valid};
  
// Sample BPV2x2 and bpv2x1
reg [13:0] bpv2x2_r [2:0][63:0][1:0][1:0];
reg [13:0] bpv2x1_r [2:0][1:0][63:0][1:0];
always @ (posedge clk)
  if (pReconLeftBlk_valid)
    for (c=0; c<3; c=c+1)
      for (b=0; b<64; b=b+1) 
        for (row=0; row<2; row=row+1) 
          for (col=0; col<2; col=col+1) begin
            bpv2x2_r[c][b][row][col] <= bpv2x2[c][b][row][col];
            bpv2x1_r[c][row][b][col] <= bpv2x1[c][row][b][col];
          end

reg bpv_ptr;
always @ (posedge clk)
  if (~rst_n)
    bpv_ptr <= 1'b0;
  else if (flush)
    bpv_ptr <= 1'b0;
  else if (pReconLeftBlk_valid_dl[1] & ~substreams123_parsed_dl[0])
    bpv_ptr <= 1'b1;
  else if (~pReconLeftBlk_valid_dl[1] & substreams123_parsed_dl[0])
    bpv_ptr <= 1'b0;

// BpMode::UpdateQp in C
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fbls_dl <= 1'b1;
  else if (flush)
    fbls_dl <= 1'b1;
  else if (qp_valid)
    fbls_dl <= fbls;
reg [2:0] masterQpOffset;
always @ (*)
  if (chroma_format == 2'd0)
    masterQpOffset = fbls_dl ? 3'd4 : 3'd2;
  else
    masterQpOffset = 3'd0;

reg [7:0] UnclampedMasterQpForBp;
always @ (*) begin
  UnclampedMasterQpForBp = masterQp + masterQpOffset;
  if (UnclampedMasterQpForBp < minQp)
    masterQpForBp = minQp;
  else if (UnclampedMasterQpForBp > maxQp)
    masterQpForBp = maxQp;
  else
    masterQpForBp = UnclampedMasterQpForBp;
end
  
function integer GetPartitionStartOffset;
  input integer partIdx;
  input integer comp;
  input reg partitionType;
  input reg [1:0] partitionSizeForComp;
  input reg [4:0] blkWidthForComp;
  integer offsetY;
  integer offsetX;
  begin
    offsetY = partIdx >> 2;
    offsetX = partIdx - (offsetY << 2);
    if (~partitionType) // 2x1
      GetPartitionStartOffset = (blkWidthForComp * offsetY) + (offsetX * partitionSizeForComp);
    else // 2x2
      GetPartitionStartOffset = ((blkWidthForComp * offsetY)<<1) + (offsetX * partitionSizeForComp);
  end
endfunction

function signed [14:0] DequantSample;
  input reg signed [15:0] quant;
  input reg [7:0] scale;
  input reg [7:0] offset;
  input reg signed [7:0] shift;
  reg sign;
  reg [14:0] absQuant;
  reg [15:0] iCoeffQClip_pos;
  reg [23:0] iCoeffQClip_pos_before_shift;
  reg [6:0] absShift;
  begin
    sign = quant[15];
    if (shift > 8'sd0) begin
      absQuant = sign ? ~((quant - 1'b1)) : quant[15:0];
      iCoeffQClip_pos_before_shift = (absQuant * scale) + offset;
      iCoeffQClip_pos = iCoeffQClip_pos_before_shift >> shift;
      DequantSample = sign ? ~(iCoeffQClip_pos - 1'b1) : $signed({1'b0, iCoeffQClip_pos});
    end
    else begin
      absShift = ~(shift - 1'b1);
      DequantSample = (quant * $signed({1'b0, scale})) <<< absShift;
    end
  end
endfunction

reg [7:0] scale [2:0];
reg [3:0] qp_scale [2:0];
reg [2:0] qp_rem [2:0];
reg signed [7:0] shift [2:0];
reg [7:0] offset [2:0];
always @ (*)
  for (c=0; c<3; c=c+1) begin
    qp_scale[c] = qp[c] >> 3;
    qp_rem[c] = qp[c] & 3'b111;
    scale[c] = bpInvQuantScales[qp_rem[c]];
    shift[c] = 4'd9 - qp_scale[c];
    if (shift[c] > 7'sd0)
      offset[c] = 1'b1 << (shift[c] - 1'b1);
    else
      offset[c] = 8'd0;
  end
        
function signed [14:0] Clip3;
  input signed [16:0] x;
  input signed [14:0] min;
  input [13:0] max;
  reg too_big;
  reg too_small;
  begin
    too_big = x > $signed({1'b0, max});
    too_small = x < min;
    case ({too_big, ~(too_big|too_small), too_small})
      3'b100: Clip3 = max;
      3'b010: Clip3 = x[14:0];
      3'b001: Clip3 = min;
      default: Clip3 = 15'sd0;
    endcase
  end
endfunction

integer x0_base [2:0][3:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    for (b=0; b<4; b=b+1)
      x0_base[c][b] = GetPartitionStartOffset(b, c, bpvTable[b], partitionSize[c], blkWidth[c]);

reg signed [13:0] pReconBlk [2:0][1:0][7:0];
reg signed [14:0] iCoeffQClip [2:0][1:0][7:0];
reg signed [13:0] predBlk [2:0][1:0][7:0];
always @ (posedge clk) begin : process_pPredBlk
  if (substreams123_parsed_dl[0] & (blockMode_dl[0] == MODE_BP)) begin
    for (c=0; c<3; c=c+1)
      for (b=0; b<4; b=b+1) 
        if (bpvTable_dl[0][b]) begin // 2x2
          for (i=0; i<partitionSize[c]; i=i+1) begin
            for (row = 0; row < blkHeight[c]; row = row + 1) begin
              //$display("time: %0t, pQuant[%0d][%0d][%0d] = %d", $realtime, c, row, x0_base[c][b] + i, pQuant[c][row][x0_base[c][b] + i]);
              //$display("time: %0t, scale[%0d] = %d\toffset[%0d] = %d\tshift[%0d] = %d", $realtime, c, scale[c], c, offset[c], c, shift[c]);
              iCoeffQClip[c][row][x0_base[c][b] + i] <= DequantSample(pQuant[c][row][x0_base[c][b] + i], scale[c], offset[c], shift[c]);
              predBlk[c][row][x0_base[c][b] + i] <= ((bpv2x2_sel[b] >= 7'd32) | ((bpv2x2_sel[b] <= 7'd7) & (row == 1))) ? // Search C
                                                                                      bpv2x2[c][bpv2x2_sel[b]][row][i & 2'b11] :
                                                                                      bpv2x2_r[c][bpv2x2_sel[b]][row][i & 2'b11];
            end
          end
        end
        else begin // 2x1
          for (i=0; i<partitionSize[c]; i=i+1) begin
            for (row = 0; row < blkHeight[c]; row = row + 1) begin
              iCoeffQClip[c][row][x0_base[c][b] + i] <= DequantSample(pQuant[c][row][x0_base[c][b] + i], scale[c], offset[c], shift[c]);
              predBlk[c][row][x0_base[c][b] + i] <= ((bpv2x1_sel[b][row] >= 7'd32) | ((row == 1) & (bpv2x1_sel[b][row] <= 7'd7))) ? // Search C
                                                                                      bpv2x1[c][row][bpv2x1_sel[b][row]][i & 2'b11] : 
                                                                                      bpv2x1_r[c][row][bpv2x1_sel[b][row]][i & 2'b11];
            end
          end
        end
  end
end

always @ (posedge clk) begin : process_pReconBlk
  if (substreams123_parsed & (blockMode == MODE_BP_SKIP)) begin
    for (c=0; c<3; c=c+1)
      for (b=0; b<4; b=b+1) 
        if (bpvTable[b]) begin // 2x2
          for (row=0; row<2; row=row+1)
            for (col=0; col<2; col=col+1)
              if ((bpv2x2_sel[b] >= 7'd32) | ((bpv2x2_sel[b] <= 7'd7) & (row == 1))) // Search C
                pReconBlk[c][row][(b<<1) + col] <= bpv2x2[c][bpv2x2_sel[b]][row][col];
              else
                pReconBlk[c][row][(b<<1) + col] <= bpv2x2_r[c][bpv2x2_sel[b]][row][col];
        end
        else begin // 2x1
          for (row=0; row<2; row=row+1)
            for (col=0; col<2; col=col+1)
              if ((bpv2x1_sel[b][row] >= 7'd32) | ((row == 1) & (bpv2x1_sel[b][row] <= 7'd7))) // Search C
                pReconBlk[c][row][(b<<1) + col] <= bpv2x1[c][row][bpv2x1_sel[b][row]][col];
              else
                pReconBlk[c][row][(b<<1) + col] <= bpv2x1_r[c][row][bpv2x1_sel[b][row]][col];
        end
  end
  else if (substreams123_parsed_dl[1] & (blockMode_dl[1] == MODE_BP)) begin
    for (c=0; c<3; c=c+1)
      for (b=0; b<4; b=b+1)
        for (i=0; i<partitionSize[c]; i=i+1) begin
          for (row = 0; row < blkHeight[c]; row = row + 1)
            pReconBlk[c][row][x0_base[c][b] + i] <= Clip3(predBlk[c][row][x0_base[c][b] + i] + iCoeffQClip[c][row][x0_base[c][b] + i], minPoint[c], maxPoint);
        end
  end
end


assign pReconBlk_valid = substreams123_parsed_dl[2];
generate
  for (ci=0; ci<3; ci=ci+1) begin : gen_out_comp
    for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_out_coli
      for (coli=0; coli<8; coli=coli+1) begin : gen_out_coli
        assign pReconBlk_p[(ci*8*2+rowi*8+coli)*14+:14] = pReconBlk[ci][rowi][coli];
      end
    end
  end
endgenerate


endmodule