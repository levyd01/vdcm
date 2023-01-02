
module out_sync_buf
#(
  parameter NUMBER_OF_LINES = 4,
  parameter DATA_WIDTH = 4*3*14,
  parameter MAX_SLICE_WIDTH        = 2560,
  parameter ID = 0
)
(
  input wire clk_rd,
  input wire clk_wr,
  input wire rst_n,
  
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  
  input wire [DATA_WIDTH-1:0] in_data,
  input wire in_valid,
  input wire in_sof,
  
  input wire out_rd_en,
  output wire empty,
  output wire fifo_almost_full, // Stall reading from RC buffer (in substream demux) to avoid overflow in out_sync_buf FIFO.
  
  output reg fifo_almost_full_rd_clk,
  output reg fifo_almost_empty_rd_clk,
  
  output wire [DATA_WIDTH-1:0] out_data,
  output wire out_valid,
  output wire out_sof
);

localparam ADDR_WIDTH = $clog2(NUMBER_OF_LINES) + 1; // Additional bit to differentiate between empty and full

wire [ADDR_WIDTH-1:0] fifo_size;
assign fifo_size = (slice_width < 9'd256) ? 8'd128 : (slice_width >> 1);

function [ADDR_WIDTH-1:0] bin2gray;
  input [ADDR_WIDTH-1:0] bin_in;
  integer i;
  begin
    bin2gray = bin_in;
    for (i = ADDR_WIDTH-1; i > 0; i = i - 1)
      bin2gray[i-1] = bin_in[i] ^ bin_in[i-1];
  end
endfunction

reg [ADDR_WIDTH-1:0] addr_w;
always @ (posedge clk_wr or negedge rst_n)
  if (~rst_n)
    addr_w <= {ADDR_WIDTH{1'b0}};
  else if (in_valid)
    if (in_sof)
      addr_w <= {ADDR_WIDTH{1'b0}};
    else if (addr_w[ADDR_WIDTH-2:0] == (fifo_size - 1'b1)) begin
      addr_w[ADDR_WIDTH-2:0] <= {ADDR_WIDTH{1'b0}};
      addr_w[ADDR_WIDTH-1] <= ~addr_w[ADDR_WIDTH-1];
    end
    else
      addr_w <= addr_w + 1'b1;
      
reg sticky_in_sof;
always @ (posedge clk_wr or negedge rst_n)
  if (~rst_n)
    sticky_in_sof <= 1'b1;
  else if (in_sof)
    sticky_in_sof <= 1'b1;
  else if (in_valid)
    sticky_in_sof <= 1'b0;

// Synchronize write pointer to read clock domain      
wire [ADDR_WIDTH-1:0] addr_w_gray;
assign addr_w_gray = bin2gray(addr_w);

genvar gi;
wire [ADDR_WIDTH-1:0] addr_w_gray_rd_clk_domain;
generate
  for (gi=0; gi<ADDR_WIDTH; gi=gi+1) begin : sync_addr_w_gray
    synchronizer sync_addr_w_gray_u (.clk(clk_rd), .in(addr_w_gray[gi]), .out(addr_w_gray_rd_clk_domain[gi]));
  end
endgenerate

function [ADDR_WIDTH-1:0] gray2bin;
  input [ADDR_WIDTH-1:0] gray_in;
  integer i;
  begin
    gray2bin[ADDR_WIDTH-1] = gray_in[ADDR_WIDTH-1];
    for (i=ADDR_WIDTH-2; i>=0; i=i-1)
      gray2bin[i] = gray2bin[i+1]^gray_in[i];
  end
endfunction

reg [ADDR_WIDTH-1:0] addr_w_rd_clk_domain;
always @ (posedge clk_rd)
  addr_w_rd_clk_domain <= gray2bin(addr_w_gray_rd_clk_domain);
  
reg [ADDR_WIDTH-1:0] addr_r;
assign empty = (addr_w_rd_clk_domain == addr_r);

wire rd_en;
assign rd_en = out_rd_en;

wire in_sof_rd_clk;
synchronizer sync_in_sof_u (.clk(clk_rd), .in(sticky_in_sof), .out(in_sof_rd_clk));
  
always @ (posedge clk_rd or negedge rst_n)
  if (~rst_n)
    addr_r <= {ADDR_WIDTH{1'b0}};
  else if (in_sof_rd_clk)
    addr_r <= addr_w_rd_clk_domain;
  else if (rd_en)
    if (addr_r[ADDR_WIDTH-2:0] == (fifo_size - 1'b1)) begin
      addr_r[ADDR_WIDTH-2:0] <= {(ADDR_WIDTH-1){1'b0}};
      addr_r[ADDR_WIDTH-1] <= ~addr_r[ADDR_WIDTH-1];
    end
    else
      addr_r <= addr_r + 1'b1;

wire [ADDR_WIDTH-2:0] ram_addr_w_rd_clk_domain;
assign ram_addr_w_rd_clk_domain = addr_w_rd_clk_domain[ADDR_WIDTH-2:0];
wire [ADDR_WIDTH-2:0] ram_addr_r;
reg [ADDR_WIDTH-2:0] fifo_fullness;
always @ (posedge clk_rd or negedge rst_n)
  if (~rst_n)
    fifo_fullness <= 0;
  else if (ram_addr_w_rd_clk_domain >= ram_addr_r)
    fifo_fullness <= ram_addr_w_rd_clk_domain - ram_addr_r;
  else
    fifo_fullness <= fifo_size - ram_addr_r + ram_addr_w_rd_clk_domain;
wire [ADDR_WIDTH-2:0] almost_full_thres;
assign almost_full_thres = (fifo_size >= 9'd256) ? fifo_size - 8'd196 : fifo_size - 8'd128;
always @ (posedge clk_rd)
  fifo_almost_full_rd_clk <= fifo_fullness > almost_full_thres;
synchronizer sync_fifo_almost_full (.clk(clk_wr), .in(fifo_almost_full_rd_clk), .out(fifo_almost_full));

wire [ADDR_WIDTH-2:0] almost_empty_thres;
assign almost_empty_thres = 7'd64;
always @ (posedge clk_rd)
  fifo_almost_empty_rd_clk <= fifo_fullness < almost_empty_thres;

wire [DATA_WIDTH-1:0] rd_data;
wire mem_valid;
wire [ADDR_WIDTH-2:0] ram_addr_w;
assign ram_addr_w = addr_w[ADDR_WIDTH-2:0];
assign ram_addr_r = addr_r[ADDR_WIDTH-2:0];


sync_dp_ram 
#(
  .NUMBER_OF_LINES  (NUMBER_OF_LINES),
  .DATA_WIDTH       (DATA_WIDTH)
)
sync_dp_ram_u
(
  .clk_w            (clk_wr),
  .clk_r            (clk_rd),
  .w_en             (in_valid),
  .r_en             (rd_en),
  .addr_w           (ram_addr_w),
  .addr_r           (ram_addr_r),
  .wr_data          (in_data),
  .rd_data          (rd_data),
  .mem_valid        (mem_valid)
);


assign out_valid = mem_valid;
assign out_data = rd_data;    
assign out_sof = in_sof_rd_clk;

endmodule
  
