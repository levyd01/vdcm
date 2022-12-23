module sp_ram #(
	parameter NUMBER_OF_LINES = 8192,
	parameter DATA_WIDTH = 128
)(
  input wire clk,
  input wire cs,
  input wire w_en,
  input wire [$clog2(NUMBER_OF_LINES)-1:0] addr,
  input wire [DATA_WIDTH-1:0] wr_data,
  output reg [DATA_WIDTH-1:0] rd_data,
  output reg mem_valid
);  

reg [DATA_WIDTH-1:0] mem [NUMBER_OF_LINES-1:0];
wire mem_valid_w;
reg mem_valid_r;

integer i;

always @(posedge clk)
begin: mem_gen
	rd_data <= {DATA_WIDTH{1'bx}};
  if (cs)
    if (w_en)
      mem[addr] <= wr_data;
    else
      rd_data <= mem[addr];
end // mem_gen

always @(posedge clk)
    mem_valid <= cs & ~w_en;


endmodule // sp_ram