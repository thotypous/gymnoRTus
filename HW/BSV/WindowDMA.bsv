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
	interface PipeOut#(WinDMASync) sync;
endinterface

typedef enum {
	DiscardedWin,
	AcceptedWin
} WinDMASync deriving (Eq, Bits, FShow);

typedef TMul#(WordsNeededForAllChannels, WindowMaxSize) SingleBufWords;

module [Module] mkWindowDMA#(PipeOut#(OutItem) winPipe, PulseWire irq) (WindowDMA);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;
	FIFOF#(WindowInfo) winInfoOut <- mkFIFOF;
	FIFOF#(WinDMASync) syncOut <- mkSizedFIFOF(4);

	Reg#(Bool) insideIncompleteWindow <- mkReg(False);
	Reg#(Bool) running <- mkReg(False);
	Array#(Reg#(Bool)) secondBuf <- mkCRegU(2);
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
		syncOut.enq(DiscardedWin);
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
		nextAddr[0] <= baseAddr + (secondBuf[0] ? 0 : fromInteger(valueOf(SingleBufWords))*dmaWordBytes);
		secondBuf[0] <= !secondBuf[0];
		syncOut.enq(AcceptedWin);
	endrule

	method Action start(PciDmaAddr addr);
		baseAddr <= addr;
		nextAddr[1] <= addr;
		secondBuf[1] <= False;
		running <= True;
	endmethod

	method Action stop;
		running <= False;
	endmethod

	method Bool isRunning = running;

	interface dmaWriteReq = f_FIFOF_to_PipeOut(dmaOut);
	interface winInfoPipe = f_FIFOF_to_PipeOut(winInfoOut);
	interface sync = f_FIFOF_to_PipeOut(syncOut);
endmodule
