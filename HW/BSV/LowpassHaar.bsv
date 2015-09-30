import PAClib::*;
import FIFOF::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import BRAM::*;
import BRAMUtils::*;
import WindowMaker::*;
import SysConfig::*;

typedef union tagged {
	ChSample ChSample;
	WindowTime EndMarker;
} OutItem deriving (Eq, Bits, FShow);

module [Module] mkLowpassHaar#(PipeOut#(WindowMaker::OutItem) winPipe) (PipeOut#(OutItem));
	BRAM1Port#(ChNum, Sample) lastSample <- mkBRAM1Server(defaultValue);
	Reg#(Bool) oddSample <- mkReg(False);
	FIFOF#(void) pendingResp <- mkFIFOF;
	FIFOF#(OutItem) fifoOut <- mkFIFOF;

	rule passAlongEndMarker (winPipe.first matches tagged EndMarker .wininfo);
		winPipe.deq;
		fifoOut.enq(tagged EndMarker (wininfo.size >> 1));
	endrule

	function updateSampleParity(ch) = action
		if (ch == lastEnabledChannel)
			oddSample <= !oddSample;
	endaction;

	rule saveSample (winPipe.first matches tagged ChSample {.ch, .sample}
			&&& !oddSample);
		lastSample.portA.request.put(makeReq(True, ch, sample));
		updateSampleParity(ch);
		winPipe.deq;
	endrule

	rule queryLastSample (winPipe.first matches tagged ChSample {.ch, .*}
			&&& oddSample && !pendingResp.notEmpty);
		lastSample.portA.request.put(makeReq(False, ch, ?));
		pendingResp.enq(?);
	endrule

	rule calcOutSig (winPipe.first matches tagged ChSample {.ch, .sample}
			&&& oddSample && pendingResp.notEmpty);
		let last <- lastSample.portA.response.get;
		Int#(TAdd#(SampleBits,1)) sum = extend(last) + extend(sample);
		fifoOut.enq(tagged ChSample tuple2(ch, truncate(sum >> 1)));
		pendingResp.deq;
		updateSampleParity(ch);
		winPipe.deq;
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule