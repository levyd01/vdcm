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

def find_nth(haystack, needle, n):
    start = haystack.find(needle)
    while start >= 0 and n > 1:
        start = haystack.find(needle, start+len(needle))
        n -= 1
    return start

# Determine number of slices per line
lines = []
slice_x_coord = []
with open('debugTracerDecoder.txt') as fr:
    line = fr.readline()
    while line:
        if (line.find("SLICE_START:") != -1):
            pos_of_1st_comma = find_nth(line, ',', 1)
            end_pos = len(line)
            new_x_coord = int(line[pos_of_1st_comma+1:end_pos-1])
            if (new_x_coord in slice_x_coord):
                break
            else:
                slice_x_coord.append(new_x_coord)
        line = fr.readline()
nbr_slices = len(slice_x_coord)
print("nbr_slices = ", nbr_slices)

f_pQuant = [0]*nbr_slices
f_qp = [0]*nbr_slices
f_bufferFullness = [0]*nbr_slices
f_rcFullness = [0]*nbr_slices
f_targetRate = [0]*nbr_slices
f_blockBits = [0]*nbr_slices
f_pReconBlk = [0]*nbr_slices

for s in range(nbr_slices):
    f_pQuant[s] = open('pQuant_gold_' + str(s) + '.txt', 'w')
    f_qp[s] = open('qp_gold_' + str(s) + '.txt', 'w')
    f_bufferFullness[s] = open('bufferFullness_gold_' + str(s) + '.txt', 'w')
    f_rcFullness[s] = open('rcFullness_gold_' + str(s) + '.txt', 'w')
    f_targetRate[s] = open('targetRate_gold_' + str(s) + '.txt', 'w')
    f_blockBits[s] = open('blockBits_gold_' + str(s) + '.txt', 'w')
    f_pReconBlk[s] = open('pReconBlk_gold_' + str(s) + '.txt', 'w')

start = 1
comp = 0
lines = []
with open('debugTracerDecoder.txt') as fr:
    line = fr.readline()
    while line:
        if (line.find("SLICE_START:") != -1):
            pos_of_1st_comma = find_nth(line, ',', 1)
            end_pos = len(line)
            new_x_coord = int(line[pos_of_1st_comma+1:end_pos-1])
            s = slice_x_coord.index(new_x_coord)
        if (line.find("BLOCK_START:") != -1):
            if (start == 1):
                start = 0
        # pQuant
        elif ((line.find("BP: QuantBlk[") != -1) or (line.find("XFORM: QuantBlk[") != -1) or (line.find("MPP: qResBlk[") != -1) or (line.find("MPPF: Quant[") != -1)):
            pos_of_2nd_opening_bracket = find_nth(line, '[', 2)
            pos_of_2nd_closing_bracket = find_nth(line, ']', 2)
            f_pQuant[s].write(line[(pos_of_2nd_opening_bracket+1):pos_of_2nd_closing_bracket])
            if ((line.find("BP: QuantBlk[0") != -1) or (line.find("XFORM: QuantBlk[0") != -1) or \
                                                       (line.find("MPP: qResBlk[0") != -1) or \
                                                       (line.find("MPPF: Quant[0") != -1) or \
                                                       (line.find("BP: QuantBlk[1") != -1) or \
                                                       (line.find("XFORM: QuantBlk[1") != -1) or \
                                                       (line.find("MPP: qResBlk[1") != -1) or \
                                                       (line.find("MPPF: Quant[1") != -1)):
                f_pQuant[s].write(', ')
            elif ((line.find("BP: QuantBlk[2") != -1) or (line.find("XFORM: QuantBlk[2") != -1) or (line.find("MPP: qResBlk[2") != -1) or (line.find("MPPF: Quant[2") != -1)):
                f_pQuant[s].write('\n')
        # qp
        elif (line.find("RC: qp = ") != -1):
            equal_index = line.find("=");
            f_qp[s].write(line[equal_index+2:-1] + '\n')
        # bufferFullness
        elif (line.find("RC: bufferFullness = ") != -1):
            equal_index = line.find("=");
            f_bufferFullness[s].write(line[equal_index+2:-1] + '\n')
        # rcFullness
        elif (line.find("RC: rcFullness = ") != -1):
            equal_index = line.find("=");
            f_rcFullness[s].write(line[equal_index+2:-1] + '\n')
        # targetRate
        elif (line.find("RC: targetRate = ") != -1):
            equal_index = line.find("=");
            f_targetRate[s].write(line[equal_index+2:-1] + '\n')
        # blockBits
        elif (line.find(": bits = ") != -1):
            pos_of_1st_equal = find_nth(line, '=', 1)
            pos_of_2nd_equal = find_nth(line, '=', 2)
            if (pos_of_2nd_equal != -1):
                f_blockBits[s].write(line[pos_of_2nd_equal+2:-1] + '\n')
            else:
                f_blockBits[s].write(line[pos_of_1st_equal+2:-1] + '\n')
        # pReconBlk
        elif (line.find(": RecBlk[") != -1):
            pos_of_2nd_opening_bracket = find_nth(line, '[', 2)
            pos_of_2nd_closing_bracket = find_nth(line, ']', 2)
            f_pReconBlk[s].write(line[(pos_of_2nd_opening_bracket+1):pos_of_2nd_closing_bracket])
            if ((line.find(": RecBlk[0") != -1) or (line.find(": RecBlk[1") != -1)):
                f_pReconBlk[s].write(', ')
            else:
                f_pReconBlk[s].write('\n')
        line = fr.readline()

for s in range(nbr_slices):
    f_pQuant[s].close()
    f_qp[s].close()
    f_bufferFullness[s].close()
    f_rcFullness[s].close()
    f_targetRate[s].close()
    f_blockBits[s].close()
    f_pReconBlk[s].close()