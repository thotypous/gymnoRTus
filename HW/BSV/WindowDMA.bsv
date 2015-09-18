import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import WindowMaker::*;
import WindowDMABuffer::*;
import SysConfig::*;

interface WindowDMA;
	method Action start(PciDmaAddr addr);
	method Action stop;
	(* always_ready *)
	method Bool isRunning;
	interface PipeOut#(PciDmaAddrData) dmaWriteReq;
	interface PipeOut#(WindowInfo) winInfoPipe;
endinterface

typedef TMul#(WordsNeededForAllChannels, WindowMaxSize) SingleBufWords;

module [Module] mkWindowDMA#(PipeOut#(OutItem) winPipe, PulseWire irq) (WindowDMA);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;
	FIFOF#(WindowInfo) winInfoOut <- mkFIFOF;

	Reg#(Bool) insideIncompleteWindow <- mkReg(False);
	Reg#(Bool) running <- mkReg(False);
	Reg#(Bool) secondBuf <- mkRegU;
	Reg#(PciDmaAddr) baseAddr <- mkRegU;
	Array#(Reg#(PciDmaAddr)) nextAddr <- mkCRegU(2);

	let wbuf <- mkWindowDMABuffer(winPipe);

	let discardDmaData = !running || insideIncompleteWindow;

	rule detectIncompleteWindow (wbuf.first matches tagged DmaData .*
				&&& discardDmaData);
		wbuf.deq;
		insideIncompleteWindow <= True;
	endrule

	rule clearIncompleteWindow (wbuf.first matches tagged EndMarker .*
				&&& discardDmaData);
		wbuf.deq;
		insideIncompleteWindow <= False;
	endrule

	rule processDmaData (wbuf.first matches tagged DmaData .dmadata
				&&& !discardDmaData);
		wbuf.deq;
		dmaOut.enq(tuple2(nextAddr[0], dmadata));
		nextAddr[0] <= nextAddr[0] + dmaWordBytes;
	endrule

	rule processEndMarker (wbuf.first matches tagged EndMarker .wininfo
				&&& !discardDmaData && !winInfoOut.notEmpty);
		wbuf.deq;
		winInfoOut.enq(wininfo);
		irq.send;
		nextAddr[0] <= baseAddr + (secondBuf ? 0 : fromInteger(valueOf(SingleBufWords))*dmaWordBytes);
		secondBuf <= !secondBuf;
	endrule

	method Action start(PciDmaAddr addr);
		baseAddr <= addr;
		nextAddr[1] <= addr;
		secondBuf <= False;
		running <= True;
	endmethod

	method Action stop;
		running <= False;
	endmethod

	method Bool isRunning = running;

	interface dmaWriteReq = f_FIFOF_to_PipeOut(dmaOut);
	interface winInfoPipe = f_FIFOF_to_PipeOut(winInfoOut);
endmodule
