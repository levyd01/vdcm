vsim -gui -t ps -gPPS_INPUT_METHOD="DIRECT"  -novopt -coverage -voptargs=\"+cover=bcfst\" work.tb_decoder
coverage save -onexit ./coverage/test27.ucdb
run -all 
quit -f