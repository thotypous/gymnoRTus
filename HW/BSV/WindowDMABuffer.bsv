import PAClib::*;
import PipeUtils::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;
import BRAM::*;
import BRAMUtils::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import WindowMaker::*;
import SysConfig::*;

typedef union tagged {
	PciDmaData DmaData;
	WindowInfo EndMarker;
} DMABufItem deriving (Eq, Bits, FShow);

typedef TDiv#(NumEnabledChannels, SamplesPerDmaWord) WordsNeededForAllChannels;
Integer wordsNeededForAllChannels = valueOf(WordsNeededForAllChannels);

typedef Vector#(SamplesPerDmaWord, Sample) BramItem;
typedef TMul#(2, TMul#(WordsNeededForAllChannels, WindowMaxSize)) NumBramItems;
typedef Bit#(TLog#(NumBramItems)) Ptr;

module [Module] mkWindowDMABuffer#(PipeOut#(OutItem) pipeIn) (PipeOut#(DMABufItem));
	FIFOF#(Tuple2#(Bool, Vector#(1, Sample))) inSamples <- mkBypassFIFOF;
	FIFOF#(Tuple2#(WindowInfo, Ptr)) inWinInfoHead <- mkLFIFOF;
	FIFOF#(WindowInfo) outWinInfo <- mkLFIFOF;
	FIFOF#(void) endToken <- mkLFIFOF;
	PipeOut#(Vector#(SamplesPerDmaWord, Sample)) unfunnel <- mkFlushableUnfunnel(f_FIFOF_to_PipeOut(inSamples));
	BRAM2Port#(Ptr, BramItem) bram <- mkBRAM2Server(defaultValue);
	Reg#(Ptr) headPtr <- mkReg(0);
	Reg#(Ptr) remaining <- mkReg(0);
	Reg#(Ptr) tailPtr <- mkRegU;
	FIFOF#(DMABufItem) fifoOut <- mkFIFOF;

	rule gatherSamples (pipeIn.first matches tagged ChSample {.ch, .sample});
		let flush = ch == lastEnabledChannel;
		inSamples.enq(tuple2(flush, vecBind(sample)));
		pipeIn.deq;
	endrule

	rule gatherWinInfo (pipeIn.first matches tagged EndMarker .wininfo);
		inWinInfoHead.enq(tuple2(wininfo, headPtr));
		pipeIn.deq;
	endrule

	rule bufferize;
		let vec <- toGet(unfunnel).get;
		bram.portA.request.put(makeReq(True, headPtr, vec));
		headPtr <= headPtr + 1;
	endrule

	rule startOut (remaining == 0);
		match {.wininfo, .headp} <- toGet(inWinInfoHead).get;
		outWinInfo.enq(wininfo);
		Ptr winwords = fromInteger(wordsNeededForAllChannels) * extend(wininfo.size);
		remaining <= winwords;
		tailPtr <= headp - winwords;
	endrule

	rule reqDmaData (remaining != 0);
		bram.portB.request.put(makeReq(False, tailPtr, ?));
		tailPtr <= tailPtr + 1;
		remaining <= remaining - 1;
	endrule

	rule sendDmaData;
		let vec <- bram.portB.response.get;
		fifoOut.enq(tagged DmaData pack(map(extend, vec)));
		if (remaining == 0)
			endToken.enq(?);
	endrule

	rule sendEndMarker;
		endToken.deq;
		let wininfo <- toGet(outWinInfo).get;
		fifoOut.enq(tagged EndMarker wininfo);
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule