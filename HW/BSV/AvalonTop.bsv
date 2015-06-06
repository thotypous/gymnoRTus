import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;
import PipeUtils::*;
import Vector::*;

typedef 2  PciBarAddrSize;
typedef 32 PciBarDataSize;
typedef 32 PciDmaAddrSize;
typedef 64 PciDmaDataSize;

interface AvalonTop;
	(* prefix="" *)
	interface InterruptSenderWires irqWires;
	(* prefix="" *)
	interface AvalonSlaveWires#(PciBarAddrSize, PciBarDataSize) barWires;
	(* prefix="dma" *)
	interface AvalonMasterWires#(PciDmaAddrSize, PciDmaDataSize) dmaWires;
	(* prefix="" *)
	interface DualADWires adWires;
	(* always_ready, result="LED" *)
	method Bit#(8) getLed;
endinterface

(* synthesize, clock_prefix="clk", reset_prefix="reset_n" *)
module mkAvalonTop(Clock adsclk, Clock slowclk, AvalonTop ifc);

	AvalonSlave#(PciBarAddrSize, PciBarDataSize) pcibar <- mkAvalonSlave;
	AvalonMaster#(PciDmaAddrSize, PciDmaDataSize) pcidma <- mkAvalonMaster;
	DualAD adc <- mkDualAD(adsclk);

	Array#(Reg#(Bit#(PciBarDataSize))) epoch <- mkCRegU(2);
	Reg#(Maybe#(Bit#(PciBarDataSize))) dmaAddress <- mkReg(tagged Invalid);
	Array#(Reg#(Bit#(11))) dmaPtr <- mkCRegU(2);
	Array#(Reg#(Bool)) irqFlag <- mkCReg(2, False);

	function filterCh(ch, chsample) = tpl_1(chsample) == ch;
	PipeOut#(ChSample) onlyCh0Pipe <- mkPipeFilter(filterCh(0), adc.acq);
	function vecSingleElem(chsample) = Vector::cons(tpl_2(chsample), Vector::nil);
	PipeOut#(Vector#(1,Sample)) vecSingleElemPipe <- mkFn_to_Pipe(vecSingleElem, onlyCh0Pipe);
	PipeOut#(Vector#(5,Sample)) vecFiveElemPipe <- mkUnfunnel(False, vecSingleElemPipe);

	rule handleCmd;
		let cmd <- pcibar.busClient.request.get;
		(*split*)
		case (cmd) matches
			tagged AvalonRequest{addr: 0, data: .x, command: Write}:
				action
					dmaAddress <= tagged Valid x;
					dmaPtr[1] <= 0;
					epoch[1] <= 0;
				endaction
			tagged AvalonRequest{addr: 0, data: .*, command: Read}:
				action
					pcibar.busClient.response.put(epoch[0]);
					irqFlag[0] <= False;
				endaction
			tagged AvalonRequest{addr: 1, data: .*, command: Write}:
				action
					dmaAddress <= tagged Invalid;
				endaction
			tagged AvalonRequest{addr: .*, data: .*, command: Read}:
				action
					pcibar.busClient.response.put(32'hBADC0FFE);
				endaction
		endcase
	endrule

	rule discardSamples(dmaAddress matches tagged Invalid);
		vecFiveElemPipe.deq;
	endrule

	rule transferSamples(dmaAddress matches tagged Valid .dmaAddr);
		Bit#(PciDmaDataSize) dataWord = extend(pack(vecFiveElemPipe.first));
		vecFiveElemPipe.deq;

		pcidma.busServer.request.put(AvalonRequest{
			command: Write,
			addr: dmaAddr + extend(dmaPtr[0]),
			data: dataWord
		});

		if(dmaPtr[0] == 0 || dmaPtr[0] == 1024) begin
			irqFlag[1] <= True;
			epoch[0] <= epoch[0] + 1;
		end

		dmaPtr[0] <= dmaPtr[0] + 1;
	endrule

	interface irqWires = irqSender(irqFlag[0]);
	interface barWires = pcibar.slaveWires;
	interface dmaWires = pcidma.masterWires;
	interface adWires  = adc.wires;
	method Bit#(8) getLed = ~extend(isValid(dmaAddress) ? 1'b1 : 1'b0);

endmodule
