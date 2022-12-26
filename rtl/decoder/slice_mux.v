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
  input wire [15:0] frame_height,
  input wire [3:0] eoc_valid_pixs,
  
  output wire [MAX_NBR_SLICES-1:0] fifo_almost_full,
  
  input wire [MAX_NBR_SLICES*4*3*14-1:0] pixs_in_p,
  input wire [MAX_NBR_SLICES-1:0] pixs_in_sof,
  input wire [MAX_NBR_SLICES-1:0] pixs_in_valid,
  
  output reg pixs_out_sof,
  output reg [4*3*14-1:0] pixs_out,
  output reg [3:0] pixs_out_valid,
  output reg pixs_out_eol,
  output reg pixs_out_eof,
  output wire pixs_out_eof_clk_core
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
  else if (flush)
    mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (mem_rd_sof[0])
    mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (rd_eoc[mem_rd_sel] & mem_rd_en[mem_rd_sel])
    if (mem_rd_sel == slices_per_line-1'b1)
      mem_rd_sel <= {$clog2(MAX_NBR_SLICES){1'b0}};
    else
      mem_rd_sel <= mem_rd_sel + 1'b1;

reg eof_rd;
      
reg [15:0] line_cnt_until_eof;   
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    line_cnt_until_eof <= 16'b0;
  else if (flush)
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
    
reg eol_rd;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    eol_rd <= 1'b0;
  else if (mem_rd_sof[0])
    eol_rd <= 1'b0;
  else if (rd_eoc[slices_per_line-1] & mem_rd_en[slices_per_line-1])
    eol_rd <= 1'b1;
  else
    eol_rd <= 1'b0;


localparam ADDR_WIDTH = $clog2(((MAX_SLICE_WIDTH>>2))+4);

reg [$clog2(MAX_NBR_SLICES)-1:0] mem_rd_sel_dl [1:0];
always @ (posedge clk_out_int) begin
  mem_rd_sel_dl[0] <= mem_rd_sel;
  mem_rd_sel_dl[1] <= mem_rd_sel_dl[0];
end

wire [MAX_NBR_SLICES-1:0] fifo_almost_empty_clk_int;
reg [5:0] intervalDesired;
always @ (*)
  case (slices_per_line[3:0])
    4'd1: intervalDesired = 6'd16;
    4'd2: intervalDesired = 6'd8;
    4'd3, 4'd4: intervalDesired = 6'd4;
    4'd5, 4'd6, 4'd7, 4'd8: intervalDesired = 6'd2;
    default: intervalDesired = 6'd16;
  endcase
reg [5:0] intervalActual;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    intervalActual <= 6'd0;
  else if (flush)
    intervalActual <= 6'd0;
  else if (fifo_almost_empty_clk_int[mem_rd_sel])
    intervalActual <= intervalDesired << 1;
  else
    intervalActual <= intervalDesired;

wire [MAX_NBR_SLICES-1:0] fifo_almost_full_clk_int;
reg [7:0] intervalCnt;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    intervalCnt <= 8'd0;
  else if (flush)
    intervalCnt <= 8'd0;
  else if (pixs_out_eof)
    intervalCnt <= 8'd0;
  else if (intervalCnt >= intervalActual - 1'b1)
    intervalCnt <= 8'd0;
  else if (fifo_almost_full_clk_int[mem_rd_sel])
    intervalCnt <= intervalCnt + 2'd2;
  else
    intervalCnt <= intervalCnt + 1'b1;

reg enableInitDelay;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    enableInitDelay <= 1'b0;
  else if (flush)
    enableInitDelay <= 1'b0;
  else if (pixs_out_sof)
    enableInitDelay <= 1'b1;
  else if (pixs_out_eof)
    enableInitDelay <= 1'b0;
    
localparam INIT_DELAY_BEFORE_RD = 64;
reg enableStartRd;
reg [9:0] initDelayCnt;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n) begin
    initDelayCnt <= 10'd0;
    enableStartRd <= 1'b0;
  end
  else if (flush) begin
    initDelayCnt <= 10'd0;
    enableStartRd <= 1'b0;
  end
  else if (pixs_out_sof | pixs_out_eof) begin
    initDelayCnt <= 10'd0;
    enableStartRd <= 1'b0;
  end
  else if (enableInitDelay)
    if (initDelayCnt < INIT_DELAY_BEFORE_RD) begin
      initDelayCnt <= initDelayCnt + 1'b1;
      enableStartRd <= 1'b0;
    end
    else
      enableStartRd <= 1'b1;
  
reg enable_rd;
always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    enable_rd <= 1'b0;
  else if (intervalCnt >= intervalActual - 1'b1)
    enable_rd <= 1'b1;
  else
    enable_rd <= 1'b0;

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
      else if (flush)
        wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (pixs_in_sof[gs])
        wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (pixs_in_valid[gs])
        if (wr_pix4_cnt[gs] == (slice_width>>2) - 1'b1)
          wr_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
        else
          wr_pix4_cnt[gs] <= wr_pix4_cnt[gs] + 1'b1;
    
    always @ (posedge clk_out_int or negedge rst_n)
      if (~rst_n)
        rd_pix4_cnt[gs] <= {ADDR_WIDTH{1'b0}};
      else if (flush)
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
    
    
    assign mem_rd_en[gs] = (mem_rd_sel == gs) & enableStartRd & enable_rd & ~mem_empty[gs];
    
    out_sync_buf 
      #(
        .NUMBER_OF_LINES          (MAX_SLICE_WIDTH>>1),
        .DATA_WIDTH               (4*3*14),
        .ID                       (gs)
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
        .fifo_almost_full_rd_clk      (fifo_almost_full_clk_int[gs]),
        .fifo_almost_empty_rd_clk     (fifo_almost_empty_clk_int[gs]),
        .out_rd_en                    (mem_rd_en[gs]),
        .out_data                     (mem_rd_data[gs]),
        .out_sof                      (mem_rd_sof[gs]),
        .out_valid                    (mem_rd_valid[gs])
        
      );  
      
  end
endgenerate

reg lastBlockOfChunk;
reg lastBlockOfChunk_dl;
reg firstPartOfLastBlockOfChunk;
wire secondPartOfLastBlockOfChunk;

always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    lastBlockOfChunk <= 1'b0;
  else if (mem_rd_sof[0])
    lastBlockOfChunk <= 1'b0;
  else if ((rd_pix4_cnt[mem_rd_sel_dl[0]] >= (slice_width>>2) - 2'd2) & mem_rd_valid[mem_rd_sel_dl[0]])
    lastBlockOfChunk <= 1'b1;
  else if (mem_rd_valid[mem_rd_sel_dl[0]])
    lastBlockOfChunk <= 1'b0;  
    

always @ (posedge clk_out_int)
  lastBlockOfChunk_dl <= lastBlockOfChunk;

always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    firstPartOfLastBlockOfChunk <= 1'b0;
  else if (flush)
    firstPartOfLastBlockOfChunk <= 1'b0;
  else if (mem_rd_sof[0])
    firstPartOfLastBlockOfChunk <= 1'b0;
  else if ((rd_pix4_cnt[mem_rd_sel_dl[0]] == (slice_width>>2) - 2'd2) & mem_rd_valid[mem_rd_sel_dl[0]])
    firstPartOfLastBlockOfChunk <= 1'b1;
  else if (mem_rd_valid[mem_rd_sel_dl[0]])
    firstPartOfLastBlockOfChunk <= 1'b0;

assign secondPartOfLastBlockOfChunk = lastBlockOfChunk & ~firstPartOfLastBlockOfChunk;


always @ (posedge clk_out_int or negedge rst_n)
  if (~rst_n)
    pixs_out_valid <= 4'b0;
  else if (flush)
    pixs_out_valid <= 4'b0;
  else if (mem_rd_sof[0])
    pixs_out_valid <= 4'b0;
  else if ((eoc_valid_pixs <= 4'd4) & firstPartOfLastBlockOfChunk & mem_rd_valid[mem_rd_sel_dl[0]]) // last pixel is in first part of the last block
    case (eoc_valid_pixs)
      4'd1: pixs_out_valid <= 4'b0001;
      4'd2: pixs_out_valid <= 4'b0011;
      4'd3: pixs_out_valid <= 4'b0111;
      4'd4: pixs_out_valid <= 4'b1111;
      default: pixs_out_valid <= 4'b0001;
    endcase
  else if ((eoc_valid_pixs >= 4'd5) & secondPartOfLastBlockOfChunk & mem_rd_valid[mem_rd_sel_dl[0]]) // last pixel is in second part of the last block
    case (eoc_valid_pixs)
      4'd5: pixs_out_valid <= 4'b0001;
      4'd6: pixs_out_valid <= 4'b0011;
      4'd7: pixs_out_valid <= 4'b0111;
      4'd8: pixs_out_valid <= 4'b1111;
      default: pixs_out_valid <= 4'b0001;
    endcase
  else if (mem_rd_valid[mem_rd_sel_dl[0]] & ~(secondPartOfLastBlockOfChunk & (eoc_valid_pixs <= 4'd4))) // disable valid when the last pixel of the chunk is in the first part of the block
    pixs_out_valid <= 4'b1111;
  else
    pixs_out_valid <= 4'b0;
 
always @ (posedge clk_out_int) begin
  pixs_out_sof <= mem_rd_sof[0];
  pixs_out <= mem_rd_data[mem_rd_sel_dl[0]];
  pixs_out_eof <= eof_rd;
  pixs_out_eol <= eol_rd;
end

synchronizer sync_pixs_out_eof (.clk(clk_core), .in(pixs_out_eof), .out(pixs_out_eof_clk_core));

wire [13:0] pixs_out_unpacked [2:0][3:0];
generate
  for (gp = 0; gp < 4; gp = gp + 1) begin : gen_pixs_out_unpacked_p
    for (gc = 0; gc < 3; gc = gc + 1) begin : gen_pixs_out_unpacked_c
      assign pixs_out_unpacked[gc][gp] = pixs_out[(gp*3+gc)*14+:14];
    end
  end
endgenerate

endmodule