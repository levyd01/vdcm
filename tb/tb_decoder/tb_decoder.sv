`timescale 1ns / 1ps

`default_nettype none


module tb_decoder
#(
)();

parameter MAX_SLICE_WIDTH     = 2560;
parameter MAX_SLICE_HEIGHT    = 2560;
parameter MAX_BPC = 8;
parameter MAX_NBR_SLICES = 2;

real AVG_PIXEL_RATE = 1.2*(10**6); // pixels per second
real SPEED_FACTOR = 1.2; // Factor mutiplying the minimum required rate of the internal DSC clock.

real CLK_CORE_PERIOD = 100.0; // 16 pixels processed per slice per clock cycle
reg clk_core = 1;
always
  #(CLK_CORE_PERIOD/2) clk_core = ~clk_core;
  
  
integer fc;
integer file_test_cfg;
integer chunks_per_line;
real bits_per_pixel;
string comment;
real CLK_IN_INT_PERIOD;
real CLK_OUT_INT_PERIOD;
initial begin
  file_test_cfg = $fopen("test_cfg.txt", "r");
  fc = $fscanf(file_test_cfg,"%d\t%s\n",chunks_per_line, comment);
  fc = $fscanf(file_test_cfg,"%f\t%s\n", bits_per_pixel, comment);

  CLK_CORE_PERIOD = (10**6) / (AVG_PIXEL_RATE / 16.0 / chunks_per_line * SPEED_FACTOR);
  CLK_IN_INT_PERIOD = (10**6) / AVG_PIXEL_RATE * (16*256.0/bits_per_pixel);
  CLK_OUT_INT_PERIOD = (10**6) / (AVG_PIXEL_RATE / 4.0 * SPEED_FACTOR);
  
end

reg clk_in_int = 1;
always
  #(CLK_IN_INT_PERIOD/2) clk_in_int = ~clk_in_int;
  
reg clk_out_int = 1;
always
  #(CLK_OUT_INT_PERIOD/2) clk_out_int = ~clk_out_int;

reg pps_done = 0;
initial begin
  @(posedge uut.pps_valid);
  pps_done = 1;
end
  
reg rst_n = 1'b0;
reg flush = 1'b0;
reg in_sof = 1'b0;
reg in_valid = 1'b0;
reg [255:0] in_data = 256'hx;
reg in_data_is_pps = 1'b0;
reg [128*8-1:0] pps;
integer w;
reg [255:0] tmp_data;
integer file_vdcm_bits;
integer file_qp [MAX_NBR_SLICES-1:0];
integer file_pQuant [MAX_NBR_SLICES-1:0];
integer file_bufferFullness [MAX_NBR_SLICES-1:0];
integer file_rcFullness [MAX_NBR_SLICES-1:0];
integer file_targetRate [MAX_NBR_SLICES-1:0];
integer file_blockBits [MAX_NBR_SLICES-1:0];
integer file_pReconBlk [MAX_NBR_SLICES-1:0];
reg [128*8-1:0] pps_rev;
integer cread;
integer b;
integer s;
integer ReadStatus;
reg [255:0] tmp_data_rev;
integer closing_files = 0;
reg pixs_out_eof_dl;

initial begin
  #55;
  rst_n = 1'b1;
  #15;
  @(negedge clk_in_int);
  flush = 1'b1;
  @(negedge clk_in_int);
  flush = 1'b0;
  @(negedge clk_in_int);
  file_vdcm_bits = $fopen("vdcm.bits", "rb");
  cread = $fread(pps_rev, file_vdcm_bits);
  for(b=0; b<128; b=b+1)
    pps[8*b+:8] = pps_rev[(127-b)*8+:8];

  // Send PPS in 4 bursts of 256 bits each
  for (w=0; w<4; w=w+1) begin
    in_valid = 1'b1;
    in_data = pps[w*256+:256];
    in_data_is_pps = 1'b1;
    @(negedge clk_in_int);
    in_valid = 1'b0;
    in_data_is_pps = 1'b0;
    in_data = 256'hx;
  end
  in_sof = 1'b1;
  in_valid = 1'b0;
  in_data_is_pps = 1'b0;
  in_data = 256'hx;
  while (!pps_done) begin
    @(negedge clk_in_int);
  end
  #(CLK_IN_INT_PERIOD*4);
  @(negedge clk_in_int);
  while (!pps_done) begin
    @(posedge clk_in_int);
  end
  #(CLK_IN_INT_PERIOD*3);
  @(negedge clk_in_int);
  while (!$feof(file_vdcm_bits)) begin
    ReadStatus  = $fread(tmp_data_rev,file_vdcm_bits);
    for(b=0; b<32; b=b+1)
      tmp_data[8*b+:8] = tmp_data_rev[(31-b)*8+:8];
    in_valid = 1'b1;
    in_data = tmp_data;
    @(negedge clk_in_int);
    in_sof = 1'b0;
    in_valid = 1'b0;
    in_data = 256'hx;
  end
  @(negedge clk_in_int);
  in_valid = 1'b0;
  in_data = 256'hx;
  #50;
  closing_files = 1;
  $fclose(file_vdcm_bits);
  #(CLK_IN_INT_PERIOD*3);
  #(CLK_CORE_PERIOD*3);
  @(negedge clk_out_int);
  while (!pixs_out_eof_dl)
    @(negedge clk_out_int);
  #(CLK_OUT_INT_PERIOD*3);
  $fclose(output_image_file);

  $finish;
  
end
  
wire [4*3*14-1:0] pixs_out;
wire [3:0] pixs_out_valid;
wire pixs_out_eof; //stop writing to file after the last 4 pixels of the frame
wire [3:0] pixs_out_eol; // indicates position of last valid pixel on the line

vdcm_decoder
#(
  .MAX_NBR_SLICES            (MAX_NBR_SLICES),
  .MAX_BPC                   (MAX_BPC),
  .MAX_SLICE_WIDTH           (MAX_SLICE_WIDTH),
  .MAX_SLICE_HEIGHT          (MAX_SLICE_HEIGHT)
)
uut
(
  .clk_core             (clk_core),
  .clk_in_int           (clk_in_int),
  .clk_out_int          (clk_out_int),
  .rst_n                (rst_n),
  .flush                (flush),
  
  .in_data              (in_data),
  .in_valid             (in_valid),
  .in_sof               (in_sof),  // Start of frame
  .in_data_is_pps       (in_data_is_pps), // in_data contains PPS before in_sof
  
  .pixs_out             (pixs_out),
  .pixs_out_eof         (pixs_out_eof),
  .pixs_out_valid       (pixs_out_valid)

);

// Write PPM file
// --------------
// PPM header
integer output_image_file;
integer CompBitWidth; 
initial begin
  output_image_file = $fopen("output_image.ppm", "wb");
  while (!pps_done) @(posedge clk_in_int);
  $fdisplay(output_image_file, "P6");
  $fdisplay(output_image_file, "# VDC-M");
  $fdisplay(output_image_file, "%0d %0d", uut.frame_width, uut.frame_height);
  $fdisplay(output_image_file, "%0d", uut.maxPoint);
  CompBitWidth = (uut.maxPoint == 255) ? 8 : 16;
end
// PPM data
genvar gc, cpi;
wire [13:0] pixs_out_unpacked [3:0][2:0];
generate
  for (gc=0; gc<4; gc=gc+1) begin : gen_out_data_p_gc
    for (cpi=0; cpi<3; cpi=cpi+1) begin : gen_out_data_p_cpi
      assign pixs_out_unpacked[gc][cpi] = pixs_out[(gc*3+cpi)*14+:14];
    end
  end
endgenerate

always @ (posedge clk_out_int)
  pixs_out_eof_dl <= pixs_out_eof;
  
integer cp;
integer c;
always @ (negedge clk_out_int)
  if (~pixs_out_eof_dl)
    for (c=0; c<4; c=c+1)
      if (pixs_out_valid[c])
        for (cp=0; cp<3; cp=cp+1)
          if (CompBitWidth == 8)
             $fwrite(output_image_file, "%c", pixs_out_unpacked[c][cp][7:0]);
           else
             $fwrite(output_image_file, "%s", {2'b0, pixs_out_unpacked[c][cp][13:0]});

/////////////////////////
// Validation
/////////////////////////
localparam MAX_ERROR = 2;

integer err_cnt = 0;
event error_found;

always @(error_found) begin
  err_cnt = err_cnt + 1;
  if (err_cnt >= MAX_ERROR)
    $fatal;
end

string slice_no_str;
string filename;
initial begin
  for (s=0; s<chunks_per_line; s=s+1) begin 
    slice_no_str.itoa(s);
    filename = {"golden/qp_gold_", slice_no_str, ".txt"};
    file_qp[s] = $fopen(filename, "r");
    filename = {"golden/pQuant_gold_", slice_no_str, ".txt"};
    file_pQuant[s] = $fopen(filename, "r");
    filename = {"golden/bufferFullness_gold_", slice_no_str, ".txt"};
    file_bufferFullness[s] = $fopen(filename, "r");
    filename = {"golden/rcFullness_gold_", slice_no_str, ".txt"};
    file_rcFullness[s] = $fopen(filename, "r");
    filename = {"golden/targetRate_gold_", slice_no_str, ".txt"};
    file_targetRate[s] = $fopen(filename, "r");
    filename = {"golden/blockBits_gold_", slice_no_str, ".txt"};
    file_blockBits[s] = $fopen(filename, "r");
    filename = {"golden/pReconBlk_gold_", slice_no_str, ".txt"};
    file_pReconBlk[s] = $fopen(filename, "r");
  end
  $timeformat(-9, 0, " ns");
end


task Assert;
  input integer gold;
  input integer sut;
  input string message;
  begin
    if (gold != sut) begin
      $display("time: %0t, %0s", $realtime, message);
      $display("Expected: %d", gold);
      $display("Received: %d", sut);
      -> error_found;
    end
  end
endtask


genvar gs;
string s_idx_str;
integer slice_cnt [MAX_NBR_SLICES-1:0];
generate
  for (gs=0; gs<MAX_NBR_SLICES; gs=gs+1) begin : gen_slice_validation
    string slice_cnt_str;
    always @ (negedge rst_n or negedge uut.gen_slice_decoder[gs].slice_decoder_u.sos)
      if (gs < chunks_per_line)
        if (!rst_n)
          slice_cnt[gs] = 0;
        else begin
          s_idx_str.itoa(gs);
          slice_cnt_str.itoa(slice_cnt[gs]);
          $display ({"slice coordinate: ", slice_cnt_str, ", ", s_idx_str});
          slice_cnt[gs] = slice_cnt[gs] + 1;
        end
  
    // qp validation
    integer fd;
    integer qp_g;
    always @ (negedge clk_core)
      if (gs < chunks_per_line)
        if (uut.gen_slice_decoder[gs].slice_decoder_u.dec_rate_control_u.qp_valid)
          if (!$feof(file_qp[gs])) begin
            fd = $fscanf(file_qp[gs],"%d\n",qp_g);
            s_idx_str.itoa(gs);
            Assert(qp_g, uut.gen_slice_decoder[gs].slice_decoder_u.dec_rate_control_u.qp, {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong qp"});     
          end
        else
          $fclose(file_qp[gs]);
    
    // pQuant validation
    integer pQuant_g[2:0][15:0];
    string c_str;
    string s_str;
    always @ (negedge clk_core)
      if (gs < chunks_per_line)
        if ((uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.pQuant_r_valid) & // Quantized residuals only present when not in MODE_BP_SKIP
                    ((uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockMode == uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.MODE_TRANSFORM) | 
                     (uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockMode == uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.MODE_BP) |
                     (uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockMode == uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.MODE_MPP) |
                     (uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockMode == uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.MODE_MPPF)))
          if (!$feof(file_pQuant[gs])) begin  
            fd = $fscanf(file_pQuant[gs],"%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d",
                         pQuant_g[0][0], pQuant_g[0][1], pQuant_g[0][2], pQuant_g[0][3], pQuant_g[0][4], pQuant_g[0][5], pQuant_g[0][6], pQuant_g[0][7],
                         pQuant_g[0][8], pQuant_g[0][9], pQuant_g[0][10], pQuant_g[0][11], pQuant_g[0][12], pQuant_g[0][13], pQuant_g[0][14], pQuant_g[0][15],
                         pQuant_g[1][0], pQuant_g[1][1], pQuant_g[1][2], pQuant_g[1][3], pQuant_g[1][4], pQuant_g[1][5], pQuant_g[1][6], pQuant_g[1][7],
                         pQuant_g[1][8], pQuant_g[1][9], pQuant_g[1][10], pQuant_g[1][11], pQuant_g[1][12], pQuant_g[1][13], pQuant_g[1][14], pQuant_g[1][15],
                         pQuant_g[2][0], pQuant_g[2][1], pQuant_g[2][2], pQuant_g[2][3], pQuant_g[2][4], pQuant_g[2][5], pQuant_g[2][6], pQuant_g[2][7],
                         pQuant_g[2][8], pQuant_g[2][9], pQuant_g[2][10], pQuant_g[2][11], pQuant_g[2][12], pQuant_g[2][13], pQuant_g[2][14], pQuant_g[2][15]);
            for (c=0; c<3; c=c+1)
              for (s=0; s<16; s=s+1) begin
                if ($isunknown(uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.pQuant_r[c][s])) begin
                  $display("Failure: pQuant_r is X");
                  $fatal;
                end
                c_str = $sformatf("%0d", c);
                s_str = $sformatf("%0d", s);
                s_idx_str.itoa(gs);
                Assert(pQuant_g[c][s], uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.pQuant_r[c][s], {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong pQuant_r[",c_str,"][",s_str,"]"});
              end
          end
          else
            $fclose(file_pQuant[gs]);
      
    // bufferFullness validation
    integer bufferFullness;
    integer bufferFullness_g;
    always @ (negedge clk_core)
      if (gs < chunks_per_line)
        if (uut.gen_slice_decoder[gs].slice_decoder_u.block_position_u.substreams123_parsed)
          if (!$feof(file_bufferFullness[gs])) begin
            fd = $fscanf(file_bufferFullness[gs],"%d\n",bufferFullness_g);
            s_idx_str.itoa(gs);
            Assert(bufferFullness_g, uut.gen_slice_decoder[gs].slice_decoder_u.dec_rate_control_u.bufferFullness_r, {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong bufferFullness"});
          end
          else
            $fclose(file_bufferFullness[gs]);
        
    // rcFullness validation
    integer rcFullness;
    integer rcFullness_g;
    always @ (negedge clk_core)
      if (gs < chunks_per_line)
        if (uut.gen_slice_decoder[gs].slice_decoder_u.block_position_u.substreams123_parsed)
          if (!$feof(file_rcFullness[gs])) begin
            fd = $fscanf(file_rcFullness[gs],"%d\n",rcFullness_g);
            slice_cnt_str.itoa(slice_cnt[gs]-1);
            s_idx_str.itoa(gs);
            Assert(rcFullness_g, uut.gen_slice_decoder[gs].slice_decoder_u.dec_rate_control_u.rcFullness, {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong rcFullness"});
          end
        else
          $fclose(file_rcFullness[gs]);
        
    // targetRate validation
    integer targetRate;
    integer targetRate_g;
    always @ (negedge clk_core) 
      if (gs < chunks_per_line)
        if (uut.gen_slice_decoder[gs].slice_decoder_u.block_position_u.substreams123_parsed)
          if (!$feof(file_targetRate[gs])) begin
            fd = $fscanf(file_targetRate[gs],"%d\n",targetRate_g);
            s_idx_str.itoa(gs);
            if (~uut.gen_slice_decoder[gs].slice_decoder_u.block_position_u.isFirstBlock) // We do not care about the first block targetRate because it is not used in this block
              Assert(targetRate_g, uut.gen_slice_decoder[gs].slice_decoder_u.dec_rate_control_u.targetRate, {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong targetRate"});
          end
        else
          $fclose(file_targetRate[gs]);
    
    // blockBits validation
    integer blockBits_g;
        always @ (negedge clk_core)
          if (gs < chunks_per_line)
            if (uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockBits_valid)
              if (!$feof(file_blockBits[gs])) begin
                fd = $fscanf(file_blockBits[gs],"%d\n",blockBits_g);
                s_idx_str.itoa(gs);
                Assert(blockBits_g, uut.gen_slice_decoder[gs].slice_decoder_u.syntax_parser_u.blockBits, {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong blockBits"});
              end
            else
              $fclose(file_blockBits[gs]);
    
    // Reconstructed block validation    
    integer comp;
    integer r;
    reg signed [13:0] pReconBlk_uut[MAX_NBR_SLICES-1:0][2:0][1:0][7:0];
    always @ (*)
      for(comp=0; comp<3; comp=comp+1)             
        for (r=0; r<2; r=r+1)
          for (c=0; c<8; c=c+1)
            pReconBlk_uut[gs][comp][r][c] = uut.gen_slice_decoder[gs].slice_decoder_u.decoding_processor_u.pReconBlk_p[(comp*8*2+r*8+c)*14+:14];
       
    string comp_str;
    string r_str;
    integer pReconBlk_g[2:0][1:0][7:0];
    always @ (negedge clk_core)
      if (gs < chunks_per_line)
        if (uut.gen_slice_decoder[gs].slice_decoder_u.decoding_processor_u.pReconBlk_valid)
          if (!$feof(file_pReconBlk[gs])) begin
            if ($isunknown(uut.gen_slice_decoder[gs].slice_decoder_u.decoding_processor_u.pReconBlk_p)) begin
              $display("Failure: pReconBlk is X");
              $fatal;
            end
            fd = $fscanf(file_pReconBlk[gs],"%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d",
                         pReconBlk_g[0][0][0], pReconBlk_g[0][0][1], pReconBlk_g[0][0][2], pReconBlk_g[0][0][3], pReconBlk_g[0][0][4], pReconBlk_g[0][0][5], pReconBlk_g[0][0][6], pReconBlk_g[0][0][7],
                         pReconBlk_g[0][1][0], pReconBlk_g[0][1][1], pReconBlk_g[0][1][2], pReconBlk_g[0][1][3], pReconBlk_g[0][1][4], pReconBlk_g[0][1][5], pReconBlk_g[0][1][6], pReconBlk_g[0][1][7],
                         pReconBlk_g[1][0][0], pReconBlk_g[1][0][1], pReconBlk_g[1][0][2], pReconBlk_g[1][0][3], pReconBlk_g[1][0][4], pReconBlk_g[1][0][5], pReconBlk_g[1][0][6], pReconBlk_g[1][0][7],
                         pReconBlk_g[1][1][0], pReconBlk_g[1][1][1], pReconBlk_g[1][1][2], pReconBlk_g[1][1][3], pReconBlk_g[1][1][4], pReconBlk_g[1][1][5], pReconBlk_g[1][1][6], pReconBlk_g[1][1][7],
                         pReconBlk_g[2][0][0], pReconBlk_g[2][0][1], pReconBlk_g[2][0][2], pReconBlk_g[2][0][3], pReconBlk_g[2][0][4], pReconBlk_g[2][0][5], pReconBlk_g[2][0][6], pReconBlk_g[2][0][7],
                         pReconBlk_g[2][1][0], pReconBlk_g[2][1][1], pReconBlk_g[2][1][2], pReconBlk_g[2][1][3], pReconBlk_g[2][1][4], pReconBlk_g[2][1][5], pReconBlk_g[2][1][6], pReconBlk_g[2][1][7]);
            for(comp=0; comp<3; comp=comp+1)             
              for (r=0; r<2; r=r+1)
                for (c=0; c<8; c=c+1) begin
                  r_str = $sformatf("%0d", r);
                  c_str = $sformatf("%0d", c);
                  comp_str = $sformatf("%0d", comp);
                  s_idx_str.itoa(gs);
                  Assert(pReconBlk_g[comp][r][c], pReconBlk_uut[gs][comp][r][c], {"Slice ", slice_cnt_str, ", ", s_idx_str, ": Wrong pReconBlk[",comp_str,"][",r_str,"][",c_str,"]"});
                end
          end
        else
          $fclose(file_pReconBlk[gs]);

  end
endgenerate

    
endmodule

`default_nettype wire

