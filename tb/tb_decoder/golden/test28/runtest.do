vsim -gui -t ps -gPPS_INPUT_METHOD="APB"  -novopt -coverage -voptargs=\"+cover=bcfst\" work.tb_decoder
coverage save -onexit ./coverage/test28.ucdb
run -all 
quit -f