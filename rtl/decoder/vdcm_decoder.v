`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module vdcm_decoder
#(
  parameter MAX_NBR_SLICES          = 2,
  parameter MAX_BPC                 = 16,   // Max bits-per-color internally used by the DSC Decoder
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_SLICE_HEIGHT        = 2560
)
(
  input wire clk_core,
  input wire clk_in_int,
  input wire clk_out_int,
  input wire rst_n,
  input wire flush,
  
  input wire [255:0] in_data,
  input wire in_valid,
  input wire in_sof,              // Start of frame
  input wire in_data_is_pps, // in_data contains PPS before in_sof
  
  output wire [4*3*14-1:0] pixs_out,
  output wire pixs_out_eof,
  output wire [3:0] pixs_out_valid
);

wire sync_buf_valid;
wire [255:0] sync_buf_data;
wire sync_buf_sof;
wire sync_buf_data_is_pps;

// Sync buffer
// -----------
in_sync_buf 
#(
  .NUMBER_OF_LINES          (4),
  .DATA_WIDTH               (256)
)
input_sync_buf_u
(
  .clk_wr                       (clk_in_int),
  .clk_rd                       (clk_core),
  .rst_n                        (rst_n),
  .flush                        (flush),
  .in_data                      (in_data),
  .in_sof                       (in_sof),
  .in_valid                     (in_valid),
  .in_data_is_pps               (in_data_is_pps),
  .out_data                     (sync_buf_data),
  .out_sof                      (sync_buf_sof),
  .out_data_is_pps              (sync_buf_data_is_pps),
  .out_valid                    (sync_buf_valid)
  
);

wire [1:0] version_minor;
wire [15:0] frame_width;
wire [15:0] frame_height;
wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width;
wire [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height;
wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] slice_num_px;
wire [9:0] bits_per_pixel;
wire [1:0] bits_per_component_coded;
wire [1:0] source_color_space; // Image original color space 0: RGB, 1: YCoCg, 2: YCbCr (YCoCg is impossible)
wire [1:0] chroma_format;
wire [15:0] chunk_size;
wire [15:0] rc_buffer_init_size;
wire [7:0] rc_stuffing_bits;
wire [7:0] rc_init_tx_delay;
wire [15:0] rc_buffer_max_size;
wire [31:0] rc_target_rate_threshold;
wire [7:0] rc_target_rate_scale;
wire [7:0] rc_fullness_scale;
wire [15:0] rc_fullness_offset_threshold;
wire [23:0] rc_fullness_offset_slope;
wire [3:0] rc_target_rate_extra_fbls;
wire [7:0] flatness_qp_very_flat_fbls;
wire [7:0] flatness_qp_very_flat_nfbls;
wire [7:0] flatness_qp_somewhat_flat_fbls;
wire [7:0] flatness_qp_somewhat_flat_nfbls;
wire [8*8-1:0] flatness_qp_lut_p;
wire [8*8-1:0] max_qp_lut_p;
wire [16*8-1:0] target_rate_delta_lut_p;
wire [3:0] mppf_bits_per_comp_R_Y;
wire [3:0] mppf_bits_per_comp_G_Cb;
wire [3:0] mppf_bits_per_comp_B_Cr;
wire [3:0] mppf_bits_per_comp_Y;
wire [3:0] mppf_bits_per_comp_Co;
wire [3:0] mppf_bits_per_comp_Cg;
wire [7:0] ssm_max_se_size;
wire [39:0] slice_num_bits;
wire [3:0] chunk_adj_bits;
wire [15:0] num_extra_mux_bits;
wire [9:0] slices_per_line;
wire [2:0] slice_pad_x;
wire [3:0] eoc_valid_pixs;
wire [3:0] mpp_min_step_size;
wire pps_valid;
wire data_in_is_pps;

wire [$clog2(MAX_SLICE_WIDTH)-1:0] origSliceWidth;
wire [$clog2(MAX_SLICE_HEIGHT)+16-1:0] b0;
wire [8+9-1:0] rcOffsetInit;
wire [3:0] maxAdjBits;
wire [1:0] csc; // Color Space before CSC conversion: 1: YCoCg, 2: YCbCr
wire [12:0] midPoint;
wire [12:0] maxPoint;
wire [3*14-1:0] minPoint_p;
wire [3*2-1:0] blkHeight_p;
wire [3*4-1:0] blkWidth_p;
wire [3*5-1:0] neighborsAboveLenAdjusted_p;
wire [3*5-1:0] compNumSamples_p;
wire isSliceWidthMultipleOf16;
wire [11:0] rcStuffingBitsX9;
wire signed [6:0] minQp;
wire [3*2-1:0] partitionSize_p;
wire [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] rcOffsetThreshold;
wire [4:0] OffsetAtBeginOfSlice;
wire [34:0] sliceSizeInRamInBytes;

pps_regs 
#(
  .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH),
  .MAX_SLICE_HEIGHT        (MAX_SLICE_HEIGHT)
)
pps_regs_u
(
  .clk                            (clk_core),
  .rst_n                          (rst_n),
  .flush                          (flush),
                                  
  .in_data                        (sync_buf_data),
  .in_valid                       (sync_buf_valid),
  .data_in_is_pps                 (sync_buf_data_is_pps),
                                
  .version_minor                  (version_minor),
  .frame_width                    (frame_width),
  .frame_height                   (frame_height),
  .slice_width                    (slice_width),
  .slice_height                   (slice_height),
  .slice_num_px                   (slice_num_px),
  .bits_per_pixel                 (bits_per_pixel),
  .bits_per_component_coded       (bits_per_component_coded),
  .source_color_space             (source_color_space),
  .chroma_format                  (chroma_format),
  .chunk_size                     (chunk_size),
  .rc_buffer_init_size            (rc_buffer_init_size),
  .rc_stuffing_bits               (rc_stuffing_bits),
  .rc_init_tx_delay               (rc_init_tx_delay),
  .rc_buffer_max_size             (rc_buffer_max_size),
  .rc_target_rate_threshold       (rc_target_rate_threshold),
  .rc_target_rate_scale           (rc_target_rate_scale),
  .rc_fullness_scale              (rc_fullness_scale),
  .rc_fullness_offset_threshold   (rc_fullness_offset_threshold),
  .rc_fullness_offset_slope       (rc_fullness_offset_slope),
  .rc_target_rate_extra_fbls      (rc_target_rate_extra_fbls),
  .flatness_qp_very_flat_fbls     (flatness_qp_very_flat_fbls),
  .flatness_qp_very_flat_nfbls    (flatness_qp_very_flat_nfbls),
  .flatness_qp_somewhat_flat_fbls (flatness_qp_somewhat_flat_fbls),
  .flatness_qp_somewhat_flat_nfbls(flatness_qp_somewhat_flat_nfbls),
  .flatness_qp_lut_p              (flatness_qp_lut_p),
  .max_qp_lut_p                   (max_qp_lut_p),
  .target_rate_delta_lut_p        (target_rate_delta_lut_p),
  .mppf_bits_per_comp_R_Y         (mppf_bits_per_comp_R_Y ),
  .mppf_bits_per_comp_G_Cb        (mppf_bits_per_comp_G_Cb), 
  .mppf_bits_per_comp_B_Cr        (mppf_bits_per_comp_B_Cr), 
  .mppf_bits_per_comp_Y           (mppf_bits_per_comp_Y),
  .mppf_bits_per_comp_Co          (mppf_bits_per_comp_Co),
  .mppf_bits_per_comp_Cg          (mppf_bits_per_comp_Cg),
  .ssm_max_se_size                (ssm_max_se_size),
  .slice_num_bits                 (slice_num_bits),
  .chunk_adj_bits                 (chunk_adj_bits),
  .num_extra_mux_bits             (num_extra_mux_bits),
  .slices_per_line                (slices_per_line),
  .slice_pad_x                    (slice_pad_x),
  .eoc_valid_pixs                 (eoc_valid_pixs),
  .mpp_min_step_size              (mpp_min_step_size),
  
  
  .origSliceWidth                 (origSliceWidth),
  .b0                             (b0),
  .rcOffsetInit                   (rcOffsetInit),
  .maxAdjBits                     (maxAdjBits),
  .csc                            (csc),
  .blkHeight_p                    (blkHeight_p),
  .blkWidth_p                     (blkWidth_p),
  .compNumSamples_p               (compNumSamples_p),
  .midPoint                       (midPoint),
  .maxPoint                       (maxPoint),
  .minPoint_p                     (minPoint_p),
  .neighborsAboveLenAdjusted_p    (neighborsAboveLenAdjusted_p),
  .isSliceWidthMultipleOf16       (isSliceWidthMultipleOf16),
  .rcStuffingBitsX9               (rcStuffingBitsX9),
  .minQp                          (minQp),
  .partitionSize_p                (partitionSize_p),
  .rcOffsetThreshold              (rcOffsetThreshold),
  .OffsetAtBeginOfSlice           (OffsetAtBeginOfSlice),
  .sliceSizeInRamInBytes          (sliceSizeInRamInBytes),
  
  .pps_valid                      (pps_valid)
);

wire [MAX_NBR_SLICES-1:0] slice_demux_valid;
wire [MAX_NBR_SLICES*256-1:0] slice_demux_data_p;
wire [MAX_NBR_SLICES-1:0] slice_demux_sof;
wire [MAX_NBR_SLICES-1:0] slice_demux_data_out_is_pps;

// Slice Demux
// -----------
slice_demux
#(
  .MAX_NBR_SLICES               (MAX_NBR_SLICES),
  .MAX_SLICE_WIDTH              (MAX_SLICE_WIDTH)
)
slice_demux_u
(
  .clk                          (clk_core),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .slices_per_line              (slices_per_line),
  .chunk_size                   (chunk_size),
  
  .in_data                      (sync_buf_data),
  .in_sof                       (sync_buf_sof),
  .in_valid                     (sync_buf_valid),
  .data_in_is_pps               (sync_buf_data_is_pps),
  
  .out_data_p                   (slice_demux_data_p),
  .out_sof                      (slice_demux_sof),
  .out_valid                    (slice_demux_valid),
  .data_out_is_pps              (slice_demux_data_out_is_pps)

);

// Slice decoders
// -------------
wire [4*3*14-1:0] slice_pixs_out [MAX_NBR_SLICES-1:0];
wire [MAX_NBR_SLICES-1:0] slice_pixs_out_valid;
wire [MAX_NBR_SLICES-1:0] slice_pixs_out_sof;
wire [MAX_NBR_SLICES*4*3*14-1:0] slice_pixs_out_p;
wire [MAX_NBR_SLICES-1:0] out_fifo_almost_full;
genvar s;
generate
  for (s=0; s<MAX_NBR_SLICES; s=s+1) begin : gen_slice_decoder
    slice_decoder
    #(
      .MAX_SLICE_WIDTH         (MAX_SLICE_WIDTH),
      .MAX_SLICE_HEIGHT        (MAX_SLICE_HEIGHT),
      .MAX_BPC                 (MAX_BPC)
    )
    slice_decoder_u
    (
      .clk                          (clk_core),
      .rst_n                        (rst_n),
      .flush                        (flush),
                                    
      .bits_per_pixel                 (bits_per_pixel),
      .rc_init_tx_delay               (rc_init_tx_delay),
      .rc_buffer_max_size             (rc_buffer_max_size),
      .ssm_max_se_size                (ssm_max_se_size),
      .chunk_size                     (chunk_size),
      .slice_width                    (slice_width),
      .slice_height                   (slice_height),
      .slices_per_line                (slices_per_line),
      .frame_height                   (frame_height),
      .slice_num_px                   (slice_num_px),
      .slice_num_bits                 (slice_num_bits),
      .b0                             (b0),
      .num_extra_mux_bits             (num_extra_mux_bits),
      .rc_target_rate_threshold       (rc_target_rate_threshold),
      .rc_target_rate_scale           (rc_target_rate_scale),
      .rc_target_rate_extra_fbls      (rc_target_rate_extra_fbls),
      .rc_fullness_scale              (rc_fullness_scale),
      .rc_fullness_offset_slope       (rc_fullness_offset_slope),
      .rcOffsetInit                   (rcOffsetInit), 
      .target_rate_delta_lut_p        (target_rate_delta_lut_p),
      .mppf_bits_per_comp_R_Y         (mppf_bits_per_comp_R_Y ),
      .mppf_bits_per_comp_G_Cb        (mppf_bits_per_comp_G_Cb), 
      .mppf_bits_per_comp_B_Cr        (mppf_bits_per_comp_B_Cr), 
      .mppf_bits_per_comp_Y           (mppf_bits_per_comp_Y),
      .mppf_bits_per_comp_Co          (mppf_bits_per_comp_Co),
      .mppf_bits_per_comp_Cg          (mppf_bits_per_comp_Cg),
      .chunk_adj_bits                 (chunk_adj_bits),
      .maxAdjBits                     (maxAdjBits), 
      .csc                            (csc),
      .blkHeight_p                    (blkHeight_p),
      .blkWidth_p                     (blkWidth_p),
      .compNumSamples_p               (compNumSamples_p),
      .bits_per_component_coded       (bits_per_component_coded),
      .chroma_format                  (chroma_format),
      .midPoint                       (midPoint),
      .maxPoint                       (maxPoint),
      .minPoint_p                     (minPoint_p),
      .neighborsAboveLenAdjusted_p    (neighborsAboveLenAdjusted_p),
      .rc_stuffing_bits               (rc_stuffing_bits),
      .version_minor                  (version_minor),
      .isSliceWidthMultipleOf16       (isSliceWidthMultipleOf16),
      .rcStuffingBitsX9               (rcStuffingBitsX9),
      .max_qp_lut_p                   (max_qp_lut_p),
      .minQp                          (minQp),
      .rc_buffer_init_size            (rc_buffer_init_size),
      .flatness_qp_very_flat_fbls     (flatness_qp_very_flat_fbls),
      .flatness_qp_very_flat_nfbls    (flatness_qp_very_flat_nfbls),
      .flatness_qp_somewhat_flat_fbls (flatness_qp_somewhat_flat_fbls),
      .flatness_qp_somewhat_flat_nfbls(flatness_qp_somewhat_flat_nfbls),
      .flatness_qp_lut_p              (flatness_qp_lut_p),
      .partitionSize_p                (partitionSize_p),
      .rcOffsetThreshold              (rcOffsetThreshold),
      .OffsetAtBeginOfSlice           (OffsetAtBeginOfSlice),
      .sliceSizeInRamInBytes          (sliceSizeInRamInBytes),
      .source_color_space             (source_color_space),
      
      .in_data                        (slice_demux_data_p[s*256+:256]),
      .in_sof                         (slice_demux_sof[s]),
      .in_valid                       (slice_demux_valid[s]),
      .data_in_is_pps                 (slice_demux_data_out_is_pps[s]),
      
      .flow_stop                      (out_fifo_almost_full[s]),
                                      
      .pixs_out                       (slice_pixs_out[s]),
      .pixs_out_sof                   (slice_pixs_out_sof[s]),
      .pixs_out_valid                 (slice_pixs_out_valid[s])
    
    );
    assign slice_pixs_out_p[s*4*3*14+:4*3*14] = slice_pixs_out[s];
  end
endgenerate

// Slice Mux
// ---------
slice_mux
#(
  .MAX_NBR_SLICES               (MAX_NBR_SLICES),
  .MAX_SLICE_WIDTH              (MAX_SLICE_WIDTH)
)
slice_mux_u
(
  .clk_core                     (clk_core),
  .clk_out_int                  (clk_out_int),
  .rst_n                        (rst_n),
  .flush                        (flush),
  
  .slices_per_line              (slices_per_line),
  .slice_width                  (slice_width),
  .slice_height                 (slice_height),
  .frame_height                 (frame_height),
  .eoc_valid_pixs               (eoc_valid_pixs),
  
  .fifo_almost_full             (out_fifo_almost_full),
  
  .pixs_in_p                    (slice_pixs_out_p),
  .pixs_in_valid                (slice_pixs_out_valid),
  .pixs_in_sof                  (slice_pixs_out_sof),
  
  .pixs_out                     (pixs_out),
  .pixs_out_valid               (pixs_out_valid),
  .pixs_out_eof                 (pixs_out_eof)
);
  

endmodule

`default_nettype wire

