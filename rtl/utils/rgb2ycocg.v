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

module rgb2ycocg
(
  input wire [11:0] src_r,
  input wire [11:0] src_g,
  input wire [11:0] src_b,
  
  output reg signed [13:0] dst_y,
  output reg signed [13:0] dst_co,
  output reg signed [13:0] dst_cg
);

reg signed [13:0] temp;
always @ (*) begin
  dst_co = $signed({1'b0, src_r}) - $signed({1'b0, src_b});
  temp = $signed({1'b0, src_b}) + (dst_co>>>1);
  dst_cg = $signed({1'b0, src_g})- temp;
  dst_y = temp + (dst_cg>>>1);
end

endmodule