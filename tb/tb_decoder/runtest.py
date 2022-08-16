import os
import sys
import argparse
from os.path import exists

# Parse input parameters
parser  = argparse.ArgumentParser(description="Parse test parameters", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-c", "--compile", action="store_true", help="Compile only, no test run")
parser.add_argument("-p", "--prepare", type=int, help="Test to prepare")
parser.add_argument("-t", '--test_number', nargs='+', type=int, help="List of tests to run")

args = parser.parse_args()
config = vars(args)
print(config)
compile_only = config['compile']
prepare_test_nbr = config['prepare']
test_nbr_list = config['test_number']
print(test_nbr_list)

if (config['prepare'] != None):
  prepare_only = True
  test_nbr_list = [prepare_test_nbr]
else:
  prepare_only = False

# Create Modelsim library
#os.system("vlib work")
#os.system("vmap work")
# Compile
verilog_file_list = ["tb_decoder.sv", \
                     "../../rtl/utils/synchronizer.v", \
                     "../../rtl/utils/dp_ram.v", \
                     "../../rtl/utils/sp_ram.v", \
                     "../../rtl/utils/sync_dp_ram.v", \
                     "../../rtl/decoder/vdcm_decoder.v", \
                     "../../rtl/decoder/pps_regs.v", \
                     "../../rtl/decoder/in_sync_buf.v", \
                     "../../rtl/decoder/slice_demux.v", \
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
                     "../../rtl/decoder/output_buffers.v", \
                     "../../rtl/decoder/out_sync_buf.v", \
                     "../../rtl/decoder/slice_mux.v" ]

if (prepare_only == False):
  for file_name in verilog_file_list:
    vlog_arg = "vlog " + file_name             
    status = os.system(vlog_arg)
    if (status != 0):
      print("Compilation failed")
      exit(-1)
    
if (compile_only):
  exit(0)
   
test_status_dict = {}
for test_nbr in test_nbr_list:
  test_status_dict[test_nbr] = True
  # Copy from selected test directory to main test directory
  os.system("cp golden/test" + str(test_nbr) + "/debugTracerDecoder.txt golden/debugTracerDecoder.txt")
  os.system("cp golden/test" + str(test_nbr) + "/golden_image.out.ppm golden/golden_image.out.ppm")
  os.system("cp golden/test" + str(test_nbr) + "/test_cfg.txt .")
  os.system("cp golden/test" + str(test_nbr) + "/vdcm.bits .")
  
  # Generate from debugTracerDecoder.txt all golden files needed by Verilog testbench
  os.chdir('./golden')
  os.system("python C_golden_to_RTL_golden.py")
  os.chdir("./..")
  
  # Delete existing image
  os.system("rm -f ./output_image.ppm")
  
  if (prepare_only):
    exit(0)
    
  # Run simulation
  print("###################################")
  print("#         Running test " + str(test_nbr) + "          #")
  print("###################################")

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
     print("###################################")
     print("#      Simulation failed :-(      #")
     print("###################################")
     test_status_dict[test_nbr] = False
  log_file.close() 
  
  # Compare output image to golden image
  if (test_status_dict[test_nbr] == True):
    file_exists = exists("./output_image.ppm")
    if (file_exists == False):
       print("Output image does not exist")
       print("###################################")
       print("#      Simulation failed :-(      #")
       print("###################################")
       test_status_dict[test_nbr] = False
    if (test_status_dict[test_nbr] == True):
      cmp_status = os.system("cmp ./output_image.ppm ./golden/golden_image.out.ppm")
      if (cmp_status != 0):
         print("Output image does not match with golden image")
         print("###################################")
         print("#      Simulation failed :-(      #")
         print("###################################")
         test_status_dict[test_nbr] = False
      else:
         test_status_dict[test_nbr] = True
         print("###################################")
         print("#      Simulation passed :-)      #")
         print("###################################")
     
# Test result summary
all_pass = True
for test_nbr in test_status_dict:
  if (test_status_dict[test_nbr] == False):
    print("Test " + str(test_nbr) + " failed :-(")
    all_pass = False
  else:
    print("Test " + str(test_nbr) + " passed :-)")
if (all_pass == True):
  print("All tests passed :-))")
  exit(0)
else:
  exit(-1)
  
