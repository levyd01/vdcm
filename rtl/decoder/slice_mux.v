module slice_mux
#(
  parameter MAX_NBR_SLICES         = 2,
  parameter MAX_SLICE_WIDTH        = 2560,
  parameter MAX_SLICE_HEIGHT       = 2560
)
(
  input wire clk_core,
  input wire clk_out_int,
  input wire rst_n,
  input wire flush,
  
  input wire [9:0] slices_per_line,
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [$clog2(MAX_SLICE_HEIGHT)-1:0] slice_height,
  input wire [15:0] frame_height,
  input wire [3:0] eoc_valid_pixs,
  
  output wire [MAX_NBR_SLICES-1:0] fifo_almost_full,
  
  input wire [MAX_NBR_SLICES*4*3*14-1:0] pixs_in_p,
  input wire [MAX_NBR_SLICES-1:0] pixs_in_sof,
  input wire [MAX_NBR_SLICES-1:0] pixs_in_valid,
  
  output reg [4*3*14-1:0] pixs_out,
  output reg [3:0] pixs_out_eol,
  output reg pixs_out_eof,
  output reg pixs_out_valid
);

genvar gs, gc, gp, gm;
wire [13:0] pixs_in [MAX_NBR_SLICES-1:0][2:0][3:0];
wire [4*3*14-1:0] mem_wr_data [MAX_NBR_SLICES-1:0];
wire [4*3*14-1:0] data_per_slice [MAX_NBR_SLICES-1:0];
wire [MAX_NBR_SLICES-1:0] mem_rd_sof;

// Unpack inputs
generate
  for (gs = 0; gs < MAX_NBR_SLICES; gs = gs + 1) begin  : gen_pixs_in_s
    assign data_per_slice[gs] = pixs_in_p[gs*3*4*14+:14*3*4];
    assign mem_wr_data[gs] = pixs_in_p[gs*3*4*14+:14*3*4];
    for (gp = 0; gp < 4; gp = gp + 1) begin : gen_pixs_in_p
      for (gc = 0; gc < 3; gc = gc + 1) begin : gen_pixs_in_c
        assign pixs_in[gs][gc][gp] = pixs_in_p[(gs*3*4+gp*3+gc)*14+:14];
      end
    end
  end
endgenerate

reg [MAX_NBR_SLICES-1:0] rd_eoc;
reg [$clog2(MAX_NBR_SLICES)-1:0] mem_rd_sel;
wire [MAX_NBR_SLICES-1:0] mem_rd_en;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (mem_rd_sof[0])
    mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (rd_eoc[mem_rd_sel] & mem_rd_en[mem_rd_sel])
    if (mem_rd_sel == slices_per_line-1'b1)
      mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
    else
      mem_rd_sel <= mem_rd_sel + 1'b1;

reg eof_rd;
reg [$clog2(MAX_SLICE_HEIGHT)-1:0] line_cnt_rd;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    line_cnt_rd <= {$clog2(MAX_SLICE_HEIGHT){1'b0}};
  else if (mem_rd_sof[0])
    line_cnt_rd <= {$clog2(MAX_SLICE_HEIGHT){1'b0}};
  else if (rd_eoc[slices_per_line-1] & mem_rd_en[slices_per_line-1])
    if (line_cnt_rd == slice_height - 1'b1) 
      line_cnt_rd <= {$clog2(MAX_SLICE_HEIGHT){1'b0}};
    else
      line_cnt_rd <= line_cnt_rd + 1'b1;
      
reg [15:0] line_cnt_until_eof;   
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    line_cnt_until_eof <= 16'b0;
  else if (mem_rd_sof[0])
    line_cnt_until_eof <= 16'b0;
  else if (rd_eoc[slices_per_line-1] & mem_rd_en[slices_per_line-1])
    line_cnt_until_eof <= line_cnt_until_eof + 1'b1;
    
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    eof_rd <= 1'b0;
  else if (mem_rd_sof[0])
    eof_rd <= 1'b0;
  else if (rd_eoc[slices_per_line-1] & (line_cnt_until_eof >= frame_height - 1'b1) & mem_rd_en[slices_per_line-1])
    eof_rd <= 1'b1;

wire [MAX_NBR_SLICES-1:0] wr_eoc;

parameter ADDR_WIDTH = $clog2(((MAX_SLICE_WIDTH>>2))+4);

integer m;
genvar gn;

wire [4*3*14-1:0] mem_rd_data [MAX_NBR_SLICES-1:0];
wire [MAX_NBR_SLICES-1:0] mem_rd_valid;
reg [ADDR_WIDTH-1:0] rd_pix4_cnt [MAX_NBR_SLICES-1:0];
reg [ADDR_WIDTH-1:0] wr_pix4_cnt [MAX_NBR_SLICES-1:0];
wire [MAX_NBR_SLICES-1:0] mem_empty;

generate
  for (gs = 0; gs < MAX_NBR_SLICES; gs = gs + 1) begin  : gen_fifos
  
    always @ (posedge clk_core or negedge rst_n)
      if (~rst_n)
        wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (pixs_in_sof[gs])
        wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (pixs_in_valid[gs])
        if (wr_pix4_cnt[gs] == (slice_width>>2) - 1'b1)
          wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
        else
          wr_pix4_cnt[gs] <= wr_pix4_cnt[gs] + 1'b1;
          
    assign wr_eoc[gs] = wr_pix4_cnt[gs] == (slice_width>>2) - 1'b1;
    
    always @ (posedge clk_out_int or negedge rst_n)
      if (~rst_n)
        rd_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (mem_rd_sof[gs])
        rd_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (mem_rd_en[gs])
        if (rd_pix4_cnt[gs] == (slice_width>>2) - 1'b1)
          rd_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
        else
          rd_pix4_cnt[gs] <= rd_pix4_cnt[gs] + 1'b1;
    
    always @ (posedge clk_out_int or negedge rst_n)
      if (~rst_n)
        rd_eoc[gs] <= 1'b0;
      else if (mem_rd_sof[gs])
        rd_eoc[gs] <= 1'b0;
      else if (mem_rd_en[gs])
        if (rd_pix4_cnt[gs] == (slice_width>>2) - 2'd2)
          rd_eoc[gs] <= 1'b1;
        else 
          rd_eoc[gs] <= 1'b0;
    
    
    assign mem_rd_en[gs] = (mem_rd_sel == gs) & ~mem_empty[gs];
    
    out_sync_buf 
      #(
        .NUMBER_OF_LINES          (MAX_SLICE_WIDTH>>1),
        .DATA_WIDTH               (4*3*14)
      )
      output_sync_buf_u
      (
        .clk_wr                       (clk_core),
        .clk_rd                       (clk_out_int),
        .rst_n                        (rst_n),
        .slice_width                  (slice_width),
        .in_data                      (mem_wr_data[gs]),
        .in_sof                       (pixs_in_sof[gs]),
        .in_valid                     (pixs_in_valid[gs]),
        .empty                        (mem_empty[gs]),
        .fifo_almost_full             (fifo_almost_full[gs]),
        .out_rd_en                    (mem_rd_en[gs]),
        .out_data                     (mem_rd_data[gs]),
        .out_sof                      (mem_rd_sof[gs]),
        .out_valid                    (mem_rd_valid[gs])
        
      );  
  end
endgenerate

reg [$clog2(MAX_NBR_SLICES)-1:0] mem_rd_sel_dl [1:0];
always @ (posedge clk_out_int or negedge rst_n) begin
  mem_rd_sel_dl[0] <= mem_rd_sel;
  mem_rd_sel_dl[1] <= mem_rd_sel_dl[0];
end

reg lastBlockOfLine;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    lastBlockOfLine <= 1'b0;
  else if (mem_rd_sof[0])
    lastBlockOfLine <= 1'b0;
  else if ((rd_pix4_cnt[slices_per_line-1] >= (slice_width>>2) - 2'd2) & mem_rd_en[slices_per_line-1])
    lastBlockOfLine <= 1'b1;
  else if (|mem_rd_en)
    lastBlockOfLine <= 1'b0;
    
reg lastBlockOfLine_dl;
always @ (posedge clk_out_int)
  lastBlockOfLine_dl <= lastBlockOfLine;
wire lastBlockOfLine_pulse;
assign lastBlockOfLine_pulse = lastBlockOfLine & ~lastBlockOfLine_dl;

reg firstPartOflastBlockOfLine;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    firstPartOflastBlockOfLine <= 1'b0;
  else if (mem_rd_sof[0])
    firstPartOflastBlockOfLine <= 1'b0;
  else if ((rd_pix4_cnt[slices_per_line-1] == (slice_width>>2) - 2'd2) & mem_rd_en[slices_per_line-1])
    firstPartOflastBlockOfLine <= 1'b1;
  else if (|mem_rd_en)
    firstPartOflastBlockOfLine <= 1'b0;
wire secondPartOflastBlockOfLine;
assign secondPartOflastBlockOfLine = lastBlockOfLine & ~firstPartOflastBlockOfLine;
  
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    pixs_out_eol <= 4'b0;
  else if (mem_rd_sof[0])
    pixs_out_eol <= 4'b0;
  else if ((eoc_valid_pixs <= 4'd4) & lastBlockOfLine_pulse) // last pixel is in first part of the last block
    case (eoc_valid_pixs)
      4'd1: pixs_out_eol <= 4'b0001;
      4'd2: pixs_out_eol <= 4'b0010;
      4'd3: pixs_out_eol <= 4'b0100;
      4'd4: pixs_out_eol <= 4'b1000;
    endcase
  else if ((eoc_valid_pixs >= 4'd5) & rd_eoc[slices_per_line-1] & mem_rd_en[slices_per_line-1]) // last pixel is in second part of the last block
    case (eoc_valid_pixs)
      4'd5: pixs_out_eol <= 4'b0001;
      4'd6: pixs_out_eol <= 4'b0010;
      4'd7: pixs_out_eol <= 4'b0100;
      4'd8: pixs_out_eol <= 4'b1000;
    endcase
  else if (|mem_rd_en)
    pixs_out_eol <= 4'b0;

always @ (posedge clk_out_int) begin
  pixs_out <= mem_rd_data[mem_rd_sel_dl[0]];
  pixs_out_valid <= mem_rd_valid[mem_rd_sel_dl[0]] & ~(secondPartOflastBlockOfLine & (eoc_valid_pixs <= 4'd4)); // disable valid when the last pixel of the line is in the first part of the block
  pixs_out_eof <= eof_rd;
end

wire [13:0] pixs_out_unpacked [2:0][3:0];
generate
  for (gp = 0; gp < 4; gp = gp + 1) begin : gen_pixs_out_unpacked_p
    for (gc = 0; gc < 3; gc = gc + 1) begin : gen_pixs_out_unpacked_c
      assign pixs_out_unpacked[gc][gp] = pixs_out[(gp*3+gc)*14+:14];
    end
  end
endgenerate

endmodule