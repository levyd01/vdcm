vsim -gui -t ps -gPPS_INPUT_METHOD="IN_BAND"  -novopt -coverage -voptargs=\"+cover=bcfst\" work.tb_decoder
coverage save -onexit ./coverage/test18.ucdb
run -all 
quit -f