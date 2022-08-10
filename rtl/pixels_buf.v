module pixels_buf
#(
  parameter MAX_SLICE_WIDTH         = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire sos,
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [12:0] maxPoint,
  
  input wire pReconBlk_valid,
  input wire [2*8*3*14-1:0] pReconBlk_p,
  
  input decoding_proc_rd_req,
  output wire [16*3*14-1:0] pixelsAboveForTrans_p, // 16 pixels for Transform (4 to the left above the current, 8 exactly above, and 4 to the right above)
  output wire [33*3*14-1:0] pixelsAboveForBp_p, // 33 pixels above for BP (A0 to A7 and B0 to B24)
  output wire decoding_proc_rd_valid

);

genvar cpi, gc, gr;
// unpack input
wire signed [13:0] pReconBlk [2:0][1:0][7:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_pReconBlk_cpi
    for (gr=0; gr<2; gr=gr+1) begin : gen_pReconBlk_gr
      for (gc=0; gc<8; gc=gc+1)  begin : gen_pReconBlk_gc // TBD 4:2:2 and 4:2:0
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
    assign src_co[gc] = pReconBlk[1][1][gc];
    assign src_cg[gc] = pReconBlk[2][1][gc];
  end
endgenerate

integer cp, ci;
reg signed [13:0] temp_wr;
reg signed [13:0] R_wr, G_wr, B_wr;
reg [11:0] dst_r [7:0];
reg [11:0] dst_g [7:0];
reg [11:0] dst_b [7:0];
always @ (*)
  for (ci=0; ci<8; ci=ci+1) begin
    temp_wr = src_y[ci] - (src_cg[ci] >>> 1);
    G_wr = src_cg[ci] + temp_wr;
    B_wr = temp_wr - (src_co[ci] >>> 1);
    R_wr = B_wr + src_co[ci];
    case (maxPoint)
      12'd255:
        begin
          if (G_wr[13]) dst_g[ci] = 12'd0; else if (|G_wr[12:8]) dst_g[ci] = 12'd255; else dst_g[ci] = G_wr[11:0];
          if (B_wr[13]) dst_b[ci] = 12'd0; else if (|B_wr[12:8]) dst_b[ci] = 12'd255; else dst_b[ci] = B_wr[11:0];
          if (R_wr[13]) dst_r[ci] = 12'd0; else if (|R_wr[12:8]) dst_r[ci] = 12'd255; else dst_r[ci] = R_wr[11:0];
        end
      12'd1023:
        begin
          if (G_wr[13]) dst_g[ci] = 12'd0; else if (|G_wr[12:10]) dst_g[ci] = 12'd1023; else dst_g[ci] = G_wr[11:0];
          if (B_wr[13]) dst_b[ci] = 12'd0; else if (|B_wr[12:10]) dst_b[ci] = 12'd1023; else dst_b[ci] = B_wr[11:0];
          if (R_wr[13]) dst_r[ci] = 12'd0; else if (|R_wr[12:10]) dst_r[ci] = 12'd1023; else dst_r[ci] = R_wr[11:0];
        end
      12'd1023:
        begin
          if (G_wr[13]) dst_g[ci] = 12'd0; else if (G_wr[12]) dst_g[ci] = 12'd4095; else dst_g[ci] = G_wr[11:0];
          if (B_wr[13]) dst_b[ci] = 12'd0; else if (B_wr[12]) dst_b[ci] = 12'd4095; else dst_b[ci] = B_wr[11:0];
          if (R_wr[13]) dst_r[ci] = 12'd0; else if (R_wr[12]) dst_r[ci] = 12'd4095; else dst_r[ci] = R_wr[11:0];
        end
      default:
        begin
          if (G_wr[13]) dst_g[ci] = 12'd0; else if (|G_wr[12:8]) dst_g[ci] = 12'd255; else dst_g[ci] = G_wr[11:0];
          if (B_wr[13]) dst_b[ci] = 12'd0; else if (|B_wr[12:8]) dst_b[ci] = 12'd255; else dst_b[ci] = B_wr[11:0];
          if (R_wr[13]) dst_r[ci] = 12'd0; else if (|R_wr[12:8]) dst_r[ci] = 12'd255; else dst_r[ci] = R_wr[11:0];
        end
    endcase
  end

reg [11:0] rgb_reg [2:0][7:0];
always @ (posedge clk)
  if (pReconBlk_valid)
    for (cp=0; cp<3; cp=cp+1)
      for (ci=0; ci<8; ci=ci+1)
        case(cp)
          2'd0: rgb_reg[0][ci] <= (csc == 2'd1) ? dst_r[ci] : pReconBlk[0][1][ci];
          2'd1: rgb_reg[1][ci] <= (csc == 2'd1) ? dst_g[ci] : pReconBlk[1][1][ci];
          2'd2: rgb_reg[2][ci] <= (csc == 2'd1) ? dst_b[ci] : pReconBlk[2][1][ci];
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
    for (cp=0; cp<3; cp=cp+1)
      for (ci=colIndexStart; ci<(colIndexStart+4); ci=ci+1) 
        csc_lb_data_wr[cp][ci-colIndexStart] <= rgb_reg[cp][ci];
        
integer dl;
reg [11:0] csc_lb_data_wr_dl [1:0][2:0][3:0]; // data to save to RAM delayed to avoid wr and rd on same cycles
always @ (posedge clk)
    for (cp=0; cp<3; cp=cp+1)
      for (ci=colIndexStart; ci<(colIndexStart+4); ci=ci+1) begin
        csc_lb_data_wr_dl[0][cp][ci-colIndexStart] <= csc_lb_data_wr[cp][ci-colIndexStart];
        csc_lb_data_wr_dl[1][cp][ci-colIndexStart] <= csc_lb_data_wr_dl[0][cp][ci-colIndexStart];
      end
  
// Line buffer
wire wr_pixels_buf_en;
wire [3*4*12-1:0] wr_pixels_buf_data;

assign wr_pixels_buf_en = |pReconBlk_valid_dl[6:5/*4:3*/];

generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_wr_pixels_buf_data_cpi
    for (gc=0; gc<4; gc=gc+1) begin : gen_wr_pixels_buf_data_gc
      assign wr_pixels_buf_data[(cpi*4+gc)*12+:12] = csc_lb_data_wr_dl[1][cpi][gc];
    end
  end
endgenerate

parameter ADDR_WIDTH = $clog2((MAX_SLICE_WIDTH>>2)+1);

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
  
assign decoding_proc_rd_valid = decoding_proc_rd_req_dl[3];

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
    
reg signed [13:0] pixelForDecodingProc [2:0][3:0];
reg signed [13:0] temp_rd;
reg signed [13:0] R_rd;
reg signed [13:0] G_rd;
reg signed [13:0] B_rd;
reg signed [13:0] Y;
reg signed [13:0] Co;
reg signed [13:0] Cg;
always @ (*)
  for (p = 0; p < 4; p = p + 1) 
    if (csc == 2'd1) begin
      R_rd = $signed({1'b0, pixelFromRam[0][p]});
      G_rd = $signed({1'b0, pixelFromRam[1][p]});
      B_rd = $signed({1'b0, pixelFromRam[2][p]});
      Co = R_rd - B_rd;
      temp_rd = B_rd + (Co>>>1);
      Cg = G_rd - temp_rd;
      Y = temp_rd + (Cg>>>1);
      pixelForDecodingProc[0][p] = Y;
      pixelForDecodingProc[1][p] = Co;
      pixelForDecodingProc[2][p] = Cg;
    end
    // else TBD
    
reg ram_data_valid_dl;
always @ (posedge clk)
  ram_data_valid_dl <= ram_data_valid;
  
reg signed [13:0] pixelsShiftReg [2:0][43:0];
always @ (posedge clk)
  if (ram_data_valid_dl)
    for (c = 0; c < 3; c = c + 1) begin
      for (p = 0; p < 4; p = p + 1) 
        pixelsShiftReg[c][3-p] <= pixelForDecodingProc[c][p];
      for (p = 4; p < 44; p = p + 1)
          pixelsShiftReg[c][p] <= pixelsShiftReg[c][p - 4];    
    end

genvar compi;
genvar coli;
generate
  for (compi = 0; compi < 3; compi = compi + 1) begin : gen_pixelsAbove_comp
    for (coli = 0; coli < 33; coli = coli + 1) begin : gen_pixelsAboveForBp_col
      assign pixelsAboveForBp_p[(33*compi + coli)*14+:14] = pixelsShiftReg[compi][coli+7];
    end
    for (coli = 0; coli < 16; coli = coli + 1) begin : gen_pixelsAboveForTransform_col
      assign pixelsAboveForTrans_p[(16*compi + coli)*14+:14] = pixelsShiftReg[compi][31-coli];
    end
  end
endgenerate
  
endmodule