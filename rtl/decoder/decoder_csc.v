`ifndef SYNTHESIS
// synopsys translate_off
`timescale 1ns / 1ns
// synopsys translate_on
`endif

`default_nettype none

module decoder_csc
#(
  parameter MAX_SLICE_WIDTH         = 2560,
  parameter MAX_SLICE_HEIGHT        = 2560
)
(
  input wire clk,
  input wire rst_n,
  input wire flush,
  
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [$clog2(MAX_SLICE_WIDTH)-1:0] slice_width,
  input wire [12:0] maxPoint,
  
  input wire pReconBlk_valid,
  input wire [2*8*3*14-1:0] pReconBlk_p,
  
  output reg cscBlk_valid,
  output wire [2*8*3*14-1:0] cscBlk_p
);

genvar cpi, gc, gr;
// unpack input
wire signed [13:0] pReconBlk [2:0][1:0][7:0];
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_pReconBlk_cpi
    for (gr=0; gr<2; gr=gr+1) begin : gen_pReconBlk_gr
      for (gc=0; gc<8; gc=gc+1) begin : gen_pReconBlk_gc // TBD 4:2:2 and 4:2:0
        assign pReconBlk[cpi][gr][gc] = pReconBlk_p[(cpi*16+gr*8+gc)*14+:14];
      end
    end
  end
endgenerate

wire signed [13:0] src_y [1:0][7:0];
wire signed [13:0] src_co [1:0][7:0];
wire signed [13:0] src_cg [1:0][7:0];
generate
  for (gr=0; gr<2; gr=gr+1)
    for (gc=0; gc<8; gc=gc+1) begin // TBD 4:2:2 and 4:2:0
      assign src_y[gr][gc] =  pReconBlk[0][gr][gc];
      assign src_co[gr][gc] = pReconBlk[1][gr][gc];
      assign src_cg[gr][gc] = pReconBlk[2][gr][gc];
    end
endgenerate

wire [11:0] dst_r [1:0][7:0];
wire [11:0] dst_g [1:0][7:0];
wire [11:0] dst_b [1:0][7:0];

generate
  for (gr=0; gr<2; gr=gr+1) begin : gen_conv_to_rgb_row
    for (gc=0; gc<8; gc=gc+1) begin : gen_conv_to_rgb_col
      ycocg2rgb ycocg2rgb_u
      (
        .maxPoint         (maxPoint),
        .src_y            (src_y[gr][gc]),
        .src_co           (src_co[gr][gc]),
        .src_cg           (src_cg[gr][gc]),
        .dst_r            (dst_r[gr][gc]),
        .dst_g            (dst_g[gr][gc]),
        .dst_b            (dst_b[gr][gc])
      );
    end
  end
endgenerate

integer cp, ci, ri;

reg [13:0] rgb_reg [2:0][1:0][7:0];
always @ (posedge clk)
  if (pReconBlk_valid)
    for (cp=0; cp<3; cp=cp+1)
      for (ri=0; ri<2; ri=ri+1)
        for (ci=0; ci<8; ci=ci+1)
          case(cp)
            2'd0: rgb_reg[0][ri][ci] <= (csc == 2'd1) ? {2'b0, dst_r[ri][ci]} : pReconBlk[0][ri][ci];
            2'd1: rgb_reg[1][ri][ci] <= (csc == 2'd1) ? {2'b0, dst_g[ri][ci]} : pReconBlk[1][ri][ci];
            2'd2: rgb_reg[2][ri][ci] <= (csc == 2'd1) ? {2'b0, dst_b[ri][ci]} : pReconBlk[2][ri][ci];
          endcase

always @ (posedge clk or negedge rst_n)
  if (~rst_n)
    cscBlk_valid <= 1'b0;
  else
    cscBlk_valid <= pReconBlk_valid;
          
generate
  for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_cscBlk_p_cpi
    for (gr=0; gr<2; gr=gr+1) begin : gen_cscBlk_p_gr
      for (gc=0; gc<8; gc=gc+1) begin : gen_cscBlk_p_gc // TBD 4:2:2 and 4:2:0
        assign cscBlk_p[(cpi*16+gr*8+gc)*14+:14] = rgb_reg[cpi][gr][gc];
      end
    end
  end
endgenerate

  
endmodule