module dp_ram #(
	parameter NUMBER_OF_LINES = 8192,
	parameter DATA_WIDTH = 128
)(
 input wire clk,
 input wire w_en,
 input wire r_en,
 input wire [$clog2(NUMBER_OF_LINES)-1:0] addr_w,
 input wire [$clog2(NUMBER_OF_LINES)-1:0] addr_r,
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
  if (w_en)
    mem[addr_w] <= wr_data;
  if (r_en)
    rd_data <= mem[addr_r];
end // mem_gen

always @(posedge clk)
    mem_valid <= r_en;


endmodule // dp_ram