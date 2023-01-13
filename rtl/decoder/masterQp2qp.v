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

module masterQp2qp
(
  input wire [1:0] bits_per_component_coded,
  input wire [1:0] csc, // 0: RGB, 1: YCoCg, 2: YCbCr
  input wire [1:0] version_minor,
  
  input wire signed [7:0] masterQp,
  input wire masterQp_valid,
  
  output wire [3*7-1:0] qp_p,
  output wire qp_valid
);

// LUTs
wire [6:0] qStepChroma [56:0];
assign qStepChroma[0 ] = 7'd16;
assign qStepChroma[1 ] = 7'd17;
assign qStepChroma[2 ] = 7'd18;
assign qStepChroma[3 ] = 7'd20; 
assign qStepChroma[4 ] = 7'd21; 
assign qStepChroma[5 ] = 7'd22; 
assign qStepChroma[6 ] = 7'd23; 
assign qStepChroma[7 ] = 7'd24; 
assign qStepChroma[8 ] = 7'd26; 
assign qStepChroma[9 ] = 7'd27; 
assign qStepChroma[10] = 7'd28; 
assign qStepChroma[11] = 7'd29; 
assign qStepChroma[12] = 7'd30; 
assign qStepChroma[13] = 7'd31; 
assign qStepChroma[14] = 7'd33; 
assign qStepChroma[15] = 7'd34; 
assign qStepChroma[16] = 7'd35; 
assign qStepChroma[17] = 7'd37; 
assign qStepChroma[18] = 7'd38; 
assign qStepChroma[19] = 7'd39; 
assign qStepChroma[20] = 7'd40; 
assign qStepChroma[21] = 7'd41; 
assign qStepChroma[22] = 7'd43; 
assign qStepChroma[23] = 7'd44; 
assign qStepChroma[24] = 7'd45; 
assign qStepChroma[25] = 7'd46; 
assign qStepChroma[26] = 7'd47; 
assign qStepChroma[27] = 7'd48; 
assign qStepChroma[28] = 7'd50; 
assign qStepChroma[29] = 7'd51; 
assign qStepChroma[30] = 7'd52; 
assign qStepChroma[31] = 7'd53; 
assign qStepChroma[32] = 7'd54; 
assign qStepChroma[33] = 7'd56; 
assign qStepChroma[34] = 7'd57; 
assign qStepChroma[35] = 7'd58; 
assign qStepChroma[36] = 7'd59; 
assign qStepChroma[37] = 7'd60; 
assign qStepChroma[38] = 7'd62; 
assign qStepChroma[39] = 7'd63; 
assign qStepChroma[40] = 7'd64; 
assign qStepChroma[41] = 7'd65; 
assign qStepChroma[42] = 7'd66; 
assign qStepChroma[43] = 7'd67; 
assign qStepChroma[44] = 7'd68; 
assign qStepChroma[45] = 7'd70; 
assign qStepChroma[46] = 7'd71; 
assign qStepChroma[47] = 7'd72; 
assign qStepChroma[48] = 7'd72; 
assign qStepChroma[49] = 7'd72; 
assign qStepChroma[50] = 7'd72; 
assign qStepChroma[51] = 7'd72; 
assign qStepChroma[52] = 7'd72; 
assign qStepChroma[53] = 7'd72; 
assign qStepChroma[54] = 7'd72; 
assign qStepChroma[55] = 7'd72; 
assign qStepChroma[56] = 7'd72;

wire [6:0] qStepCo [56:0];
assign qStepCo[0 ] = 7'd24; 
assign qStepCo[1 ] = 7'd25; 
assign qStepCo[2 ] = 7'd26; 
assign qStepCo[3 ] = 7'd27; 
assign qStepCo[4 ] = 7'd29; 
assign qStepCo[5 ] = 7'd30; 
assign qStepCo[6 ] = 7'd31; 
assign qStepCo[7 ] = 7'd33; 
assign qStepCo[8 ] = 7'd34; 
assign qStepCo[9 ] = 7'd35; 
assign qStepCo[10] = 7'd37; 
assign qStepCo[11] = 7'd38; 
assign qStepCo[12] = 7'd39; 
assign qStepCo[13] = 7'd40; 
assign qStepCo[14] = 7'd42; 
assign qStepCo[15] = 7'd43; 
assign qStepCo[16] = 7'd44; 
assign qStepCo[17] = 7'd46; 
assign qStepCo[18] = 7'd47; 
assign qStepCo[19] = 7'd48; 
assign qStepCo[20] = 7'd50; 
assign qStepCo[21] = 7'd51; 
assign qStepCo[22] = 7'd52; 
assign qStepCo[23] = 7'd53; 
assign qStepCo[24] = 7'd55; 
assign qStepCo[25] = 7'd56; 
assign qStepCo[26] = 7'd57; 
assign qStepCo[27] = 7'd59; 
assign qStepCo[28] = 7'd60; 
assign qStepCo[29] = 7'd61; 
assign qStepCo[30] = 7'd63; 
assign qStepCo[31] = 7'd64; 
assign qStepCo[32] = 7'd65; 
assign qStepCo[33] = 7'd66; 
assign qStepCo[34] = 7'd68; 
assign qStepCo[35] = 7'd69; 
assign qStepCo[36] = 7'd70; 
assign qStepCo[37] = 7'd72; 
assign qStepCo[38] = 7'd72; 
assign qStepCo[39] = 7'd72; 
assign qStepCo[40] = 7'd72; 
assign qStepCo[41] = 7'd72; 
assign qStepCo[42] = 7'd72; 
assign qStepCo[43] = 7'd72; 
assign qStepCo[44] = 7'd72; 
assign qStepCo[45] = 7'd72; 
assign qStepCo[46] = 7'd72; 
assign qStepCo[47] = 7'd72; 
assign qStepCo[48] = 7'd72; 
assign qStepCo[49] = 7'd72; 
assign qStepCo[50] = 7'd72; 
assign qStepCo[51] = 7'd72; 
assign qStepCo[52] = 7'd72; 
assign qStepCo[53] = 7'd72; 
assign qStepCo[54] = 7'd72; 
assign qStepCo[55] = 7'd72; 
assign qStepCo[56] = 7'd72;

wire [6:0] qStepCg [56:0];
assign qStepCg[0 ] = 7'd24; 
assign qStepCg[1 ] = 7'd25; 
assign qStepCg[2 ] = 7'd26; 
assign qStepCg[3 ] = 7'd27; 
assign qStepCg[4 ] = 7'd28; 
assign qStepCg[5 ] = 7'd29; 
assign qStepCg[6 ] = 7'd30; 
assign qStepCg[7 ] = 7'd31; 
assign qStepCg[8 ] = 7'd32; 
assign qStepCg[9 ] = 7'd33; 
assign qStepCg[10] = 7'd34; 
assign qStepCg[11] = 7'd35; 
assign qStepCg[12] = 7'd36; 
assign qStepCg[13] = 7'd37; 
assign qStepCg[14] = 7'd38; 
assign qStepCg[15] = 7'd39; 
assign qStepCg[16] = 7'd40; 
assign qStepCg[17] = 7'd41; 
assign qStepCg[18] = 7'd42; 
assign qStepCg[19] = 7'd43; 
assign qStepCg[20] = 7'd45; 
assign qStepCg[21] = 7'd46; 
assign qStepCg[22] = 7'd47; 
assign qStepCg[23] = 7'd48; 
assign qStepCg[24] = 7'd49; 
assign qStepCg[25] = 7'd50; 
assign qStepCg[26] = 7'd51; 
assign qStepCg[27] = 7'd52; 
assign qStepCg[28] = 7'd53; 
assign qStepCg[29] = 7'd54; 
assign qStepCg[30] = 7'd55; 
assign qStepCg[31] = 7'd56; 
assign qStepCg[32] = 7'd57; 
assign qStepCg[33] = 7'd58; 
assign qStepCg[34] = 7'd59; 
assign qStepCg[35] = 7'd60; 
assign qStepCg[36] = 7'd61; 
assign qStepCg[37] = 7'd62; 
assign qStepCg[38] = 7'd63; 
assign qStepCg[39] = 7'd64; 
assign qStepCg[40] = 7'd66; 
assign qStepCg[41] = 7'd67; 
assign qStepCg[42] = 7'd68; 
assign qStepCg[43] = 7'd69; 
assign qStepCg[44] = 7'd70; 
assign qStepCg[45] = 7'd71; 
assign qStepCg[46] = 7'd72; 
assign qStepCg[47] = 7'd72; 
assign qStepCg[48] = 7'd72; 
assign qStepCg[49] = 7'd72; 
assign qStepCg[50] = 7'd72; 
assign qStepCg[51] = 7'd72; 
assign qStepCg[52] = 7'd72; 
assign qStepCg[53] = 7'd72; 
assign qStepCg[54] = 7'd72; 
assign qStepCg[55] = 7'd72; 
assign qStepCg[56] = 7'd72;

integer c;
reg signed [7:0] tempQp [2:0];
always @ (*)
  for (c=0; c<3; c=c+1)
    case (csc)
      2'd0: tempQp[c] = masterQp;
      2'd2:
        if (masterQp < 8'sd16)
          tempQp[c] = masterQp;
        else
          tempQp[c] = ((c == 0) ? masterQp : qStepChroma[masterQp - 8'sd16]);
      2'd1:
        if (masterQp < 8'sd16)
          tempQp[c] = ((c == 0) ? masterQp : (masterQp + 8'sd8));
        else
          tempQp[c] = ((c == 0) ? masterQp : (c == 1) ? $signed({1'b0, qStepCo[masterQp - 8'sd16]}) : $signed({1'b0, qStepCg[masterQp - 8'sd16]}));
      default: tempQp[c] = masterQp;
    endcase

reg [5:0] qpAdj;
reg signed [5:0] minQp;
always @ (*)
  case (bits_per_component_coded)
    2'd0: begin qpAdj = 6'd0;  minQp = 6'sd16;  end
    2'd1: begin qpAdj = 6'd16; minQp = 6'sd0;   end
    2'd2: begin qpAdj = 6'd32; minQp = -6'sd16; end
    default: begin qpAdj = 6'd0;  minQp = 6'sd16;  end
  endcase

reg too_big;
reg too_small;
reg signed [7:0] modQp [2:0];
always @ (*)
  for (c=0; c<3; c=c+1) begin
    too_big = (tempQp[c] > 8'sd72);
    too_small = (tempQp[c] < minQp);
    case({too_big, ~(too_big|too_small), too_small})
      3'b100: modQp[c] = $signed({1'b0, 8'd72 + qpAdj});
      3'b010: modQp[c] = tempQp[c] + $signed({1'b0, qpAdj});
      3'b001: modQp[c] = minQp + $signed({1'b0, qpAdj});
      default: modQp[c] = $signed({1'b0, 8'd72 + qpAdj});
    endcase
  end
    
assign qp_valid = masterQp_valid;
  
genvar gi;
generate
  for (gi=0; gi<3; gi=gi+1) begin : pack_output
    assign qp_p[gi*7+:7] = modQp[gi][6:0];
  end
endgenerate

endmodule