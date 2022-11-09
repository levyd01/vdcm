class BitWriter(object):
    def __init__(self, f):
        self.accumulator = 0
        self.bcount = 0
        self.out = f

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.flush()

    def __del__(self):
        try:
            self.flush()
        except ValueError:   # I/O operation on closed file.
            pass

    def _writebit(self, bit):
        if self.bcount == 8:
            self.flush()
        if bit > 0:
            self.accumulator |= 1 << 7-self.bcount
        self.bcount += 1

    def writebits(self, bits, n):
        while n > 0:
            self._writebit(bits & 1 << n-1)
            n -= 1

    def flush(self):
        self.out.write(bytearray([self.accumulator]))
        self.accumulator = 0
        self.bcount = 0


class BitReader(object):
    def __init__(self, f):
        self.input = f
        self.accumulator = 0
        self.bcount = 0
        self.read = 0

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        pass

    def _readbit(self):
        if not self.bcount:
            a = self.input.read(1)
            if a:
                self.accumulator = ord(a)
            self.bcount = 8
            self.read = len(a)
        rv = (self.accumulator & (1 << self.bcount-1)) >> self.bcount-1
        self.bcount -= 1
        return rv

    def readbits(self, n):
        v = 0
        while n > 0:
            v = (v << 1) | self._readbit()
            n -= 1
        return v



if __name__ == '__main__':
    import argparse
    import os
    import sys

    # Parse input parameters
    parser  = argparse.ArgumentParser(description="Parse test parameters", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-i", "--in_file_name", type=str, help="YUV input file name")
    parser.add_argument("-d", "--depth", type=int, help="Bit depth")
    parser.add_argument("-o", '--out_file_name', type=str, help="YUV output file name")
    
    args = parser.parse_args()
    config = vars(args)
    #print(config)
    
    in_file_name = config['in_file_name']
    depth = config['depth']
    out_file_name = config['out_file_name']
    # Determine this module's name from it's file name and import it.
    module_name = os.path.splitext(os.path.basename(__file__))[0]
    bitio = __import__(module_name)

    with open(in_file_name, 'rb') as infile:
        with bitio.BitReader(infile) as reader:
            chars = []
            while True:
                x_lsb = reader.readbits(8)
                x_msb = reader.readbits(depth-8)
                if not reader.read:  # End-of-file?
                    break
                chars.append(chr(x_lsb))
                chars.append(chr(x_msb))
                #print("x_msb = " + str(x_msb))
                #print("x_lsb = " + str(x_lsb))
            #print(''.join(chars))
            
    with open(out_file_name, 'wb') as outfile:
        with bitio.BitWriter(outfile) as writer:
            for ch in chars:
                writer.writebits(ord(ch), 8)

            