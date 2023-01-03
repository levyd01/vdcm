`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module substream_demux
#(
  parameter RATE_BUFF_NUM_LINES     = 2**8,
  parameter MAX_FUNNEL_SHIFTER_SIZE = 2*248 - 1,
  parameter MAX_SLICE_WIDTH         = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [9:0] bits_per_pixel,
  input wire [7:0] rc_init_tx_delay,
  input wire [15:0] rc_buffer_max_size,
  input wire [7:0] ssm_max_se_size,
  input wire [39:0] slice_num_bits,
  input wire [15:0] num_extra_mux_bits,
  input wire [15:0] chunk_size,
  input wire [4:0] OffsetAtBeginOfSlice,
  input wire [34:0] sliceSizeInRamInBytes,
  input wire [9:0] slices_per_line,
  
  input wire [255:0] in_data,
  input wire in_sof,
  input wire in_valid,
  input wire data_in_is_pps,
  input wire sos,
  input wire eos,
  input wire eof, // before vertical padding
  input wire early_eos,
  input wire isLastBlock,
  
  output wire start_decode,
  input wire disable_rcb_rd,
  output wire ssm_sof,
  output wire sos_for_rc,
  output reg [1:0] sos_fsm,
  output reg [1:0] eos_fsm,
  
  output wire [4*MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_p,
  output wire [3:0] fs_ready,

  input wire substream0_parsed,
  input wire parse_substreams,
  input wire [9*4-1:0] size_to_remove_p,
  input wire size_to_remove_valid

);

localparam RATE_BUFF_ADDR_WIDTH = $clog2(RATE_BUFF_NUM_LINES);

// Unpack inputs
genvar gi;
wire [8:0] size_to_remove [3:0];
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_unpack_inputs
    assign size_to_remove[gi] = size_to_remove_p[gi*9+:9];
  end
endgenerate

reg [RATE_BUFF_ADDR_WIDTH-1:0] rate_buffer_addr_w;
reg nbr_wrap_around_wr;
always @ (posedge clk)
  if (in_valid)
    if (in_sof) begin
      rate_buffer_addr_w <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
      nbr_wrap_around_wr <= 1'b0;
    end
    else if (rate_buffer_addr_w == RATE_BUFF_NUM_LINES-1) begin
      rate_buffer_addr_w <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
      nbr_wrap_around_wr <= ~nbr_wrap_around_wr;
    end
    else 
      rate_buffer_addr_w <= rate_buffer_addr_w + 1'b1;

reg w_en;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    w_en <= 1'b0;
  else
    w_en <= in_valid & ~data_in_is_pps;
integer b; 
reg [255:0] wr_data;  
always @ (posedge clk)
  if (in_valid)
    for(b=0; b<32; b=b+1)
      wr_data[8*b+:8] = in_data[(31-b)*8+:8];

// Convert rc_init_tx_delay from block time to number of in_data input words    
reg [15:0] initDecodeDelay_i;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    initDecodeDelay_i <= 16'hffff;
  else if (in_sof)
    initDecodeDelay_i <= (rc_init_tx_delay * bits_per_pixel); // TBD !!!! Avoid the multiplier with sequential add & shift
wire [9:0] initDecodeDelay;
assign initDecodeDelay = initDecodeDelay_i >> 8;

wire alt_early_eos;
reg [9:0] initDecodeDelayCnt;
reg rate_buf_read_allowed;
wire rd_en;
wire rd_valid;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    initDecodeDelayCnt <= 10'd0;
    rate_buf_read_allowed <= 1'b0;
  end
  else if (alt_early_eos) begin
    initDecodeDelayCnt <= 10'd0;
    rate_buf_read_allowed <= 1'b0;
  end
  else if (in_valid) begin
    if (in_sof) begin
      initDecodeDelayCnt <= 10'd0;
      rate_buf_read_allowed <= 1'b0;
    end
    else if ((initDecodeDelayCnt < initDecodeDelay) & ~data_in_is_pps)
      initDecodeDelayCnt <= initDecodeDelayCnt + 1'b1;
    else if (~data_in_is_pps)
      rate_buf_read_allowed <= 1'b1;
  end
  
reg rate_buf_read_allowed_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    rate_buf_read_allowed_dl <= 1'b0;
  else
    rate_buf_read_allowed_dl <= rate_buf_read_allowed;
assign start_decode = rate_buf_read_allowed & ~rate_buf_read_allowed_dl;

reg first_rd_valid_of_slice;
reg first_rd_en_of_slice;    
always @ (posedge clk)
  first_rd_valid_of_slice <= first_rd_en_of_slice & rd_en;
reg [RATE_BUFF_ADDR_WIDTH+5-1:0] nextStartOfSliceInBytes;
always @ (posedge clk)
  if (in_sof)
    nextStartOfSliceInBytes <= {(RATE_BUFF_ADDR_WIDTH+5){1'b0}};
  else if (first_rd_en_of_slice & rd_en)
    nextStartOfSliceInBytes <= nextStartOfSliceInBytes + (sliceSizeInRamInBytes & ((RATE_BUFF_NUM_LINES<<5)-1));
wire [RATE_BUFF_ADDR_WIDTH-1:0] nextStartOfSliceAddr;
wire [4:0] nextStartOfSliceOffsetInWord;
assign nextStartOfSliceAddr = (nextStartOfSliceInBytes>>5) & (RATE_BUFF_NUM_LINES-1);
assign nextStartOfSliceOffsetInWord = nextStartOfSliceInBytes & 5'h1f;
  
reg [1:0] pos_in_block;
reg [RATE_BUFF_ADDR_WIDTH-1:0] rate_buffer_addr_r;
reg nbr_wrap_around_rd;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
    nbr_wrap_around_rd <= 1'b0;
  end
  else if (in_sof) begin
    rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
    nbr_wrap_around_rd <= 1'b0;
  end
  // Bypass garbage at end of slice. See spec. p.157 "SSM needs a small portion of the total slice rate to be set aside to guarantee correct behavior at the end of the slice.  
  else if (start_decode) begin
    rate_buffer_addr_r <= nextStartOfSliceAddr;
    if ((nextStartOfSliceAddr > rate_buffer_addr_r) ? ((nextStartOfSliceAddr - rate_buffer_addr_r) > (RATE_BUFF_NUM_LINES>>1)) : ((rate_buffer_addr_r - nextStartOfSliceAddr) > (RATE_BUFF_NUM_LINES>>1))) // there was a wrap around
      nbr_wrap_around_rd <= ~nbr_wrap_around_rd;
  end
  else if (rd_en)
    if (rate_buffer_addr_r == RATE_BUFF_NUM_LINES-1) begin
      rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
      nbr_wrap_around_rd <= ~nbr_wrap_around_rd;
    end
    else
      rate_buffer_addr_r <= rate_buffer_addr_r + 1'b1;

wire [255:0] rd_data;

dp_ram
#(
  .NUMBER_OF_LINES         (RATE_BUFF_NUM_LINES),
  .DATA_WIDTH              (256)
)
rate_buffer_u
(
  .clk                          (clk),
                                
  .addr_w                       (rate_buffer_addr_w),
  .wr_data                      (wr_data),
  .w_en                         (w_en),
  
  .r_en                         (rd_en),
  .addr_r                       (rate_buffer_addr_r),
  .rd_data                      (rd_data),
  .mem_valid                    (rd_valid) 
);

wire buffer_empty;
assign buffer_empty = ~(nbr_wrap_around_wr ^ nbr_wrap_around_rd) ? (rate_buffer_addr_w == rate_buffer_addr_r) : (RATE_BUFF_NUM_LINES + rate_buffer_addr_w == rate_buffer_addr_r);

`ifdef SIM_DEBUG
  wire buffer_full;
  assign buffer_full = (nbr_wrap_around_wr ^ nbr_wrap_around_rd) & (rate_buffer_addr_w == rate_buffer_addr_r);
  reg overflow;
  reg underflow;
  wire [9:0] rb_fullness;
  assign rb_fullness = ~(nbr_wrap_around_wr ^ nbr_wrap_around_rd) ? (rate_buffer_addr_w - rate_buffer_addr_r) : (RATE_BUFF_NUM_LINES + rate_buffer_addr_w - rate_buffer_addr_r);
  
  always @ (posedge clk or negedge rst_n)
    if (~rst_n) begin
      overflow <= 1'b0;
      underflow <= 1'b0;
    end
    else begin
      overflow <= buffer_full & w_en;
      underflow <= buffer_empty & rd_en;
    end
`endif
  
wire [3:0] mux_word_request_i; 
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    eos_fsm <= 2'b0;
  else
    case (eos_fsm)
      2'd0: if (isLastBlock) eos_fsm <= 2'd1;
      2'd1: if (parse_substreams) eos_fsm <= 2'd2;
      2'd2: eos_fsm <= 2'b0;
      default: eos_fsm <= 2'b0;
    endcase
assign alt_early_eos = (eos_fsm == 2'd2);

localparam SOS_FSM_IDLE = 2'd0;
localparam SOS_FSM_FETCH_SSM0 = 2'd1;
localparam SOS_FSM_PARSE_SSM0 = 2'd2;
localparam SOS_FSM_RUNTIME = 2'd3;

reg [1:0] fsm_cnt;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fsm_cnt <= 2'd0;
  else if (flush)
    fsm_cnt <= 2'd0;
  else if ((sos_fsm == SOS_FSM_IDLE) | (alt_early_eos & ~eof))
    fsm_cnt <= 2'd0;
  else if ((sos_fsm == SOS_FSM_FETCH_SSM0) | (sos_fsm == SOS_FSM_PARSE_SSM0))
    fsm_cnt <= fsm_cnt + 1'b1;  
  
reg [3:0] mux_word_valid;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos_fsm <= SOS_FSM_IDLE;
  else if (flush)
    sos_fsm <= SOS_FSM_IDLE;
  else
    case (sos_fsm)
      SOS_FSM_IDLE      : if (start_decode) sos_fsm <= SOS_FSM_FETCH_SSM0;
      SOS_FSM_FETCH_SSM0: if /*(fsm_cnt == 2'd3)*/(mux_word_valid[0]) sos_fsm <= SOS_FSM_PARSE_SSM0;
      SOS_FSM_PARSE_SSM0: if (fsm_cnt == 2'd3) sos_fsm <= SOS_FSM_RUNTIME;
      SOS_FSM_RUNTIME   : if (alt_early_eos) sos_fsm <= SOS_FSM_IDLE;
    endcase

wire sos_rd_en;
assign sos_rd_en = (sos_fsm == SOS_FSM_FETCH_SSM0) | (sos_fsm == SOS_FSM_PARSE_SSM0);
wire sos_mux_word_request_0;
assign sos_mux_word_request_0 = (sos_fsm == SOS_FSM_FETCH_SSM0) & (fsm_cnt == 2'd2);

reg [1:0] sos_fsm_dl;
always @ (posedge clk)
  sos_fsm_dl <= sos_fsm;
assign sos_for_rc = (sos_fsm_dl == SOS_FSM_PARSE_SSM0) & (sos_fsm == SOS_FSM_RUNTIME);

reg [3:0] num_mux_word_valid;
always @ (*)
  case (mux_word_valid)
    4'b0000:  num_mux_word_valid = 4'd0;
    4'b0001, 4'b0010, 4'b0100, 4'b1000: num_mux_word_valid = 4'd1;
    4'b0011, 4'b0101, 4'b1001, 4'b0110, 4'b1010, 4'b1100: num_mux_word_valid = 4'd2;
    4'b0111, 4'b1011, 4'b1101, 4'b1110: num_mux_word_valid = 4'd3;
    4'b1111: num_mux_word_valid = 4'd4;
  endcase

reg [15:0] byte_cnt;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    byte_cnt <= 16'd0;
  else if (in_sof | alt_early_eos | (slices_per_line == 10'd1))
      byte_cnt <= 16'd0;
  else if (rd_en)
    if (byte_cnt + 6'd32 >= chunk_size) 
      byte_cnt <= 16'd0;
    else
      byte_cnt <= byte_cnt + 6'd32;

reg [5:0] rd_data_fullness;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    rd_data_fullness <= 6'd32;
  else if ((alt_early_eos & ~eof) | (slices_per_line == 10'd1) | (chunk_size[4:0] == 5'd0))
      rd_data_fullness <= 6'd32;
  else if (rd_en)
    if ((byte_cnt + 7'd64 >= chunk_size) & (rd_data_fullness == 6'd32))
      rd_data_fullness <= chunk_size - byte_cnt - 6'd32;
    else 
      rd_data_fullness <= 6'd32;

      
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    first_rd_en_of_slice <= 1'b0;
  else if (flush | rd_en/*first_rd_en_of_slice*/)
    first_rd_en_of_slice <= 1'b0;
  else if (start_decode)
    first_rd_en_of_slice <= 1'b1;
    
reg [8:0] commonByteBufferFullness; // In bytes
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    commonByteBufferFullness <= 8'd0;
  else if ((in_sof & in_valid) | (alt_early_eos & ~eof))
    commonByteBufferFullness <= 8'd0;
  else if (initDecodeDelayCnt >= initDecodeDelay - 3'd2) // Start to fill the common buffer a bit before it is allowed to read
    if (rd_en & first_rd_en_of_slice) // We know that at this point in time there will never be pull
      commonByteBufferFullness <= commonByteBufferFullness + 6'd32 - nextStartOfSliceOffsetInWord;
    else if (rd_en & ~(|mux_word_valid)) // Only push to commonByteBuffer
      commonByteBufferFullness <= commonByteBufferFullness + rd_data_fullness;
    else if ((|mux_word_valid) & ~rd_en) // Only pull from commonByteBuffer
      commonByteBufferFullness <= commonByteBufferFullness - (num_mux_word_valid*ssm_max_se_size[7:3]);
    else if ((|mux_word_valid) & rd_en) // Push and pull simultaneously
      commonByteBufferFullness <= commonByteBufferFullness - (num_mux_word_valid*ssm_max_se_size[7:3]) + rd_data_fullness;

assign rd_en = rate_buf_read_allowed_dl & (commonByteBufferFullness <= (ssm_max_se_size[7:3]<<2)) & (sos_rd_en | (sos_fsm == SOS_FSM_RUNTIME)) & ~buffer_empty & ~disable_rcb_rd;

reg [5:0] rd_data_fullness_dl;
always @ (posedge clk)
  rd_data_fullness_dl <= rd_data_fullness;
  
reg [4:0] alt_nextStartOfSliceOffsetInWord_dl;
always @ (posedge clk)
  alt_nextStartOfSliceOffsetInWord_dl <= nextStartOfSliceOffsetInWord;

integer i;
localparam MAX_SSM_MAX_SE_SIZE = 160; // 160 bits = 36-bpp maximum for 4:4:4 at 12bpc (see Figure D-6 in spec), per substream
reg [1023:0] commonByteBuffer;
always @ (posedge clk)
  if (rd_valid)
    if (first_rd_valid_of_slice)
      case (alt_nextStartOfSliceOffsetInWord_dl)
        5'd0  : commonByteBuffer <= {commonByteBuffer[767:0], rd_data};
        5'd1  : commonByteBuffer <= {commonByteBuffer[1024 -31* 8-1:0], rd_data[31*8-1:0]};
        5'd2  : commonByteBuffer <= {commonByteBuffer[1024 -30* 8-1:0], rd_data[30*8-1:0]};
        5'd3  : commonByteBuffer <= {commonByteBuffer[1024 -29* 8-1:0], rd_data[29*8-1:0]};
        5'd4  : commonByteBuffer <= {commonByteBuffer[1024 -28* 8-1:0], rd_data[28*8-1:0]};
        5'd5  : commonByteBuffer <= {commonByteBuffer[1024 -27* 8-1:0], rd_data[27*8-1:0]};
        5'd6  : commonByteBuffer <= {commonByteBuffer[1024 -26* 8-1:0], rd_data[26*8-1:0]};
        5'd7  : commonByteBuffer <= {commonByteBuffer[1024 -25* 8-1:0], rd_data[25*8-1:0]};
        5'd8  : commonByteBuffer <= {commonByteBuffer[1024 -24* 8-1:0], rd_data[24*8-1:0]};
        5'd9  : commonByteBuffer <= {commonByteBuffer[1024 -23* 8-1:0], rd_data[23*8-1:0]};
        5'd10 : commonByteBuffer <= {commonByteBuffer[1024 -22* 8-1:0], rd_data[22*8-1:0]};
        5'd11 : commonByteBuffer <= {commonByteBuffer[1024 -21* 8-1:0], rd_data[21*8-1:0]};
        5'd12 : commonByteBuffer <= {commonByteBuffer[1024 -20* 8-1:0], rd_data[20*8-1:0]};
        5'd13 : commonByteBuffer <= {commonByteBuffer[1024 -19* 8-1:0], rd_data[19*8-1:0]};
        5'd14 : commonByteBuffer <= {commonByteBuffer[1024 -18* 8-1:0], rd_data[18*8-1:0]};
        5'd15 : commonByteBuffer <= {commonByteBuffer[1024 -17* 8-1:0], rd_data[17*8-1:0]};
        5'd16 : commonByteBuffer <= {commonByteBuffer[1024 -16* 8-1:0], rd_data[16*8-1:0]};
        5'd17 : commonByteBuffer <= {commonByteBuffer[1024 -15* 8-1:0], rd_data[15*8-1:0]};
        5'd18 : commonByteBuffer <= {commonByteBuffer[1024 -14* 8-1:0], rd_data[14*8-1:0]};
        5'd19 : commonByteBuffer <= {commonByteBuffer[1024 -13* 8-1:0], rd_data[13*8-1:0]};
        5'd20 : commonByteBuffer <= {commonByteBuffer[1024 -12* 8-1:0], rd_data[12*8-1:0]};
        5'd21 : commonByteBuffer <= {commonByteBuffer[1024 -11* 8-1:0], rd_data[11*8-1:0]};
        5'd22 : commonByteBuffer <= {commonByteBuffer[1024 -10* 8-1:0], rd_data[10*8-1:0]};
        5'd23 : commonByteBuffer <= {commonByteBuffer[1024 - 9* 8-1:0], rd_data[ 9*8-1:0]};
        5'd24 : commonByteBuffer <= {commonByteBuffer[1024 - 8* 8-1:0], rd_data[ 8*8-1:0]};
        5'd25 : commonByteBuffer <= {commonByteBuffer[1024 - 7* 8-1:0], rd_data[ 7*8-1:0]};
        5'd26 : commonByteBuffer <= {commonByteBuffer[1024 - 6* 8-1:0], rd_data[ 6*8-1:0]};
        5'd27 : commonByteBuffer <= {commonByteBuffer[1024 - 5* 8-1:0], rd_data[ 5*8-1:0]};
        5'd28 : commonByteBuffer <= {commonByteBuffer[1024 - 4* 8-1:0], rd_data[ 4*8-1:0]};
        5'd29 : commonByteBuffer <= {commonByteBuffer[1024 - 3* 8-1:0], rd_data[ 3*8-1:0]};
        5'd30 : commonByteBuffer <= {commonByteBuffer[1024 - 2* 8-1:0], rd_data[ 2*8-1:0]};
        5'd31 : commonByteBuffer <= {commonByteBuffer[1024 - 1* 8-1:0], rd_data[ 1*8-1:0]};
      endcase
    else
      case (rd_data_fullness_dl)
        6'd1  : commonByteBuffer <= {commonByteBuffer[1024 - 1* 8-1:0], rd_data[31*8+:   8]};
        6'd2  : commonByteBuffer <= {commonByteBuffer[1024 - 2* 8-1:0], rd_data[30*8+: 2*8]};
        6'd3  : commonByteBuffer <= {commonByteBuffer[1024 - 3* 8-1:0], rd_data[29*8+: 3*8]};
        6'd4  : commonByteBuffer <= {commonByteBuffer[1024 - 4* 8-1:0], rd_data[28*8+: 4*8]};
        6'd5  : commonByteBuffer <= {commonByteBuffer[1024 - 5* 8-1:0], rd_data[27*8+: 5*8]};
        6'd6  : commonByteBuffer <= {commonByteBuffer[1024 - 6* 8-1:0], rd_data[26*8+: 6*8]};
        6'd7  : commonByteBuffer <= {commonByteBuffer[1024 - 7* 8-1:0], rd_data[25*8+: 7*8]};
        6'd8  : commonByteBuffer <= {commonByteBuffer[1024 - 8* 8-1:0], rd_data[24*8+: 8*8]};
        6'd9  : commonByteBuffer <= {commonByteBuffer[1024 - 9* 8-1:0], rd_data[23*8+: 9*8]};
        6'd10 : commonByteBuffer <= {commonByteBuffer[1024 -10* 8-1:0], rd_data[22*8+:10*8]};
        6'd11 : commonByteBuffer <= {commonByteBuffer[1024 -11* 8-1:0], rd_data[21*8+:11*8]};
        6'd12 : commonByteBuffer <= {commonByteBuffer[1024 -12* 8-1:0], rd_data[20*8+:12*8]};
        6'd13 : commonByteBuffer <= {commonByteBuffer[1024 -13* 8-1:0], rd_data[19*8+:13*8]};
        6'd14 : commonByteBuffer <= {commonByteBuffer[1024 -14* 8-1:0], rd_data[18*8+:14*8]};
        6'd15 : commonByteBuffer <= {commonByteBuffer[1024 -15* 8-1:0], rd_data[17*8+:15*8]};
        6'd16 : commonByteBuffer <= {commonByteBuffer[1024 -16* 8-1:0], rd_data[16*8+:16*8]};
        6'd17 : commonByteBuffer <= {commonByteBuffer[1024 -17* 8-1:0], rd_data[15*8+:17*8]};
        6'd18 : commonByteBuffer <= {commonByteBuffer[1024 -18* 8-1:0], rd_data[14*8+:18*8]};
        6'd19 : commonByteBuffer <= {commonByteBuffer[1024 -19* 8-1:0], rd_data[13*8+:19*8]};
        6'd20 : commonByteBuffer <= {commonByteBuffer[1024 -20* 8-1:0], rd_data[12*8+:20*8]};
        6'd21 : commonByteBuffer <= {commonByteBuffer[1024 -21* 8-1:0], rd_data[11*8+:21*8]};
        6'd22 : commonByteBuffer <= {commonByteBuffer[1024 -22* 8-1:0], rd_data[10*8+:22*8]};
        6'd23 : commonByteBuffer <= {commonByteBuffer[1024 -23* 8-1:0], rd_data[ 9*8+:23*8]};
        6'd24 : commonByteBuffer <= {commonByteBuffer[1024 -24* 8-1:0], rd_data[ 8*8+:24*8]};
        6'd25 : commonByteBuffer <= {commonByteBuffer[1024 -25* 8-1:0], rd_data[ 7*8+:25*8]};
        6'd26 : commonByteBuffer <= {commonByteBuffer[1024 -26* 8-1:0], rd_data[ 6*8+:26*8]};
        6'd27 : commonByteBuffer <= {commonByteBuffer[1024 -27* 8-1:0], rd_data[ 5*8+:27*8]};
        6'd28 : commonByteBuffer <= {commonByteBuffer[1024 -28* 8-1:0], rd_data[ 4*8+:28*8]};
        6'd29 : commonByteBuffer <= {commonByteBuffer[1024 -29* 8-1:0], rd_data[ 3*8+:29*8]};
        6'd30 : commonByteBuffer <= {commonByteBuffer[1024 -30* 8-1:0], rd_data[ 2*8+:30*8]};
        6'd31 : commonByteBuffer <= {commonByteBuffer[1024 -31* 8-1:0], rd_data[ 1*8+:31*8]};
        6'd32 : commonByteBuffer <= {commonByteBuffer[767:0], rd_data};
        default: commonByteBuffer <= {commonByteBuffer[767:0], rd_data};
      endcase
    
reg [8:0] commonByteBufferFullness_dl;
always @ (posedge clk) 
    commonByteBufferFullness_dl <= commonByteBufferFullness;
    
integer s;
reg [255:0] mux_word [3:0];
always @ (*) begin
  for (s = 0; s < 4; s=s+1)
    mux_word[s] = 256'b0; // Default
  if (mux_word_valid[0]) // mux_word_valid = xxx1
    for (i=0; i<32; i=i+1)
      mux_word[0][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-ssm_max_se_size[7:3]+i)*8+:8]; 
  if (mux_word_valid[1]) begin
    if (mux_word_valid[0]) // mux_word_valid = xx11
      for (i=0; i<32; i=i+1)
        mux_word[1][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(ssm_max_se_size[7:3]<<1)+i)*8+:8];
    else // mux_word_valid = xx10
      for (i=0; i<32; i=i+1)
        mux_word[1][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-ssm_max_se_size[7:3]+i)*8+:8];          
  end
  if (mux_word_valid[2]) begin
    if (mux_word_valid[0] & mux_word_valid[1]) // mux_word_valid = x111
      for (i=0; i<32; i=i+1)
        mux_word[2][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(2'd3*ssm_max_se_size[7:3])+i)*8+:8];
    else if (mux_word_valid[0] | mux_word_valid[1]) // mux_word_valid = x101 or x110
      for (i=0; i<32; i=i+1)
        mux_word[2][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(ssm_max_se_size[7:3]<<1)+i)*8+:8];
    else // mux_word_valid = x100
      for (i=0; i<32; i=i+1)
        mux_word[2][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-ssm_max_se_size[7:3]+i)*8+:8]; 
  end
  if (mux_word_valid[3]) begin
    if (&mux_word_valid[2:0]) // mux_word_valid = 1111
      for (i=0; i<32; i=i+1)
        mux_word[3][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(ssm_max_se_size[7:3]<<2)+i)*8+:8];
    else if ((mux_word_valid[0] & mux_word_valid[1]) | (mux_word_valid[0] & mux_word_valid[2]) | (mux_word_valid[1] & mux_word_valid[2])) // // mux_word_valid = 1011 or 1101 or 1110
      for (i=0; i<32; i=i+1)
        mux_word[3][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(2'd3*ssm_max_se_size[7:3])+i)*8+:8];
    else if (|mux_word_valid[2:0]) // mux_word_valid = 1001 or 1010 or 1100
      for (i=0; i<32; i=i+1)
        mux_word[3][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-(ssm_max_se_size[7:3]<<1)+i)*8+:8];
    else // mux_word_valid = 1000
      for (i=0; i<32; i=i+1)
        mux_word[3][i*8+:8] = commonByteBuffer[(commonByteBufferFullness_dl-ssm_max_se_size[7:3]+i)*8+:8];
  end
  /* Sets x for easier debugging
  for (s = 0; s < 4; s=s+1)
    for (i = 0; i < 256; i = i + 1)
      if (i >= ssm_max_se_size)
        mux_word[s][i] = 1'bx; // Default
  */
end

reg [3:0] start_decode_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    start_decode_dl <= 4'b0;
  else
    start_decode_dl <= {start_decode_dl[2:0], start_decode};
assign ssm_sof = start_decode | (|start_decode_dl[2:0]);
wire ssm_sof_pulse;
assign ssm_sof_pulse = start_decode_dl[3];

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    pos_in_block <= 2'd0;
  else if (ssm_sof & mux_word_request_i[0])
    pos_in_block <= 2'd1;
  else
    pos_in_block <= pos_in_block + 1'b1;


reg [2:0] nbr_mux_word_request_i;
always @ (*) begin
  nbr_mux_word_request_i = ((sos_fsm == SOS_FSM_FETCH_SSM0) ? sos_mux_word_request_0 : mux_word_request_i[0]) & ~mux_word_valid[0];
  for (i = 1; i < 4; i = i + 1)
    nbr_mux_word_request_i = nbr_mux_word_request_i + (mux_word_request_i[i] & ~mux_word_valid[i]);
end

wire [3:0] mux_word_request;
wire en_mux_word_request;
assign en_mux_word_request = (((pos_in_block == 2'd0) & ~ssm_sof) | ssm_sof) & ~eos & (commonByteBufferFullness >= (ssm_max_se_size[7:3]<<2)) & ~disable_rcb_rd;
assign mux_word_request[0] = (eos_fsm == 2'b0) & (sos_fsm != SOS_FSM_IDLE) & ((sos_fsm == SOS_FSM_FETCH_SSM0) ? sos_mux_word_request_0 : mux_word_request_i[0]) & ~mux_word_valid[0] & en_mux_word_request;
assign mux_word_request[1] = rate_buf_read_allowed & mux_word_request_i[1] & ~mux_word_valid[1] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
assign mux_word_request[2] = rate_buf_read_allowed & mux_word_request_i[2] & ~mux_word_valid[2] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
assign mux_word_request[3] = rate_buf_read_allowed & mux_word_request_i[3] & ~mux_word_valid[3] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
always @ (posedge clk) 
  if (rate_buf_read_allowed)
    mux_word_valid <= mux_word_request;
  else
    mux_word_valid <= 4'b0; // Default
    

wire [3:0] flush_fs;
assign flush_fs[0] = in_sof | start_decode;
assign flush_fs[1] = in_sof | start_decode;
assign flush_fs[2] = in_sof | start_decode;
assign flush_fs[3] = in_sof | start_decode;

wire [3:0] size_to_remove_valid_i;
assign size_to_remove_valid_i[0] = (sos_fsm == SOS_FSM_PARSE_SSM0) ? substream0_parsed : size_to_remove_valid;
assign size_to_remove_valid_i[3:1] = {size_to_remove_valid, size_to_remove_valid, size_to_remove_valid};

wire [MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed [3:0];
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_ssmFunnelShifter   
    ssmFunnelShifter
    #(
      .MAX_FUNNEL_SHIFTER_SIZE      (MAX_FUNNEL_SHIFTER_SIZE)
    )
    ssmFunnelShifter_u
    (
      .clk                          (clk),
      .rst_n                        (rst_n),
      .flush                        (flush_fs[gi]),
      
      .ssm_max_se_size              (ssm_max_se_size),
      
      .en_funnel_shifter            (rate_buf_read_allowed),
      .mux_word_request             (mux_word_request_i[gi]),
      .mux_word_valid               (mux_word_valid[gi]),
      .mux_word                     (mux_word[gi]),
      .data_to_be_parsed            (data_to_be_parsed[gi]),
      .ready                        (fs_ready[gi]),
      .size_to_remove               (size_to_remove[gi]),
      .size_to_remove_valid         (size_to_remove_valid_i[gi])
    );
  end
endgenerate

// pack outputs
generate
  for (gi=0; gi<4; gi=gi+1) begin : gen_outputs
    assign data_to_be_parsed_p[gi*MAX_FUNNEL_SHIFTER_SIZE+:MAX_FUNNEL_SHIFTER_SIZE] = data_to_be_parsed[gi];
  end
endgenerate
endmodule
  
