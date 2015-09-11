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
	Bit#(32) timestamp;
	WindowTime size;
	WindowTime reference;
} WindowInfo deriving (Eq, Bits);

typedef union tagged {
	ChSample ChSample;
	WindowInfo EndMarker;
} OutItem deriving (Eq, Bits);

module [Module] mkWindowMaker#(PipeOut#(ChSample) acq) (PipeOut#(OutItem));
	Reg#(Maybe#(WindowTime)) beginning <- mkReg(Nothing);
	Reg#(Maybe#(WindowTime)) activityStart <- mkReg(Nothing);
	Reg#(WindowTime) lastActivity <- mkRegU;
	Reg#(WindowTime) lastEnd <- mkReg(maxBound);
	Reg#(Tuple2#(HilbSum, Maybe#(WindowTime))) maxHilbDuringActivity <- mkReg(tuple2(0, Nothing));
	Reg#(HilbSum) lastHilb <- mkReg(0);

	let hilbSummer <- mkHilbertSummer(acq);
	FIFOF#(OutItem) fifoOut <- mkFIFOF;

	rule forwardSample (hilbSummer.first matches tagged ChSample .chsample);
		fifoOut.enq(tagged ChSample chsample);
		hilbSummer.deq;
	endrule

	rule processHilb (hilbSummer.first matches tagged HilbSum .hilb);
		hilbSummer.deq;
	endrule

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule