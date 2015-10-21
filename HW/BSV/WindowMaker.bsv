import PAClib::*;
import FIFOF::*;
import GetPut::*;
import BUtils::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import LFilter::*;
import Hilbert::*;
import SysConfig::*;

HilbSum detThreshold = 205;
HilbSum beginningLevelThreshold = 25;
Timestamp beginningClearance = 4;
HilbSum activityDerivThreshold = 20;
Timestamp activityHysteresis = 4;
Timestamp minActivity = 12;
Timestamp minActivityBeforeMax = 4;
Timestamp forceSamplesAfterMax = 35 /*38*/;

typedef struct {
	Timestamp timestamp;
	WindowTime size;
	WindowTime reference;
} WindowInfo deriving (Eq, Bits, FShow);

typedef union tagged {
	ChSample ChSample;
	WindowInfo EndMarker;
} OutItem deriving (Eq, Bits, FShow);

interface WindowMaker;
	method Action resetTs;
	interface PipeOut#(OutItem) out;
endinterface

module [Module] mkWindowMaker#(PipeOut#(ChSample) acq) (WindowMaker);
	Array#(Reg#(Timestamp)) cregTs <- mkCReg(2, 0);
	Reg#(Maybe#(Timestamp)) beginning <- mkReg(Nothing);
	Reg#(Maybe#(Timestamp)) activityStart <- mkReg(Nothing);
	Reg#(Timestamp) start <- mkReg(0);
	Reg#(Timestamp) lastActivity <- mkRegU;
	Reg#(Timestamp) lastEnd <- mkReg(0);
	Reg#(Tuple2#(HilbSum, Maybe#(Timestamp))) maxHilbDuringActivity <- mkReg(tuple2(0, Nothing));
	Reg#(HilbSum) lastHilb <- mkReg(0);

	let hilbSummer <- mkHilbertSummer(acq);
	FIFOF#(OutItem) fifoOut <- mkFIFOF;

	let ts = asReg(cregTs[0]);

	rule forwardSample (hilbSummer.first matches tagged ChSample .chsample);
		fifoOut.enq(tagged ChSample chsample);
		hilbSummer.deq;
	endrule

	function HilbSum absDiff(HilbSum a, HilbSum b);
		Int#(TAdd#(HilbSumBits,1)) diff = cExtend(a) - cExtend(b);
		return cExtend(abs(diff));
	endfunction

	rule processHilb (hilbSummer.first matches tagged HilbSum .hilb);
		ts <= ts + 1;

		let deriv = absDiff(hilb, lastHilb);
		lastHilb <= hilb;
		hilbSummer.deq;

		if (activityStart matches tagged Nothing) begin
			if (hilb < beginningLevelThreshold)
				beginning <= tagged Nothing;
			else
				beginning <= tagged Just ts;
		end

		if (activityStart matches tagged Nothing
				&&& deriv >= activityDerivThreshold) begin
			// start of activity
			activityStart <= tagged Just ts;
		end

		if (deriv >= activityDerivThreshold) begin
			lastActivity <= ts;
		end

		let nextMaxHilb = maxHilbDuringActivity;

		if (activityStart matches tagged Just .*
				&&& hilb >= tpl_1(maxHilbDuringActivity)) begin
			nextMaxHilb = tuple2(hilb, tagged Just ts);
		end

		// pre-calc start for next cycle, to shorten combinational path
		if (activityStart matches tagged Valid .actStart) begin
			start <= max(
					fromMaybe(actStart, beginning) - beginningClearance,
					lastEnd);
		end

		if (tpl_2(maxHilbDuringActivity) matches tagged Valid .maxHilbTs
				&&& activityStart matches tagged Valid .actStart
				&&& deriv < activityDerivThreshold
				&& ts - lastActivity > activityHysteresis) begin
			// end of activity
			let size = ts - start;
			let chirp = size > extend(windowMaxSize);
			// criteria for gluing together EODs which are very close
			let inProtectedInterval =
					ts - maxHilbTs <= forceSamplesAfterMax;
			// criteria for discarding impulsive noise (and chirps)
			let validActivity =
					tpl_1(maxHilbDuringActivity) >= detThreshold
					&& ts - actStart >= minActivity
					&& maxHilbTs - actStart >= minActivityBeforeMax
					&& !chirp;
			if (validActivity && !inProtectedInterval) begin
				// valid activity period
				lastEnd <= ts;
				fifoOut.enq(tagged EndMarker WindowInfo{
						timestamp: ts,
						size: truncate(size),
						reference: truncate(ts - maxHilbTs)
				});
			end
			if (!validActivity || !inProtectedInterval) begin
				beginning <= tagged Nothing;
				activityStart <= tagged Nothing;
				nextMaxHilb = tuple2(0, tagged Nothing);
			end
		end

		maxHilbDuringActivity <= nextMaxHilb;
	endrule

	method Action resetTs;
		cregTs[1] <= 0;
	endmethod

	interface out = f_FIFOF_to_PipeOut(fifoOut);
endmodule
