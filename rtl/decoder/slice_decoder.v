`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module slice_decoder
#(
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_SLICE_HEIGHT        = 2560,
  parameter MAX_BPC                 = 12
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [9:0] bits_per_pixel,
  input wire [7:0] rc_init_tx_delay,
  input wire [15:0] rc_buffer_max_size,
  input wire [7:0] ssm_max_se_size,
  input wire [15:0] chunk_size,
  input wire [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height,
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [9:0] slices_per_line,
  input wire [15:0] frame_height,
  input wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] slice_num_px,
  input wire [$clog2(MAX_SLICE_HEIGHT)+16-1:0] b0,
  input wire [15:0] num_extra_mux_bits,
  input wire [31:0] rc_target_rate_threshold,
  input wire [7:0] rc_target_rate_scale,
  input wire [3:0] rc_target_rate_extra_fbls,
  input wire [7:0] rc_fullness_scale,
  input wire [23:0] rc_fullness_offset_slope,
  input wire [8+9-1:0] rcOffsetInit,
  input wire [16*8-1:0] target_rate_delta_lut_p,
  input wire [3:0] mppf_bits_per_comp_R_Y,
  input wire [3:0] mppf_bits_per_comp_G_Cb,
  input wire [3:0] mppf_bits_per_comp_B_Cr,
  input wire [3:0] mppf_bits_per_comp_Y,
  input wire [3:0] mppf_bits_per_comp_Co,
  input wire [3:0] mppf_bits_per_comp_Cg,
  input wire [3:0] chunk_adj_bits,
  input wire [3:0] maxAdjBits,
  input wire [1:0] source_color_space, // Image original color space 0: RGB, 1: YCoCg, 2: YCbCr (YCoCg is impossible)
  input wire [1:0] csc, // Color Space before CSC conversion: 0: RGB, 1: YCoCg, 2: YCbCr (RGB is impossible)
  input wire [3*2-1:0] blkHeight_p,
  input wire [3*4-1:0] blkWidth_p,
  input wire [3*5-1:0] compNumSamples_p,
  input wire [1:0] bits_per_component_coded,
  input wire [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  input wire [12:0] midPoint,
  input wire [12:0] maxPoint,
  input wire [3*14-1:0] minPoint_p,
  input wire [3*5-1:0] neighborsAboveLenAdjusted_p,
  input wire [7:0] rc_stuffing_bits,
  input wire [1:0] version_minor,
  input wire isSliceWidthMultipleOf16,
  input wire [11:0] rcStuffingBitsX9,
  input wire [8*8-1:0] max_qp_lut_p,
  input wire signed [6:0] minQp,
  input wire [15:0] rc_buffer_init_size,
  input wire [7:0] flatness_qp_very_flat_fbls,
  input wire [7:0] flatness_qp_very_flat_nfbls,
  input wire [7:0] flatness_qp_somewhat_flat_fbls,
  input wire [7:0] flatness_qp_somewhat_flat_nfbls,
  input wire [8*8-1:0] flatness_qp_lut_p,
  input wire [3*2-1:0] partitionSize_p,
  input wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] rcOffsetThreshold,
  input wire [39:0] slice_num_bits,
  input wire [4:0] OffsetAtBeginOfSlice,
  input wire [34:0] sliceSizeInRamInBytes,
  
  input wire [255:0] in_data,
  input wire in_sof,
  input wire in_valid,
  input wire data_in_is_pps,
  
  input wire flow_stop,
  
  output wire [4*3*14-1:0] pixs_out, // 4 pixels: {p3c2, p3c1, p3c0, p2c2, p2c1, p2c0, p1c2, p1c1, p1c0, p0c2, p0c1, p0c0}
  output wire pixs_out_sof,
  output wire pixs_out_valid
);

wire start_decode;
wire soc;
wire eoc;
wire sos;
wire eos;
wire early_eos;
wire eof;
wire eob;
wire fbls;
wire resetLeft;
wire isEvenChunk;
wire substream0_parsed;
wire isFirstParse; // Parse Subsstream 0 one block-time ahead of other subsreams
wire isFirstBlock; // First time in slice substreams 1 2 3 are parsed
wire isLastBlock; // Last time in slice substreams 1 2 3 are parsed
wire nextBlockIsFls;
wire neighborsAbove_rd_en;
wire block_push;
wire [1:0] sos_fsm;
wire parse_substreams;
wire substreams123_parsed;
wire sof;

block_position
#(
  .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH),
  .MAX_SLICE_HEIGHT        (MAX_SLICE_HEIGHT)
)
block_position_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .slice_width                  (slice_width),
  .slice_height                 (slice_height),
  .frame_height                 (frame_height),
                                
  .start_decode                 (start_decode),
  .in_valid                     (in_valid),
  .in_sof                       (in_sof),
  .parse_substreams             (parse_substreams),
  .substream0_parsed            (substream0_parsed),
  .substreams123_parsed         (substreams123_parsed),
  .sof                          (sof),
  .soc                          (soc),
  .eoc                          (eoc),
  .sos                          (sos),
  .eos                          (eos),
  .early_eos                    (early_eos),
  .eof                          (eof),
  .eob                          (eob),
  .fbls                         (fbls),
  .isFirstParse                 (isFirstParse),
  .isFirstBlock                 (isFirstBlock),
  .isLastBlock                  (isLastBlock),
  .nextBlockIsFls               (nextBlockIsFls),
  .neighborsAbove_rd_en         (neighborsAbove_rd_en),
  .block_push                   (block_push),
  .resetLeft                    (resetLeft),
  .isEvenChunk                  (isEvenChunk)
);

wire [9*4-1:0] size_to_remove_p;
wire size_to_remove_valid;
parameter MAX_FUNNEL_SHIFTER_SIZE = 2*248 - 1;
wire [4*MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_p;
wire [3:0] fs_ready;
wire ssm_sof;
wire sos_for_rc;

substream_demux
#(
  .MAX_FUNNEL_SHIFTER_SIZE      (MAX_FUNNEL_SHIFTER_SIZE)
)
substream_demux_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
                                
  .bits_per_pixel               (bits_per_pixel),
  .rc_init_tx_delay             (rc_init_tx_delay),
  .rc_buffer_max_size           (rc_buffer_max_size),
  .ssm_max_se_size              (ssm_max_se_size),
  .slice_num_bits               (slice_num_bits),
  .num_extra_mux_bits           (num_extra_mux_bits),
  .chunk_size                   (chunk_size),
  .OffsetAtBeginOfSlice         (OffsetAtBeginOfSlice),
  .sliceSizeInRamInBytes        (sliceSizeInRamInBytes),
  .slices_per_line              (slices_per_line),

  .in_data                      (in_data),
  .in_sof                       (in_sof),
  .sos                          (sos),
  .eos                          (eos),
  .early_eos                    (early_eos),
  .eof                          (eof),
  .isLastBlock                  (isLastBlock),
  .ssm_sof                      (ssm_sof),
  .in_valid                     (in_valid),
  .data_in_is_pps               (data_in_is_pps),
  
  .start_decode                 (start_decode),
  .disable_rcb_rd               (flow_stop),
  .sos_for_rc                   (sos_for_rc),
  .sos_fsm                      (sos_fsm),
  
  .substream0_parsed            (substream0_parsed),
  .data_to_be_parsed_p          (data_to_be_parsed_p),
  .fs_ready                     (fs_ready),
  .size_to_remove_p             (size_to_remove_p),
  .size_to_remove_valid         (size_to_remove_valid)
);

wire [2:0] blockMode;
wire [2:0] prevBlockMode;
wire flatnessFlag;
wire [1:0] flatnessType;
wire enableUnderflowPrevention;
wire [16*3*16-1:0] pQuant_p;
wire pQuant_valid;
wire signed [7:0] masterQp;
wire masterQp_valid;
wire [12:0] blockBits;
wire blockBits_valid;
wire [12:0] prevBlockBitsWithoutPadding;
wire prevBlockBitsWithoutPadding_valid;
wire [2:0] bestIntraPredIdx;
wire [7*4-1:0] bpv2x2_p;
wire [7*4*2-1:0] bpv2x1_p;
wire [3:0] bpvTable;
wire [1:0] blockCsc;
wire [3:0] blockStepSize;
wire mppfIndex;
wire mpp_ctrl_valid;
wire stall_pull;

syntax_parser
#(
  .MAX_FUNNEL_SHIFTER_SIZE      (MAX_FUNNEL_SHIFTER_SIZE)
)
syntax_parser_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .compNumSamples_p             (compNumSamples_p),
  .chroma_format                (chroma_format),
  .rc_stuffing_bits             (rc_stuffing_bits),
  .rcStuffingBitsX9             (rcStuffingBitsX9),
  .source_color_space           (source_color_space),
  .bits_per_component_coded     (bits_per_component_coded),
  .mppf_bits_per_comp_R_Y       (mppf_bits_per_comp_R_Y ),
  .mppf_bits_per_comp_G_Cb      (mppf_bits_per_comp_G_Cb), 
  .mppf_bits_per_comp_B_Cr      (mppf_bits_per_comp_B_Cr), 
  .mppf_bits_per_comp_Y         (mppf_bits_per_comp_Y),
  .mppf_bits_per_comp_Co        (mppf_bits_per_comp_Co),
  .mppf_bits_per_comp_Cg        (mppf_bits_per_comp_Cg),
                                
  .data_to_be_parsed_p          (data_to_be_parsed_p),
  .nextBlockIsFls               (nextBlockIsFls),
  .isFirstParse                 (isFirstParse),
  .isLastBlock                  (isLastBlock),
  .sos                          (sos),
  .ssm_sof                      (ssm_sof),
  .sos_fsm                      (sos_fsm),
  .eos                          (eos),
 
  .fs_ready                     (fs_ready),
  .size_to_remove_p             (size_to_remove_p),
  .size_to_remove_valid         (size_to_remove_valid),
  
  .enableUnderflowPrevention    (enableUnderflowPrevention),
  
  .blockMode                    (blockMode),
  .prevBlockMode_r              (prevBlockMode),
  .flatnessFlag_r               (flatnessFlag),
  .flatnessType_r               (flatnessType),
  .nextBlockBestIntraPredIdx_r  (bestIntraPredIdx),
  .bpv2x2_p                     (bpv2x2_p),
  .bpv2x1_p                     (bpv2x1_p),
  .bpvTable                     (bpvTable),
  .substream0_parsed            (substream0_parsed),
  .substreams123_parsed         (substreams123_parsed),
  .stall_pull                   (stall_pull),
  .parse_substreams             (parse_substreams),
  .pQuant_r_p                   (pQuant_p),
  .pQuant_r_valid               (pQuant_valid),
  .blockBits                    (blockBits),
  .blockBits_valid              (blockBits_valid),
  .prevBlockBitsWithoutPadding  (prevBlockBitsWithoutPadding),
  .prevBlockBitsWithoutPadding_valid (prevBlockBitsWithoutPadding_valid),
  .blockCsc_r                   (blockCsc),
  .blockStepSize_r              (blockStepSize),
  .mppfIndex_r                  (mppfIndex),
  .mpp_ctrl_valid               (mpp_ctrl_valid)
);

wire pReconBlk_valid;
wire [2*8*3*14-1:0] pReconBlk_p;
wire pixels_buf_rd_req;
wire [16*3*14-1:0] pixelsAboveForTrans_p;
wire [33*3*14-1:0] pixelsAboveForBp_p;
wire decoding_proc_rd_valid;
wire [8:0] maxQp;

decoding_processor
#(
  .MAX_SLICE_WIDTH              (MAX_SLICE_WIDTH),
  .MAX_BPC                      (MAX_BPC)
)
decoding_processor_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
                                
  .fbls                         (fbls),
  .sos                          (sos),
  .eos                          (eos),
  .eob                          (eob),
  .soc                          (soc),
  .eoc                          (eoc),
  .resetLeft                    (resetLeft),
  .slice_width                  (slice_width),
  
  .substreams123_parsed         (substreams123_parsed),
  .substream0_parsed            (substream0_parsed),
  .stall_pull                   (stall_pull),
  .parse_substreams             (parse_substreams),
  .neighborsAbove_rd_en         (neighborsAbove_rd_en),
  .block_push                   (block_push),
  .blockMode                    (blockMode),
  .prevBlockMode                (prevBlockMode),
  .bestIntraPredIdx             (bestIntraPredIdx),
  .bpv2x1_sel_p                 (bpv2x1_p),
  .bpv2x2_sel_p                 (bpv2x2_p),
  .bpvTable                     (bpvTable),
  .underflowPreventionMode      (enableUnderflowPrevention),
  .csc                          (csc),
  .blkHeight_p                  (blkHeight_p),
  .blkWidth_p                   (blkWidth_p),
  .bits_per_component_coded     (bits_per_component_coded),
  .chroma_format                (chroma_format),
  .version_minor                (version_minor),
  .midPoint                     (midPoint),
  .maxPoint                     (maxPoint),
  .minPoint_p                   (minPoint_p),
  .neighborsAboveLenAdjusted_p  (neighborsAboveLenAdjusted_p),
  .partitionSize_p              (partitionSize_p),
  .mppf_bits_per_comp_R_Y       (mppf_bits_per_comp_R_Y ),
  .mppf_bits_per_comp_G_Cb      (mppf_bits_per_comp_G_Cb), 
  .mppf_bits_per_comp_B_Cr      (mppf_bits_per_comp_B_Cr), 
  .mppf_bits_per_comp_Y         (mppf_bits_per_comp_Y),
  .mppf_bits_per_comp_Co        (mppf_bits_per_comp_Co),
  .mppf_bits_per_comp_Cg        (mppf_bits_per_comp_Cg),
  
  .pQuant_p                     (pQuant_p),
  .pQuant_valid                 (pQuant_valid),
  .masterQp                     (masterQp),
  .masterQp_valid               (masterQp_valid),
  .minQp                        (minQp),
  .maxQp                        (maxQp),
  .blockCsc                     (blockCsc),
  .blockStepSize                (blockStepSize),
  .mppfIndex                    (mppfIndex),
  .mpp_ctrl_valid               (mpp_ctrl_valid),
  
  .pReconBlk_valid              (pReconBlk_valid),
  .pReconBlk_p                  (pReconBlk_p)
);

wire cscBlk_valid;
wire [2*8*3*14-1:0] cscBlk_p;

decoder_csc 
#(
  .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH),
  .MAX_SLICE_HEIGHT        (MAX_SLICE_HEIGHT)
)
decoder_csc_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  .csc                          (csc),
  .slice_width                  (slice_width),
  .maxPoint                     (maxPoint),
  .pReconBlk_valid              (pReconBlk_valid),
  .pReconBlk_p                  (pReconBlk_p),
  .cscBlk_valid                 (cscBlk_valid),
  .cscBlk_p                     (cscBlk_p)
);

dec_rate_control
#(
  .MAX_SLICE_HEIGHT        (MAX_SLICE_HEIGHT),
  .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH)
)
dec_rate_control_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .rc_buffer_max_size           (rc_buffer_max_size),
  .chunk_size                   (chunk_size),
  .slice_height                 (slice_height),
  .slice_width                  (slice_width),
  .slice_num_px                 (slice_num_px),
  .b0                           (b0),
  .num_extra_mux_bits           (num_extra_mux_bits),
  .rc_target_rate_threshold     (rc_target_rate_threshold),
  .rc_target_rate_scale         (rc_target_rate_scale),
  .rc_target_rate_extra_fbls    (rc_target_rate_extra_fbls),
  .rc_fullness_scale            (rc_fullness_scale),
  .rc_init_tx_delay             (rc_init_tx_delay),
  .rc_fullness_offset_slope     (rc_fullness_offset_slope),
  .rcOffsetInitAtSos            (rcOffsetInit),
  .target_rate_delta_lut_p      (target_rate_delta_lut_p),
  .chunk_adj_bits               (chunk_adj_bits),
  .maxAdjBits                   (maxAdjBits),
  .bits_per_pixel               (bits_per_pixel),
  .isSliceWidthMultipleOf16     (isSliceWidthMultipleOf16),
  .chroma_format                (chroma_format),
  .max_qp_lut_p                 (max_qp_lut_p),
  .rc_buffer_init_size          (rc_buffer_init_size),
  .minQp                        (minQp),
  .flatness_qp_very_flat_fbls   (flatness_qp_very_flat_fbls),
  .flatness_qp_very_flat_nfbls  (flatness_qp_very_flat_nfbls),
  .flatness_qp_somewhat_flat_fbls(flatness_qp_somewhat_flat_fbls),
  .flatness_qp_somewhat_flat_nfbls(flatness_qp_somewhat_flat_nfbls),
  .flatness_qp_lut_p            (flatness_qp_lut_p),
  .rcOffsetThreshold            (rcOffsetThreshold),
  
  .sof                          (sof),
  .sos                          (sos),
  .eoc                          (eoc),
  .substreams123_parsed         (substreams123_parsed),
  .isFirstBlock                 (isFirstBlock),
  .isLastBlock                  (isLastBlock),
  .fbls                         (fbls),
  .isEvenChunk                  (isEvenChunk),
  .sos_for_rc                   (sos_for_rc),
  .sos_fsm                      (sos_fsm),
  
  .blockBits                    (blockBits),
  .blockBits_valid              (blockBits_valid),
  .prevBlockBitsWithoutPadding  (prevBlockBitsWithoutPadding),
  .prevBlockBitsWithoutPadding_valid (prevBlockBitsWithoutPadding_valid),
  
  .flatnessFlag                 (flatnessFlag),
  .flatnessType                 (flatnessType),  
  
  .qp                           (masterQp),
  .qp_valid                     (masterQp_valid),
  .maxQp                        (maxQp),
  .enableUnderflowPrevention    (enableUnderflowPrevention)
);

output_buffers
#(
  .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH)
)
output_buffers_u
(
  .clk                          (clk),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .sof                          (sof),
  .slice_width                  (slice_width),
  .chroma_format                (chroma_format),

  .cscBlk_valid                 (cscBlk_valid),
  .cscBlk_p                     (cscBlk_p),
  
  .out_data_valid               (pixs_out_valid),
  .out_sof                      (pixs_out_sof),
  .out_data_p                   (pixs_out)

);



endmodule
  
