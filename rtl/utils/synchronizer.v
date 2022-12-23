module synchronizer
(
  input wire clk,
  input wire in,
  output wire out
);

reg [1:0] in_dl;
always @ (posedge clk)
  in_dl <= {in_dl[0], in};

assign out = in_dl[1];

endmodule