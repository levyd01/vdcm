vsim -gui -t ps -gPPS_INPUT_METHOD="IN_BAND"  -novopt work.tb_decoder
run -all 
quit -f