`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none


// Write 2 pixels per clock cycle: one to even_buf and one to odd_buf
// Write directly to RAM reconEven/OddPix_wr_data_p[0] and sample the remaining 6 pixels to reconEven/OddPix_wr_data_p_buf
// when reconBlk_wr_en is asserted


module above_pixels_buf
#(
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_BPC                 = 12
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire fbls,
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  
  input wire reconBlk_wr_en,
  input wire [8*3*14-1:0] reconBlk_wr_data_p, // Write 8 pixels
  
  input wire reconBlk_rd_en,
  output wire [16*3*14-1:0] reconBlk_rd_data_p, // Fetch 16 pixels for Transform (4 to the left above the current, 8 exactly above, and 4 to the right above)
  output wire [33*3*14-1:0] pixelsAboveForBp_p, // Fetch 33 pixels above for BP (A0 to A7 and B0 to B24)
  output wire reconBlk_rd_valid
);

wire [13:0] reconPix_wr_data [2:0][7:0];
// unpack inputs
genvar compi;
genvar coli;
generate
  for (compi = 0; compi < 3; compi = compi + 1) begin : gen_reconBlk_wr_data_comp
    for (coli = 0; coli < 8; coli = coli + 1) begin : gen_reconBlk_wr_data_col
      assign reconPix_wr_data[compi][coli] = reconBlk_wr_data_p[(8*compi + coli)*14+:14];
    end
    
  end
endgenerate

// pack outputs
wire [13:0] reconPix_rd_data [2:0][15:0];
reg [13:0] pixelsShiftReg [2:0][43:0];
wire [13:0] test [2:0][32:0];
wire [13:0] testA [2:0][7:0];
wire [13:0] testB [2:0][24:0];
generate
  for (compi = 0; compi < 3; compi = compi + 1) begin : gen_reconBlk_rd_data_comp
    for (coli = 0; coli < 16; coli = coli + 1) begin : gen_reconBlk_rd_data_col
      assign reconBlk_rd_data_p[(16*compi + coli)*14+:14] = reconPix_rd_data[compi][coli];
    end
    for (coli = 0; coli < 33; coli = coli + 1) begin : gen_pixelsAboveForBp_col
      assign pixelsAboveForBp_p[(33*compi + coli)*14+:14] = pixelsShiftReg[compi][coli+7];
      //assign test[compi][coli] = pixelsAboveForBp_p[(33*compi + 32-coli)*14+:14];
    end
    /*
    for (coli = 0; coli < 8; coli = coli + 1) begin : gen_testA_col
      assign testA[compi][coli] = pixelsAboveForBp_p[(33*compi + 32-coli)*14+:14];
    end
    for (coli = 0; coli < 25; coli = coli + 1) begin : gen_testB_col
      assign testB[compi][coli] = pixelsAboveForBp_p[(33*compi + 24-coli)*14+:14];
    end
    */
  end
endgenerate


// Write interface
// ---------------

reg [2:0] reconBlk_wr_en_dl;
always @ (posedge clk)
  reconBlk_wr_en_dl <= {reconBlk_wr_en_dl[1:0], reconBlk_wr_en};
  
// Pack to pixels
wire [3*14-1:0] reconEvenPix_wr_data_p [3:0];
wire [3*14-1:0] reconOddPix_wr_data_p [3:0];

genvar comi;
genvar bii;
genvar cii;
generate
  for (bii = 0; bii < 4; bii = bii + 1) begin : gen_reconBiPix_wr_data_bi
    for (comi = 0; comi < 3; comi = comi + 1) begin : gen_reconBiPix_wr_data_comp
        assign reconEvenPix_wr_data_p[bii][comi*14+:14] = reconPix_wr_data[comi][bii<<1];
        assign reconOddPix_wr_data_p[bii][comi*14+:14] = reconPix_wr_data[comi][(bii<<1) + 1];
    end
  end
endgenerate

reg [2*3*14-1:0] reconEvenPix_wr_data_p_buf [2:0];
reg [2*3*14-1:0] reconOddPix_wr_data_p_buf [2:0];
integer b;
always @ (posedge clk)
  if (reconBlk_wr_en)
    for (b = 0; b < 3; b = b + 1) begin
      reconEvenPix_wr_data_p_buf[b] <= reconEvenPix_wr_data_p[b+1];
      reconOddPix_wr_data_p_buf[b]  <=  reconOddPix_wr_data_p[b+1];
    end
  
wire [3:0] bi_sel_wr;
assign bi_sel_wr = {reconBlk_wr_en_dl, reconBlk_wr_en};
reg [3*14-1:0] even_ram_data_wr;
reg [3*14-1:0] odd_ram_data_wr;
always @ (*)
  case(bi_sel_wr)
    4'b0001: begin even_ram_data_wr = reconEvenPix_wr_data_p[0]; odd_ram_data_wr = reconOddPix_wr_data_p[0]; end
    4'b0010: begin even_ram_data_wr = reconEvenPix_wr_data_p_buf[0]; odd_ram_data_wr = reconOddPix_wr_data_p_buf[0]; end
    4'b0100: begin even_ram_data_wr = reconEvenPix_wr_data_p_buf[1]; odd_ram_data_wr = reconOddPix_wr_data_p_buf[1]; end
    4'b1000: begin even_ram_data_wr = reconEvenPix_wr_data_p_buf[2]; odd_ram_data_wr = reconOddPix_wr_data_p_buf[2]; end
    default: begin even_ram_data_wr = reconEvenPix_wr_data_p[0]; odd_ram_data_wr = reconOddPix_wr_data_p[0]; end
  endcase

wire ram_wr_en;
assign ram_wr_en = |bi_sel_wr;

localparam RAM_ADDR_WIDTH = $clog2(MAX_SLICE_WIDTH); //1 pixel per line
localparam MAX_RAM_LINES = MAX_SLICE_WIDTH;
wire [RAM_ADDR_WIDTH-1:0] ram_lines;
assign ram_lines = slice_width>>1;
reg [RAM_ADDR_WIDTH-1:0] ram_wr_addr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    ram_wr_addr <= {RAM_ADDR_WIDTH{1'b0}};
  else if (flush)
    ram_wr_addr <= {RAM_ADDR_WIDTH{1'b0}};
  else if (ram_wr_en)
    if (ram_wr_addr == ram_lines - 1'b1)
      ram_wr_addr <= {RAM_ADDR_WIDTH{1'b0}};
    else
      ram_wr_addr <= ram_wr_addr + 1'b1;

// Read Interface
// --------------

reg [2:0] reconBlk_rd_en_dl;
always @ (posedge clk)
  reconBlk_rd_en_dl <= {reconBlk_rd_en_dl[1:0], reconBlk_rd_en};

wire ram_rd_en;
assign ram_rd_en = reconBlk_rd_en | (|reconBlk_rd_en_dl);
reg [RAM_ADDR_WIDTH-1:0] ram_rd_addr;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    ram_rd_addr <= {RAM_ADDR_WIDTH{1'b0}};
  else if (flush)
    ram_rd_addr <= {RAM_ADDR_WIDTH{1'b0}};
  else if (ram_rd_en)
    if (ram_rd_addr == ram_lines - 1'b1)
      ram_rd_addr <= {RAM_ADDR_WIDTH{1'b0}};
    else
      ram_rd_addr <= ram_rd_addr + 1'b1;

wire ram_data_valid; // take only even RAM, assuming odd RAM gives valid at exactly the same time

wire [3*14-1:0] even_ram_data_rd;
wire [3*14-1:0] odd_ram_data_rd;

reg [1:0] sel_rd;
always @ (posedge clk)
  sel_rd <= ram_rd_addr[1:0];
  
wire end_of_block;
assign end_of_block = (sel_rd == 2'd3);
reg [4:0] end_of_block_dl;
always @ (posedge clk)
  end_of_block_dl <= {end_of_block_dl[3:0], end_of_block};
assign reconBlk_rd_valid = end_of_block_dl[4];

integer i;
integer c;
always @ (posedge clk)
  if (ram_data_valid)
    for (c = 0; c < 3; c = c + 1) begin
      pixelsShiftReg[c][1] <= even_ram_data_rd[c*14+:14];
      pixelsShiftReg[c][0] <= odd_ram_data_rd[c*14+:14];
      for (i = 2; i < 44; i = i + 1)
        pixelsShiftReg[c][i] <= pixelsShiftReg[c][i - 2];
    end
    
generate
  for (comi = 0; comi < 3; comi = comi + 1) begin : gen_reconBiPix_rd_data_comp
    for (cii = 0; cii < 16; cii = cii + 1) begin : gen_reconBiPix_rd_data_col
      assign reconPix_rd_data[comi][cii] = pixelsShiftReg[comi][35-cii];
    end
  end
endgenerate


  
  
// RAM instances
// -------------

dp_ram
#(
  .NUMBER_OF_LINES       (MAX_RAM_LINES),
  .DATA_WIDTH            (3*14) // 1 Pixel per write
)
above_pixels_ram_even_u
(
  .clk                   (clk),
  .w_en                  (ram_wr_en),
  .addr_w                (ram_wr_addr),
  .wr_data               (even_ram_data_wr),
  .r_en                  (ram_rd_en),
  .addr_r                (ram_rd_addr),
  .rd_data               (even_ram_data_rd),
  .mem_valid             (ram_data_valid)
);

dp_ram
#(
  .NUMBER_OF_LINES       (MAX_RAM_LINES),
  .DATA_WIDTH            (3*14) // 1 Pixel per write
)
above_pixels_ram_odd_u
(
  .clk                   (clk),
  .w_en                  (ram_wr_en),
  .addr_w                (ram_wr_addr),
  .wr_data               (odd_ram_data_wr),
  .r_en                  (ram_rd_en),
  .addr_r                (ram_rd_addr),
  .rd_data               (odd_ram_data_rd),
  .mem_valid             () // TBD
);


endmodule