import PAClib::*;
import FIFOF::*;
import BRAM::*;
import BRAMUtils::*;
import BUtils::*;
import GetPut::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

export Sample(..);
export ChSample(..);
export ChNum(..);
export NumChannels(..);
export OffsetSubtractor(..);
export mkOffsetSubtractor;

typedef Int#(SampleBits) Sample;
typedef Tuple2#(ChNum, Sample) ChSample;

// Intermediate value for offset subtraction,
// before clipping the value to the accepted range
typedef Int#(TAdd#(SampleBits, 2)) IntermediateValue;

interface OffsetSubtractor;
	method Action setOffset(ChNum ch, DualAD::Sample off);
	interface PipeOut#(ChSample) out;
endinterface

module mkOffsetSubtractor#(PipeOut#(DualAD::ChSample) acq) (OffsetSubtractor);
	FIFOF#(ChSample) fifoOut <- mkFIFOF;
	FIFOF#(void) pendingResp <- mkFIFOF;
	BRAM2Port#(ChNum, DualAD::Sample) offsets <- mkBRAM2Server(defaultValue);

	rule requestOffset (!pendingResp.notEmpty);
		offsets.portA.request.put(makeReq(False, tpl_1(acq.first), ?));
		pendingResp.enq(?);
	endrule

	rule subtractOffset (pendingResp.notEmpty);
		let offset <- offsets.portA.response.get;
		pendingResp.deq;
		acq.deq;

		IntermediateValue sub = cExtend(tpl_2(acq.first)) - cExtend(offset);
		Sample min = minBound, max = maxBound;
		Sample sample =
				  (sub < extend(min)) ? min
				: (sub > extend(max)) ? max
				: truncate(sub);
		fifoOut.enq(tuple2(tpl_1(acq.first), sample));
	endrule

	method Action setOffset(ChNum ch, DualAD::Sample off);
		offsets.portB.request.put(makeReq(True, ch, off));
	endmethod

	interface out = f_FIFOF_to_PipeOut(fifoOut);
endmodule