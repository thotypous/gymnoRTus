import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import LFilter::*;
import Hilbert::*;
import SysConfig::*;

HilbSum detThreshold = 205;
HilbSum beginningLevelThreshold = 25;
WindowTime beginningClearance = 4;
HilbSum activityDerivThreshold = 20;
WindowTime activityHysteresis = 4;
WindowTime minActivity = 12;
WindowTime minActivityBeforeMax = 4;
WindowTime forceSamplesAfterMax = 35 /*38*/;

typedef struct {
	WindowTime size;
	WindowTime reference;
} WindowInfo deriving (Eq, Bits);

typedef union tagged {
	ChSample ChSample;
	WindowInfo EndMarker;
	void AbortMarker;
} OutItem deriving (Eq, Bits);

module [Module] mkWindowMaker#(PipeOut#(ChSample) acq) (PipeOut#(OutItem));
	Reg#(Maybe#(WindowTime)) beginning <- mkReg(Nothing);
	Reg#(Maybe#(WindowTime)) activityStart <- mkReg(Nothing);
	Reg#(WindowTime) lastActivity <- mkRegU;
	Reg#(WindowTime) lastEnd <- mkReg(maxBound);
	Reg#(Tuple2#(HilbSum, Maybe#(WindowTime))) maxHilbDuringActivity <- mkReg(tuple2(0, Nothing));

	FIFOF#(OutItem) fifoOut <- mkFIFOF;

	rule test;
		$display(fshow(acq.first));
		acq.deq;
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule