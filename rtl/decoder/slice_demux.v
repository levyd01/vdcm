module slice_demux
#(
  parameter MAX_NBR_SLICES        = 2,
  parameter MAX_SLICE_WIDTH       = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [9:0] slices_per_line,
  input wire [15:0] chunk_size,
  
  input wire [255:0] in_data,
  input wire in_valid,
  input wire in_sof,
  input wire data_in_is_pps,
  
  output reg [MAX_NBR_SLICES-1:0] out_valid,
  output wire [256*MAX_NBR_SLICES-1:0] out_data_p,
  output reg [MAX_NBR_SLICES-1:0] out_sof,
  output reg [MAX_NBR_SLICES-1:0] data_out_is_pps

);

wire one_slice_active;
assign one_slice_active = (slices_per_line == 10'd1);

reg [15:0] byte_cnt;
wire [5:0] remainder;
reg [5:0] remainder_r;
reg [4:0] byte_offset;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    byte_cnt <= 16'b0;
    remainder_r <= 6'd0;
  end
  else if (in_valid & ~one_slice_active) 
    if (in_sof) begin
      byte_cnt <= 16'd32;
      remainder_r <= 6'd0;
    end
    else if (byte_cnt + 6'd32 > chunk_size) begin
      remainder_r <= (byte_cnt + 6'd32) - chunk_size;
      if (((byte_offset + remainder) & 5'h1f) != 5'd0)
        byte_cnt <= 16'd0;
      else
        byte_cnt <= 16'd32;
    end
    else
      byte_cnt <= byte_cnt + 6'd32;
      
assign remainder = (byte_cnt + 6'd32 > chunk_size) ? ((byte_cnt + 6'd32) - chunk_size) : remainder_r;

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    byte_offset <= 5'd0;
  else if (in_valid) 
    if (in_sof)
      byte_offset <= 5'd0;
    else if ((byte_cnt + 6'd32 > chunk_size) & ~one_slice_active)
      byte_offset <= byte_offset + remainder;
      
integer i;
reg [255:0] tmp_buf;
always @ (posedge clk)
  if (in_valid & ~one_slice_active)
    tmp_buf <= in_data;

reg [$clog2(MAX_NBR_SLICES)-1:0] active_fifo;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (in_sof)
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (~one_slice_active) begin
    if (in_valid & (byte_cnt + 6'd32 > chunk_size))
      active_fifo <= active_fifo + 1'b1;
  end
  else
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};

reg [255:0] out_data [MAX_NBR_SLICES-1:0];
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    out_valid <= {MAX_NBR_SLICES{1'b0}};
  else if (in_sof & ~in_valid)
    out_valid <= {MAX_NBR_SLICES{1'b0}};
  else if (in_valid) begin
    out_valid[active_fifo] <= 1'b1;
    if (~one_slice_active) begin
      if ((byte_cnt + 6'd32 > chunk_size) & (((byte_offset + remainder) & 5'h1f) == 5'd0)) begin
        if (active_fifo+1 == slices_per_line) begin
          out_data[0] <= in_data;
          out_valid[0] <= 1'b1;
        end
        else begin
          out_data[active_fifo+1] <= in_data;
          out_valid[active_fifo+1] <= 1'b1;
        end
      end
      if (byte_offset == 0)
        out_data[active_fifo] <= in_data;
      else
        for (i = 0; i<32 ;i=i+1)
          if (i<byte_offset) begin
            out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
          end
          else
            out_data[active_fifo][i*8+:8] <= in_data[(i-byte_offset)*8+:8];
    end
    else
      out_data[0] <= in_data;
  end
  else
    out_valid <= {MAX_NBR_SLICES{1'b0}};

always @ (posedge clk)
  if (in_sof)
    out_sof <= {MAX_NBR_SLICES{1'b1}};
  else
    for (i=0; i<MAX_NBR_SLICES; i=i+1)
      if (out_valid[i])
        out_sof[i] <= 1'b0;
    
always @ (posedge clk)
  data_out_is_pps <= data_in_is_pps;    

genvar s;
generate
  for (s=0; s<MAX_NBR_SLICES; s=s+1) begin: gen_out_data
    assign out_data_p [s*256+:256] = out_data[s];
  end
endgenerate
  
endmodule