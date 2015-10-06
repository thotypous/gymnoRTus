import PAClib::*;
import FIFOF::*;
import BRAMFIFO::*;
import GetPut::*;
import Connectable::*;
import Vector::*;
import BUtils::*;
import Assert::*;
import RegDelayer::*;
import ChannelFilter::*;
import OffsetSubtractor::*;
import LowpassHaar::*;
import AdderTree::*;
import SysConfig::*;

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
} SpikesInWin deriving(Eq, Bits, FShow);

typedef struct {
	SpikesInWin spk;
	CycleCount rot;
	FinalSum sum;
} Result deriving (Eq, Bits, FShow);


interface DistMinimizer;
	interface PipeOut#(Result) result;
	interface Put#(SpikesInWin) feedback;
endinterface

typedef TAdd#(TAdd#(TLog#(WindowMaxSize), TLog#(NumEnabledChannels)), 1) TotalTreeDelay;

module [Module] mkDistMinimizer#(PipeOut#(OutItem) inPipe) (DistMinimizer);
	FIFOF#(OutItem) inBuf <- mkSizedBRAMFIFOF(oneMsBufSize);
	FIFOF#(SpikesInWin) feedbackFifo <- mkFIFOF;
	FIFOF#(Result) resultFifo <- mkFIFOF;
	Reg#(Result) curMin <- mkRegU;

	Vector#(NumEnabledChannels, FIFOF#(SingleChItem)) fifos
			<- replicateM(mkFIFOF);
	Vector#(NumEnabledChannels, SingleChDistMinimizer) minimizers
			<- mapM(mkSingleChDistMinimizer, map(f_FIFOF_to_PipeOut, fifos));

	function SingleChSum getSum(SingleChDistMinimizer ifc) = ifc.sum;
	AdderN#(TExp#(TLog#(NumEnabledChannels)), SingleChSumBits) adderTree
			<- mkAdderN(append(map(getSum, minimizers), replicate(0)));

	Bit#(TotalTreeDelay) dummyDelay = ?;
	let state <- mkRegDelayer(dummyDelay, FillSegment, minimizers[0].getState);
	let remainingRotations <- mkRegDelayer(dummyDelay, 0, minimizers[0].getRemainingRotations);

	let prevState <- mkRegDelayer(1'b0, FillSegment, state);

	mkConnection(toGet(inPipe), toPut(inBuf));

	function eqState(ifc) = ifc.getState == minimizers[0].getState;
	continuousAssert(Vector::all(eqState, minimizers),
			"State should be equal across all child minimizers");

	function eqRemRot(ifc) = ifc.getRemainingRotations == minimizers[0].getRemainingRotations;
	continuousAssert(Vector::all(eqRemRot, minimizers),
			"Remaining rotations should be equal across all child minimizers");

	(* fire_when_enabled *)
	rule readSample (inBuf.first matches tagged ChSample {.ch, .sample});
		let mi = Vector::findElem(ch, enabledChannels);
		dynamicAssert(isValid(mi), "Disabled channels should not appear in the pipeline");
		let i = fromMaybe(?, mi);
		fifos[i].enq(tagged Sample sample);
		inBuf.deq;
	endrule

	(* fire_when_enabled *)
	rule readEndMarker (inBuf.first matches tagged EndMarker .size);
		for (Integer i = 0; i < numEnabledChannels; i = i + 1)
			fifos[i].enq(tagged EndMarker size);
		inBuf.deq;
	endrule

	(* fire_when_enabled *)
	rule replicateFeedback;
		let fdbk <- toGet(feedbackFifo).get;
		for (Integer i = 0; i < numEnabledChannels; i = i + 1)
			minimizers[i].feedback.put(fdbk);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule resetMin (state == FillSegment);
		curMin <= Result{spk: ?, rot: ?, sum: maxBound};
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule updateMin ((state == RotateBoth || state == RotateA || state == RotateB)
			&& adderTree < curMin.sum);
		SpikesInWin spk =
				state == RotateBoth ? Both :
				state == RotateA ? OnlyA :
				state == RotateB ? OnlyB : (?);
		curMin <= Result{spk: spk, rot: remainingRotations, sum: adderTree};
	endrule

	(* fire_when_enabled *)
	rule enqResult (prevState != RestoreA && state == RestoreA);
		resultFifo.enq(curMin);
	endrule

	interface result = f_FIFOF_to_PipeOut(resultFifo);
	interface feedback = toPut(feedbackFifo);
endmodule


interface SingleChDistMinimizer;
	method State getState;
	method CycleCount getRemainingRotations;
	method SingleChSum sum;
	interface Put#(SpikesInWin) feedback;
endinterface

typedef union tagged {
	Sample Sample;
	WindowTime EndMarker;
} SingleChItem deriving (Eq, Bits, FShow);

typedef enum {
	FillSegment,
	RotateBoth,
	CleanB,
	RotateA,
	RestoreBCleanA,
	RotateB,
	RestoreA,
	FeedbackCopy
} State deriving (Eq, Bits, FShow);

typedef Int#(TAdd#(SampleBits,1)) SampleDiff;
typedef Vector#(WindowMaxSize, Reg#(Sample)) RegVec;

module [Module] mkSingleChDistMinimizer#(PipeOut#(SingleChItem) winPipe) (SingleChDistMinimizer);
	RegVec spikeA  <- Vector::replicateM(mkRegU);
	RegVec spikeB  <- Vector::replicateM(mkRegU);
	RegVec segment <- Vector::replicateM(mkRegU);

	Vector#(WindowMaxSize, Reg#(Bit#(SampleBits))) firstLevel <- Vector::replicateM(mkRegU);
	AdderN#(WindowMaxSize, SampleBits) adderTree <- mkAdderN(readVReg(firstLevel));

	FIFOF#(Sample) spkAFifo <- mkSizedBRAMFIFOF(valueOf(WindowMaxSize));
	FIFOF#(Sample) spkBFifo <- mkSizedBRAMFIFOF(valueOf(WindowMaxSize));
	FIFOF#(Sample) segmFifo <- mkSizedBRAMFIFOF(valueOf(WindowMaxSize));

	Reg#(State) state <- mkReg(FillSegment);

	Reg#(Maybe#(WindowTime)) remainingFill <- mkReg(tagged Invalid);
	Reg#(CycleCount) remainingRotations <- mkReg(0);
	Reg#(WindowTime) stepsLeftForInnerRotation <- mkRegU;

	FIFOF#(SpikesInWin) feedbackIn <- mkFIFOF;

	function Action shiftRegVec(RegVec regVec, Sample in) = action
		select(regVec, 0) <= in;
		for (Integer i = 1; i < valueOf(WindowMaxSize); i = i + 1)
			select(regVec, i) <= select(regVec, i - 1)._read;
	endaction;

	function Action rotateRegVec(RegVec regVec) = shiftRegVec(regVec, regVec[windowMaxSize-1]);

	function Action cleanRegVec(RegVec regVec, FIFOF#(Sample) bkpFifo) = action
		bkpFifo.enq(regVec[windowMaxSize-1]);
		shiftRegVec(regVec, 0);
	endaction;

	function Action restoreRegVec(RegVec regVec, FIFOF#(Sample) bkpFifo) = action
		shiftRegVec(regVec, bkpFifo.first);
		bkpFifo.deq;
	endaction;

	(* fire_when_enabled *)
	rule consumeSample (winPipe.first matches tagged Sample .sample
			&&& state == FillSegment);
		shiftRegVec(segment, sample);
		segmFifo.enq(sample);
		winPipe.deq;
	endrule

	(* fire_when_enabled *)
	rule setupFilling (winPipe.first matches tagged EndMarker .size
			&&& remainingFill matches tagged Invalid
			&&& state == FillSegment);
		remainingFill <= tagged Valid (windowMaxSize - size);
	endrule

	(* fire_when_enabled *)
	rule doFilling (winPipe.first matches tagged EndMarker .*
			&&& remainingFill matches tagged Valid .rem
			&&& rem != 0
			&&  state == FillSegment);
		remainingFill <= tagged Valid (rem - 1);
		shiftRegVec(segment, 0);
		segmFifo.enq(0);
	endrule

	(* fire_when_enabled *)
	rule finishFilling (winPipe.first matches tagged EndMarker .*
			&&& remainingFill matches tagged Valid .rem
			&&& rem == 0
			&&  state == FillSegment);
		remainingFill <= tagged Invalid;
		remainingRotations <= maxCycles;
		state <= RotateBoth;
		stepsLeftForInnerRotation <= windowMaxSize - 1;
		winPipe.deq;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateBoth (state == RotateBoth
			&& remainingRotations != 0);
		rotateRegVec(spikeA);
		if (stepsLeftForInnerRotation == 0) begin
			rotateRegVec(spikeB);
			stepsLeftForInnerRotation <= windowMaxSize - 1;
		end else begin
			stepsLeftForInnerRotation <= stepsLeftForInnerRotation - 1;
		end
		remainingRotations <= remainingRotations - 1;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateBothFinish (state == RotateBoth
			&& remainingRotations == 0);
		state <= CleanB;
	endrule

	(* fire_when_enabled *)
	rule cleanB (state == CleanB
			&& spkBFifo.notFull);
		cleanRegVec(spikeB, spkBFifo);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule cleanBFinish (state == CleanB
			&& !spkBFifo.notFull);
		remainingRotations <= extend(windowMaxSize);
		state <= RotateA;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateA (state == RotateA
			&& remainingRotations != 0);
		rotateRegVec(spikeA);
		remainingRotations <= remainingRotations - 1;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateAFinish (state == RotateA
			&& remainingRotations == 0);
		state <= RestoreBCleanA;
	endrule

	(* fire_when_enabled *)
	rule restoreBcleanA (state == RestoreBCleanA
			&& spkAFifo.notFull);
		restoreRegVec(spikeB, spkBFifo);
		cleanRegVec(spikeA, spkAFifo);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule restoreBcleanAFinish (state == RestoreBCleanA
			&& !spkAFifo.notFull);
		remainingRotations <= extend(windowMaxSize);
		state <= RotateB;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateB (state == RotateB
			&& remainingRotations != 0);
		rotateRegVec(spikeB);
		remainingRotations <= remainingRotations - 1;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rotateBFinish (state == RotateB
			&& remainingRotations == 0);
		state <= RestoreA;
	endrule

	(* fire_when_enabled *)
	rule restoreA (state == RestoreA
			&& spkAFifo.notEmpty);
		restoreRegVec(spikeA, spkAFifo);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule restoreAFinish (state == RestoreA
			&& !spkAFifo.notEmpty);
		state <= FeedbackCopy;
	endrule

	(* fire_when_enabled *)
	rule feedbackCopy (state == FeedbackCopy
			&& segmFifo.notEmpty);
		case (feedbackIn.first) matches
			OnlyA: shiftRegVec(spikeA, segmFifo.first);
			OnlyB: shiftRegVec(spikeB, segmFifo.first);
		endcase
		segmFifo.deq;
	endrule

	(* fire_when_enabled *)
	rule feedbackDone (state == FeedbackCopy
			&& !segmFifo.notEmpty);
		feedbackIn.deq;
		state <= FillSegment;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule calcFirstLevel;
		for (Integer i = 0; i < valueOf(WindowMaxSize); i = i + 1) begin
			Sample spikeSum = boundedPlus(spikeA[i], spikeB[i]);
			SampleDiff diff = cExtend(segment[i]) - cExtend(spikeSum);
			firstLevel[i] <= truncate(pack(abs(diff)));
		end
	endrule

	method getState = state;
	method getRemainingRotations = remainingRotations;
	method sum = adderTree;
	interface feedback = toPut(feedbackIn);
endmodule
