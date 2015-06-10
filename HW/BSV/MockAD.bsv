import PAClib::*;
import AvalonCommon::*;
import ClientServer::*;
import GetPut::*;
import FIFOF::*;
import MIMO::*;
import Vector::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

interface MockAD;
	method Bool isBusy;
	method Action start(PciDmaAddr addr);
	interface Client#(AvalonRequest#(PciDmaAddrSize,PciDmaDataSize), PciDmaData) dmaCli;
	interface PipeOut#(ChSample) acq;
endinterface

module [Module] mkMockAD(MockAD);
	FIFOF#(PciDmaAddr) dmaReadReq <- mkFIFOF;
	FIFOF#(PciDmaData) dmaResp <- mkFIFOF;
	FIFOF#(Vector#(SamplesPerDmaWord, ChSample)) dmaOut <- mkFIFOF;

	PipeOut#(ChSample) acqOut <- mkCompose(
			mkFunnel,
			mkFn_to_Pipe(vecUnbind),
			f_FIFOF_to_PipeOut(dmaOut));

	Reg#(LUInt#(MockADBufSize)) remaining <- mkReg(0);
	Reg#(PciDmaAddr) nextAddr <- mkRegU;
	Reg#(ChNum) nextCh <- mkRegU;
	FIFOF#(ChNum) firstChPending <- mkFIFOF;

	Array#(Reg#(Bool)) busyReg <- mkCReg(2, False);
	let busy = busyReg[0];
	let nextBusy = remaining != 0
			|| dmaReadReq.notEmpty
			|| firstChPending.notEmpty
			|| dmaResp.notEmpty
			|| dmaOut.notEmpty
			|| acqOut.notEmpty;

	rule updateBusy; // buffers the busy signal
		busyReg[0] <= nextBusy;
	endrule

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

	PciDmaAddr wordBytes = fromInteger(valueOf(PciDmaDataSize) / 8);

	rule requestDma (remaining != 0);
		dmaReadReq.enq(nextAddr);
		firstChPending.enq(nextCh);
		nextAddr <= nextAddr + wordBytes;
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

		dmaOut.enq(chSamples);
	endrule

	method Action start(PciDmaAddr addr) if (!busy);
		busyReg[1] <= True;
		nextAddr <= addr;
		nextCh <= 0;
		remaining <= fromInteger(valueOf(MockADBufSize));
	endmethod

	method Bool isBusy = busy;

	interface acq = acqOut;
	interface Client dmaCli;
		interface Get request;
			method ActionValue#(AvalonRequest#(PciDmaAddrSize,PciDmaDataSize)) get if (busy);
				dmaReadReq.deq;
				return AvalonRequest{addr: dmaReadReq.first, data: ?, command: Read};
			endmethod
		endinterface
		interface Put response = when(busy, toPut(dmaResp));
	endinterface
endmodule