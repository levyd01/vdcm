module ycocg2rgb
(
  input wire [12:0] maxPoint,
  
  input wire signed [13:0] src_y,
  input wire signed [13:0] src_co,
  input wire signed [13:0] src_cg,
  
  output reg [11:0] dst_r,
  output reg [11:0] dst_g,
  output reg [11:0] dst_b
);

reg signed [13:0] temp;
reg signed [13:0] R, G, B;
always @ (*) begin
  temp = src_y - (src_cg >>> 1);
  G = src_cg + temp;
  B = temp - (src_co >>> 1);
  R = B + src_co;
  case (maxPoint)
    12'd255:
      begin
        if (G[13]) dst_g = 12'd0; else if (|G[12:8]) dst_g = 12'd255; else dst_g = G[11:0];
        if (B[13]) dst_b = 12'd0; else if (|B[12:8]) dst_b = 12'd255; else dst_b = B[11:0];
        if (R[13]) dst_r = 12'd0; else if (|R[12:8]) dst_r = 12'd255; else dst_r = R[11:0];
      end
    12'd1023:
      begin
        if (G[13]) dst_g = 12'd0; else if (|G[12:10]) dst_g = 12'd1023; else dst_g = G[11:0];
        if (B[13]) dst_b = 12'd0; else if (|B[12:10]) dst_b = 12'd1023; else dst_b = B[11:0];
        if (R[13]) dst_r = 12'd0; else if (|R[12:10]) dst_r = 12'd1023; else dst_r = R[11:0];
      end
    12'd4095:
      begin
        if (G[13]) dst_g = 12'd0; else if (G[12]) dst_g = 12'd4095; else dst_g = G[11:0];
        if (B[13]) dst_b = 12'd0; else if (B[12]) dst_b = 12'd4095; else dst_b = B[11:0];
        if (R[13]) dst_r = 12'd0; else if (R[12]) dst_r = 12'd4095; else dst_r = R[11:0];
      end
    default:
      begin
        if (G[13]) dst_g = 12'd0; else if (|G[12:8]) dst_g = 12'd255; else dst_g = G[11:0];
        if (B[13]) dst_b = 12'd0; else if (|B[12:8]) dst_b = 12'd255; else dst_b = B[11:0];
        if (R[13]) dst_r = 12'd0; else if (|R[12:8]) dst_r = 12'd255; else dst_r = R[11:0];
      end
  endcase
end

endmodule