`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module transform_mode
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire fbls, // First line of slice
  input wire resetLeft, // First block of chunk
  input wire soc,
  input wire eoc,
  input wire eob,
  input wire sos,
  
  input wire [2:0] bestIntraPredIdx,
  input wire underflowPreventionMode,
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [3*2-1:0] blkHeight_p,
  input wire [3*4-1:0] blkWidth_p,
  input wire [1:0] bits_per_component_coded,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [3*14-1:0] minPoint_p,
  input wire [12:0] midPoint,
  input wire [12:0] maxPoint,
  input wire [3*5-1:0] neighborsAboveLenAdjusted_p,
  input wire [16*3*14-1:0] neighborsAbove_rd_p, // Fetch 16 pixels (4 to the left above the current, 8 exactly above, and 4 to the right above)
  input wire neighborsAbove_valid,
  
  input wire [16*3*16-1:0] pQuant_p,
  input wire pQuant_valid,
  
  input wire [3*7-1:0] qp_p,
  input wire qp_valid,
  
  output reg pReconBlk_valid,
  output wire [2*8*3*14-1:0] pReconBlk_p
);

// LUTs
wire [5:0] dctInverseQuant_8x2 [7:0][3:0];
assign dctInverseQuant_8x2[0][0] = 6'd16; 
assign dctInverseQuant_8x2[0][1] = 6'd18; 
assign dctInverseQuant_8x2[0][2] = 6'd33; 
assign dctInverseQuant_8x2[0][3] = 6'd26;
assign dctInverseQuant_8x2[1][0] = 6'd17;
assign dctInverseQuant_8x2[1][1] = 6'd20;
assign dctInverseQuant_8x2[1][2] = 6'd36;
assign dctInverseQuant_8x2[1][3] = 6'd28;
assign dctInverseQuant_8x2[2][0] = 6'd19;
assign dctInverseQuant_8x2[2][1] = 6'd22; 
assign dctInverseQuant_8x2[2][2] = 6'd39; 
assign dctInverseQuant_8x2[2][3] = 6'd30;
assign dctInverseQuant_8x2[3][0] = 6'd21;
assign dctInverseQuant_8x2[3][1] = 6'd23;
assign dctInverseQuant_8x2[3][2] = 6'd42;
assign dctInverseQuant_8x2[3][3] = 6'd33;
assign dctInverseQuant_8x2[4][0] = 6'd23;
assign dctInverseQuant_8x2[4][1] = 6'd26;
assign dctInverseQuant_8x2[4][2] = 6'd46;
assign dctInverseQuant_8x2[4][3] = 6'd36;
assign dctInverseQuant_8x2[5][0] = 6'd25;
assign dctInverseQuant_8x2[5][1] = 6'd28;
assign dctInverseQuant_8x2[5][2] = 6'd50;
assign dctInverseQuant_8x2[5][3] = 6'd39;
assign dctInverseQuant_8x2[6][0] = 6'd27;
assign dctInverseQuant_8x2[6][1] = 6'd30;
assign dctInverseQuant_8x2[6][2] = 6'd55;
assign dctInverseQuant_8x2[6][3] = 6'd43;
assign dctInverseQuant_8x2[7][0] = 6'd29;
assign dctInverseQuant_8x2[7][1] = 6'd33; 
assign dctInverseQuant_8x2[7][2] = 6'd60; 
assign dctInverseQuant_8x2[7][3] = 6'd47;

wire [2:0] dctQuantMapping_8x2 [7:0];
assign dctQuantMapping_8x2[0] = 3'd0;
assign dctQuantMapping_8x2[1] = 3'd1; 
assign dctQuantMapping_8x2[2] = 3'd2; 
assign dctQuantMapping_8x2[3] = 3'd3; 
assign dctQuantMapping_8x2[4] = 3'd0; 
assign dctQuantMapping_8x2[5] = 3'd3; 
assign dctQuantMapping_8x2[6] = 3'd2; 
assign dctQuantMapping_8x2[7] = 3'd1;

wire [6:0] dctInverseQuant_4x2 [7:0][1:0];
assign dctInverseQuant_4x2[0][0] = 7'd23;
assign dctInverseQuant_4x2[0][1] = 7'd46;
assign dctInverseQuant_4x2[1][0] = 7'd25;
assign dctInverseQuant_4x2[1][1] = 7'd50;
assign dctInverseQuant_4x2[2][0] = 7'd27;
assign dctInverseQuant_4x2[2][1] = 7'd55;
assign dctInverseQuant_4x2[3][0] = 7'd29;
assign dctInverseQuant_4x2[3][1] = 7'd60;
assign dctInverseQuant_4x2[4][0] = 7'd32;
assign dctInverseQuant_4x2[4][1] = 7'd65;
assign dctInverseQuant_4x2[5][0] = 7'd35;
assign dctInverseQuant_4x2[5][1] = 7'd71;
assign dctInverseQuant_4x2[6][0] = 7'd38;
assign dctInverseQuant_4x2[6][1] = 7'd78;
assign dctInverseQuant_4x2[7][0] = 7'd41;
assign dctInverseQuant_4x2[7][1] = 7'd85;

wire [3:0] dctQuantMapping_4x2;
assign dctQuantMapping_4x2 = 4'b1010;

wire [6:0] dctInverseQuant_4x1 [7:0][1:0];
assign dctInverseQuant_4x1[0][0] = 7'd32; 
assign dctInverseQuant_4x1[0][1] = 7'd65;
assign dctInverseQuant_4x1[1][0] = 7'd35; 
assign dctInverseQuant_4x1[1][1] = 7'd71;
assign dctInverseQuant_4x1[2][0] = 7'd38; 
assign dctInverseQuant_4x1[2][1] = 7'd78;
assign dctInverseQuant_4x1[3][0] = 7'd41; 
assign dctInverseQuant_4x1[3][1] = 7'd85;
assign dctInverseQuant_4x1[4][0] = 7'd45; 
assign dctInverseQuant_4x1[4][1] = 7'd92;
assign dctInverseQuant_4x1[5][0] = 7'd49; 
assign dctInverseQuant_4x1[5][1] = 7'd101;
assign dctInverseQuant_4x1[6][0] = 7'd54; 
assign dctInverseQuant_4x1[6][1] = 7'd110;
assign dctInverseQuant_4x1[7][0] = 7'd59; 
assign dctInverseQuant_4x1[7][1] = 7'd120;

wire [3:0] dctQuantMapping_4x1;
assign dctQuantMapping_4x1 = 4'b1010;

// unpack inputs
genvar ci;
genvar si;    
genvar coli;
genvar rowi;
wire [1:0] blkHeight [2:0];
wire [4:0] blkWidth [2:0];
wire [4:0] neighborsAboveLenAdjusted [2:0];
wire signed [15:0] pQuant [2:0][15:0];
wire [6:0] qp [2:0];
wire signed [13:0] minPoint [2:0];
generate
  for (ci =0; ci < 3; ci = ci + 1) begin : gen_blk_size
    assign blkHeight[ci] = blkHeight_p[2*ci+:2];
    assign blkWidth[ci] = blkWidth_p[4*ci+:4];
    assign neighborsAboveLenAdjusted[ci] = neighborsAboveLenAdjusted_p[5*ci+:5];
    assign minPoint[ci] = minPoint_p[14*ci+:14];
    for (si=0; si<16; si=si+1)
      assign pQuant[ci][si] = pQuant_p[ci*16*16+si*16+:16];
    assign qp[ci] = qp_p[ci*7+:7];
  end
endgenerate

integer c;
integer i;
reg signed [13:0] neighborsAbove_from_ram [2:0][15:0]; // spec Fig 4-13: A-4, A-3, A-2, A-1, A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11
always @ (*)
  for (c=0; c<3; c=c+1)
    if ((chroma_format > 2'd0) & (c > 0))
      for (i = 0; i < 16; i = i + 4) begin
        neighborsAbove_from_ram[c][i>>1] = neighborsAbove_rd_p[(16*c + i)*14+:14];
        neighborsAbove_from_ram[c][(i>>1) + 1] = neighborsAbove_rd_p[(16*c + i + 1)*14+:14];
      end
    else
      for (i = 0; i < 16; i = i + 1)
        neighborsAbove_from_ram[c][i] = neighborsAbove_rd_p[(16*c + i)*14+:14];
        
        

reg pResidual_valid;
reg [2:0] bestIntraPredIdx_dl;
reg soc_dl;
always @ (posedge clk or negedge ~rst_n)
  if (~rst_n) begin
    bestIntraPredIdx_dl <= 3'd0;
    soc_dl <= 1'b0;
  end
  else if (pResidual_valid) begin
    bestIntraPredIdx_dl <= bestIntraPredIdx;
    soc_dl <= soc;
  end
reg eoc_dl;
always @ (posedge clk or negedge ~rst_n)
  if (~rst_n) begin
    eoc_dl <= 1'b0;
  end
  else begin
    eoc_dl <= eoc;
  end

reg [2:0] resetLeft_dl;
reg [2:0] fbls_dl;
always @ (posedge clk or negedge ~rst_n)
  if (~rst_n) begin
    resetLeft_dl <= 3'b111;
    fbls_dl <= 3'b111;
  end
  else if (pQuant_valid) begin
    resetLeft_dl <= {resetLeft_dl[1:0], resetLeft};
    fbls_dl <= {fbls_dl[1:0], fbls};
  end

reg [2:0] neighborsAbove_valid_dl;
always @ (posedge clk or negedge ~rst_n)
  if (~rst_n) 
    neighborsAbove_valid_dl <= 3'b0;
  else
    neighborsAbove_valid_dl <= {neighborsAbove_valid_dl[1:0], neighborsAbove_valid};


// Initialize Neighbors (InitNeighbors() in C model)
// --------------------

reg [12:0] predResetLeft [2:0]; // pred when resetLeft = 1
always @ (*)
  for (c=0; c<3; c=c+1)
    predResetLeft[c] = ((csc == 2'd1) & (c > 0)) ? 12'd0 : midPoint;
      
parameter neighborsLeftLen = 2;
integer j;
reg signed [13:0] pReconBlk [2:0][1:0][7:0];
reg signed [13:0] neighborsLeft [2:0][1:0][neighborsLeftLen-1:0];
always @ (posedge clk)
  if (pReconBlk_valid & ~fbls_dl[0]) begin
    if (resetLeft)
      for (c=0; c<3; c=c+1)
        for (j = 0; j < blkHeight[c]; j = j + 1)
          for (i = 0; i < neighborsLeftLen ; i = i + 1)
            neighborsLeft[c][j][i] <= predResetLeft[c];
    else
      for (c=0; c<3; c=c+1)
        for (j = 0; j < blkHeight[c]; j = j + 1)
          for (i = 0; i < neighborsLeftLen ; i = i + 1)
            neighborsLeft[c][j][i] <= pReconBlk[c][j][blkWidth[c] - neighborsLeftLen + i];
  end

// Initialize neighbors (above samples) for spatial prediction
reg signed [13:0] neighborsAbove [2:0][15:0];
wire resetAbove;
assign resetAbove = fbls_dl[0];
parameter neighborsAboveLen = 8;
integer col;
integer row;
always @ (posedge clk)
  for (c=0; c<3; c=c+1)
    if (pResidual_valid & resetAbove)
      for (col = 0; col < neighborsAboveLenAdjusted[c]; col = col + 1)
        neighborsAbove[c][col] <= {1'b0, midPoint};
    else if (neighborsAbove_valid)
      for (col = 0; col < neighborsAboveLenAdjusted[c]; col = col + 1)
        neighborsAbove[c][col] <= neighborsAbove_from_ram[c][col];

reg signed [13:0] neighborsAbove_from_ram_i [2:0][15:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    for (col = 0; col < neighborsAboveLenAdjusted[c]; col = col + 1)
      if (neighborsAbove_valid)
        neighborsAbove_from_ram_i[c][col] = neighborsAbove_from_ram[c][col];
      else
        neighborsAbove_from_ram_i[c][col] = neighborsAbove[c][col];
        
// Perform Intra Prediction (PerfPrediction (IntraPredictorType predictor) in C model)
// ------------------------ 
    
// IntraPredictionFbls
reg [12:0] meanValue [2:0];
reg signed [14:0] predBlkFbls_d [2:0][1:0][7:0];
always @ (*)
  for (c=0; c<3; c=c+1) begin
    meanValue[c] = ((csc == 2'd1) & (c > 0)) ? 12'd0 : midPoint;
    for (row = 0; row < blkHeight[c]; row = row + 1)
      for (col = 0; col < blkWidth[c]; col = col + 1)
        predBlkFbls_d[c][row][col] = $signed({2'b0, meanValue[c]});
  end



// IntraDC: A0 + A1 + A2 + A3 + A4 + A5 + A6 + A7 for 4:4:4, A0 + A1 + A2 + A3 for 4:2:2 and 4:2:0
wire [1:0] sel_neighborsAbove_from_ram;
assign sel_neighborsAbove_from_ram = 
          {neighborsAbove_valid_dl[0], neighborsAbove_valid};
          
reg signed [22:0] sum_r [2:0];
always @ (posedge clk) 
  for (c=0; c<3; c=c+1)
    if ((chroma_format > 2'd0) & (c > 0))
      case (sel_neighborsAbove_from_ram)
        2'b01: sum_r[c] <= neighborsAbove_from_ram_i[c][0] + neighborsAbove_from_ram_i[c][1];
        2'b10: sum_r[c] <= sum_r[c] + neighborsAbove_from_ram_i[c][2] + neighborsAbove_from_ram_i[c][3];
      endcase
    else
      case (sel_neighborsAbove_from_ram)
        2'b01: sum_r[c] <= neighborsAbove_from_ram_i[c][0] + neighborsAbove_from_ram_i[c][1] + neighborsAbove_from_ram_i[c][4] + neighborsAbove_from_ram_i[c][5];
        2'b10: sum_r[c] <= sum_r[c] + neighborsAbove_from_ram_i[c][2] + neighborsAbove_from_ram_i[c][3] + neighborsAbove_from_ram_i[c][6] + neighborsAbove_from_ram_i[c][7];
      endcase
          
reg signed [14:0] mean [2:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    mean[c] <= (blkWidth[c] == 4'd8) ? sum_r[c] >>> 3 : sum_r[c] >>> 2;

// Table 4-42        
localparam INTRA_DC = 0;
localparam INTRA_V  = 1;
localparam INTRA_DR = 2;
localparam INTRA_DL = 3;
localparam INTRA_VR = 4;
localparam INTRA_VL = 5;
localparam INTRA_HR = 6;
localparam INTRA_HL = 7;

reg [13:0] neighborsAbove_r [2:0][3:0];
always @ (posedge clk) 
  for (c=0; c<3; c=c+1)
    if (neighborsAbove_valid)
      if ((chroma_format > 2'd0) & (c > 0))
        for (col = 0; col < 2; col = col + 1)
          neighborsAbove_r[c][col] <= neighborsAbove[c][2+col];
      else
        for (col = 0; col < 4; col = col + 1)
          neighborsAbove_r[c][col] <= neighborsAbove[c][4+col];
        
reg signed [13:0] neighborsAboveForIntra [2:0][15:0]; // other than DC
always @ (*)
  for (c=0; c<3; c=c+1) begin
    if ((chroma_format > 2'd0) & (c > 0)) begin
      for (col = 0; col < 2; col = col + 1)
        neighborsAboveForIntra[c][col] = neighborsAbove_r[c][col];
      for (col = 2; col < 8; col = col + 1)
        neighborsAboveForIntra[c][col] = neighborsAbove[c][col-2];
    end
    else begin
      for (col = 0; col < 4; col = col + 1)
        neighborsAboveForIntra[c][col] = neighborsAbove_r[c][col];
      for (col = 4; col < 16; col = col + 1)
        neighborsAboveForIntra[c][col] = neighborsAbove[c][col-4];
    end
  end

function signed [14:0] Filter3;
  input signed [13:0] left;
  input signed [13:0] center;
  input signed [13:0] right;
  begin
    Filter3 = (left + (center<<1) + right + $signed(3'b010)) >>> 2;
  end
endfunction

function signed [14:0] Filter2;
  input signed [13:0] left;
  input signed [13:0] right;
  begin
    Filter2 = (left + right + $signed(2'b01)) >>> 1;
  end
endfunction


reg pDequant_valid;
reg signed [14:0] predBlk [2:0][1:0][7:0];
always @ (posedge clk) 
  for (c=0; c<3; c=c+1) begin
    if (pDequant_valid)
      if (resetAbove)
        for (row = 0; row < blkHeight[c]; row = row + 1)
          for (col = 0; col < blkWidth[c]; col = col + 1)
            predBlk[c][row][col] <= predBlkFbls_d[c][row][col];
      else
        case (bestIntraPredIdx_dl)
          INTRA_DC:
            begin
              for (row = 0; row < blkHeight[c]; row = row + 1)
                for (col = 0; col < blkWidth[c]; col = col + 1)
                  predBlk[c][row][col] <= mean[c];
            end
          INTRA_V:
            for (row = 0; row < blkHeight[c]; row = row + 1)
              for (col = 0; col < blkWidth[c]; col = col + 1)
                if ((chroma_format > 2'd0) & (c > 0))
                  predBlk[c][row][col] <= neighborsAboveForIntra[c][2+col];
                else
                  predBlk[c][row][col] <= neighborsAboveForIntra[c][4+col];
          INTRA_DR:
            case (chroma_format)
              2'd0: // 4:4:4
                for (col = 0; col < 8; col = col + 1) begin
                  if (soc_dl) begin
                    if (col == 0) begin
                      predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= $signed({2'b0, meanValue[c]});
                    end
                    else if (col == 1) begin
                      predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1]);
                    end
                    else if (col == 2) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                    end
                    else begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                    end
                  end
                  else begin
                    predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                  end
                end
              2'd1: // 4:2:2
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (soc_dl) begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      if (col == 0) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= $signed({2'b0, meanValue[c]});
                      end
                      else if (col == 1) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1]);
                      end
                      else if (col == 2) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      end
                      else begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      end
                    end
                    else begin // Chroma components see spec. page 94
                      if (col == 0) begin
                        predBlk[c][0][col] <= Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}),
                                                      $signed({2'b0, meanValue[c]}),
                                                      Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col]));
                      end
                      else if (col == 1) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]);
                        predBlk[c][1][col] <= Filter3(Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1],
                                                      Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                      end
                      else begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]);
                        predBlk[c][1][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1],
                                                      Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                    end
                    else begin // Chroma components see spec. page 94
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]);
                      predBlk[c][1][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                    neighborsAboveForIntra[c][2+col-1],
                                                    Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase
          INTRA_DL:
            case (chroma_format)
              2'd0: // 4:4:4
                for (col = 0; col < 8; col = col + 1) begin
                  if (eoc_dl) begin // Pixel duplication at chunk boundary
                    if (col < 5) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                    end
                    else if (col == 5) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                    end
                    else if (col == 6) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                      predBlk[c][1][col] <= neighborsAboveForIntra[c][4+col+1];
                    end
                    else begin // col == 7
                      predBlk[c][0][col] <= neighborsAboveForIntra[c][4+col];
                      predBlk[c][1][col] <= neighborsAboveForIntra[c][4+col];
                    end
                  end
                  else begin
                    predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                  end
                end
              2'd1: // 4:2:2
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (eoc_dl) begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      if (col < 5) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                      end
                      else if (col == 5) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                      end
                      else if (col == 6) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][4+col+1];
                      end
                      else begin // col == 7
                        predBlk[c][0][col] <= neighborsAboveForIntra[c][4+col];
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][4+col];
                      end
                    end
                    else begin // Chroma components see spec. page 94
                      if (col < 2) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]);
                        predBlk[c][1][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]), 
                                                      neighborsAboveForIntra[c][2+col+1],
                                                      Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]));
                      end
                      else if (col == 2) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]);
                        predBlk[c][1][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]), 
                                                      neighborsAboveForIntra[c][2+col+1],
                                                      neighborsAboveForIntra[c][2+col+1]);
                      end
                      else if (col == 3) begin
                        predBlk[c][0][col] <= neighborsAboveForIntra[c][2+col];
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][2+col];
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                    end
                    else begin // Chroma components see spec. page 94
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]);
                      predBlk[c][1][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]), 
                                                    neighborsAboveForIntra[c][2+col+1],
                                                    Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]));
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase
          INTRA_VL:
            case (chroma_format)
              2'd0: // 4:4:4
                for (col = 0; col < 8; col = col + 1) begin
                  if (eoc_dl) begin // Pixel duplication at chunk boundary
                    if (col < 6) begin  
                       predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                       predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                    end
                    else if (col == 6) begin
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                    end
                    else if (col == 7) begin
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                    end         
                  end
                  else begin
                    predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                  end
                end
              2'd1: // 4:2:2 TBD
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (eoc_dl) begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      if (col < 6) begin  
                         predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                         predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                      end
                      else if (col == 6) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                      end
                      else if (col == 7) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                      end   
                    end
                    else begin // Chroma components
                      if (col < 3) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col],
                                                      Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]));
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col],
                                                      Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]),
                                                      neighborsAboveForIntra[c][2+col+1]);
                      end
                      else if (col == 3) begin
                        predBlk[c][0][col] <= neighborsAboveForIntra[c][2+col];
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][2+col];
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2]);
                    end
                    else begin // Chroma components see spec. page 95
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][2+col],
                                                    Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]));
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col],
                                                    Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]),
                                                    neighborsAboveForIntra[c][2+col+1]);
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase      
          INTRA_VR:
            case (chroma_format)
              2'd0: // 4:4:4
                for (col = 0; col < 8; col = col + 1) begin
                  if (soc_dl)
                    if (col == 0) begin
                      predBlk[c][0][col] <= Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3($signed({1'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                    end
                    else if (col == 1) begin
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                    end
                    else begin
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                    end
                  else begin
                    predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                  end
                end
              2'd1: // 4:2:2
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (soc_dl) begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      if (col == 0) begin
                        predBlk[c][0][col] <= Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3($signed({1'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col]);
                      end
                      else if (col == 1) begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      end
                      else begin
                        predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      end   
                    end
                    else begin
                      if (col == 0) begin
                        predBlk[c][0][col] <= Filter2(Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col]), 
                                                      neighborsAboveForIntra[c][2+col]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}),
                                                      Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col]),
                                                      neighborsAboveForIntra[c][2+col]);
                      end
                      else begin
                        predBlk[c][0][col] <= Filter2(Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]), 
                                                      neighborsAboveForIntra[c][2+col]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col-1],
                                                      Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]),
                                                      neighborsAboveForIntra[c][2+col]);
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter2(neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1], neighborsAboveForIntra[c][4+col]);
                    end
                    else begin // Chroma components see spec. page 95
                      predBlk[c][0][col] <= Filter2(Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]), 
                                                    neighborsAboveForIntra[c][2+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col-1],
                                                    Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]),
                                                    neighborsAboveForIntra[c][2+col]);
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase  
          INTRA_HR:
            case (chroma_format)
              2'd0: // 4:4:4
		            for (col = 0; col < 8; col = col + 1) begin
                  if (soc_dl) begin
                    if (col==0) begin
                      predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                    end
                    else if (col==1) begin
                      predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                    end
                    else if (col==2) begin
                      predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2]);
                    end
                    else if (col==3) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                    end
                    else begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-4], neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                    end
                  end
                  else begin
                    predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-4], neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                  end
                end
              2'd1: // 4:2:2
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (soc_dl) begin // Pixel duplication at chunk boundary 
                    if (c == 0) begin
                      if (col==0) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                      end
                      else if (col==1) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-1]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}));
                      end
                      else if (col==2) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), $signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-2]);
                      end
                      else if (col==3) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                      end
                      else begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-4], neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                      end
                    end
                    else begin
                      if (col==0) begin
                        predBlk[c][0][col] <= Filter3($signed({2'b0, meanValue[c]}),
                                                      $signed({2'b0, meanValue[c]}),
                                                      Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col]));
                        predBlk[c][1][col] <= $signed({2'b0, meanValue[c]});
                      end
                      else if (col==1) begin
                        predBlk[c][0][col] <= Filter3(Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1],
                                                      Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                        predBlk[c][1][col] <= Filter3($signed({2'b0, meanValue[c]}),
                                                      Filter2($signed({2'b0, meanValue[c]}), neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1]);
                      end
                      else begin
                        predBlk[c][0][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1],
                                                      Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col-2],
                                                      Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                      neighborsAboveForIntra[c][2+col-1]);
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2], neighborsAboveForIntra[c][4+col-1]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col-4], neighborsAboveForIntra[c][4+col-3], neighborsAboveForIntra[c][4+col-2]);
                    end
                    else begin // Chroma components see spec. page 95
                      predBlk[c][0][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                    neighborsAboveForIntra[c][2+col-1],
                                                    Filter2(neighborsAboveForIntra[c][2+col-1], neighborsAboveForIntra[c][2+col]));
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col-2],
                                                    Filter2(neighborsAboveForIntra[c][2+col-2], neighborsAboveForIntra[c][2+col-1]),
                                                    neighborsAboveForIntra[c][2+col-1]);
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase
          INTRA_HL:
            case (chroma_format)
              2'd0: // 4:4:4
                for (col = 0; col < 8; col = col + 1) begin
                  if (eoc_dl) begin // Pixel duplication at chunk boundary
                    if (col < 4) begin  
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+4]);
                    end
                    else if (col == 4) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+3]);
                    end
                    else if (col == 5) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                    end
                    else if (col == 6) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                    end
                    else if (col == 7) begin
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                    end
                  end
                  else begin
                    predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                    predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+4]);
                  end
                end
              2'd1: // 4:2:2
                for (col = 0; col < blkWidth[c]; col = col + 1) begin
                  if (eoc_dl) begin // Pixel duplication at chunk boundary
                    if (c == 0) begin // luma component identical to 4:4:4
                      if (col < 4) begin  
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+4]);
                      end
                      else if (col == 4) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+3]);
                      end
                      else if (col == 5) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+2]);
                      end
                      else if (col == 6) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+1]);
                      end
                      else if (col == 7) begin
                        predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col], neighborsAboveForIntra[c][4+col]);
                      end
                    end
                    else begin
                      if (col < 2) begin
                        predBlk[c][0][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]),
                                                      neighborsAboveForIntra[c][2+col+1],
                                                      Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]));
                        predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col+1],
                                                      Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]),
                                                      neighborsAboveForIntra[c][2+col+2]);
                      end
                      else if (col == 2) begin
                        predBlk[c][0][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]),
                                                      neighborsAboveForIntra[c][2+col+1],
                                                      neighborsAboveForIntra[c][2+col+1]);
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][2+col+1];
                      end
                      else if (col == 3) begin
                        predBlk[c][0][col] <= neighborsAboveForIntra[c][2+col];
                        predBlk[c][1][col] <= neighborsAboveForIntra[c][2+col];
                      end
                    end
                  end
                  else begin
                    if (c == 0) begin // luma component identical to 4:4:4
                      predBlk[c][0][col] <= Filter3(neighborsAboveForIntra[c][4+col+1], neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3]);
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][4+col+2], neighborsAboveForIntra[c][4+col+3], neighborsAboveForIntra[c][4+col+4]);
                    end
                    else begin // Chroma components see spec. page 95
                      predBlk[c][0][col] <= Filter3(Filter2(neighborsAboveForIntra[c][2+col], neighborsAboveForIntra[c][2+col+1]),
                                                    neighborsAboveForIntra[c][2+col+1],
                                                    Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]));
                      predBlk[c][1][col] <= Filter3(neighborsAboveForIntra[c][2+col+1],
                                                    Filter2(neighborsAboveForIntra[c][2+col+1], neighborsAboveForIntra[c][2+col+2]),
                                                    neighborsAboveForIntra[c][2+col+2]);
                    end
                  end
                end
              // 2'd2: // 4:2:0 TBD
            endcase
        endcase
  end         
         
// Reconstruct
// -----------
reg [4:0] blkStride [2:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    case (chroma_format)
      2'd0: blkStride[c] = blkWidth[c];
      2'd1, 2'd2: if (c > 0) blkStride[c] = blkWidth[c] >> 1; else blkStride[c] = blkWidth[c];
      default: blkStride[c] = blkWidth[c];
    endcase
    
reg [3:0] transBitDepth [2:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    transBitDepth[c] = 4'd8 + (bits_per_component_coded << 1) + 1'b1 + ((csc == 2'd1) & (c>0));

// DeQuantLlm: De-quantize transform coefficients (includes noramlization)
reg [6:0] quantTable [2:0][3:0];
reg [2:0] mapping [2:0][7:0];
integer k;
always @ (*) 
  for (c=0; c<3; c=c+1) begin
    for (k=0; k<8; k=k+1)
      mapping[c][k] = 3'd0;
    for (k=0; k<4; k=k+1)
      quantTable[c][k] = 7'd0;  
    if ((blkWidth[c] == 4'd8) & (blkHeight[c] == 2'd2)) begin
      for (k=0; k<4; k=k+1)
        quantTable[c][k] = dctInverseQuant_8x2[qp[c][2:0]][k];
      for (k=0; k<8; k=k+1)
        mapping[c][k] = dctQuantMapping_8x2[k];
    end
    else if ((blkWidth[c] == 4'd4) & (blkHeight[c] == 2'd2)) begin
      for (k=0; k<2; k=k+1)
        quantTable[c][k] = dctInverseQuant_4x2[qp[c][2:0]][k];
      for (k=0; k<4; k=k+1)
        mapping[c][k] = dctQuantMapping_4x2[k];
    end
    else begin// (blkWidth[c] == 4'd4) & (blkHeight[c] == 2'd1)
      for (k=0; k<1; k=k+1)
        quantTable[c][k] = dctInverseQuant_4x1[qp[c][2:0]][k];
      for (k=0; k<4; k=k+1)
        mapping[c][k] = dctQuantMapping_4x1[k];
    end
  end

localparam DEQUANT_WIDTH = 16 + 7 + (7-3); // pQuant width + quantTable width + (qp width - 3)
reg signed [DEQUANT_WIDTH-1:0] pDequant [2:0][15:0];
always @ (posedge clk)
  if (pQuant_valid)
    for (c=0; c<3; c=c+1)
      for (row=0; row<blkHeight[c]; row=row+1)
        for (col=0; col<blkWidth[c]; col=col+1) begin
          //$display("pQuant[%0d][%0d] = %d", c, (row * blkWidth[c]) + col, pQuant[c][(row * blkWidth[c]) + col]);
          //$display("quantTable[%0d][%0d] = %d", c, mapping[c][col], quantTable[c][mapping[c][col]]);
          //$display("qp[%0d] = %d", c, qp[c]);
          pDequant[c][(row * blkWidth[c]) + col] <= (pQuant[c][(row * blkWidth[c]) + col] * $signed({1'b0, quantTable[c][mapping[c][col]]})) <<< (qp[c]>>3);
        end
always @ (posedge clk)
  pDequant_valid <= pQuant_valid;

localparam TEMPARRAY_WIDTH = DEQUANT_WIDTH + 1;
function [8*(TEMPARRAY_WIDTH+3)-1:0] dct8_II_bw_LLM_int;
  input [8*TEMPARRAY_WIDTH-1:0] x_p;
  reg signed [TEMPARRAY_WIDTH-1:0] x [7:0];
  reg signed [TEMPARRAY_WIDTH-1:0] z [7:0];
  reg signed [TEMPARRAY_WIDTH+1-1:0] ea [3:0];
  reg signed [TEMPARRAY_WIDTH+2-1:0] eb [3:0];
  reg signed [TEMPARRAY_WIDTH+1-1:0] da [3:0];
  reg signed [TEMPARRAY_WIDTH+2-1:0] db [3:0];
  reg signed [TEMPARRAY_WIDTH+2-1:0] dc [3:0];
  reg signed [TEMPARRAY_WIDTH+3-1:0] f [7:0];
  integer i;
  begin
    //$display("x_p = %x", x_p);
    //unpack
    for (i=0; i<8; i=i+1) begin
      x[i] = x_p[i*TEMPARRAY_WIDTH+:TEMPARRAY_WIDTH];
      //$display("x[%0d] = %d", i, x[i]);
    end
    // input reordering
    z[0] = x[0];
    z[1] = x[4];
    z[2] = x[2];
    z[3] = x[6];
    z[4] = x[7];
    z[5] = x[3];
    z[6] = x[5];
    z[7] = x[1];
    // first stage, even part
    ea[0] = z[0] + z[1];
    ea[1] = z[0] - z[1];
    ea[2] = (6'sd17 * z[2] - 7'sd41 * z[3]) >>> 6;
    ea[3] = (7'sd41 * z[2] + 6'sd17 * z[3]) >>> 6;
    //for (i=0; i<4; i=i+1)
    //  $display("ea[%d] = %d", i, ea[i]);
    // second stage, even part
    eb[0] = ea[0] + ea[3];
    eb[1] = ea[1] + ea[2];
    eb[2] = ea[1] - ea[2];
    eb[3] = ea[0] - ea[3];
    //for (i=0; i<4; i=i+1)
    //  $display("eb[%d] = %d", i, eb[i]);
    // first stage, odd part
    da[0] = -z[4] + z[7];
    da[1] = z[5];
    da[2] = z[6];
    da[3] = z[4] + z[7];
    //for (i=0; i<4; i=i+1)
    //  $display("da[%d] = %d", i, da[i]);
    // second stage, odd part
    db[0] = da[0] + da[2];
    db[1] = da[3] - da[1];
    db[2] = da[0] - da[2];
    db[3] = da[1] + da[3];
    //for (i=0; i<4; i=i+1)
    //  $display("db[%d] = %d", i, db[i]);
    // third stage, odd part
    dc[0] = (8'sd94  * db[0] - 7'sd63  * db[3]) >>> 7;
    dc[1] = (8'sd111 * db[1] - 6'sd22  * db[2]) >>> 7;
    dc[2] = (6'sd22  * db[1] + 8'sd111 * db[2]) >>> 7;
    dc[3] = (7'sd63  * db[0] + 8'sd94  * db[3]) >>> 7;
    // final stage
    //for (i=0; i<4; i=i+1)
    //  $display("dc[%d] = %d", i, dc[i]);
    f[0] = eb[0] + dc[3];
    f[1] = eb[1] + dc[2];
    f[2] = eb[2] + dc[1];
    f[3] = eb[3] + dc[0];
    f[4] = eb[3] - dc[0];
    f[5] = eb[2] - dc[1];
    f[6] = eb[1] - dc[2];
    f[7] = eb[0] - dc[3];
    // pack outputs
    for (i=0; i<8; i=i+1) begin
      //$display("f[%d] = %d", i, f[i]);
      dct8_II_bw_LLM_int[(TEMPARRAY_WIDTH+3)*i+:(TEMPARRAY_WIDTH+3)] = f[i];
    end
  end
endfunction

function [4*(TEMPARRAY_WIDTH+3)-1:0] dct4_II_bw_LLM_int;
  input [4*TEMPARRAY_WIDTH-1:0] x_p;
  reg signed [TEMPARRAY_WIDTH-1:0] x [3:0];
  reg signed [TEMPARRAY_WIDTH+2-1:0] a [3:0];
  reg signed [TEMPARRAY_WIDTH+3:0] f [3:0];
  integer i;
  begin
    //unpack
    for (i=0; i<4; i=i+1) begin
      x[i] = x_p[i*TEMPARRAY_WIDTH+:TEMPARRAY_WIDTH];
      //$display("x[%d] = %d", i, x[i]);
    end
    // first stage (even part)
    a[0] = x[0] + x[2];
    a[1] = x[0] - x[2];
    // first stage (odd part)
    a[2] = (6'sd17 * x[1] - 7'sd41 * x[3]) >>> 6;
    a[3] = (7'sd41 * x[1] + 6'sd17 * x[3]) >>> 6;
    // second stage
    f[0] = a[0] + a[3];
    f[1] = a[1] + a[2];
    f[2] = a[1] - a[2];
    f[3] = a[0] - a[3];
    // pack outputs
    for (i=0; i<4; i=i+1) begin
      //$display("f[%d] = %d", i, f[i]);
      dct4_II_bw_LLM_int[(TEMPARRAY_WIDTH+3)*i+:(TEMPARRAY_WIDTH+3)] = f[i];
    end
  end
endfunction

// DctLlmInverse: Inverse 2D DCT transform (SOIT)
reg signed [TEMPARRAY_WIDTH+3-1:0] tempArray[2:0][15:0]; // width TBD
reg [8*TEMPARRAY_WIDTH-1:0] tempArray_in_p [2:0];
reg [8*(TEMPARRAY_WIDTH+3)-1:0] tempArray_out_p [2:0];
reg sign;
reg signed [16:0] pResidual_d [2:0][15:0]; // predicted residuals, width TBD
reg [TEMPARRAY_WIDTH+2-1:0] absTempArray [2:0][15:0];
reg [16:0] unsignedPredResidual_d [2:0][15:0];
integer s;
always @ (*)
  for (c=0; c<3; c=c+1) begin
    //$display("Component %d", c);
    // Haar on columns
    if (blkHeight[c] == 2'd2)
      for (col=0; col<blkWidth[c]; col=col+1) begin
        tempArray[c][col] = pDequant[c][col] + pDequant[c][col + blkWidth[c]];
        //$display("tempArray[%d][%d] = %d", c, col, tempArray[c][col]);
        tempArray[c][col + blkWidth[c]] = pDequant[c][col] - pDequant[c][col + blkWidth[c]];
        //$display("tempArray[%d][%d] = %d", c, col + blkWidth[c], tempArray[c][col + blkWidth[c]]);
      end
    else 
      for (col=0; col<blkWidth[c]; col=col+1)
        tempArray[c][col] = pDequant[c][col];
    // inverse DCT for each row
    for (row=0; row<blkHeight[c]; row=row+1)
      if (blkWidth[c] == 4'd4) 
      begin
        //$display("Row %d", row);
        for (k=0; k<4; k=k+1)
          tempArray_in_p[c][k*TEMPARRAY_WIDTH+:TEMPARRAY_WIDTH] = tempArray[c][row*4+k][TEMPARRAY_WIDTH-1:0];
        tempArray_out_p[c] = dct4_II_bw_LLM_int(tempArray_in_p[c]);
        for (k=0; k<4; k=k+1)
          tempArray[c][row*4+k] = $signed(tempArray_out_p[c][k*(TEMPARRAY_WIDTH+3)+:(TEMPARRAY_WIDTH+3)]);
      end
        
      else // blkWidth[c] == 4'd8
        begin
          for (k=0; k<8; k=k+1)
            tempArray_in_p[c][k*TEMPARRAY_WIDTH+:TEMPARRAY_WIDTH] = tempArray[c][row*8+k][TEMPARRAY_WIDTH-1:0];
          tempArray_out_p[c] = dct8_II_bw_LLM_int(tempArray_in_p[c]);
          for (k=0; k<8; k=k+1)
            tempArray[c][row*8+k] = $signed(tempArray_out_p[c][k*(TEMPARRAY_WIDTH+3)+:(TEMPARRAY_WIDTH+3)]);
        end
    // Post-shift right by DCT8_2D_UP_SHIFT
    for (s=0; s<blkHeight[c]*blkWidth[c]; s=s+1) begin
      sign = tempArray[c][s][TEMPARRAY_WIDTH+3-1]; // < 17'sd0;
      absTempArray[c][s] = sign ? -tempArray[c][s] : tempArray[c][s];
      unsignedPredResidual_d[c][s] = (absTempArray[c][s] + 16'd128) >> 8;
      pResidual_d[c][s] = sign ? -$signed({1'b0, unsignedPredResidual_d[c][s]}) : {1'b0, unsignedPredResidual_d[c][s]};
    end
  end

reg signed [16:0] pResidual [2:0][15:0]; // predicted residuals, width TBD  
always @ (posedge clk)
  if (pDequant_valid)
    for (c=0; c<3; c=c+1)
      for (s=0; s<blkHeight[c]*blkWidth[c]; s=s+1)
        pResidual[c][s] <= pResidual_d[c][s];
always @ (posedge clk)
  pResidual_valid <= pDequant_valid;

// AddPredValue - add predictor back to the residue
function signed [13:0] Clip3;
  input signed [13:0] min;
  input [13:0] max;
  input signed [16:0] x;
  reg too_big;
  reg too_small;
  begin
    too_big = x > $signed({1'b0, max});
    too_small = x < min;
    case ({too_big, ~(too_big|too_small), too_small})
      3'b100: Clip3 = max;
      3'b010: Clip3 = x[13:0];
      3'b001: Clip3 = min;
      default: Clip3 = 13'sd0;
    endcase
  end
endfunction

always @ (posedge clk)
  if (pResidual_valid)
    for (c=0; c<3; c=c+1)
      for (row=0; row<blkHeight[c]; row=row+1)
        for (col=0; col<blkWidth[c]; col=col+1) begin
          pReconBlk[c][row][col] <= Clip3(minPoint[c], $signed({1'b0, maxPoint}), predBlk[c][row][col] + pResidual[c][row*blkWidth[c] + col]);
          //$display("pred+res=%d", $signed({1'b0, predBlk[c][row][col]}) + pResidual[c][row*blkWidth[c] + col]);
        end
always @ (posedge clk)
  pReconBlk_valid <= pResidual_valid;
  
  
// Pack output
generate
  for (ci=0; ci<3; ci=ci+1) begin : gen_out_comp
    for (rowi=0; rowi<2; rowi=rowi+1) begin : gen_out_rowi
      for (coli=0; coli<8; coli=coli+1) begin : gen_out_coli
        assign pReconBlk_p[(ci*8*2+rowi*8+coli)*14+:14] = pReconBlk[ci][rowi][coli];
      end
    end
  end
endgenerate

endmodule