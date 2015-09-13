typedef 14 PciBarAddrSize;
typedef 32 PciBarDataSize;
typedef 32 PciDmaAddrSize;
typedef 64 PciDmaDataSize;

typedef 8192 MockADBufSize;        // number of 64-bit words
typedef 8192 ContinuousAcqBufSize; // number of 64-bit words, multiple of 2

typedef 4 SamplesPerDmaWord;

typedef 256 WindowMaxSize;
typedef Bit#(28) Timestamp;


// Derived types

import BUtils::*;
import AvalonCommon::*;

typedef Bit#(PciBarAddrSize) PciBarAddr;
typedef Bit#(PciBarDataSize) PciBarData;
typedef Bit#(PciDmaAddrSize) PciDmaAddr;
typedef Bit#(PciDmaDataSize) PciDmaData;
typedef Tuple2#(PciDmaAddr, PciDmaData) PciDmaAddrData;

typedef TDiv#(PciDmaDataSize, SamplesPerDmaWord) DmaSampleSize;
typedef Bit#(DmaSampleSize) DmaSample;

PciDmaAddr dmaWordBytes = fromInteger(valueOf(PciDmaDataSize) / 8);

typedef LBit#(WindowMaxSize)  WindowTime;
WindowTime windowMaxSize = fromInteger(valueOf(WindowMaxSize));
