import PAClib::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import BUtils::*;
import ChannelFilter::*;
import OffsetSubtractor::*;
import LowpassHaar::*;
import AdderTree::*;
import SysConfig::*;

// Correction for signal after decimation
typedef TDiv#(SysConfig::WindowMaxSize, 2) WindowMaxSize;
WindowTime windowMaxSize = fromInteger(valueOf(WindowMaxSize));

typedef TMul#(WindowMaxSize, WindowMaxSize) MaxCycles;
typedef LBit#(MaxCycles) CycleCount;
CycleCount maxCycles = fromInteger(valueOf(MaxCycles));

typedef TAdd#(SampleBits, TLog#(WindowMaxSize)) SingleChSumBits;
typedef Bit#(SingleChSumBits) SingleChSum;

typedef TAdd#(SingleChSumBits, TLog#(NumEnabledChannels)) FinalSumBits;
typedef Bit#(FinalSumBits) FinalSum;

typedef Tuple2#(CycleCount, FinalSum) Result;

typedef enum {
	Discard = 0,
	CopyA = 1,
	CopyB = 2
} CurWinFeedback deriving(Eq, Bits);

interface DistMinimizer;
	interface PipeOut#(Result) result;
	interface Put#(CurWinFeedback) feedback;
endinterface

module [Module] mkDistMinimizer#(PipeOut#(OutItem) winPipe) (DistMinimizer);
	FIFOF#(SingleChItem) fifo <- mkFIFOF;
	let singleCh <- mkSingleChDistMinimizer(f_FIFOF_to_PipeOut(fifo));
	mkSink(winPipe);
endmodule

interface SingleChDistMinimizer;
	method SingleChSum sum;
	interface Put#(CurWinFeedback) feedback;
endinterface

typedef union tagged {
	Sample Sample;
	WindowTime EndMarker;
} SingleChItem deriving (Eq, Bits, FShow);

typedef Vector#(WindowMaxSize, Reg#(Sample)) RegVec;

module [Module] mkSingleChDistMinimizer#(PipeOut#(SingleChItem) winPipe) (SingleChDistMinimizer);
	RegVec spikeA  <- Vector::replicateM(mkRegU);
	RegVec spikeB  <- Vector::replicateM(mkRegU);
	RegVec segment <- Vector::replicateM(mkRegU);

	Vector#(WindowMaxSize, Reg#(Bit#(SampleBits))) firstLevel <- Vector::replicateM(mkRegU);
	AdderN#(WindowMaxSize, SampleBits) adderTree <- mkAdderN(readVReg(firstLevel));

	Reg#(Maybe#(WindowTime)) remainingFill <- mkReg(tagged Invalid);
	Reg#(WindowTime) remainingFeedback <- mkRegU;
	Reg#(CycleCount) remainingRotations <- mkReg(0);
	Reg#(WindowTime) stepsLeftForInnerRotation <- mkRegU;
	FIFOF#(CurWinFeedback) feedbackIn <- mkFIFOF;
	FIFOF#(void) feedbackPending <- mkFIFOF;

	function Action shiftRegVec(RegVec regVec, Sample in) = action
		select(regVec, 0) <= in;
		for (Integer i = 1; i < valueOf(WindowMaxSize); i = i + 1)
			select(regVec, i) <= select(regVec, i - 1)._read;
	endaction;

	(* fire_when_enabled *)
	rule consumeSample (winPipe.first matches tagged Sample .sample
			&&& !feedbackPending.notEmpty);
		shiftRegVec(segment, sample);
		winPipe.deq;
	endrule

	(* fire_when_enabled *)
	rule setupFilling (winPipe.first matches tagged EndMarker .size
			&&& remainingFill matches tagged Invalid
			&&& !feedbackPending.notEmpty);
		remainingFill <= tagged Valid (windowMaxSize - size);
	endrule

	(* fire_when_enabled *)
	rule doFilling (winPipe.first matches tagged EndMarker .*
			&&& remainingFill matches tagged Valid .rem
			&&& rem != 0
			&&  !feedbackPending.notEmpty);
		remainingFill <= tagged Valid (rem - 1);
		shiftRegVec(segment, 0);
	endrule

	(* fire_when_enabled *)
	rule finishFilling (winPipe.first matches tagged EndMarker .*
			&&& remainingFill matches tagged Valid .rem
			&&& rem == 0
			&&  remainingRotations == 0
			&&  !feedbackPending.notEmpty);
		remainingFill <= tagged Invalid;
		remainingRotations <= maxCycles;
		remainingFeedback <= windowMaxSize;
		stepsLeftForInnerRotation <= windowMaxSize - 1;
		feedbackPending.enq(?);
		winPipe.deq;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateSpikes (remainingRotations != 0);
		shiftRegVec(spikeA, spikeA[windowMaxSize-1]);
		if (stepsLeftForInnerRotation == 0) begin
			shiftRegVec(spikeB, spikeB[windowMaxSize-1]);
			stepsLeftForInnerRotation <= windowMaxSize - 1;
		end else begin
			stepsLeftForInnerRotation <= stepsLeftForInnerRotation - 1;
		end
		remainingRotations <= remainingRotations - 1;
	endrule

	let feedbackCopyRunning = feedbackIn.first != Discard && remainingFeedback != 0;

	(* fire_when_enabled *)
	rule feedbackDone (remainingRotations == 0
			&& feedbackPending.notEmpty
			&& !feedbackCopyRunning);
		feedbackPending.deq;
		feedbackIn.deq;
	endrule

	(* fire_when_enabled *)
	rule feedbackCopy (remainingRotations == 0
			&& feedbackPending.notEmpty
			&& feedbackCopyRunning);
		shiftRegVec(feedbackIn.first == CopyA ? spikeA : spikeB,
				segment[windowMaxSize-1]);
		shiftRegVec(segment, ?);
		remainingFeedback <= remainingFeedback - 1;
	endrule

	interface feedback = toPut(feedbackIn);
	method sum = adderTree;
endmodule
