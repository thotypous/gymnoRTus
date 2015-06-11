typedef 2  PciBarAddrSize;
typedef 32 PciBarDataSize;
typedef 32 PciDmaAddrSize;
typedef 64 PciDmaDataSize;

typedef 8192 MockADBufSize;  // number of 64-bit words

typedef 4 SamplesPerDmaWord;


// Derived types

import AvalonCommon::*;

typedef Bit#(PciBarAddrSize) PciBarAddr;
typedef Bit#(PciBarDataSize) PciBarData;
typedef Bit#(PciDmaAddrSize) PciDmaAddr;
typedef Bit#(PciDmaDataSize) PciDmaData;
typedef AvalonRequest#(PciDmaAddrSize, PciDmaDataSize) PciDmaReq;

typedef TDiv#(PciDmaDataSize, SamplesPerDmaWord) DmaSampleSize;
typedef Bit#(DmaSampleSize) DmaSample;
