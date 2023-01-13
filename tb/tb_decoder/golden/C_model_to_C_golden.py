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
    line = fr.readline()  # bpp
    line_split = line.split('#')
    bpp = line_split[0].rstrip()
    line = fr.readline()  # Source image name
    line_split = line.split('#')
    inFile = line_split[0].rstrip()
    file_ext_split = inFile.split('.')
    fileExtension = file_ext_split[1].rstrip()
    line = fr.readline()  # VDCM version (1.1 and 1.2 are the only valid values)
    line_split = line.split('#')
    vdcm_version = line_split[0].rstrip()
    line = fr.readline()  # Configuration file name
    line_split = line.split('#')
    configFile = line_split[0].rstrip()
    line = fr.readline()  # Slice Height override
    line_split = line.split('#')
    sliceHeight = int(line_split[0])
    if (fileExtension == "yuv"): # Extra arguments needed for YUV input file
      line = fr.readline() # chromaFormat
      line_split = line.split('#')
      chromaFormat = line_split[0].rstrip()
      line = fr.readline() # bitDepth
      line_split = line.split('#')
      bitDepth = line_split[0].rstrip()
      line = fr.readline() # width
      line_split = line.split('#')
      width = line_split[0].rstrip()
      line = fr.readline() # height
      line_split = line.split('#')
      height = line_split[0].rstrip()
    
os.chdir("./../../../c_model/x64")
# Run VDCM Encoder to generate compressed vdcm.bits
slicesPerLineArg = "-slicesPerLine " + str(slicesPerLine)
bppArg = "-bpp " + str(bpp)
inFileArg = "-inFile ../../images/" + inFile
bitstreamArg = "-bitstream vdcm.bits"
configFileArg = "-configFile ../config_files/v" + vdcm_version + "/" + configFile
sliceHeightArg = ""
if (sliceHeight != 0): # Override default slice height
   sliceHeightArg = "-sliceHeight " + str(sliceHeight)
if (fileExtension == "yuv"):
  chromaFormatArg = "-chromaFormat " + str(chromaFormat)
  bitDepthArg = "-bitDepth " + str(bitDepth)
  widthArg = "-width " + str(width)
  heightArg = "-height " + str(height)
  os.system("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg + " " \
                                + chromaFormatArg + " " + bppArg + " " + bitDepthArg + " " + widthArg + " " + heightArg)
  print("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg + " " \
                            + chromaFormatArg + " " + bppArg + " " + bitDepthArg + " " + widthArg + " " + heightArg)
else:
   os.system("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bppArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg)
   print("VDCM_Encoder.exe " + inFileArg + " " + slicesPerLineArg + " " + bppArg + " " + bitstreamArg + " " + configFileArg + " " + sliceHeightArg)
# Run VDCM Decoder to generate golden image
if (fileExtension == "yuv"):
   recFileArg = "-recFile golden_image.out.yuv"
else:
   recFileArg = "-recFile golden_image.out.ppm"
os.system("VDCM_Decoder.exe " + bitstreamArg + " " + recFileArg + " -debugTracer")
print("VDCM_Decoder.exe " + bitstreamArg + " " + recFileArg + " -debugTracer")

# Copy generated files to test directory
os.system("cp debugTracerDecoder.txt ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")
os.system("cp golden_image.out.* ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")
os.system("cp vdcm.bits ../../tb/tb_decoder/golden/test" + str(test_nbr) + "/.")



os.chdir("./../../tb/tb_decoder/golden")