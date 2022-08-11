import os
import argparse

# Parse input parameters
parser  = argparse.ArgumentParser(description="Get test number to process", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
requiredNamed = parser.add_argument_group('required named arguments')
requiredNamed.add_argument('-t', '--test_number', help='Test number to process', required=True)
args = parser.parse_args()
config = vars(args)
test_nbr = config['test_number']
print("Processing test " + str(test_nbr))

# Read config file
with open('test' + str(test_nbr) + '/test_cfg.txt') as fr:
    line = fr.readline() # Number of slices per line
    line_split = line.split('#')
    slicesPerLine = int(line_split[0])
    line = fr.readline()  # bpp (only used by verilog testbench)
    line = fr.readline()  # Source image name
    line_split = line.split('#')
    inFile = line_split[0].rstrip()
    line = fr.readline()  # VDCM version (1.1 and 1.2 are the only valid values)
    line_split = line.split('#')
    vdcm_version = line_split[0].rstrip()
    line = fr.readline()  # Configuration file name
    line_split = line.split('#')
    configFile = line_split[0].rstrip()
    line = fr.readline()  # Slice Height override
    line_split = line.split('#')
    sliceHeight = int(line_split[0])
    

os.chdir("./../../../c_model/x64")
# Run VDCM Encoder to generate compressed vdcm.bits
slicesPerLineArg = "-slicesPerLine " + str(slicesPerLine)
inFileArg = "-inFile ../../images/" + inFile
bitstreamArg = "-bitstream vdcm.bits"
configFileArg = "-configFile ../config_files/v" + vdcm_version + "/" + configFile
sliceHeightArg = ""
if (sliceHeight != 0): # Override default slice height
   sliceHeightArg = "-sliceHeight " + str(sliceHeight)
os.system("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg)
print("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg)
# Run VDCM Decoder to generate golden image
recFileArg = "-recFile golden_image.out.ppm"
os.system("VDCM_Decoder.exe " + bitstreamArg + " " + recFileArg + " -debugTracer")

# Copy generated files to test directory
os.system("cp debugTracerDecoder.txt ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")
os.system("cp golden_image.out.ppm ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")
os.system("cp vdcm.bits ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")



os.chdir("./../../tb/tb_decoder/golden")