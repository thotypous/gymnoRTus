import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;
import StmtFSM::*;

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

	Array#(Reg#(Bool)) irqFlag <- mkCReg(2, False);

	Reg#(Bit#(PciDmaAddrSize)) curAddr   <- mkRegU;
	Reg#(Bit#(PciBarDataSize)) startData <- mkRegU;
	Reg#(Bit#(11)) i <- mkRegU;

	Stmt stmt = seq
		while (i < 1024)
			action
				Bit#(PciDmaDataSize) data = extend(startData) + extend(i);
				pcidma.busServer.request.put(AvalonRequest{
					addr: curAddr,
					data: data,
					command: Write
				});
				curAddr <= curAddr + fromInteger(valueOf(PciDmaDataSize)/8);
				i <= i + 1;
			endaction
		irqFlag[1] <= True;
	endseq;

	FSM fsm <- mkFSM(stmt);

	rule handleCmd;
		let cmd <- pcibar.busClient.request.get;
		(*split*)
		case (cmd) matches
			tagged AvalonRequest{addr: 0, data: .x, command: Write}:
				action
					startData <= x;
				endaction
			tagged AvalonRequest{addr: 1, data: .x, command: Write}:
				action
					curAddr <= x;
					i <= 0;
					fsm.start;
				endaction
			tagged AvalonRequest{addr: 2, data: .*, command: Read}:
				action
					irqFlag[0] <= False;
					pcibar.busClient.response.put(startData);
				endaction
			tagged AvalonRequest{addr: .*, data: .*, command: Read}:
				action
					pcibar.busClient.response.put(32'hBADC0FFE);
				endaction
		endcase
	endrule

	interface irqWires = irqSender(irqFlag[0]);
	interface barWires = pcibar.slaveWires;
	interface dmaWires = pcidma.masterWires;
	interface adWires  = adc.wires;
	method Bit#(8) getLed = 0;

endmodule
