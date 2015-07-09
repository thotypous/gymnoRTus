import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import LFilter::*;
import SysConfig::*;

typedef union tagged {
	ChSample ChSample;
	WindowSize StartFound;
	void EndMarker;
} OutItem deriving (Eq, Bits);

module [Module] mkWindowMaker#(PipeOut#(ChSample) acq) (PipeOut#(OutItem));
	FIFOF#(OutItem) fifoOut <- mkFIFOF;

	rule test;
		$display(fshow(acq.first));
		acq.deq;
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule