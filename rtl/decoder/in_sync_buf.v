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


module in_sync_buf
#(
  parameter NUMBER_OF_LINES = 4,
  parameter DATA_WIDTH = 256
)
(
  input wire clk_rd,
  input wire clk_wr,
  input wire rst_n,
  
  input wire flush,
  
  input wire [DATA_WIDTH-1:0] in_data,
  input wire in_valid,
  input wire in_sof,
  input wire in_eof,
  input wire in_data_is_pps,
  
  output reg [DATA_WIDTH-1:0] out_data,
  output reg out_valid,
  output reg out_sof,
  output reg out_eof,
  output reg out_data_is_pps
);

localparam ADDR_WIDTH = $clog2(NUMBER_OF_LINES) + 1; // Additional bit to differentiate between empty and full

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
  else if (flush)
    addr_w <= {ADDR_WIDTH{1'b0}};
  else if (in_valid)
    if (addr_w + 1'b1 == NUMBER_OF_LINES<<1)
      addr_w <= {ADDR_WIDTH{1'b0}};
    else
      addr_w <= addr_w + 1'b1;

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
wire empty;
assign empty = (addr_w_rd_clk_domain == addr_r);

wire rd_en;
assign rd_en = ~empty;

always @ (posedge clk_rd or negedge rst_n)
  if (~rst_n)
    addr_r <= {ADDR_WIDTH{1'b0}};
  else if (flush)
    addr_r <= {ADDR_WIDTH{1'b0}};
  else if (rd_en)
    if (addr_r + 1'b1 == NUMBER_OF_LINES<<1)
      addr_r <= {ADDR_WIDTH{1'b0}};
    else
      addr_r <= addr_r + 1'b1;
	     
wire [DATA_WIDTH+3-1:0] rd_data;
wire mem_valid;
sync_dp_ram 
#(
  .NUMBER_OF_LINES  (NUMBER_OF_LINES),
  .DATA_WIDTH       (DATA_WIDTH + 3) // in_data_is_pps in DATA_WIDTH-1, sof in DATA_WIDTH-2, eof in DATA_WIDTH-3, data in DATA_WIDTH-4:0
)
sync_dp_ram_u
(
  .clk_w            (clk_wr),
  .clk_r            (clk_rd),
  .w_en             (in_valid),
  .r_en             (rd_en),
  .addr_w           (addr_w[ADDR_WIDTH-2:0]),
  .addr_r           (addr_r[ADDR_WIDTH-2:0]),
  .wr_data          ({in_data_is_pps, in_sof, in_eof, in_data}),
  .rd_data          (rd_data),
  .mem_valid        (mem_valid)
);

always @ (posedge clk_rd or negedge rst_n)
  if (~rst_n) begin
    out_sof <= 1'b0;
    out_data_is_pps <= 1'b0;
    out_eof <= 1'b0;
  end
  else if (flush) begin
    out_sof <= 1'b0;
    out_data_is_pps <= 1'b0;
    out_eof <= 1'b0;
  end
  else if (mem_valid) begin
    out_eof <= rd_data[DATA_WIDTH+1-1];
    out_sof <= rd_data[DATA_WIDTH+2-1];
    out_data_is_pps <= rd_data[DATA_WIDTH+3-1];
  end
  else begin
    out_sof <= 1'b0;
    out_eof <= 1'b0;
    out_data_is_pps <= 1'b0;
  end
always @ (posedge clk_rd or negedge rst_n)
  if (~rst_n)
    out_valid <= 1'b0;
  else if (flush)
    out_valid <= 1'b0;
  else
    out_valid <= mem_valid;
always @ (posedge clk_rd)
  if (mem_valid)
    out_data <= rd_data[DATA_WIDTH-1:0];

    

endmodule
  
