`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module pps_regs
#(
  parameter PPS_INPUT_METHOD        = "IN_BAND", // "IN_BAND", "DIRECT", "APB"
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_SLICE_HEIGHT        = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [255:0] in_data,
  input wire in_valid,
  input wire in_sof,
  input wire in_eof,
  input wire data_in_is_pps,
  input wire [1023:0] in_pps, // contains PPS in DIRECT method
  input wire in_pps_valid, // in_pps is valid. Clocked by clk_core
  input wire [1023:0] in_pps_apb, // PPS from APB slave
  input wire in_pps_apb_valid, // indicates which 32 bits from in_pps_apb is valid
  
  output reg [1:0] version_minor,
  output reg [15:0] frame_width,
  output reg [15:0] frame_height,
  output reg [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  output reg [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height,
  output reg [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0] slice_num_px,
  output reg [9:0] bits_per_pixel,
  output reg [1:0] bits_per_component_coded, // 0: 8 bpc, 1: 10 bpc, 2: 12 bpc
  output reg [1:0] source_color_space, // Image original color space 0: RGB, 1: YCoCg, 2: YCbCr (YCoCg is impossible)
  output reg [1:0] chroma_format, // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0
  output reg [15:0] chunk_size,
  output reg [15:0] rc_buffer_init_size,
  output reg [7:0] rc_stuffing_bits,
  output reg [7:0] rc_init_tx_delay,
  output reg [15:0] rc_buffer_max_size,
  output reg [31:0] rc_target_rate_threshold,
  output reg [7:0] rc_target_rate_scale,
  output reg [7:0] rc_fullness_scale,
  output reg [15:0] rc_fullness_offset_threshold,
  output reg [23:0] rc_fullness_offset_slope,
  output reg [3:0] rc_target_rate_extra_fbls,
  output reg signed [7:0] flatness_qp_very_flat_fbls,
  output reg signed [7:0] flatness_qp_very_flat_nfbls,
  output reg signed [7:0] flatness_qp_somewhat_flat_fbls,
  output reg signed [7:0] flatness_qp_somewhat_flat_nfbls,
  output wire [8*8-1:0] flatness_qp_lut_p,
  output wire [8*8-1:0] max_qp_lut_p,
  output wire [16*8-1:0] target_rate_delta_lut_p,
  output reg [3:0] mppf_bits_per_comp_R_Y,
  output reg [3:0] mppf_bits_per_comp_G_Cb,
  output reg [3:0] mppf_bits_per_comp_B_Cr,
  output reg [3:0] mppf_bits_per_comp_Y,
  output reg [3:0] mppf_bits_per_comp_Co,
  output reg [3:0] mppf_bits_per_comp_Cg,
  output reg [7:0] ssm_max_se_size,
  output reg [39:0] slice_num_bits,
  output reg [3:0] chunk_adj_bits,
  output reg [15:0] num_extra_mux_bits,
  output reg [9:0] slices_per_line,
  output reg [2:0] slice_pad_x,
  output reg [3:0] eoc_valid_pixs,
  output reg [3:0] mpp_min_step_size,
  
  output reg [$clog2(MAX_SLICE_WIDTH)-1:0] origSliceWidth,
  output reg [$clog2(MAX_SLICE_HEIGHT)+16-1:0] b0,
  output reg [8+9-1:0] rcOffsetInit,
  output reg [3:0] maxAdjBits,
  output wire [1:0] csc, // VDCM internal color space. 0: RGB, 1: YCoCg, 2: YCbCr (RGB is impossible)
  output wire [3*2-1:0] blkHeight_p,
  output wire [3*4-1:0] blkWidth_p,
  output reg [12:0] midPoint,
  output wire [3*5-1:0] neighborsAboveLenAdjusted_p,
  output wire [3*5-1:0] compNumSamples_p,
  output reg [12:0] maxPoint,
  output reg isSliceWidthMultipleOf16,
  output reg [11:0] rcStuffingBitsX9,
  output reg signed [6:0] minQp,
  output wire [3*2-1:0] partitionSize_p,
  output wire [3*14-1:0] minPoint_p,
  output reg [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] rcOffsetThreshold,
  output reg [4:0] OffsetAtBeginOfSlice,
  output reg [34:0] sliceSizeInRamInBytes, // Bigger because each chunk occupies a full Dword (256 bits) which may contain garbage at the end of chunk. TBD: improve this.
  
  output reg pps_valid
);

reg [1:0] line_cnt;
reg [1:0] data_in_is_pps_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    data_in_is_pps_dl <= 2'b0;
  else
    data_in_is_pps_dl <= {data_in_is_pps_dl[0], data_in_is_pps};
    
wire [255:0] in_data_gated;
assign in_data_gated = data_in_is_pps ? in_data : 256'b0;

reg in_eof_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    in_eof_dl <= 1'b0;
  else
    in_eof_dl <= in_eof;
    
reg inside_frame;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    inside_frame <= 1'b0;
  else if (in_sof)
    inside_frame <= 1'b1;
  else if (in_eof)
    inside_frame <= 1'b0;

reg [1:0] in_pps_valid_dl;    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    in_pps_valid_dl <= 2'b0;
  else
    in_pps_valid_dl <= {in_pps_valid_dl[0], in_pps_valid};
    
reg [1:0] in_pps_apb_valid_dl;    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    in_pps_apb_valid_dl <= 2'b0;
  else
    in_pps_apb_valid_dl <= {in_pps_apb_valid_dl[0], in_pps_apb_valid};
    
reg pps_valid_i;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    pps_valid_i <= 1'b0;
  else if (((line_cnt == 2'd3) & in_valid) | ((~inside_frame & (in_pps_valid_dl[0] | in_pps_apb_valid_dl[0])) | in_eof))
    pps_valid_i <= 1'b1;
  else
    pps_valid_i <= 1'b0;
    
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    pps_valid <= 1'b0;
  else
    pps_valid <= pps_valid_i;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    line_cnt <= 2'd0;
  else if (data_in_is_pps & in_valid)
    line_cnt <= line_cnt + 1'b1;
    
reg [1023:0] pps_reg;
wire [15:0] slice_width_a;
wire [15:0] slice_height_a;
wire [31:0] slice_num_px_a;
wire [3:0] slices_per_line_1_1_a; // only support slices_per_line = 2^n, limited to 8
wire [39:0] slice_num_bits_a;
wire [15:0] frameWidthRoundedUp;
generate
  if (PPS_INPUT_METHOD == "IN_BAND") begin : gen_in_band_slice
    assign slice_width_a = {in_data_gated[8*8+:8], in_data_gated[9*8+:8]};
    assign slice_height_a = {in_data_gated[10*8+:8], in_data_gated[11*8+:8]};
    assign slice_num_px_a = {in_data_gated[12*8+:8], in_data_gated[13*8+:8], in_data_gated[14*8+:8], in_data_gated[15*8+:8]};
    assign frameWidthRoundedUp = (|frame_width[2:0]) ? (frame_width & 16'hfff8) + 4'd8 : frame_width;
    assign slices_per_line_1_1_a = {6'b0,
                                    ((frameWidthRoundedUp>>3) >= (slice_width - 4'd8)) & ((frameWidthRoundedUp>>3) <= (slice_width + 4'd8)),
                                    ((frameWidthRoundedUp>>2) >= (slice_width - 4'd8)) & ((frameWidthRoundedUp>>2) <= (slice_width + 4'd8)),
                                    ((frameWidthRoundedUp>>1) >= (slice_width - 4'd8)) & ((frameWidthRoundedUp>>1) <= (slice_width + 4'd8)),
                                    (frameWidthRoundedUp >= (slice_width - 4'd8))      & (frameWidthRoundedUp <= (slice_width + 4'd8))};
    assign slice_num_bits_a = {in_data_gated[27*8+:8], in_data_gated[28*8+:8], in_data_gated[29*8+:8], in_data_gated[30*8+:8], in_data_gated[31*8+:8]};
  end
  else if (PPS_INPUT_METHOD == "DIRECT") begin : gen_direct_slice
    assign slice_width_a = {pps_reg[8*8+:8], pps_reg[9*8+:8]};
    assign slice_height_a = {pps_reg[10*8+:8], pps_reg[11*8+:8]};
    assign slice_num_px_a = {pps_reg[12*8+:8], pps_reg[13*8+:8], pps_reg[14*8+:8], pps_reg[15*8+:8]};
    assign frameWidthRoundedUp = (|pps_reg[5*8+:3]) ? ({pps_reg[4*8+:8], pps_reg[5*8+:8]} & 16'hfff8) + 4'd8 :  {pps_reg[4*8+:8], pps_reg[5*8+:8]};
    assign slices_per_line_1_1_a = {6'b0,
                                    ((frameWidthRoundedUp>>3) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>3) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    ((frameWidthRoundedUp>>2) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>2) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    ((frameWidthRoundedUp>>1) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>1) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    (frameWidthRoundedUp >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0]))      & (frameWidthRoundedUp <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8))};
    assign slice_num_bits_a = {pps_reg[91*8+:8], pps_reg[92*8+:8], pps_reg[93*8+:8], pps_reg[94*8+:8], pps_reg[95*8+:8]};
  end
  else if (PPS_INPUT_METHOD == "APB") begin : gen_apb_slice
    assign slice_width_a = {in_pps_apb[8*8+:8], in_pps_apb[9*8+:8]};
    assign slice_height_a = {in_pps_apb[10*8+:8], in_pps_apb[11*8+:8]};
    assign slice_num_px_a = {in_pps_apb[12*8+:8], in_pps_apb[13*8+:8], in_pps_apb[14*8+:8], in_pps_apb[15*8+:8]};
    assign frameWidthRoundedUp = (|in_pps_apb[5*8+:3]) ? ({in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]} & 16'hfff8) + 4'd8 :  {in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]};
    assign slices_per_line_1_1_a = {6'b0,
                                    ((frameWidthRoundedUp>>3) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>3) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    ((frameWidthRoundedUp>>2) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>2) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    ((frameWidthRoundedUp>>1) >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] - 4'd8)) & ((frameWidthRoundedUp>>1) <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8)),
                                    (frameWidthRoundedUp >= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0]))      & (frameWidthRoundedUp <= (slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0] + 4'd8))};
    assign slice_num_bits_a = {in_pps_apb[91*8+:8], in_pps_apb[92*8+:8], in_pps_apb[93*8+:8], in_pps_apb[94*8+:8], in_pps_apb[95*8+:8]};
  end
endgenerate

reg [7:0] flatness_qp_lut [7:0];
reg [7:0] max_qp_lut [7:0];
reg [7:0] target_rate_delta_lut [15:0];
integer i;


reg [3:0] slices_per_line_1_1;
wire [$clog2(MAX_SLICE_WIDTH)-3-1:0] numBlocksInLine;
reg [$clog2(MAX_SLICE_WIDTH)-3+9-1:0] blocksInLine_mult_rcFullnessOffsetThreshold;
reg [$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-4-1:0] numBlocksInSlice;
generate 
  if (PPS_INPUT_METHOD == "IN_BAND") begin : gen_pps_in_band
    always @ (posedge clk)
      if (data_in_is_pps & in_valid)
        case(line_cnt)
          2'd0:
            begin
              version_minor <= in_data_gated[1*8+:2];
              frame_width <= {in_data_gated[4*8+:8], in_data_gated[5*8+:8]};
              frame_height <= {in_data_gated[6*8+:8], in_data_gated[7*8+:8]};
              slice_width <= slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0];
              slice_height <= slice_height_a[$clog2(MAX_SLICE_HEIGHT)-1:0];
              slice_num_px <= slice_num_px_a[$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0];
              bits_per_pixel <= {in_data_gated[16*8+:2], in_data_gated[17*8+:8]};
              bits_per_component_coded <= in_data_gated[(19*8+4)+:2];
              source_color_space <= (in_data_gated[(19*8+2)+:2] == 2'b0) ? 2'd0 : 2'd2; // Color code: 0: RGB, 2: YCbCr
              chroma_format <= in_data_gated[(19*8+0)+:2];
              chunk_size <= {in_data_gated[22*8+:8], in_data_gated[23*8+:8]};
              rc_buffer_init_size <= {in_data_gated[26*8+:8], in_data_gated[27*8+:8]};
              rc_stuffing_bits <= in_data_gated[28*8+:8];
              rc_init_tx_delay <= in_data_gated[29*8+:8];
              rc_buffer_max_size <= {in_data_gated[30*8+:8], in_data_gated[31*8+:8]};
            end
          2'd1:
            begin
              rc_target_rate_threshold <= {in_data_gated[0*8+:8], in_data_gated[1*8+:8], in_data_gated[2*8+:8], in_data_gated[3*8+:8]};
              rc_target_rate_scale <= in_data_gated[4*8+:8];
              rc_fullness_scale <= in_data_gated[5*8+:8];
              rc_fullness_offset_threshold <= {in_data_gated[6*8+:8], in_data_gated[7*8+:8]};
              rc_fullness_offset_slope <= {in_data_gated[8*8+:8], in_data_gated[9*8+:8], in_data_gated[10*8+:8]};
              rc_target_rate_extra_fbls <= in_data_gated[11*8+:4];
              flatness_qp_very_flat_fbls <= in_data_gated[12*8+:8];
              flatness_qp_very_flat_nfbls <= in_data_gated[13*8+:8];
              flatness_qp_somewhat_flat_fbls <= in_data_gated[14*8+:8];
              flatness_qp_somewhat_flat_nfbls <= in_data_gated[15*8+:8];
              for (i=0; i<8; i=i+1) begin
                flatness_qp_lut[i] <= in_data_gated[(16+i)*8+:8];
                max_qp_lut[i] <= in_data_gated[(24+i)*8+:8];
              end
              numBlocksInSlice <= numBlocksInLine * (slice_height >> 1);
              slices_per_line_1_1 <= slices_per_line_1_1_a;
            end
          2'd2:
            begin
              for (i=0; i<16; i=i+1)
                target_rate_delta_lut[i] <= in_data_gated[i*8+:8];
              mppf_bits_per_comp_R_Y <= in_data_gated[(17*8+4)+:4];
              mppf_bits_per_comp_G_Cb <= in_data_gated[17*8+:4];
              mppf_bits_per_comp_B_Cr <= in_data_gated[(18*8+4)+:4];
              mppf_bits_per_comp_Y <= in_data_gated[18*8+:4];
              mppf_bits_per_comp_Co <= in_data_gated[(19*8+4)+:4];
              mppf_bits_per_comp_Cg <= in_data_gated[19*8+:4];
              ssm_max_se_size <= in_data_gated[23*8+:8];
              slice_num_bits <= slice_num_bits_a;
              blocksInLine_mult_rcFullnessOffsetThreshold <= numBlocksInLine * rc_fullness_offset_threshold;
            end
          2'd3:
            begin
              chunk_adj_bits <= in_data_gated[1*8+:4];
              num_extra_mux_bits <= {in_data_gated[2*8+:8], in_data_gated[3*8+:8]};
              if (version_minor == 2'd2) begin
                slices_per_line <= {in_data_gated[4*8+:2], in_data_gated[5*8+:8]};
                slice_pad_x <= in_data_gated[6*8+:3];
              end
              else begin // Only support 1, 2, 4 and 8 slices per line in v1.1
                slices_per_line <= slices_per_line_1_1;
                case (slices_per_line_1_1)
                  4'd1: slice_pad_x <= 4'd8 - (frame_width      & 3'b111);
                  4'd2: slice_pad_x <= 4'd8 - ((frame_width>>1) & 3'b111);
                  4'd4: slice_pad_x <= 4'd8 - ((frame_width>>2) & 3'b111);
                  4'd8: slice_pad_x <= 4'd8 - ((frame_width>>3) & 3'b111);
                  default: slice_pad_x <= 4'd8 - (frame_width      & 3'b111);
                endcase
              end
              mpp_min_step_size <= in_data_gated[7*8+:4];
            end
        endcase
  end
  else if (PPS_INPUT_METHOD == "DIRECT") begin : gen_pps_direct
    always @ (posedge clk) begin
      if (in_pps_valid)
        pps_reg <= in_pps;
      if ((~inside_frame & in_pps_valid_dl[0]) | in_eof) begin
        version_minor <= pps_reg[1*8+:2];
        frame_width <= {pps_reg[4*8+:8], pps_reg[5*8+:8]};
        frame_height <= {pps_reg[6*8+:8], pps_reg[7*8+:8]};
        slice_width <= slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0];
        slice_height <= slice_height_a[$clog2(MAX_SLICE_HEIGHT)-1:0];
        slice_num_px <= slice_num_px_a[$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0];
        bits_per_pixel <= {pps_reg[16*8+:2], pps_reg[17*8+:8]};
        bits_per_component_coded <= pps_reg[(19*8+4)+:2];
        source_color_space <= (pps_reg[(19*8+2)+:2] == 2'b0) ? 2'd0 : 2'd2; // Color code: 0: RGB, 2: YCbCr
        chroma_format <= pps_reg[(19*8+0)+:2];
        chunk_size <= {pps_reg[22*8+:8], pps_reg[23*8+:8]};
        rc_buffer_init_size <= {pps_reg[26*8+:8], pps_reg[27*8+:8]};
        rc_stuffing_bits <= pps_reg[28*8+:8];
        rc_init_tx_delay <= pps_reg[29*8+:8];
        rc_buffer_max_size <= {pps_reg[30*8+:8], pps_reg[31*8+:8]};

        rc_target_rate_threshold <= {pps_reg[32*8+:8], pps_reg[33*8+:8], pps_reg[34*8+:8], pps_reg[35*8+:8]};
        rc_target_rate_scale <= pps_reg[36*8+:8];
        rc_fullness_scale <= pps_reg[37*8+:8];
        rc_fullness_offset_threshold <= {pps_reg[38*8+:8], pps_reg[39*8+:8]};
        rc_fullness_offset_slope <= {pps_reg[40*8+:8], pps_reg[41*8+:8], pps_reg[42*8+:8]};
        rc_target_rate_extra_fbls <= pps_reg[43*8+:4];
        flatness_qp_very_flat_fbls <= pps_reg[44*8+:8];
        flatness_qp_very_flat_nfbls <= pps_reg[45*8+:8];
        flatness_qp_somewhat_flat_fbls <= pps_reg[46*8+:8];
        flatness_qp_somewhat_flat_nfbls <= pps_reg[47*8+:8];
        for (i=0; i<8; i=i+1) begin
          flatness_qp_lut[i] <= pps_reg[(48+i)*8+:8];
          max_qp_lut[i] <= pps_reg[(56+i)*8+:8];
        end
        numBlocksInSlice <= (slice_width_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 3) * (slice_height_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 1);
        
        for (i=0; i<16; i=i+1)
          target_rate_delta_lut[i] <= pps_reg[(64+i)*8+:8];
        mppf_bits_per_comp_R_Y <= pps_reg[(81*8+4)+:4];
        mppf_bits_per_comp_G_Cb <= pps_reg[81*8+:4];
        mppf_bits_per_comp_B_Cr <= pps_reg[(82*8+4)+:4];
        mppf_bits_per_comp_Y <= pps_reg[82*8+:4];
        mppf_bits_per_comp_Co <= pps_reg[(83*8+4)+:4];
        mppf_bits_per_comp_Cg <= pps_reg[83*8+:4];
        ssm_max_se_size <= pps_reg[87*8+:8];
        slice_num_bits <= slice_num_bits_a;
        blocksInLine_mult_rcFullnessOffsetThreshold <= (slice_width_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 3) * {pps_reg[38*8+:8], pps_reg[39*8+:8]};
        
        chunk_adj_bits <= pps_reg[97*8+:4];
        num_extra_mux_bits <= {pps_reg[98*8+:8], pps_reg[99*8+:8]};
        if (version_minor == 2'd2) begin
          slices_per_line <= {pps_reg[100*8+:2], pps_reg[101*8+:8]};
          slice_pad_x <= pps_reg[102*8+:3];
        end
        else begin // Only support 1, 2, 4 and 8 slices per line in v1.1
          slices_per_line <= slices_per_line_1_1_a;
          case (slices_per_line_1_1_a)
            4'd1: slice_pad_x <= 4'd8 - ({pps_reg[4*8+:8], pps_reg[5*8+:8]}      & 3'b111);
            4'd2: slice_pad_x <= 4'd8 - (({pps_reg[4*8+:8], pps_reg[5*8+:8]}>>1) & 3'b111);
            4'd4: slice_pad_x <= 4'd8 - (({pps_reg[4*8+:8], pps_reg[5*8+:8]}>>2) & 3'b111);
            4'd8: slice_pad_x <= 4'd8 - (({pps_reg[4*8+:8], pps_reg[5*8+:8]}>>3) & 3'b111);
          endcase
        end
        mpp_min_step_size <= pps_reg[103*8+:4];

      end
    end
  end
  else if (PPS_INPUT_METHOD == "APB") begin : gen_pps_apb
    always @ (posedge clk) begin
      if ((in_pps_apb_valid & ~inside_frame) | in_eof) begin
        version_minor <= in_pps_apb[1*8+:2];
        frame_width <= {in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]};
        frame_height <= {in_pps_apb[6*8+:8], in_pps_apb[7*8+:8]};
        slice_width <= slice_width_a[$clog2(MAX_SLICE_WIDTH)-1:0];
        slice_height <= slice_height_a[$clog2(MAX_SLICE_HEIGHT)-1:0];
        slice_num_px <= slice_num_px_a[$clog2(MAX_SLICE_WIDTH*MAX_SLICE_HEIGHT)-1:0];
        bits_per_pixel <= {in_pps_apb[16*8+:2], in_pps_apb[17*8+:8]};
        bits_per_component_coded <= in_pps_apb[(19*8+4)+:2];
        source_color_space <= (in_pps_apb[(19*8+2)+:2] == 2'b0) ? 2'd0 : 2'd2; // Color code: 0: RGB, 2: YCbCr
        chroma_format <= in_pps_apb[(19*8+0)+:2];
        chunk_size <= {in_pps_apb[22*8+:8], in_pps_apb[23*8+:8]};
        rc_buffer_init_size <= {in_pps_apb[26*8+:8], in_pps_apb[27*8+:8]};
        rc_stuffing_bits <= in_pps_apb[28*8+:8];
        rc_init_tx_delay <= in_pps_apb[29*8+:8];
        rc_buffer_max_size <= {in_pps_apb[30*8+:8], in_pps_apb[31*8+:8]};
        rc_target_rate_threshold <= {in_pps_apb[32*8+:8], in_pps_apb[33*8+:8], in_pps_apb[34*8+:8], in_pps_apb[35*8+:8]};
        rc_target_rate_scale <= in_pps_apb[36*8+:8];
        rc_fullness_scale <= in_pps_apb[37*8+:8];
        rc_fullness_offset_threshold <= {in_pps_apb[38*8+:8], in_pps_apb[39*8+:8]};
        rc_fullness_offset_slope <= {in_pps_apb[40*8+:8], in_pps_apb[41*8+:8], in_pps_apb[42*8+:8]};
        rc_target_rate_extra_fbls <= in_pps_apb[43*8+:4];
        flatness_qp_very_flat_fbls <= in_pps_apb[44*8+:8];
        flatness_qp_very_flat_nfbls <= in_pps_apb[45*8+:8];
        flatness_qp_somewhat_flat_fbls <= in_pps_apb[46*8+:8];
        flatness_qp_somewhat_flat_nfbls <= in_pps_apb[47*8+:8];
        for (i=0; i<8; i=i+1) begin
          flatness_qp_lut[i] <= in_pps_apb[(48+i)*8+:8];
          max_qp_lut[i] <= in_pps_apb[(56+i)*8+:8];
        end
        numBlocksInSlice <= (slice_width_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 3) * (slice_height_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 1);
        for (i=0; i<16; i=i+1)
          target_rate_delta_lut[i] <= in_pps_apb[(64+i)*8+:8];
        mppf_bits_per_comp_R_Y <= in_pps_apb[(81*8+4)+:4];
        mppf_bits_per_comp_G_Cb <= in_pps_apb[81*8+:4];
        mppf_bits_per_comp_B_Cr <= in_pps_apb[(82*8+4)+:4];
        mppf_bits_per_comp_Y <= in_pps_apb[82*8+:4];
        mppf_bits_per_comp_Co <= in_pps_apb[(83*8+4)+:4];
        mppf_bits_per_comp_Cg <= in_pps_apb[83*8+:4];
        ssm_max_se_size <= in_pps_apb[87*8+:8];
        slice_num_bits <= slice_num_bits_a;
        blocksInLine_mult_rcFullnessOffsetThreshold <= (slice_width_a[$clog2(MAX_SLICE_HEIGHT)-1:0] >> 3) * {in_pps_apb[38*8+:8], in_pps_apb[39*8+:8]};
        chunk_adj_bits <= in_pps_apb[97*8+:4];
        num_extra_mux_bits <= {in_pps_apb[98*8+:8], in_pps_apb[99*8+:8]};
        if (in_pps_apb[1*8+:2] == 2'd2) begin // version = 1.2
          slices_per_line <= {in_pps_apb[100*8+:2], in_pps_apb[101*8+:8]};
          slice_pad_x <= in_pps_apb[102*8+:3];
        end
        else begin // Only support 1, 2, 4 and 8 slices per line in v1.1
          slices_per_line <= slices_per_line_1_1_a;
          case (slices_per_line_1_1_a)
            4'd1: slice_pad_x <= 4'd8 - ({in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]}      & 3'b111);
            4'd2: slice_pad_x <= 4'd8 - (({in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]}>>1) & 3'b111);
            4'd4: slice_pad_x <= 4'd8 - (({in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]}>>2) & 3'b111);
            4'd8: slice_pad_x <= 4'd8 - (({in_pps_apb[4*8+:8], in_pps_apb[5*8+:8]}>>3) & 3'b111);
          endcase
        end
        mpp_min_step_size <= in_pps_apb[103*8+:4];
      end
    end
  end
endgenerate
    
// Derived parameters
integer c;
localparam [3*3-1:0] compScaleX = 9'b110110000;
localparam [3*3-1:0] compScaleY = 9'b100100000;
wire [2:0] compNumSamplesShift [2:0][2:0];
assign compNumSamplesShift[0][0] = 2'd0;
assign compNumSamplesShift[1][0] = 2'd0;
assign compNumSamplesShift[2][0] = 2'd0;
assign compNumSamplesShift[0][1] = 2'd0;
assign compNumSamplesShift[1][1] = 2'd1;
assign compNumSamplesShift[2][1] = 2'd1;
assign compNumSamplesShift[0][2] = 2'd0;
assign compNumSamplesShift[1][2] = 2'd2;
assign compNumSamplesShift[2][2] = 2'd2;
reg [1:0] blkHeight [2:0];
reg [3:0] blkWidth [2:0];
reg [4:0] neighborsAboveLenAdjusted [2:0];
reg [4:0] compNumSamples [2:0];
reg [1:0] partitionSize [2:0];
always @ (*) begin
    for (c=0; c<3; c=c+1) begin
      case(chroma_format)
        2'd0: // 4:4:4
          begin
            blkWidth[c] = 4'd8 >> compScaleX[c*3+0];
            blkHeight[c] = 2'd2 >> compScaleY[c*3+0];
            compNumSamples[c] = 5'd16 >> compNumSamplesShift[c][0];
            neighborsAboveLenAdjusted[c] = 5'd16 >> compScaleX[c*3+0];
            partitionSize[c] = 2'd2 >> compScaleX[c*3+0];
          end
        2'd1: // 4:2:2
          begin
            blkWidth[c] = 4'd8 >> compScaleX[c*3+1];
            blkHeight[c] = 2'd2 >> compScaleY[c*3+1];
            compNumSamples[c] = 5'd16 >> compNumSamplesShift[c][1];
            neighborsAboveLenAdjusted[c] = 5'd16 >> compScaleX[c*3+1];
            partitionSize[c] = 2'd2 >> compScaleX[c*3+1];
          end
        2'd2: // 4:2:0
          begin
            blkWidth[c] = 4'd8 >> compScaleX[c*3+2];
            blkHeight[c] = 2'd2 >> compScaleY[c*3+2];
            compNumSamples[c] = 5'd16 >> compNumSamplesShift[c][2];
            neighborsAboveLenAdjusted[c] = 5'd16 >> compScaleX[c*3+2];
            partitionSize[c] = 2'd2 >> compScaleX[c*3+2];
          end
        default:
          begin
            blkWidth[c] = 4'd8 >> compScaleX[c*3+0];
            blkHeight[c] = 2'd2 >> compScaleY[c*3+0];
            compNumSamples[c] = 5'd16 >> (compScaleX[c*3+0] + compScaleY[c*3+0]);
            neighborsAboveLenAdjusted[c] = 5'd16 >> compScaleX[c*3+0];
            partitionSize[c] = 2'd2 >> compScaleX[c*3+0];
          end
      endcase 
    end
    case (bits_per_component_coded)
      2'd0: midPoint = 1'b1 << 7;
      2'd1: midPoint = 1'b1 << 9;
      2'd2: midPoint = 1'b1 << 11;
      default: midPoint = 1'b1 << 7;
    endcase
end

wire [15:0] chunkSizeRoundedUp; // to the next value divisible by 32 (bytes)
assign chunkSizeRoundedUp = (chunk_size[4:0] == 5'd0) ? chunk_size : (chunk_size[15:5] + 1'b1) << 5;


wire [34:0] sliceSizeInBytes;
assign sliceSizeInBytes = slice_height * chunk_size;
wire [39:0] slicesPerLineSizeInBytes;
assign slicesPerLineSizeInBytes = sliceSizeInBytes * slices_per_line;

wire [5:0] lastWordOfSliceSizeFullnessInBytes_a;
assign lastWordOfSliceSizeFullnessInBytes_a = (slicesPerLineSizeInBytes[4:0] == 5'd0) ? 6'd32 : slicesPerLineSizeInBytes[4:0];
reg [5:0] lastWordOfSliceSizeFullnessInBytes;
always @ (posedge clk)
  if ((data_in_is_pps&in_valid) | flush)
    OffsetAtBeginOfSlice <= 5'd0;
  else
    OffsetAtBeginOfSlice <= lastWordOfSliceSizeFullnessInBytes[4:0];
    
reg signed [13:0] minPoint [2:0];
assign numBlocksInLine = slice_width >> 3;
always @ (posedge clk)
  if ((data_in_is_pps_dl[0] & ~data_in_is_pps) | ((~inside_frame & (in_pps_valid_dl[1] | in_pps_apb_valid_dl[1])) | in_eof_dl)) begin
    origSliceWidth <= slice_width - slice_pad_x;
    eoc_valid_pixs <= 4'd8 - slice_pad_x;
    b0 <= sliceSizeInBytes << 3; // B0 in spec section 4.5.2
    rcOffsetInit <= rc_init_tx_delay * bits_per_pixel;
    maxAdjBits <= (chunk_adj_bits + 1'b1) >> 1;
    rcOffsetThreshold <= numBlocksInSlice - blocksInLine_mult_rcFullnessOffsetThreshold;
    sliceSizeInRamInBytes = slice_height * ((slices_per_line == 10'd1) ? chunk_size : chunkSizeRoundedUp);
    lastWordOfSliceSizeFullnessInBytes <= lastWordOfSliceSizeFullnessInBytes_a;
    case (bits_per_component_coded)
      2'd0: maxPoint <= (1'b1 << 8) - 1'b1;
      2'd1: maxPoint <= (1'b1 << 10) - 1'b1;
      2'd2: maxPoint <= (1'b1 << 12) - 1'b1;
      default: maxPoint <= (1'b1 << 8) - 1'b1;
    endcase
    for (c = 0; c < 3; c = c + 1)
      if ((csc == 2'd1) & (c > 0))
        case (bits_per_component_coded)
          2'd0: minPoint[c] <= ~((1'b1 << 8) - 1'b1);
          2'd1: minPoint[c] <= ~((1'b1 << 10) - 1'b1);
          2'd2: minPoint[c] <= ~((1'b1 << 12) - 1'b1);
          default: minPoint[c] <= ~((1'b1 << 8) - 1'b1);
        endcase
      else
        minPoint[c] <= 14'sd0;
    isSliceWidthMultipleOf16 <= ~(|slice_width[3:0]);
    rcStuffingBitsX9 <= 4'd9 * rc_stuffing_bits;
    case (bits_per_component_coded)
      2'd0: minQp <= 7'sd16;
      2'd1: minQp <= 7'sd0;
      2'd2: minQp <= -7'sd16;
      default: minQp <= 7'sd16;
    endcase
  end
    

// Pack outputs
genvar ci, gi;
generate
  for (gi = 0; gi < 8 ; gi = gi + 1) begin : gen_flatness_qp_lut
    assign flatness_qp_lut_p[gi*8+:8] = flatness_qp_lut[gi];
    assign max_qp_lut_p[gi*8+:8] = max_qp_lut[gi];
  end
  for (gi = 0; gi < 16 ; gi = gi + 1) begin : gen_target_rate_delta_lut
    assign target_rate_delta_lut_p[gi*8+:8] = target_rate_delta_lut[gi];
  end
  for (ci =0; ci < 3; ci = ci + 1) begin : gen_blk_size
    assign blkHeight_p[2*ci+:2] = blkHeight[ci];
    assign blkWidth_p[4*ci+:4] = blkWidth[ci];
    assign neighborsAboveLenAdjusted_p[5*ci+:5] = neighborsAboveLenAdjusted[ci];
    assign compNumSamples_p[5*ci+:5] = compNumSamples[ci];
    assign partitionSize_p[2*ci+:2] = partitionSize[ci];
    assign minPoint_p[14*ci+:14] = minPoint[ci];
  end
  
endgenerate
assign csc = (source_color_space == 2'd0) ? 2'd1 : 2'd2; // PPS RGB becomes internally YCoCg. PPS YUV becomes internally YCbCr.

endmodule

`default_nettype wire

