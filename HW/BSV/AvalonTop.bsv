import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;

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
	Reg#(Sample) test <- mkRegU;

	Reg#(Bit#(PciBarDataSize)) ireg <- mkReg(0);
	Reg#(Bool) irqFlag <- mkReg(False);

	rule handleCmd;
		let cmd <- pcibar.busClient.request.get;
		(*split*)
		case (cmd) matches
			tagged AvalonRequest{addr: .*, data: .*, command: Read}:
				pcibar.busClient.response.put(32'hBADC0FFE);
		endcase
	endrule

	rule getSample;
		let chsample <- toGet(adc.acq).get;
		match {.*, .sample} = chsample;
		test <= sample;
	endrule

	interface irqWires = irqSender(irqFlag);
	interface barWires = pcibar.slaveWires;
	interface dmaWires = pcidma.masterWires;
	interface adWires  = adc.wires;
	method Bit#(8) getLed = truncate(test);

endmodule
