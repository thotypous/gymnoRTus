import PAClib::*;
import PipeUtils::*;
import FIFOF::*;
import GetPut::*;
import Assert::*;
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
	FIFOF#(Tuple2#(Bool, Vector#(1, Maybe#(Sample)))) fifoSamples <- mkFIFOF;
	FIFOF#(WindowInfo) fifoWinInfo <- mkFIFOF;
	FIFOF#(WindowInfo) outWinInfo <- mkFIFOF;
	FIFOF#(Bool) isLast <- mkLFIFOF;
	FIFOF#(void) endToken <- mkLFIFOF;
	PipeOut#(Vector#(SamplesPerDmaWord, Maybe#(Sample))) unfunnel <- mkFlushableUnfunnel(f_FIFOF_to_PipeOut(fifoSamples));
	BRAM2Port#(Ptr, BramItem) bram <- mkBRAM2Server(defaultValue);
	Reg#(Ptr) headPtr <- mkReg(0);
	Reg#(Ptr) remaining <- mkReg(0);
	Reg#(Ptr) tailPtr <- mkRegU;
	FIFOF#(DMABufItem) fifoOut <- mkFIFOF;

	rule gatherSamples (pipeIn.first matches tagged ChSample {.ch, .sample});
		let flush = ch == lastEnabledChannel;
		fifoSamples.enq(tuple2(flush, vecBind(tagged Just sample)));
		pipeIn.deq;
	endrule

	rule gatherWinInfo (pipeIn.first matches tagged EndMarker .wininfo);
		fifoWinInfo.enq(wininfo);
		fifoSamples.enq(tuple2(True, vecBind(tagged Nothing)));
		pipeIn.deq;
	endrule

	rule bufferize (unfunnel.first[0] matches tagged Just .*);
		unfunnel.deq;
		dynamicAssert(Vector::all(isValid, unfunnel.first), "All entries should be valid");
		let vec = map(fromMaybe(0), unfunnel.first);
		bram.portA.request.put(makeReq(True, headPtr, vec));
		headPtr <= headPtr + 1;
	endrule

	rule startOut (unfunnel.first[0] matches tagged Nothing &&& remaining == 0);
		unfunnel.deq;
		let wininfo <- toGet(fifoWinInfo).get;
		outWinInfo.enq(wininfo);
		Ptr winwords = fromInteger(wordsNeededForAllChannels) * extend(wininfo.size);
		remaining <= winwords;
		tailPtr <= headPtr - winwords;
	endrule

	rule reqDmaData (remaining != 0);
		bram.portB.request.put(makeReq(False, tailPtr, ?));
		isLast.enq(remaining == 1);
		tailPtr <= tailPtr + 1;
		remaining <= remaining - 1;
	endrule

	rule sendDmaData (!endToken.notEmpty);
		let vec <- bram.portB.response.get;
		let last <- toGet(isLast).get;
		fifoOut.enq(tagged DmaData pack(map(extend, vec)));
		if (last)
			endToken.enq(?);
	endrule

	rule sendEndMarker;
		endToken.deq;
		let wininfo <- toGet(outWinInfo).get;
		fifoOut.enq(tagged EndMarker wininfo);
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule