Introduction:

VESA has developed the new-generation standard: VDC-M, which is now ready for release to clients requiring video compression over HDMI, Display Port or MIPI.
It is a quasi-lossless compression scheme, with a compression factor of 2 to 4, allowing good compression with a high data rate.

Applications:

It is very suitable for high image quality and size. The applications are for display devices with good screen quality: 
- TV sets,
- Tablets,
- PC monitors,
- high end mobile phones and
- automotive display screens.
Basically everywhere were HDMI, Display Port or MIPI are used.
The IP can also be used as a "verification IP": the IP can be used to test the real product being developed. For example, the real product is a VDC-M Encoder. Connect it to the verification IP, the VDC-M Decoder, to check things are working properly.

Features:

Standard features:
- Compliant to VESA VDC-M standard versions 1.1 and 1.2
- Supports 8, 10 and 12 bits per component.
- Supports all chroma sampling formats: 4:4:4 in RGB format, 4:4:4, 4:2:2 and 4:2:0 in YCbCr format. 
- Supports all VDC-M defined coding modes: transform, BP, MPP, MPPF, BP-SKIP.
Architecture features:
- 4 pixels per clock per slice architecture
- Multiple choices of Picture Parameter Set (PPS) input format: 
- APB slave,
- In-Band (time multiplexed with the data),
- Direct input (1024 bit bus)
- Parameterizable number of hardware slices: 1, 2, 4 or 8 slices.

Decoder Architecture:

Input Sync: buffer to adapt from input to internal data width and clock
Slice demux: distribute data to slices to achieve maximum parallel decoding
Substream demux: distribute data to substreams (Y, Co, Cg, control)
Slice Mux: gather data from all slices in the correct order and buffer it to adapt to output data width and clock

Resource Usage:

Settings:
- one slice
- in-band PPS
- Slice width: 1280 pixels
- Rate buffer lines: 256
Vivado report:
- Slice LUTs Logic: 338224
- FFs: 38479
- DP Memories: 258176 bits
- SP Memories: 46224 bits

Performance:

4 pixels per clock cycle with 8 slices → 32 pixels per clock cycle
Maximum frequency is difficult to estimate: it depends very much on the technology node. FPGA results are irrelevant
Great care is taken to reduce the length of the critical path by using deep pipelining

