import PAClib::*;
import FIFOF::*;
import BRAMFIFO::*;
import GetPut::*;
import Connectable::*;
import Vector::*;
import BUtils::*;
import ChannelFilter::*;
import OffsetSubtractor::*;
import LowpassHaar::*;
import AdderTree::*;
import SysConfig::*;

import JtagGetPut::*;
import AltSourceProbe::*;

// Correction for signal after decimation (LowpassHaar)
typedef TDiv#(SysConfig::WindowMaxSize, 2) WindowMaxSize;
WindowTime windowMaxSize = fromInteger(valueOf(WindowMaxSize));

typedef TMul#(WindowMaxSize, WindowMaxSize) MaxCycles;
typedef LBit#(MaxCycles) CycleCount;
CycleCount maxCycles = fromInteger(valueOf(MaxCycles));

typedef TAdd#(SampleBits, TLog#(WindowMaxSize)) SingleChSumBits;
typedef Bit#(SingleChSumBits) SingleChSum;

typedef TAdd#(SingleChSumBits, TLog#(NumEnabledChannels)) FinalSumBits;
typedef Bit#(FinalSumBits) FinalSum;

typedef enum {
	Both = 0,
	OnlyA = 1,
	OnlyB = 2
} SpikesInWin deriving(Eq, Bits);

typedef struct {
	SpikesInWin spk;
	CycleCount cycles;
	FinalSum sum;
} Result deriving (Eq, Bits);


interface DistMinimizer;
	//interface PipeOut#(Result) result;
	//interface Put#(SpikesInWin) feedback;
endinterface

module [Module] mkDistMinimizer#(PipeOut#(OutItem) winPipe) (DistMinimizer);
	FIFOF#(SingleChItem) fifo <- mkFIFOF;
	let singleCh <- mkSingleChDistMinimizer(f_FIFOF_to_PipeOut(fifo));
	Get#(SpikesInWin) feedback <- mkJtagGet("FDBK", mkFIFOF);
	AltSourceProbe#(void, SingleChSum) result <- mkAltSourceDProbe("RES", ?, singleCh.sum);

	mkConnection(feedback, singleCh.feedback);

	rule readCh0samp (winPipe.first matches tagged ChSample {0, .sample});
		fifo.enq(tagged Sample sample);
		winPipe.deq;
	endrule

	rule readCh0end (winPipe.first matches tagged EndMarker .size);
		fifo.enq(tagged EndMarker size);
		winPipe.deq;
	endrule
endmodule


interface SingleChDistMinimizer;
	method SingleChSum sum;
	interface Put#(SpikesInWin) feedback;
endinterface

typedef union tagged {
	Sample Sample;
	WindowTime EndMarker;
} SingleChItem deriving (Eq, Bits, FShow);

typedef Int#(TAdd#(SampleBits,1)) SampleDiff;
typedef Vector#(WindowMaxSize, Reg#(Sample)) RegVec;

module [Module] mkSingleChDistMinimizer#(PipeOut#(SingleChItem) winPipe) (SingleChDistMinimizer);
	RegVec spikeA  <- Vector::replicateM(mkRegU);
	RegVec spikeB  <- Vector::replicateM(mkRegU);
	RegVec segment <- Vector::replicateM(mkRegU);

	Vector#(WindowMaxSize, Reg#(Bit#(SampleBits))) firstLevel <- Vector::replicateM(mkRegU);
	AdderN#(WindowMaxSize, SampleBits) adderTree <- mkAdderN(readVReg(firstLevel));

	Reg#(Maybe#(WindowTime)) remainingFill <- mkReg(tagged Invalid);
	Reg#(CycleCount) remainingRotations <- mkReg(0);
	Reg#(WindowTime) stepsLeftForInnerRotation <- mkRegU;

	FIFOF#(Sample) segmFifo <- mkSizedBRAMFIFOF(valueOf(WindowMaxSize));

	FIFOF#(SpikesInWin) feedbackIn <- mkFIFOF;
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
		segmFifo.enq(sample);
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
		segmFifo.enq(0);
	endrule

	(* fire_when_enabled *)
	rule finishFilling (winPipe.first matches tagged EndMarker .*
			&&& remainingFill matches tagged Valid .rem
			&&& rem == 0
			&&  remainingRotations == 0
			&&  !feedbackPending.notEmpty);
		remainingFill <= tagged Invalid;
		remainingRotations <= maxCycles;
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

	(* fire_when_enabled, no_implicit_conditions *)
	rule calcFirstLevel;
		for (Integer i = 0; i < valueOf(WindowMaxSize); i = i + 1) begin
			Sample spikeSum = boundedPlus(spikeA[i], spikeB[i]);
			SampleDiff diff = cExtend(segment[i]) - cExtend(spikeSum);
			firstLevel[i] <= truncate(pack(abs(diff)));
		end
	endrule

	(* fire_when_enabled *)
	rule feedbackCopy (remainingRotations == 0
			&& feedbackPending.notEmpty
			&& segmFifo.notEmpty);
		if (feedbackIn.first == OnlyA)
			shiftRegVec(spikeA, segmFifo.first);
		if (feedbackIn.first == OnlyB)
			shiftRegVec(spikeB, segmFifo.first);
		segmFifo.deq;
	endrule

	(* fire_when_enabled *)
	rule feedbackDone (remainingRotations == 0
			&& feedbackPending.notEmpty
			&& !segmFifo.notEmpty);
		feedbackPending.deq;
		feedbackIn.deq;
	endrule

	interface feedback = toPut(feedbackIn);
	method sum = adderTree;
endmodule
