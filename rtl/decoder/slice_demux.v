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

module slice_demux
#(
  parameter MAX_NBR_SLICES        = 2,
  parameter MAX_SLICE_WIDTH       = 2560
)
(
  input wire clk ,
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

reg first_chunk_of_slice;
wire last_word_of_chunk;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    first_chunk_of_slice <= 1'b0;
  else if (flush)
    first_chunk_of_slice <= 1'b0;
  else if (in_sof)
    first_chunk_of_slice <= 1'b1;
  else if (in_valid & last_word_of_chunk & ~data_in_is_pps)
    first_chunk_of_slice <= 1'b0;

reg [4:0] byte_offset;

wire [5:0] remainder;
assign remainder = chunk_size & 5'h1f;

reg [11:0] word_cnt;
wire [4:0] next_byte_offset;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    word_cnt <= 12'd0;
  else if (flush)
    word_cnt <= 12'd0;
  else if (in_valid & ~data_in_is_pps)
    if (in_sof)
      word_cnt <= 12'd0;
    else if (last_word_of_chunk)
      if (((next_byte_offset - byte_offset) >= remainder) & (next_byte_offset >= byte_offset) & (remainder != 6'd0))
        word_cnt <= 12'd1;
      else
        word_cnt <= 12'd0;
    else
      word_cnt <= word_cnt + 1'b1;
      
wire [11:0] chunk_size_in_words;
assign chunk_size_in_words = (chunk_size[4:0] == 5'b0) ? (chunk_size >> 5) : ((chunk_size >> 5) + 1'b1);
assign last_word_of_chunk = (word_cnt == chunk_size_in_words - 1'b1);

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    byte_offset <= 5'd0;
  else if (in_sof) 
    byte_offset <= 5'd0;
  else if (in_valid & last_word_of_chunk & ~one_slice_active & ~data_in_is_pps)
    byte_offset <= (byte_offset + remainder) & 5'h1f;
	
reg [15:0] byte_cnt;
always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    byte_cnt <= 15'd0;
  else if (in_sof) 
    byte_cnt <= 15'd0;
  else if (~one_slice_active)
    if (in_valid & ~data_in_is_pps)
	    if (last_word_of_chunk)
	      if (next_byte_offset != 0)
	        byte_cnt <= 15'd32;
		    else
		      byte_cnt <= 15'd0;
	    else
	      byte_cnt <= byte_cnt + 15'd32;
      
	  

      
integer i;
reg [255:0] tmp_buf;
always @ (posedge clk)
  if (in_valid & ~one_slice_active & ~data_in_is_pps)
    tmp_buf <= in_data;
    
reg [$clog2(MAX_NBR_SLICES)-1:0] active_fifo;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) 
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (flush)
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (in_sof)
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
  else if (~one_slice_active) begin
    if (in_valid & last_word_of_chunk & ~data_in_is_pps)
      if (active_fifo+1 == slices_per_line)
        active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};
      else
        active_fifo <= active_fifo + 1'b1;
  end
  else
    active_fifo <= {$clog2(MAX_NBR_SLICES){1'b0}};

wire [$clog2(MAX_NBR_SLICES)-1:0] next_active_fifo;
assign next_active_fifo = (active_fifo+1'b1 == slices_per_line) ? {$clog2(MAX_NBR_SLICES){1'b0}} : active_fifo + 1'b1;

assign next_byte_offset = (byte_offset + remainder) & 5'h1f;

reg [255:0] out_data [MAX_NBR_SLICES-1:0];
integer f;
always @ (posedge clk or negedge rst_n)
  if (~rst_n) begin
    out_valid <= {MAX_NBR_SLICES{1'b0}};
    for (f = 0; f < MAX_NBR_SLICES; f = f + 1)
      out_data[f] <= 256'b0;
  end
  else if (flush)
    out_valid <= {MAX_NBR_SLICES{1'b0}};
  else if (in_sof & ~in_valid)
    out_valid <= {MAX_NBR_SLICES{1'b0}};
  else if (in_valid & ~data_in_is_pps) begin
    if (~one_slice_active) begin
      if (last_word_of_chunk)
        if (next_byte_offset == 0) begin
          out_valid[active_fifo] <= 1'b1;
		      for (i = 0; i<32 ;i=i+1)
		        if (i < 32-byte_offset)
              out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
			    else
			      out_data[active_fifo][i*8+:8] <= 8'b0;
        end
        else begin
          if (byte_offset == 0) begin
            out_valid[active_fifo] <= 1'b1;
            for (i = 0; i<32 ;i=i+1)
              if (i < next_byte_offset)
                out_data[active_fifo][i*8+:8] <= tmp_buf[i*8+:8];
              else
                out_data[active_fifo][i*8+:8] <= 8'b0;
		    if (remainder != 0) begin
			    out_valid[next_active_fifo] <= 1'b1;
            for (i = 0; i<32 ;i=i+1)
              if (i<32-next_byte_offset)
                out_data[next_active_fifo][i*8+:8] <= tmp_buf[(i+next_byte_offset)*8+:8];
              else
                out_data[next_active_fifo][i*8+:8] <= in_data[(i-(32-next_byte_offset))*8+:8];
			  end
    end
    //else if (byte_offset >= remainder)
    //  out_valid[active_fifo] <= 1'b0;
    else begin
		  out_valid[active_fifo] <= 1'b1;
			if (next_byte_offset > byte_offset) begin
        for (i = 0; i<32 ;i=i+1)
          if (i<next_byte_offset-byte_offset)
            out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
          else
            out_data[active_fifo][i*8+:8] <= 8'b0;
			  out_valid[next_active_fifo] <= 1'b1;
        for (i = 0; i<32 ;i=i+1)
          if (i<32-next_byte_offset)
            out_data[next_active_fifo][i*8+:8] <= tmp_buf[(i+next_byte_offset)*8+:8];
          else
            out_data[next_active_fifo][i*8+:8] <= in_data[(i-(32-next_byte_offset))*8+:8];
			end
		  else if (byte_cnt + 32 < chunk_size) begin
			  for (i = 0; i<32 ;i=i+1)
			    if (i<byte_offset)
				    out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
          else
            out_data[active_fifo][i*8+:8] <= 8'b0;
			  out_valid[next_active_fifo] <= 1'b1;
        for (i = 0; i<32 ;i=i+1)
          if (i<32-next_byte_offset)
            out_data[next_active_fifo][i*8+:8] <= tmp_buf[(i+next_byte_offset)*8+:8];
          else
            out_data[next_active_fifo][i*8+:8] <= in_data[(i-(32-next_byte_offset))*8+:8];
		  end
		  else
			for (i = 0; i<32 ;i=i+1)
			  if (i<32-byte_offset)
			    out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
        else
          out_data[active_fifo][i*8+:8] <= in_data[(i-(32-byte_offset))*8+:8];
        end
      end
    else if (~in_sof) begin
      out_valid[active_fifo] <= 1'b1;
      for (i = 0; i<32 ;i=i+1)
        if (i<32-byte_offset)
          out_data[active_fifo][i*8+:8] <= tmp_buf[(i+byte_offset)*8+:8];
        else
          out_data[active_fifo][i*8+:8] <= in_data[(i-(32-byte_offset))*8+:8];
  end
end
  else begin
    out_data[0] <= in_data;
    out_valid[0] <= 1'b1;
  end
end
  else
    out_valid <= {MAX_NBR_SLICES{1'b0}};

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    out_sof <= {MAX_NBR_SLICES{1'b0}};
  else if (in_sof)
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