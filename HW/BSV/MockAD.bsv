import PAClib::*;
import AvalonCommon::*;
import ClientServer::*;
import GetPut::*;
import FIFOF::*;
import BUtils::*;
import Vector::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

interface MockAD;
	method Action start(PciDmaAddr addr);
	(* always_ready *)
	method Bool isBusy;
	interface PipeOut#(PciDmaAddr) dmaReadReq;
	interface Put#(PciDmaData) dmaReadResp;
	interface PipeOut#(ChSample) acq;
endinterface

module [Module] mkMockAD(MockAD)
		provisos (
			Bits#(ChNum, chnum_bits),
			// make sure a whole block of channels fits into the buffer
			Mul#(TExp#(chnum_bits), ignore_1, TMul#(MockADBufSize, SamplesPerDmaWord))
		);
	FIFOF#(PciDmaAddr) dmaReq <- mkFIFOF;
	FIFOF#(PciDmaData) dmaResp <- mkFIFOF;
	FIFOF#(Vector#(SamplesPerDmaWord, ChSample)) fromDma <- mkFIFOF;

	PipeOut#(ChSample) acqOut <- mkCompose(
			PipeUtils::mkFunnel,
			mkFn_to_Pipe(vecUnbind),
			f_FIFOF_to_PipeOut(fromDma));

	Reg#(LUInt#(MockADBufSize)) remaining <- mkReg(0);
	Reg#(PciDmaAddr) nextAddr <- mkRegU;
	Reg#(ChNum) nextCh <- mkRegU;
	FIFOF#(ChNum) firstChPending <- mkFIFOF;

	let busy = remaining != 0;

	function ChNum incCh(ChNum ch);
		Bit#(1) msb = truncateLSB(ch);
		ChSel sel = truncate(ch);
		if (msb == 1)
			sel = sel + 1;
		msb = ~msb;
		return {msb, sel};
	endfunction

	function ChNum chSkipWord(ChNum ch);
		for(Integer i = 0; i < valueOf(SamplesPerDmaWord); i = i + 1)
			ch = incCh(ch);
		return ch;
	endfunction

	rule requestDma (remaining != 0);
		dmaReq.enq(nextAddr);
		firstChPending.enq(nextCh);
		nextAddr <= nextAddr + dmaWordBytes;
		nextCh <= chSkipWord(nextCh);
		remaining <= remaining - 1;
	endrule

	rule receiveDma;
		ChNum ch <- toGet(firstChPending).get;

		Vector#(SamplesPerDmaWord, DmaSample) samples = unpack(dmaResp.first);
		dmaResp.deq;

		Vector#(SamplesPerDmaWord, ChSample) chSamples;
		for(Integer i = 0; i < valueOf(SamplesPerDmaWord); i = i + 1) begin
			chSamples[i] = tuple2(ch, truncate(samples[i]));
			ch = incCh(ch);
		end

		fromDma.enq(chSamples);
	endrule

	method Action start(PciDmaAddr addr) if (!busy);
		nextAddr <= addr;
		nextCh <= 0;
		remaining <= fromInteger(valueOf(MockADBufSize));
	endmethod

	method Bool isBusy = busy;

	interface acq = acqOut;
	interface dmaReadReq = f_FIFOF_to_PipeOut(dmaReq);
	interface dmaReadResp = toPut(dmaResp);
endmodule
