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

module output_buffers
#(
  parameter MAX_SLICE_WIDTH         = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  input wire sof,
  
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [1:0] chroma_format,
  
  input wire cscBlk_valid,
  input wire [2*8*3*14-1:0] cscBlk_p, // 4 pixels: {p3c2, p2c2, p1c2, p0c2, p3c1, p2c1, p1c1, p0c1, p3c0, p2c0, p1c0, p0c0}
  
  output wire out_sof,
  output wire [4*3*14-1:0] out_data_p, // 4 pixels: {p3c2, p3c1, p3c0, p2c2, p2c1, p2c0, p1c2, p1c1, p1c0, p0c2, p0c1, p0c0}
  output reg out_data_valid

);

genvar cpi, gc, gr;
// unpack input
wire signed [13:0] cscBlk [2:0][1:0][7:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_cscBlk_cpi
    for (gr=0; gr<2; gr=gr+1) begin : gen_cscBlk_gr
      for (gc=0; gc<8; gc=gc+1) begin : gen_cscBlk_gc
        assign cscBlk[cpi][gr][gc] = cscBlk_p[(cpi*16+gr*8+gc)*14+:14];
      end
    end
  end
endgenerate

reg [6:0] cscBlk_valid_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    cscBlk_valid_dl <= 7'b0;
  else
    cscBlk_valid_dl <= {cscBlk_valid_dl[5:0], cscBlk_valid};

// Even row buffer
// ---------------
// Write interface
integer cp;
integer r;
integer c;
integer dl;
reg [13:0] cscBlk_4pix_even_dl [2:0][3:0]; // save the 4 even row pixels that cannot be processed immediately.
always @ (posedge clk) 
  if (cscBlk_valid)
    for (cp=0; cp<3; cp=cp+1)
      if (cp > 0)
        case (chroma_format)
          2'd0: 
            for (c=0; c<4; c=c+1)
              cscBlk_4pix_even_dl[cp][c] <= cscBlk[cp][0][c+4];
          2'd1, 2'd2: 
            for (c=0; c<2; c=c+1)
              cscBlk_4pix_even_dl[cp][c] <= cscBlk[cp][0][c+2];
          default:
            for (c=0; c<4; c=c+1)
              cscBlk_4pix_even_dl[cp][c] <= cscBlk[cp][0][c+4];
        endcase
      else
        for (c=0; c<4; c=c+1)
          cscBlk_4pix_even_dl[cp][c] <= cscBlk[cp][0][c+4];

wire even_row_data_valid;
wire odd_row_data_valid;
assign even_row_data_valid = cscBlk_valid | cscBlk_valid_dl[0];
assign odd_row_data_valid = |cscBlk_valid_dl[2:1];

wire isSliceWidthDivBy8;
//assign isSliceWidthDivBy8 = (slice_width == ((slice_width>>3)<<3));
assign isSliceWidthDivBy8 = ~|slice_width[3:0];

localparam ER_MAX_NBR_LINES = (MAX_SLICE_WIDTH>>3)+1;
localparam ER_ADDR_WIDTH = $clog2(ER_MAX_NBR_LINES);
//reg [ER_ADDR_WIDTH-1:0] er_num_lines;
reg [ER_ADDR_WIDTH-1:0] er_wr_num_lines;
reg first_half_of_slice_wr;
always @ (posedge clk)
  if (sof)
    if (isSliceWidthDivBy8)
      er_wr_num_lines <= slice_width>>3;
    else
      er_wr_num_lines <= (slice_width>>3) + 1'b1;
  else if (isSliceWidthDivBy8)
    er_wr_num_lines <= slice_width>>3;
  else
    er_wr_num_lines <= first_half_of_slice_wr ? (slice_width>>3) + 1'b1 : (slice_width>>3) - 1'b1;

reg [ER_ADDR_WIDTH-1:0] er_addr_wr;
always @ (posedge clk)
  if (sof) begin
    er_addr_wr <= {ER_ADDR_WIDTH{1'b0}};
    first_half_of_slice_wr <= 1'b1;
  end
  else if (even_row_data_valid)
    if (er_addr_wr == er_wr_num_lines - 1'b1) begin
      first_half_of_slice_wr <= ~first_half_of_slice_wr;
      er_addr_wr <= {ER_ADDR_WIDTH{1'b0}};
    end
    else
      er_addr_wr <= er_addr_wr + 1'b1;
      
wire er_wr_wrap;
assign er_wr_wrap = ~first_half_of_slice_wr;

wire [4*3*14-1:0] er_wr_data_p;
wire [13:0] er_wr_data [3:0][2:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_er_data_p_cpi
    for (gc=0; gc<4; gc=gc+1) begin : gen_er_data_p_gc
      assign er_wr_data[gc][cpi] = cscBlk_valid ? cscBlk[cpi][0][gc] : cscBlk_4pix_even_dl[cpi][gc];
      assign er_wr_data_p[(gc*3+cpi)*14+:14] = er_wr_data[gc][cpi];
    end
  end
endgenerate

// Read interface
wire er_start_read;
reg first_half_of_slice_wr_dl;
always @ (posedge clk)
  first_half_of_slice_wr_dl <= first_half_of_slice_wr;
assign er_start_read = ~first_half_of_slice_wr & first_half_of_slice_wr_dl;

reg [1:0] er_rd_state;
reg [ER_ADDR_WIDTH-1:0] er_rd_num_lines;
reg [ER_ADDR_WIDTH-1:0] er_addr_rd;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    er_rd_state <= 2'b0;
  else if (sof)
    er_rd_state <= 2'b0;
  else
    case (er_rd_state) 
      2'd0: if (er_start_read) er_rd_state <= 2'd1;
      2'd1: if (er_addr_rd == er_rd_num_lines/*er_num_lines*/ - 1'b1) er_rd_state <= 2'd2;
      2'd2: if (er_addr_rd == er_rd_num_lines/*er_num_lines*/ - 1'b1) er_rd_state <= 2'b0;
      default: er_rd_state <= 2'b0;
    endcase
    
always @ (posedge clk)
  if (sof)
    if (isSliceWidthDivBy8)
      er_rd_num_lines <= slice_width>>3;
    else
      er_rd_num_lines <= (slice_width>>3) + 1'b1;
  else if (isSliceWidthDivBy8)
    er_rd_num_lines <= slice_width>>3;
  else if (er_rd_state == 2'd1)
    er_rd_num_lines <= (slice_width>>3) + 1'b1;
 else if (er_rd_state == 2'd2)
    er_rd_num_lines <= (slice_width>>3) - 1'b1;
    
wire er_rd_en;
wire er_empty;
assign er_rd_en = (|er_rd_state) & ~er_empty;

reg er_rd_wrap;
always @ (posedge clk)
  if (sof) begin
    er_addr_rd <= {ER_ADDR_WIDTH{1'b0}};
    er_rd_wrap <= 1'b0;
  end
  else if (er_rd_en)
    if (er_addr_rd == er_rd_num_lines/*er_num_lines*/ - 1'b1) begin
      er_rd_wrap <= ~er_rd_wrap;
      er_addr_rd <= {ER_ADDR_WIDTH{1'b0}};
    end
    else
      er_addr_rd <= er_addr_rd + 1'b1;
      
wire er_data_valid;
wire [4*3*14-1:0] er_rd_data_i_p;

assign er_empty = (er_addr_rd == er_addr_wr) & ~(er_rd_wrap ^ er_wr_wrap);

`ifdef SIM_DEBUG
  integer er_fullness;
  always @ (*)
    er_fullness = ~(er_rd_wrap ^ er_wr_wrap) ? er_addr_wr - er_addr_rd : er_wr_num_lines + er_addr_wr - er_addr_rd;
                                               
`endif

// Half slice size buffer 
dp_ram
#(
  .NUMBER_OF_LINES       (ER_MAX_NBR_LINES),
  .DATA_WIDTH            (3*4*14)
)
even_row_buf
(
  .clk          (clk),
  .w_en         (even_row_data_valid),
  .r_en         (er_rd_en),
  .addr_w       (er_addr_wr),
  .addr_r       (er_addr_rd),
  .wr_data      (er_wr_data_p),
  .rd_data      (er_rd_data_i_p),
  .mem_valid    (er_data_valid)
);

// Resolve simultaneous read and write to the same address - bypass RAM
wire needBypass;
assign needBypass = er_rd_en & even_row_data_valid & (er_addr_wr == er_addr_rd);
reg [4*3*14-1:0] er_rd_data_b_p; // Data that bypasses the RAM directly from write to read
always @ (posedge clk)
  if (needBypass)
    er_rd_data_b_p <= er_wr_data_p;
    
reg needBypass_dl;
always @ (posedge clk)
  needBypass_dl <= needBypass;
wire [4*3*14-1:0] er_rd_data_p;
assign er_rd_data_p = needBypass_dl ? er_rd_data_b_p : er_rd_data_i_p;

// Odd row buffer
// --------------
// Write interface
reg [13:0] cscBlk_8pix_odd_dl [2:0][2:0][7:0]; // save the 8 odd row pixels that cannot be processed immediately.
always @ (posedge clk) begin
  if (cscBlk_valid)
    for (cp=0; cp<3; cp=cp+1)
      if (cp > 0)
        case (chroma_format)
          2'd0: 
            for (c=0; c<8; c=c+1)
              cscBlk_8pix_odd_dl[0][cp][c] <= cscBlk[cp][1][c];
          2'd1, 2'd2:
            for (c=0; c<4; c=c+1)
              if (c < 2)
                cscBlk_8pix_odd_dl[0][cp][c] <= cscBlk[cp][1][c];
              else
                cscBlk_8pix_odd_dl[0][cp][2+c] <= cscBlk[cp][1][c];
          default:
            for (c=0; c<8; c=c+1)
              cscBlk_8pix_odd_dl[0][cp][c] <= cscBlk[cp][1][c];
        endcase
      else
        for (c=0; c<8; c=c+1)
          cscBlk_8pix_odd_dl[0][cp][c] <= cscBlk[cp][1][c];
  for(dl=1; dl<3; dl=dl+1)
    for (cp=0; cp<3; cp=cp+1)
      for (c=0; c<8; c=c+1)
        cscBlk_8pix_odd_dl[dl][cp][c] <= cscBlk_8pix_odd_dl[dl-1][cp][c];
end

localparam OR_MAX_NBR_LINES = MAX_SLICE_WIDTH>>2;
localparam OR_ADDR_WIDTH = $clog2(OR_MAX_NBR_LINES);
wire [OR_ADDR_WIDTH-1:0] or_num_lines;
assign or_num_lines = slice_width>>2;

reg [OR_ADDR_WIDTH-1:0] or_addr_wr;
reg or_wr_wrap;
always @ (posedge clk)
  if (sof) begin
    or_addr_wr <= {OR_ADDR_WIDTH{1'b0}};
    or_wr_wrap <= 1'b0;
  end
  else if (odd_row_data_valid)
    if (or_addr_wr == or_num_lines - 1'b1) begin
      or_addr_wr <= {OR_ADDR_WIDTH{1'b0}};
      or_wr_wrap <= ~or_wr_wrap;
    end
    else
      or_addr_wr <= or_addr_wr + 1'b1;
      
wire [4*3*14-1:0] or_wr_data_p;
generate
  for (gc=0; gc<4; gc=gc+1) begin : gen_or_data_p_gc
    for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_or_data_p_cpi
      assign or_wr_data_p[(gc*3+cpi)*14+:14] = cscBlk_valid_dl[1] ? cscBlk_8pix_odd_dl[1][cpi][gc] : cscBlk_8pix_odd_dl[2][cpi][gc+4];
    end
  end
endgenerate

// Read interface
reg or_rd_en;
reg [OR_ADDR_WIDTH-1:0] or_addr_rd;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    or_rd_en <= 1'b0;
  else if (sof | (or_addr_rd == or_num_lines - 1'b1))
    or_rd_en <= 1'b0;
  else if ((er_addr_rd == er_rd_num_lines/*er_num_lines*/ - 1'b1) & (er_rd_state == 2'd2))
    or_rd_en <= 1'b1;
    
reg or_rd_wrap;
wire or_empty;
assign or_empty = (or_addr_rd == or_addr_wr) & ~(or_rd_wrap ^ or_wr_wrap);

`ifdef SIM_DEBUG
  integer or_fullness;
  always @ (*)
    or_fullness = ~(or_rd_wrap ^ or_wr_wrap) ? or_addr_wr - or_addr_rd : or_num_lines + or_addr_wr - or_addr_rd;
                                               
`endif


always @ (posedge clk)
  if (sof) begin
    or_addr_rd <= {OR_ADDR_WIDTH{1'b0}};
    or_rd_wrap <= 1'b0;
  end
  else if (or_rd_en & ~or_empty)
    if (or_addr_rd == or_num_lines - 1'b1) begin
      or_addr_rd <= {OR_ADDR_WIDTH{1'b0}};
      or_rd_wrap <= ~or_rd_wrap;
    end
    else
      or_addr_rd <= or_addr_rd + 1'b1;
      
wire or_data_valid;
wire [4*3*14-1:0] or_rd_data_p;

// One slice size buffer 
dp_ram
#(
  .NUMBER_OF_LINES       (OR_MAX_NBR_LINES),
  .DATA_WIDTH            (3*4*14)
)
odd_row_buf
(
  .clk          (clk),
  .w_en         (odd_row_data_valid),
  .r_en         (or_rd_en),
  .addr_w       (or_addr_wr),
  .addr_r       (or_addr_rd),
  .wr_data      (or_wr_data_p),
  .rd_data      (or_rd_data_p),
  .mem_valid    (or_data_valid)
);

wire [13:0] or_wr_data [3:0][2:0];
wire [13:0] or_rd_data [3:0][2:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_or_wr_data_cpi
    for (gc=0; gc<4; gc=gc+1) begin : gen_or_wr_data_gc
      assign or_wr_data[gc][cpi] = or_wr_data_p[(gc*3+cpi)*14+:14];
      assign or_rd_data[gc][cpi] = or_rd_data_p[(gc*3+cpi)*14+:14];
    end
  end
endgenerate
      
reg [13:0] out_data [2:0][3:0];
always @ (posedge clk) begin
  for (cp=0; cp<3; cp=cp+1)
    for (c=0; c<4; c=c+1)
      out_data[cp][c] <= er_data_valid ? er_rd_data_p[(c*3+cp)*14+:14] : or_rd_data_p[(c*3+cp)*14+:14];
  out_data_valid <= er_data_valid | or_data_valid;
end

reg [1:0] sof_out_state;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sof_out_state <= 2'b0;
  else
    case (sof_out_state)
      2'd0: if (sof) sof_out_state <= 2'd1;
      2'd1: if (er_rd_en) sof_out_state <= 2'd2;
      2'd2: sof_out_state <= 2'b0;
      default: sof_out_state <= 2'b0;
    endcase
assign out_sof = (sof_out_state == 2'd2);
   
// Pack output 
generate
  for (gc=0; gc<4; gc=gc+1) begin : gen_out_data_p_gc
    for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_out_data_p_cpi
      assign out_data_p[(gc*3+cpi)*14+:14] = out_data[cpi][gc];
    end
  end
endgenerate
      
      
endmodule
