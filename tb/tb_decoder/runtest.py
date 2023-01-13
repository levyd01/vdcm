# *********************************************************************
#
# Property of Vicip.
# Restricted rights to use, duplicate or disclose this code are
# granted through contract.
#
# (C) Copyright Vicip 2022
#
# Author         : David Levy
# Contact        : david.levy@vic-ip.com
# *********************************************************************

import os
import sys
import argparse
from os.path import exists

# Parse input parameters
parser  = argparse.ArgumentParser(description="Parse test parameters", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-c", "--compile", action="store_true", help="Compile only, no test run")
parser.add_argument("-p", "--prepare", type=int, help="Test to prepare")
parser.add_argument("-t", '--test_number', nargs='+', type=int, help="List of tests to run")
parser.add_argument("-g", "--coverage", action="store_true", default=False, help="Enable coverage")

args = parser.parse_args()
config = vars(args)
print(config)
compile_only = config['compile']
enable_coverage = config['coverage']
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
verilog_file_list = []
with open("verilog_file_list.txt") as fp:
    for line in fp:
      verilog_file_list.append(line)

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
  os.system("cp golden/test" + str(test_nbr) + "/golden_image.out.* golden/.")
  os.system("cp golden/test" + str(test_nbr) + "/test_cfg.txt .")
  os.system("cp golden/test" + str(test_nbr) + "/vdcm.bits .")
  
  # Generate from debugTracerDecoder.txt all golden files needed by Verilog testbench
  os.chdir('./golden')
  os.system("python C_golden_to_RTL_golden.py")
  os.chdir("./..")
  
  # Delete existing image
  os.system("rm -f ./output_image.*")
  
  if (prepare_only):
    exit(0)
    
  # Create runtest.do file
  with open("./test_cfg.txt") as fp:
    for line in fp:
      if (line.find('# PPS in') != -1):
        break
  line_list = line.split(' ')
  pps_in_method = line_list[0]
  if (enable_coverage):
    vsim_args = "vsim -gui -t ps -gPPS_INPUT_METHOD=\"" + pps_in_method + "\" -novopt -coverage -voptargs=\"+cover=bcfst\" work.tb_decoder"
  else:
    vsim_args = "vsim -gui -t ps -gPPS_INPUT_METHOD=\"" + pps_in_method + "\" -novopt work.tb_decoder"
  f_runtest = open('runtest.do', 'w')
  f_runtest.write(vsim_args + '\n')
  if (enable_coverage):
    f_runtest.write("coverage save -onexit ./coverage/test" + str(test_nbr) + ".ucdb" + '\n')
  f_runtest.write("run -all" + '\n')
  f_runtest.write("quit -f" + '\n')
  f_runtest.close()
    
  # Run simulation
  print("###################################")
  print("#         Running test " + str(test_nbr) + "          #")
  print("###################################")

  if (enable_coverage):
    os.system("vsim -c -do \"runtest.do\" -l sim.log -t ps -coverage -voptargs=\"+cover=bcfst\" -novopt work.tb_decoder")
  else:
    os.system("vsim -c -do \"runtest.do\" -l sim.log -t ps -novopt work.tb_decoder")
  
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
    file_exists_ppm = exists("./output_image.ppm")
    file_exists_yuv = exists("./output_image.yuv")
    file_exists = file_exists_ppm or file_exists_yuv
    if (file_exists == False):
       print("Output image does not exist")
       print("###################################")
       print("#      Simulation failed :-(      #")
       print("###################################")
       test_status_dict[test_nbr] = False
    if (test_status_dict[test_nbr] == True):
       if (file_exists_ppm):
          cmp_status = os.system("cmp ./output_image.ppm ./golden/golden_image.out.ppm")
       else: 
          cmp_status = os.system("cmp ./output_image.yuv ./golden/golden_image.out.yuv")
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
  
