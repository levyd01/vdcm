module sync_dp_ram #(
	parameter NUMBER_OF_LINES = 16,
	parameter DATA_WIDTH = 128
)(
 input clk_w,
 input clk_r,
 input w_en,
 input r_en,
 input [$clog2(NUMBER_OF_LINES)-1:0] addr_w,
 input [$clog2(NUMBER_OF_LINES)-1:0] addr_r,
 input [DATA_WIDTH-1:0] wr_data,
 output reg [DATA_WIDTH-1:0] rd_data,
 output reg mem_valid
);  

reg [DATA_WIDTH-1:0] mem [NUMBER_OF_LINES-1:0];
wire mem_valid_w;
reg mem_valid_r;

integer i;

always @(posedge clk_r)
begin: mem_gen_rd
	rd_data <= {DATA_WIDTH{1'bx}};
  if (r_en)
    rd_data <= mem[addr_r];
end
always @(posedge clk_w)
begin: mem_gen_wr
  if (w_en)
    mem[addr_w] <= wr_data;
end

always @(posedge clk_r)
    mem_valid <= r_en;


endmodule // sync_dp_ram