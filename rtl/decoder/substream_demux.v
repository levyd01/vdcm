`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module substream_demux
#(
  parameter MAX_FUNNEL_SHIFTER_SIZE = 2*248 - 1
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
  input wire [34:0] sliceNumDwords,
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
  
  output wire [4*MAX_FUNNEL_SHIFTER_SIZE-1:0] data_to_be_parsed_p,
  output wire [3:0] fs_ready,

  input wire substream0_parsed,
  input wire [9*4-1:0] size_to_remove_p,
  input wire size_to_remove_valid

);

parameter RATE_BUFF_NUM_LINES = 512;
parameter RATE_BUFF_ADDR_WIDTH = $clog2(RATE_BUFF_NUM_LINES);

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
reg [255:0] wr_data;  
integer b; 
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    w_en <= 1'b0;
  else begin
    w_en <= in_valid & ~data_in_is_pps;
    if (in_valid)
      for(b=0; b<32; b=b+1)
        wr_data[8*b+:8] = in_data[(31-b)*8+:8];
  end

// Convert rc_init_tx_delay from block time to number of in_data input words    
reg [15:0] initDecodeDelay_i;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    initDecodeDelay_i <= 16'hffff;
  else if (in_sof)
    initDecodeDelay_i <= (rc_init_tx_delay * bits_per_pixel); // TBD !!!! Avoid the multiplier with sequential add & shift
wire [9:0] initDecodeDelay;
assign initDecodeDelay = initDecodeDelay_i >> 8;

reg [9:0] initDecodeDelayCnt;
reg rate_buf_read_allowed;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    initDecodeDelayCnt <= 10'd0;
    rate_buf_read_allowed <= 1'b0;
  end
  else if (early_eos) begin
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

wire rd_en;

reg [15:0] sliceDwordRemaining;
always @ (posedge clk)
  if ((initDecodeDelayCnt == initDecodeDelay - 3'd3) | (early_eos & ~eof))
    sliceDwordRemaining <= sliceNumDwords;
  else if (rd_en)
    sliceDwordRemaining <= sliceDwordRemaining - 1'b1;


wire eos_pulse;
reg eos_dl;
always @ (posedge clk)
  eos_dl <= eos;
assign eos_pulse = eos & ~eos_dl;
wire eos_falling_edge;
assign eos_falling_edge = ~eos & eos_dl;

reg [1:0] pos_in_block;
reg [RATE_BUFF_ADDR_WIDTH-1:0] rate_buffer_addr_r;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
  else if (in_sof)
    rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
  // Bypass garbage at end of slice. See spec. p.157 "SSM needs a small portion of the total slice rate to be set aside to guarantee correct behavior at the end of the slice.  
  else if (early_eos & ~eof) begin
    if (rate_buffer_addr_r + sliceDwordRemaining > RATE_BUFF_NUM_LINES-1)
      rate_buffer_addr_r <= rate_buffer_addr_r + sliceDwordRemaining - RATE_BUFF_NUM_LINES;
    else
      rate_buffer_addr_r <= rate_buffer_addr_r + sliceDwordRemaining;
  end
  else if (rd_en)
    if (rate_buffer_addr_r == RATE_BUFF_NUM_LINES-1)
      rate_buffer_addr_r <= {RATE_BUFF_ADDR_WIDTH{1'b0}};
    else
      rate_buffer_addr_r <= rate_buffer_addr_r + 1'b1;

wire [255:0] rd_data;
wire rd_valid;

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

reg nbr_wrap_around_rd;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    nbr_wrap_around_rd <= 1'b0;
  else if (rd_en & (rate_buffer_addr_r == RATE_BUFF_NUM_LINES-1))
    nbr_wrap_around_rd <= ~nbr_wrap_around_rd;
    
wire buffer_empty;
assign buffer_empty = ~(nbr_wrap_around_wr ^ nbr_wrap_around_rd) & (rate_buffer_addr_w == rate_buffer_addr_r);
wire buffer_full;
assign buffer_full = (nbr_wrap_around_wr ^ nbr_wrap_around_rd) & (rate_buffer_addr_w == rate_buffer_addr_r);
reg overflow;
reg underflow;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    overflow <= 1'b0;
    underflow <= 1'b0;
  end
  else begin
    overflow <= buffer_full & w_en;
    underflow <= buffer_empty & rd_en;
  end

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
  else if ((sos_fsm == SOS_FSM_IDLE) | (early_eos & ~eof))
    fsm_cnt <= 2'd0;
  else if ((sos_fsm == SOS_FSM_FETCH_SSM0) | (sos_fsm == SOS_FSM_PARSE_SSM0))
    fsm_cnt <= fsm_cnt + 1'b1;  
  
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sos_fsm <= SOS_FSM_IDLE;
  else if (flush)
    sos_fsm <= SOS_FSM_IDLE;
  else
    case (sos_fsm)
      SOS_FSM_IDLE      : if (start_decode) sos_fsm <= SOS_FSM_FETCH_SSM0;
      SOS_FSM_FETCH_SSM0: if (fsm_cnt == 2'd3) sos_fsm <= SOS_FSM_PARSE_SSM0;
      SOS_FSM_PARSE_SSM0: if (fsm_cnt == 2'd3) sos_fsm <= SOS_FSM_RUNTIME;
      SOS_FSM_RUNTIME   : if (early_eos) sos_fsm <= SOS_FSM_IDLE;
    endcase

wire sos_rd_en;
assign sos_rd_en = (sos_fsm == SOS_FSM_FETCH_SSM0) | (sos_fsm == SOS_FSM_PARSE_SSM0);
wire sos_mux_word_request_0;
assign sos_mux_word_request_0 = (sos_fsm == SOS_FSM_FETCH_SSM0) & (fsm_cnt == 2'd2);

reg [1:0] sos_fsm_dl;
always @ (posedge clk)
  sos_fsm_dl <= sos_fsm;
assign sos_for_rc = (sos_fsm_dl == SOS_FSM_PARSE_SSM0) & (sos_fsm == SOS_FSM_RUNTIME);

reg [3:0] mux_word_valid;
reg [3:0] num_mux_word_valid;
always @ (*)
  case (mux_word_valid)
    4'b0000:  num_mux_word_valid = 4'd0;
    4'b0001, 4'b0010, 4'b0100, 4'b1000: num_mux_word_valid = 4'd1;
    4'b0011, 4'b0101, 4'b1001, 4'b0110, 4'b1010, 4'b1100: num_mux_word_valid = 4'd2;
    4'b0111, 4'b1011, 4'b1101, 4'b1110: num_mux_word_valid = 4'd3;
    4'b1111: num_mux_word_valid = 4'd4;
    default: num_mux_word_valid = 4'd0;
  endcase

reg [15:0] byte_cnt;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    byte_cnt <= 16'd0;
  else if (in_sof | early_eos | (slices_per_line == 10'd1))
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
  else if (in_sof | (slices_per_line == 10'd1))
      rd_data_fullness <= 6'd32;
  else if (rd_en)
    if ((byte_cnt + 7'd64 >= chunk_size) & (rd_data_fullness == 6'd32))
      rd_data_fullness <= chunk_size - byte_cnt - 6'd32;
    else 
      rd_data_fullness <= 6'd32;

      
reg [8:0] commonByteBufferFullness; // In bytes
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    commonByteBufferFullness <= 8'd0;
  else if ((in_sof & in_valid) | (early_eos & ~eof))
    commonByteBufferFullness <= 8'd0;
  else if (initDecodeDelayCnt >= initDecodeDelay - 3'd2) // Start to fill the common buffer a bit before it is allowed to read
    if (rd_en & ~(|mux_word_valid)) // Only push to commonByteBuffer
      commonByteBufferFullness <= commonByteBufferFullness + rd_data_fullness;
    else if ((|mux_word_valid) & ~rd_en) // Only pull from commonByteBuffer
      commonByteBufferFullness <= commonByteBufferFullness - (num_mux_word_valid*ssm_max_se_size[7:3]);
    else if ((|mux_word_valid) & rd_en) // Push and pull simultaneously
      commonByteBufferFullness <= commonByteBufferFullness - (num_mux_word_valid*ssm_max_se_size[7:3]) + rd_data_fullness;

assign rd_en = rate_buf_read_allowed_dl & (commonByteBufferFullness <= (ssm_max_se_size[7:3]<<2)) & (sos_rd_en | (sos_fsm == SOS_FSM_RUNTIME)) & ~buffer_empty & ~disable_rcb_rd;

reg [5:0] rd_data_fullness_dl;
always @ (posedge clk)
  rd_data_fullness_dl <= rd_data_fullness;

integer i;
parameter MAX_SSM_MAX_SE_SIZE = 160; // 160 bits = 36-bpp maximum for 4:4:4 at 12bpc (see Figure D-6 in spec), per substream
reg [1023:0] commonByteBuffer;
always @ (posedge clk)
  if (rd_valid) 
    case (rd_data_fullness_dl)
      6'd1  : commonByteBuffer <= {commonByteBuffer[1024 - 1* 8-1:0], rd_data[31*8+:   8]};
      6'd2  : commonByteBuffer <= {commonByteBuffer[1024 - 2* 8-1:0], rd_data[30*8+: 2*8]};
      6'd16 : commonByteBuffer <= {commonByteBuffer[1024 -16* 8-1:0], rd_data[16*8+:16*8]};
      6'd32 : commonByteBuffer <= {commonByteBuffer[767:0], rd_data};
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
assign ssm_sof = start_decode | (|start_decode_dl[2:0]);// | eos;
wire ssm_sof_pulse;
assign ssm_sof_pulse = start_decode_dl[3];

reg firstSliceOfFrame;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    firstSliceOfFrame <= 1'b0;
  else if (in_sof)
    firstSliceOfFrame <= 1'b1;
  else if (eos_pulse)
    firstSliceOfFrame <= 1'b0;

wire [3:0] mux_word_request_i;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    pos_in_block <= 2'd0;
  else if (ssm_sof & mux_word_request_i[0])
    pos_in_block <= 2'd1;
  else
    pos_in_block <= pos_in_block + 1'b1;


wire [3:0] mux_word_request;
wire en_mux_word_request;
assign en_mux_word_request = (((pos_in_block == 2'd0) & ~ssm_sof) | ssm_sof) & ~eos & (commonByteBufferFullness >= (ssm_max_se_size[7:3]<<2)) & ~disable_rcb_rd;
assign mux_word_request[0] = (sos_fsm != SOS_FSM_IDLE) & ((sos_fsm == SOS_FSM_FETCH_SSM0) ? sos_mux_word_request_0 : mux_word_request_i[0]) & ~mux_word_valid[0] & en_mux_word_request;
assign mux_word_request[1] = rate_buf_read_allowed & mux_word_request_i[1] & ~mux_word_valid[1] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
assign mux_word_request[2] = rate_buf_read_allowed & mux_word_request_i[2] & ~mux_word_valid[2] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
assign mux_word_request[3] = rate_buf_read_allowed & mux_word_request_i[3] & ~mux_word_valid[3] & ((sos_fsm == SOS_FSM_PARSE_SSM0) | (sos_fsm == SOS_FSM_RUNTIME)) & en_mux_word_request;
always @ (posedge clk or negedge rst_n) 
  if (rate_buf_read_allowed)
    mux_word_valid <= mux_word_request;
  else
    mux_word_valid <= 4'b0; // Default
    

wire [3:0] flush_fs;
assign flush_fs[0] = in_sof | early_eos;
assign flush_fs[1] = in_sof | early_eos;
assign flush_fs[2] = in_sof | early_eos;
assign flush_fs[3] = in_sof | early_eos;

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
  