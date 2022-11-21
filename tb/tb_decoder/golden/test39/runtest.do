vsim -gui -t ps -gPPS_INPUT_METHOD="APB"  -novopt work.tb_decoder
run -all 
quit -f