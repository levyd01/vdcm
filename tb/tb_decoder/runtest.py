import os
import sys
import argparse
from os.path import exists

# Parse input parameters
parser  = argparse.ArgumentParser(description="Parse test parameters", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-t", "--test_number", type=int, help="Test to run")
parser.add_argument("-c", "--compile", action="store_true", help="Compile only, no test run")

args = parser.parse_args()
config = vars(args)
print(config)
test_nbr = config['test_number']
compile_only = config['compile']

# Compile
verilog_file_list = ["tb_decoder.sv", \
                     "../../rtl/utils/dp_ram.v", \
                     "../../rtl/utils/sp_ram.v", \
                     "../../rtl/decoder/vdcm_decoder.v", \
                     "../../rtl/decoder/pps_regs.v", \
                     "../../rtl/decoder/slice_decoder.v", \
                     "../../rtl/decoder/substream_demux.v", \
                     "../../rtl/decoder/ssmFunnelShifter.v", \
                     "../../rtl/decoder/block_position.v", \
                     "../../rtl/decoder/syntax_parser.v", \
                     "../../rtl/decoder/decoding_processor.v", \
                     "../../rtl/decoder/transform_mode.v", \
                     "../../rtl/decoder/above_pixels_buf.v", \
                     "../../rtl/decoder/bp_mode.v", \
                     "../../rtl/decoder/dec_rate_control.v", \
                     "../../rtl/decoder/masterQp2qp.v", \
                     "../../rtl/decoder/decoder_csc.v", \
                     "../../rtl/decoder/pixels_buf.v", \
                     "../../rtl/decoder/output_buffers.v" ]

for file_name in verilog_file_list:
  vlog_arg = "vlog " + file_name             
  status = os.system(vlog_arg)
  if (status != 0):
    print("Compilation failed")
    exit(-1)
    
if (compile_only):
  exit(0)

# Copy from selected test directory to main test directory
os.system("cp golden/test" + str(test_nbr) + "/debugTracerDecoder.txt golden/debugTracerDecoder.txt")
os.system("cp golden/test" + str(test_nbr) + "/golden_image.out.ppm golden/golden_image.out.ppm")
os.system("cp golden/test" + str(test_nbr) + "/test_cfg.txt .")

# Generate from debugTracerDecoder.txt all golden files needed by Verilog testbench
os.chdir('./golden')
os.system("python C_golden_to_RTL_golden.py")
os.chdir("./..")

# Delete existing image
os.system("rm -f ./output_image.ppm")

# Run simulation
print ("Running test number " + str(test_nbr))
vsim_args = "vsim" + " -c -do \"runtest.do\" -l sim.log -t ns -novopt work.tb_decoder"
os.system("vsim -c -do \"runtest.do\" -l sim.log -t ns -novopt work.tb_decoder")

# Parse log file for errors
error_string = "Fatal: Assertion error"
log_file = open("sim.log", "r")
flag = 0
index = 0
for line in log_file:  
    index = index + 1       
    if error_string in line:
      flag = 1
      break
if flag != 0: 
   print("Internal signals mismatch")
   print("Simulation failed")
   exit(-1)
log_file.close() 

# Compare output image to golden image
file_exists = exists("./output_image.ppm")
if (file_exists == False):
   print("Output image does not exist")
   print("Simulation failed")
   exit(-1)
cmp_status = os.system("cmp ./output_image.ppm ./golden/golden_image.out.ppm")
if (cmp_status != 0):
   print("Output image does not match with golden image")
   print("Simulation failed")
   exit(-1)
else:
   print("Simulatin passed -:)")