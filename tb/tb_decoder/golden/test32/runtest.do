vsim -gui -t ps -gPPS_INPUT_METHOD="APB"  -novopt -coverage -voptargs=\"+cover=bcfst\" work.tb_decoder
coverage save -onexit ./coverage/test32.ucdb
run -all 
quit -f