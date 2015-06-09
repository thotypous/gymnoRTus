import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;
import PipeUtils::*;
import SysConfig::*;
import Vector::*;

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
module [Module] mkAvalonTop(Clock adsclk, Clock slowclk, AvalonTop ifc);

	AvalonSlave#(PciBarAddrSize, PciBarDataSize) pcibar <- mkAvalonSlave;
	AvalonMaster#(PciDmaAddrSize, PciDmaDataSize) pcidma <- mkAvalonMaster;
	DualAD adc <- mkDualAD(adsclk);

	Array#(Reg#(PciBarData)) epoch <- mkCRegU(2);
	Reg#(Maybe#(PciBarData)) dmaAddress <- mkReg(tagged Invalid);
	Array#(Reg#(Bit#(11))) dmaPtr <- mkCRegU(2);
	Array#(Reg#(Bool)) irqFlag <- mkCReg(2, False);

	function filterCh(ch, chsample) = tpl_1(chsample) == ch;
	PipeOut#(Vector#(5,Sample)) vecFiveElemPipe <- mkCompose(
			mkCompose(
					mkPipeFilter(filterCh(0)),
					mkFn_to_Pipe(compose(vecBind, tpl_2))
			),
			mkUnfunnel(False),
			adc.acq);

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
		PciDmaData dataWord = extend(pack(vecFiveElemPipe.first));
		vecFiveElemPipe.deq;

		pcidma.busServer.request.put(AvalonRequest{
			command: Write,
			addr: dmaAddr + (extend(dmaPtr[0]) << 3),
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
