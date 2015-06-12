import PAClib::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import BUtils::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

typedef Tuple2#(PciDmaAddr, PciDmaData) PciDmaAddrData;
typedef TDiv#(ContinuousAcqBufSize, 2) HalfBufSize;

interface ContinuousAcq;
	method Action start(PciDmaAddr addr);
	method Action stop;

	(* always_ready *)
	method Bool levelAlert;

	interface Get#(PciDmaAddrData) dmaReq;
endinterface

module [Module] mkContinuousAcq#(PipeOut#(ChSample) acq) (ContinuousAcq);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;

	Reg#(Bool) running <- mkReg(False);
	Array#(Reg#(LUInt#(ContinuousAcqBufSize))) remaining <- mkCRegU(2);
	Reg#(PciDmaAddr) baseAddr <- mkRegU;
	Reg#(PciDmaAddr) nextAddr <- mkRegU;

	PulseWire levelAlertWire <- mkPulseWireOR;

	PipeOut#(Vector#(SamplesPerDmaWord, Sample)) acqVec <- mkCompose(
			mkFn_to_Pipe(compose(vecBind, tpl_2)),
			mkUnfunnel(False),
			acq);

	let halfLevel = valueOf(ContinuousAcqBufSize) / 2;

	rule recycle (running && remaining[0] == 0);
		remaining[0] <= fromInteger(valueOf(ContinuousAcqBufSize));
		levelAlertWire.send;
		nextAddr <= baseAddr;
	endrule

	rule requestDma (running && remaining[0] != 0);
		let vec <- toGet(acqVec).get;
		dmaOut.enq( tuple2( nextAddr, pack(map(extend, vec)) ) );
		if (remaining[0] == fromInteger(halfLevel))
			levelAlertWire.send;
		remaining[0] <= remaining[0] - 1;
		nextAddr <= nextAddr + dmaWordBytes;
	endrule

	rule discard (!running);
		let _ <- toGet(acqVec).get;
	endrule

	method Bool levelAlert = levelAlertWire;

	method Action start(PciDmaAddr addr);
		baseAddr <= addr;
		remaining[1] <= 0;
		running <= True;
	endmethod

	method Action stop;
		running <= False;
	endmethod

	interface Get dmaReq = toGet(dmaOut);
endmodule
