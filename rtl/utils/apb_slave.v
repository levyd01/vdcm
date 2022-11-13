`default_nettype none

module apb_slave
#(
  parameter NBR_REGS
)
(
  input wire clk_apb,
  input wire clk_core,
  input wire rst_n,
  input wire [$clog2(NBR_REGS):0] paddr,
  input wire pwrite,
  input wire psel,
  input wire penable,
  input wire [31:0] pwdata,
  output wire pready,
  output reg [31:0] prdata,
  output wire pslverr,
  output wire [32*NBR_REGS-1:0] register_bank_p,
  output wire reg_bank_valid
);

reg [31:0] register_bank [NBR_REGS-1:0];
reg send_reg_bank; // in clk_apb domain

localparam ST_SETUP = 0;
localparam ST_W_ENABLE = 1;
localparam ST_R_ENABLE = 2;
localparam ADDR_SEND_RB = NBR_REGS;
reg [1:0] apb_st;

// SETUP -> ENABLE
always @(negedge rst_n or posedge clk_apb) begin
  if (~rst_n) begin
    apb_st <= 2'b0;
    prdata <= 32'b0;
    send_reg_bank <= 1'b0;
  end
  else begin
    case (apb_st)
      ST_SETUP : begin
        // clear the prdata
        prdata <= 32'b0;
        send_reg_bank <= 1'b0;
        // Move to ENABLE when the psel is asserted
        if (psel & ~penable) begin
          if (pwrite) begin
            apb_st <= ST_W_ENABLE;
          end
          else begin
            apb_st <= ST_R_ENABLE;
          end
        end
      end

      ST_W_ENABLE : begin
        // write pwdata to memory
        if (psel & penable & pwrite) begin
          register_bank[paddr] <= pwdata;
          if (paddr == ADDR_SEND_RB)
            send_reg_bank <= 1'b1;
        end

        // return to SETUP
        apb_st <= ST_SETUP;
      end

      ST_R_ENABLE : begin
        // read prdata from memory
        if (psel & penable & ~pwrite) begin
          prdata <= register_bank[paddr];
        end

        // return to SETUP
        apb_st <= ST_SETUP;
      end
    endcase
  end
end 

wire send_reg_bank_clk_core;
synchronizer sync_send_reg_bank_u (.clk(clk_core), .in(send_reg_bank), .out(send_reg_bank_clk_core));
reg send_reg_bank_clk_core_dl;
always @(negedge rst_n or posedge clk_core)
  send_reg_bank_clk_core_dl <= send_reg_bank_clk_core;
assign reg_bank_valid = send_reg_bank_clk_core & ~send_reg_bank_clk_core_dl;

assign pready = psel & penable & ((paddr == ADDR_SEND_RB) ? send_reg_bank_clk_core_dl : 1'b1);

genvar gi;
generate
  for (gi=0; gi<NBR_REGS; gi=gi+1) begin : pack_output
    assign register_bank_p[32*gi+:32] = register_bank[gi];
  end
endgenerate

endmodule