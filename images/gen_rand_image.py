import argparse
from enum import Enum
import random

class ImgFormat(Enum):
    ppm = "ppm"
    ycocg = "ycocg"
   
    def __str__(self):
        return self.value
   
# Parse input parameters
parser  = argparse.ArgumentParser(description="Parse test generation parameters", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-f", "--img_format", type=ImgFormat, choices=list(ImgFormat), default=ImgFormat.ppm, help="Image format: ppm or ycocg")
parser.add_argument("-x", '--img_width', type=int, default=640, help="Image width")
parser.add_argument("-y", '--img_height', type=int, default=480, help="Image height")
parser.add_argument("-b", '--bpc', type=int, default=8, help="Bits per component")
args = parser.parse_args()
config = vars(args)
print(config)

h = config['img_height']
w = config['img_width']
bpc = config['bpc']
max_value = 2**bpc-1
if (bpc == 8):
    num_bytes = 1
else:
    num_bytes = 2

# PPM image generation
if (args.img_format == ImgFormat.ppm):
   print("image format is ppm" )
   with open("rnd_image.ppm", "wb") as binary_file:
       # PPM header
       ppm_header = 'P6\x0A' + str(w) + ' ' + str(h) + '\x0A' + str(max_value) + '\x0A'
       binary_file.write(ppm_header.encode('ascii'))
       # Random data
       for py in range(h):
          for px in range(w):
             for pc in range(3):
                 rand_int = random.randint(0, max_value)
                 rand_bytes = rand_int.to_bytes(num_bytes, 'big')
                 binary_file.write(rand_bytes)
else:
   print("image format ycocg is TBD" )
