import PAClib::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import BUtils::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

typedef TDiv#(ContinuousAcqBufSize, 2) HalfBufSize;

interface ContinuousAcq;
	method Action start(PciDmaAddr addr);
	method Action stop;
	(* always_ready *)
	method Bool isRunning;
	(* always_ready *)
	method Bool isSyncing;
	interface PipeOut#(PciDmaAddrData) dmaWriteReq;
endinterface

module [Module] mkContinuousAcq#(PipeOut#(ChSample) acq, PulseWire irq) (ContinuousAcq)
		provisos (
			Bits#(ChNum, chnum_bits),
			// make sure a whole block of channels fits into half the buffer
			Mul#(TExp#(chnum_bits), ignore_1, TMul#(HalfBufSize, SamplesPerDmaWord))
		);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;

	Reg#(Bool) running <- mkReg(False);
	Array#(Reg#(Bool)) startSync <- mkCRegU(2);
	Array#(Reg#(LUInt#(ContinuousAcqBufSize))) remaining <- mkCRegU(2);
	Reg#(PciDmaAddr) baseAddr <- mkRegU;
	Reg#(PciDmaAddr) nextAddr <- mkRegU;

	PulseWire clearUnfunnel <- mkPulseWire;

	function ActionValue#(Bool) letSamplePass(ChSample chsample) =
		actionvalue
			// if in startSync phase, only let pass after a channel 0 sample
			let canPass = running && (!startSync[0] || tpl_1(chsample) == 0);
			if (startSync[0] && canPass) begin
				startSync[0] <= False;
				clearUnfunnel.send;  // break cyclic reference [toUnfunnel <-> unfunnel]
			end
			return canPass;
		endactionvalue;

	let toUnfunnel <- mkCompose(mkPipeFilterWithSideEffect(letSamplePass), mkFn_to_Pipe(compose(vecBind, tpl_2)), acq);
	PipeOut#(Vector#(SamplesPerDmaWord, Sample)) unfunnel <- mkClearableUnfunnel(clearUnfunnel, toUnfunnel);

	let halfLevel = valueOf(ContinuousAcqBufSize) / 2;

	rule recycle (running && remaining[0] == 0);
		remaining[0] <= fromInteger(valueOf(ContinuousAcqBufSize));
		irq.send;
		nextAddr <= baseAddr;
	endrule

	rule requestDma (running && remaining[0] != 0);
		let vec <- toGet(unfunnel).get;
		dmaOut.enq( tuple2( nextAddr, pack(map(extend, vec)) ) );
		if (remaining[0] == fromInteger(halfLevel))
			irq.send;
		remaining[0] <= remaining[0] - 1;
		nextAddr <= nextAddr + dmaWordBytes;
	endrule

	rule discard (!running);
		unfunnel.deq;
	endrule

	method Bool isRunning = running;
	method Bool isSyncing = startSync[0];

	method Action start(PciDmaAddr addr);
		baseAddr <= addr;
		remaining[1] <= 0;
		running <= True;
		startSync[1] <= True;
	endmethod

	method Action stop;
		running <= False;
	endmethod

	interface dmaWriteReq = f_FIFOF_to_PipeOut(dmaOut);
endmodule
