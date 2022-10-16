
`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module decoding_processor
#(
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_BPC                 = 12
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire fbls,
  input wire sos,
  input wire eos,
  input wire eob, // end of block
  input wire soc,
  input wire eoc,
  input wire resetLeft,
  
  input wire substream0_parsed,
  input wire substreams123_parsed,
  input wire parse_substreams,
  output wire stall_pull, // indication not to pull new data from pixels_buf
  input wire neighborsAbove_rd_en,
  input wire block_push,

  input wire [2:0] blockMode,
  input wire [2:0] prevBlockMode,
  input wire [2:0] bestIntraPredIdx,
  input wire [7*4-1:0] bpv2x2_sel_p,
  input wire [7*4*2-1:0] bpv2x1_sel_p,

  input wire [3:0] bpvTable,
  input wire underflowPreventionMode,
  input wire [1:0] csc, // decoding color space 0: RGB, 1: YCoCg, 2: YCbCr (RGB impossible)
  input wire [3*2-1:0] blkHeight_p,
  input wire [3*4-1:0] blkWidth_p,
  input wire [1:0] bits_per_component_coded,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [1:0] version_minor,
  input wire [12:0] midPoint,
  input wire [12:0] maxPoint,
  input wire [3*14-1:0] minPoint_p,
  input wire [3*5-1:0] neighborsAboveLenAdjusted_p,
  input wire [16*3*16-1:0] pQuant_p,
  input wire pQuant_valid,
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [3*2-1:0] partitionSize_p,

  input wire signed [7:0] masterQp,
  input wire masterQp_valid,
  input wire [6:0] minQp,
  input wire [8:0] maxQp,
  input wire [1:0] blockCsc,
  input wire [3:0] blockStepSize,
  input wire mppfIndex,
  input wire mpp_ctrl_valid,
    
  output wire pReconBlk_valid,
  output reg [2*8*3*14-1:0] pReconBlk_p

);

wire [3*7-1:0] qp_p;
wire qp_valid;

wire tm_pReconBlk_valid;
wire [2*8*3*14-1:0] tm_pReconBlk_p;
wire first_header_of_slice;
assign first_header_of_slice = substream0_parsed & sos;

masterQp2qp masterQp2qpForTransformMode_u
(
  .bits_per_component_coded     (bits_per_component_coded),
  .csc                          (csc),
  .version_minor                (version_minor),
  
  .masterQp                     (masterQp),
  .masterQp_valid               (masterQp_valid | first_header_of_slice),
  
  .qp_p                         (qp_p),
  .qp_valid                     (qp_valid)
);

wire signed [7:0] masterQpForBp;
wire [3*7-1:0] qpForBp_p;

masterQp2qp masterQp2qpForBp_u
(
  .bits_per_component_coded     (bits_per_component_coded),
  .csc                          (csc),
  .version_minor                (version_minor),
  
  .masterQp                     (masterQpForBp),
  .masterQp_valid               (masterQp_valid | first_header_of_slice),
  
  .qp_p                         (qpForBp_p),
  .qp_valid                     () // same one as for masterQp2qpForTransformMode_u
);



wire [2*8*3*14-1:0] pReconBlkAbove_p;
wire pReconBlkAbove_valid;
wire pixels_buf_rd_valid;
wire [16*3*14-1:0] pixelsAboveForTrans_p;

transform_mode transform_mode_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
                                
  .fbls                         (fbls),
  .resetLeft                    (resetLeft),
  .soc                          (soc),
  .eoc                          (eoc),
  .eob                          (eob),
  .sos                          (sos),
  
  .bestIntraPredIdx             (bestIntraPredIdx),
  .underflowPreventionMode      (underflowPreventionMode),
  .csc                          (csc),
  .blkHeight_p                  (blkHeight_p),
  .blkWidth_p                   (blkWidth_p),
  .bits_per_component_coded     (bits_per_component_coded),
  .chroma_format                (chroma_format),
  .minPoint_p                   (minPoint_p),
  .midPoint                     (midPoint),
  .maxPoint                     (maxPoint),
  .neighborsAboveLenAdjusted_p  (neighborsAboveLenAdjusted_p),
  .pQuant_p                     (pQuant_p),
  .pQuant_valid                 (pQuant_valid),
  .neighborsAbove_rd_p          (pixelsAboveForTrans_p),
  .neighborsAbove_valid         (pixels_buf_rd_valid),
  .qp_p                         (qp_p),
  .qp_valid                     (qp_valid),
  .pReconBlk_valid              (tm_pReconBlk_valid),
  .pReconBlk_p                  (tm_pReconBlk_p)
);

wire bp_pReconBlk_valid;
wire [2*8*3*14-1:0] bp_pReconBlk_p;
wire [33*3*14-1:0] pixelsAboveForBp_p;

bp_mode bp_mode_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
                                
  .partitionSize_p              (partitionSize_p),
  .blkWidth_p                   (blkWidth_p),
  .blkHeight_p                  (blkHeight_p),
  .chroma_format                (chroma_format),
  .csc                          (csc),
  .minPoint_p                   (minPoint_p),
  .midPoint                     (midPoint),
  .maxPoint                     (maxPoint),
  .bits_per_component_coded     (bits_per_component_coded),
  
  .substreams123_parsed         (substreams123_parsed),
  .sos                          (sos),
  .fbls                         (fbls),
  .masterQp                     (masterQp),
  .masterQp_valid               (masterQp_valid | first_header_of_slice),
  .minQp                        (minQp),
  .maxQp                        (maxQp),
  
  .pReconLeftBlk_p              (pReconBlk_p),
  .pReconLeftBlk_valid          (pReconBlk_valid),
  
  .neighborsAbove_rd_p          (pixelsAboveForBp_p),
  .neighborsAbove_valid         (pixels_buf_rd_valid),
  
  .blockMode                    (blockMode),
  .bpv2x1_sel_p                 (bpv2x1_sel_p),
  .bpv2x2_sel_p                 (bpv2x2_sel_p),
  .bpvTable                     (bpvTable),
  
  .pQuant_p                     (pQuant_p),
  .pQuant_valid                 (pQuant_valid),
  
  .masterQpForBp                (masterQpForBp),
  .qp_p                         (qpForBp_p),
  .qp_valid                     (qp_valid),

  .pReconBlk_valid              (bp_pReconBlk_valid),
  .pReconBlk_p                  (bp_pReconBlk_p)

  
);

wire mpp_pReconBlk_valid;
wire [2*8*3*14-1:0] mpp_pReconBlk_p;
wire [8*3*14-1:0] pixelsAboveForMpp_p;

mpp_mode mpp_mode_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .chroma_format                (chroma_format),
  .csc                          (csc),
  .bits_per_component_coded     (bits_per_component_coded),
  .midPoint                     (midPoint),
  .maxPoint                     (maxPoint),

  .sos                          (sos),
  .fbls                         (fbls),
  
  .blockMode                    (blockMode),
  .blockCsc                     (blockCsc),
  .blockStepSize                (blockStepSize),
  .mppfIndex                    (mppfIndex),
  .mpp_ctrl_valid               (mpp_ctrl_valid),
  
  .pQuant_p                     (pQuant_p),
  .pQuant_valid                 (pQuant_valid),

  .pReconLeftBlk_p              (pReconBlk_p),
  .pReconLeftBlk_valid          (pReconBlk_valid),
  .pReconAboveBlk_p             (pixelsAboveForMpp_p),
  .pReconAboveBlk_valid         (pixels_buf_rd_valid),

  .pReconBlk_valid              (mpp_pReconBlk_valid),
  .pReconBlk_p                  (mpp_pReconBlk_p)

);


// Mux between all modes
// Table 4-80 in spec
parameter MODE_TRANSFORM = 3'd0;
parameter MODE_BP        = 3'd1;
parameter MODE_MPP       = 3'd2;
parameter MODE_MPPF      = 3'd3;
parameter MODE_BP_SKIP   = 3'd4;
always @ (*)
  case (prevBlockMode)
    MODE_TRANSFORM:        pReconBlk_p = tm_pReconBlk_p;
    MODE_BP, MODE_BP_SKIP: pReconBlk_p = bp_pReconBlk_p;
    MODE_MPP, MODE_MPPF  : pReconBlk_p = mpp_pReconBlk_p;
    default:               pReconBlk_p = tm_pReconBlk_p;
  endcase
assign pReconBlk_valid = tm_pReconBlk_valid; // Assume that all the valid come at the same clock cycle

integer comp;
integer c, r;
reg signed [13:0] pReconBlk[2:0][1:0][7:0];
always @ (*)
  for(comp=0; comp<3; comp=comp+1)             
    for (r=0; r<2; r=r+1)
      for (c=0; c<8; c=c+1)
        pReconBlk[comp][r][c] = pReconBlk_p[(comp*8*2+r*8+c)*14+:14];


pixels_buf
#(
  .MAX_SLICE_WIDTH             (MAX_SLICE_WIDTH)
)
pixels_buf_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  .csc                          (csc),
  .sos                          (sos),
  .eos                          (eos),
  .slice_width                  (slice_width),
  .maxPoint                     (maxPoint),
  .pReconBlk_valid              (pReconBlk_valid),
  .pReconBlk_p                  (pReconBlk_p),
  .parse_substreams             (parse_substreams),
  .stall_pull                   (stall_pull),
  .decoding_proc_rd_req         (neighborsAbove_rd_en),
  .block_push                   (block_push),
  .pixelsAboveForTrans_p        (pixelsAboveForTrans_p),
  .pixelsAboveForBp_p           (pixelsAboveForBp_p),
  .pixelsAboveForMpp_p          (pixelsAboveForMpp_p),
  .decoding_proc_rd_valid       (pixels_buf_rd_valid)
);

  
endmodule
