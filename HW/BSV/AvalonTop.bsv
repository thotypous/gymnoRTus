import AvalonSlave::*;
import InterruptSender::*;
import DualAD::*;

typedef 2 AvalonAddrSize;
typedef 32 AvalonDataSize;

interface AvalonTop;
	(* prefix="" *)
	interface InterruptSenderWires irqWires;
	(* prefix="" *)
	interface AvalonSlaveWires#(AvalonAddrSize, AvalonDataSize) avalonWires;
	(* prefix="" *)
	interface DualADWires adWires;
	(* always_ready, result="LED" *)
	method Bit#(8) getLed;
endinterface

(* synthesize, clock_prefix="clk", reset_prefix="reset_n" *)
module mkAvalonTop(Clock adsclk, Clock slowclk, AvalonTop ifc);

	AvalonSlave#(AvalonAddrSize, AvalonDataSize) avalon <- mkAvalonSlave;
	DualAD adc <- mkDualAD(adsclk);

	Reg#(Bit#(AvalonDataSize)) ireg <- mkReg(0);
	Reg#(Bool) irqFlag <- mkReg(False);

	rule handleCmd;
		let cmd <- avalon.busClient.request.get;
		(*split*)
		case (cmd) matches
			tagged AvalonRequest{addr: .*, data: .*, command: Read}:
				avalon.busClient.response.put(32'hBADC0FFE);
		endcase
	endrule

	interface irqWires = irqSender(irqFlag);
	interface avalonWires = avalon.slaveWires;
	interface adWires = adc.wires;
	method Bit#(8) getLed = 0;

endmodule
