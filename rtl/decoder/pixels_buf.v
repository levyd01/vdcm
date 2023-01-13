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

// The pixel buffer saves data in the original picture color space. But decoding is not done in RGB.
// Original color space possibilities are: RGB (0) or YCbCr (2)
// Decoding color space possibilies are: YCoCg (1) or YCbCr (2)
// csc = decoding color space
// When writing to the pixel buffer:
//   if csc = YCoCg then convert to RGB before writing.
//   if csc = YCbCr, no conversion is needed.
// Inside the buffer:
//   if csc = YCoCg, it means that the original color space is RGB, so the pixel buffer is in RGB.
//   if csc = YCbCr, it means that the original color space is YCbCr, so the pixel buffer is in YCbCr.
// When reading from the pixel buffer:
//   if csc = YCoCg then convert to YCoCg begore processing.
//   if csc = YCbCr then no conversion is needed.


module pixels_buf
#(
  parameter MAX_SLICE_WIDTH         = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire sos,
  input wire eos,
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [12:0] maxPoint,
  input wire [1:0] chroma_format,
  
  input wire parse_substreams, // Early indcation that the pipe runs/stops
  output wire stall_pull, // indication not to pull new data

  input wire pReconBlk_valid,
  input wire [2*8*3*14-1:0] pReconBlk_p,
  
  input wire decoding_proc_rd_req,
  input wire block_push,
  output wire [16*3*14-1:0] pixelsAboveForTrans_p, // 16 pixels for Transform (4 to the left above the current, 8 exactly above, and 4 to the right above)
  output wire [33*3*14-1:0] pixelsAboveForBp_p, // 33 pixels above for BP (A0 to A7 and B0 to B24)
  output wire [8*3*14-1:0] pixelsAboveForMpp_p, // 8 pixels above for MPP (for non-FBLS mean calculation)
  output wire decoding_proc_rd_valid

);

genvar cpi, gc, gr;
// unpack input
wire signed [13:0] pReconBlk [2:0][1:0][7:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_pReconBlk_cpi
    for (gr=0; gr<2; gr=gr+1) begin : gen_pReconBlk_gr
      for (gc=0; gc<8; gc=gc+1)  begin : gen_pReconBlk_gc
        assign pReconBlk[cpi][gr][gc] = pReconBlk_p[(cpi*16+gr*8+gc)*14+:14];
      end
    end
  end
endgenerate

wire signed [13:0] src_y  [7:0];
wire signed [13:0] src_co [7:0];
wire signed [13:0] src_cg [7:0];
generate
  for (gc=0; gc<8; gc=gc+1) begin // TBD 4:2:2 and 4:2:0
    assign src_y [gc] = pReconBlk[0][1][gc];
    assign src_co[gc] = (chroma_format < 2'd2) ? pReconBlk[1][1][gc] : pReconBlk[1][0][gc];
    assign src_cg[gc] = (chroma_format < 2'd2) ? pReconBlk[2][1][gc] : pReconBlk[2][0][gc];
  end
endgenerate

wire [11:0] dst_r [7:0];
wire [11:0] dst_g [7:0];
wire [11:0] dst_b [7:0];
generate
  for (gc=0; gc<8; gc=gc+1) begin : gen_rgb_gc
    ycocg2rgb ycocg2rgb_u
      (
        .maxPoint         (maxPoint),
        .src_y            (src_y[gc]),
        .src_co           (src_co[gc]),
        .src_cg           (src_cg[gc]),
        .dst_r            (dst_r[gc]),
        .dst_g            (dst_g[gc]),
        .dst_b            (dst_b[gc])
      );
  end
endgenerate

// If csc is YCoCg, it means that the original format is RGB -> convert to RGB. Otherwise (csc = YCbCr), no conversion is needed
integer cp, ci;
reg [11:0] rgb_reg [2:0][7:0];
always @ (posedge clk)
  if (pReconBlk_valid)
    for (cp=0; cp<3; cp=cp+1)
      for (ci=0; ci<8; ci=ci+1)
        case(cp)
          2'd0: rgb_reg[0][ci] <= (csc == 2'd1) ? dst_r[ci] : pReconBlk[0][1][ci];
          2'd1: rgb_reg[1][ci] <= (csc == 2'd1) ? dst_g[ci] : ((chroma_format < 2'd2) ? pReconBlk[1][1][ci] : pReconBlk[1][0][ci]);
          2'd2: rgb_reg[2][ci] <= (csc == 2'd1) ? dst_b[ci] : ((chroma_format < 2'd2) ? pReconBlk[2][1][ci] : pReconBlk[2][0][ci]);
        endcase

reg [6:0] pReconBlk_valid_dl;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    pReconBlk_valid_dl <= 7'b0;
  else
    pReconBlk_valid_dl <= {pReconBlk_valid_dl[5:0], pReconBlk_valid};
	
wire [2:0] colIndexStart; // Columns to work with when writing data to RAM
assign colIndexStart = pReconBlk_valid_dl[3] ? 3'd4 : 3'd0;
          
reg [11:0] csc_lb_data_wr [2:0][3:0]; // data to save to RAM
always @ (posedge clk)
  if (|pReconBlk_valid_dl[3:2])
    for (cp=0; cp<3; cp=cp+1) begin
      if ((chroma_format > 2'd0) & (cp > 0)) begin
        for (ci=0; ci<8; ci=ci+1)
          if ((ci >= colIndexStart>>1) & (ci < ((colIndexStart>>1)+2)))
            csc_lb_data_wr[cp][ci-(colIndexStart>>1)] <= rgb_reg[cp][ci];
      end
      else
        for (ci=0; ci<8; ci=ci+1) 
          if ((ci >= colIndexStart) & (ci<(colIndexStart+4)))
          csc_lb_data_wr[cp][ci-colIndexStart] <= rgb_reg[cp][ci];
    end
        
integer dl;
reg [11:0] csc_lb_data_wr_dl [1:0][2:0][3:0]; // data to save to RAM delayed to avoid wr and rd on same cycles
always @ (posedge clk)
    for (cp=0; cp<3; cp=cp+1)
      for (ci=0; ci<8; ci=ci+1)
        if ((ci >= colIndexStart) & (ci<(colIndexStart+4))) begin
        csc_lb_data_wr_dl[0][cp][ci-colIndexStart] <= csc_lb_data_wr[cp][ci-colIndexStart];
        csc_lb_data_wr_dl[1][cp][ci-colIndexStart] <= csc_lb_data_wr_dl[0][cp][ci-colIndexStart];
      end
  
// Line buffer
wire wr_pixels_buf_en;
wire [3*4*12-1:0] wr_pixels_buf_data;

assign wr_pixels_buf_en = |pReconBlk_valid_dl[6:5];

generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_wr_pixels_buf_data_cpi
    for (gc=0; gc<4; gc=gc+1) begin : gen_wr_pixels_buf_data_gc
      assign wr_pixels_buf_data[(cpi*4+gc)*12+:12] = csc_lb_data_wr_dl[1][cpi][gc];
    end
  end
endgenerate

localparam ADDR_WIDTH = $clog2((MAX_SLICE_WIDTH>>2)+1);

reg sof;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    sof <= 1'b1;
  else if (flush)
    sof <= 1'b1;
  else if (pReconBlk_valid)
    sof <= 1'b0;


wire [ADDR_WIDTH-1:0] ram_lines;
assign ram_lines = slice_width>>2;

reg [ADDR_WIDTH-1:0] wr_pixels_buf_addr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
	  wr_pixels_buf_addr <= {ADDR_WIDTH{1'b0}};
  else if (sof)
	  wr_pixels_buf_addr <= {ADDR_WIDTH{1'b0}};   
  else if (wr_pixels_buf_en)
		if (wr_pixels_buf_addr == ram_lines - 1'b1)
		  wr_pixels_buf_addr <= {ADDR_WIDTH{1'b0}};
		else
		  wr_pixels_buf_addr <= wr_pixels_buf_addr + 1'b1;

reg [3:0] decoding_proc_rd_req_dl;
always @ (posedge clk)
  decoding_proc_rd_req_dl <= {decoding_proc_rd_req_dl[2:0], decoding_proc_rd_req};
  
wire ram_rd_en;
assign ram_rd_en = decoding_proc_rd_req | decoding_proc_rd_req_dl[0];
reg [ADDR_WIDTH-1:0] ram_rd_addr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    ram_rd_addr <= {ADDR_WIDTH{1'b0}};
  else if (flush)
    ram_rd_addr <= {ADDR_WIDTH{1'b0}};
  else if (sos)
    ram_rd_addr <= {ADDR_WIDTH{1'b0}};
  else if (ram_rd_en)
    if (ram_rd_addr == ram_lines - 1'b1)
      ram_rd_addr <= {ADDR_WIDTH{1'b0}};
    else
      ram_rd_addr <= ram_rd_addr + 1'b1;

wire ram_data_valid;
wire [4*3*12-1:0] ram_data_rd;
wire cs;
assign cs = wr_pixels_buf_en | ram_rd_en;
wire [ADDR_WIDTH-1:0] addr;
assign addr = wr_pixels_buf_en ? wr_pixels_buf_addr : ram_rd_addr;

  
sp_ram
#(
  .NUMBER_OF_LINES       ((MAX_SLICE_WIDTH>>2)+1),
  .DATA_WIDTH            (3*4*12) // 4 Pixels per access (all on the same row)
)
prev_line_ram_u
(
  .clk                   (clk),
  .cs                    (cs),
  .w_en                  (wr_pixels_buf_en),
  .addr                  (addr),
  .wr_data               (wr_pixels_buf_data),
  .rd_data               (ram_data_rd),
  .mem_valid             (ram_data_valid)
);

integer c;
integer p;
reg [11:0] pixelFromRam [2:0][3:0];
always @ (posedge clk)
  if (ram_data_valid)
    for (c = 0; c < 3; c = c + 1)
      for (p = 0; p < 4; p = p + 1)      
        pixelFromRam[c][p] <= ram_data_rd[(c*4+p)*12+:12];

// Convert from RGB to YCoCg
genvar gp;
wire signed [13:0] pixelForDecodingProc [2:0][3:0];
wire signed [13:0] pixelConvertedToYCoCg [2:0][3:0];
generate
  for (gp = 0; gp < 4; gp = gp + 1) begin : gen_rgb2ycocg
    rgb2ycocg rgb2ycocg_u
    (
      .src_r   (pixelFromRam[0][gp]),
      .src_g   (pixelFromRam[1][gp]),
      .src_b   (pixelFromRam[2][gp]),
      .dst_y   (pixelConvertedToYCoCg[0][gp]),
      .dst_co  (pixelConvertedToYCoCg[1][gp]),
      .dst_cg  (pixelConvertedToYCoCg[2][gp])
    );
    for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_pixelForDecodingProc_cpi
      assign pixelForDecodingProc[cpi][gp] = (csc == 2'd1) ? pixelConvertedToYCoCg[cpi][gp] : pixelFromRam[cpi][gp];
    end
  end
endgenerate

reg ram_data_valid_dl;
always @ (posedge clk)
  ram_data_valid_dl <= ram_data_valid;
  
localparam PIXELS_FIFO_SIZE = 40;
reg signed [13:0] pixelsShiftReg [2:0][PIXELS_FIFO_SIZE-1:0];
always @ (posedge clk)
  if (ram_data_valid_dl)
    for (c = 0; c < 3; c = c + 1) begin
      for (p = 0; p < 4; p = p + 1) 
        pixelsShiftReg[c][3-p] <= pixelForDecodingProc[c][p];
      for (p = 4; p < PIXELS_FIFO_SIZE; p = p + 1)
        pixelsShiftReg[c][p] <= pixelsShiftReg[c][p - 4];    
    end

reg rd_active;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    rd_active <= 1'b0;
  else if (flush | sos)
    rd_active <= 1'b0;
  else if (decoding_proc_rd_req)
    rd_active <= 1'b1;

wire push;
assign push = rd_active & decoding_proc_rd_req_dl[3];
wire pull;
assign pull = rd_active & ~block_push & parse_substreams;

reg [1:0] wr_ptr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    wr_ptr <= 2'b0;
  else if (flush | sos)
    wr_ptr <= 2'b0;
  else if (push)
    wr_ptr <= wr_ptr + 1'b1;
    
reg wrap_wr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    wrap_wr <= 1'b0;
  else if (flush | sos)
    wrap_wr <= 1'b0;
  else if (push & (wr_ptr == 2'd3))
    wrap_wr <= ~wrap_wr;
    
reg [1:0] rd_ptr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    rd_ptr <= 2'b0;
  else if (flush | sos)
    rd_ptr <= 2'b0;
  else if (pull)
    rd_ptr <= rd_ptr + 1'b1;
    
reg wrap_rd;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    wrap_rd <= 1'b0;
  else if (flush | sos)
    wrap_rd <= 1'b0;
  else if (pull & (rd_ptr == 2'd3))
    wrap_rd <= ~wrap_rd;

assign decoding_proc_rd_valid = rd_active & ((decoding_proc_rd_req_dl[3] & ~push) | parse_substreams);

reg [13:0] fifo [3:0][2:0][PIXELS_FIFO_SIZE-1:0];
always @ (posedge clk)
  if (push)
    for (c = 0; c < 3; c = c + 1)
      for (p = 0; p < PIXELS_FIFO_SIZE; p = p + 1)
        fifo[wr_ptr][c][p] <= pixelsShiftReg[c][p];

wire fifo_empty;
assign fifo_empty = ~(wrap_rd ^ wrap_wr) & (rd_ptr == wr_ptr);

assign stall_pull = fifo_empty & ~push & rd_active;

reg fifo_underflow;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    fifo_underflow <= 1'b0;
  else if (flush)
    fifo_underflow <= 1'b0;
  else if (fifo_empty & pull & ~push)
    fifo_underflow <= 1'b1;

wire fifo_full;
assign fifo_full = (wrap_rd ^ wrap_wr) & (rd_ptr == wr_ptr);
reg signed [13:0] alt_pixelsShiftReg [2:0][PIXELS_FIFO_SIZE-1:0];
always @ (*)
  for (c = 0; c < 3; c = c + 1)
    for (p = 0; p < PIXELS_FIFO_SIZE; p = p + 1)
      if (fifo_empty)
        alt_pixelsShiftReg[c][p] = pixelsShiftReg[c][p];
      else
        alt_pixelsShiftReg[c][p] = fifo[rd_ptr][c][p];

genvar compi;
genvar coli;
generate
  for (compi = 0; compi < 3; compi = compi + 1) begin : gen_pixelsAbove_comp
    for (coli = 0; coli < 33; coli = coli + 1) begin : gen_pixelsAboveForBp_col
      assign pixelsAboveForBp_p[(33*compi + coli)*14+:14] = alt_pixelsShiftReg[compi][coli+7];
    end
    for (coli = 0; coli < 16; coli = coli + 1) begin : gen_pixelsAboveForTransform_col
      assign pixelsAboveForTrans_p[(16*compi + coli)*14+:14] = alt_pixelsShiftReg[compi][31-coli];
    end
    for (coli = 0; coli < 8; coli = coli + 1) begin : gen_pixelsAboveForMpp_col
      assign pixelsAboveForMpp_p[(8*compi + coli)*14+:14] = alt_pixelsShiftReg[compi][31-coli];
    end
  end
endgenerate
  
endmodule