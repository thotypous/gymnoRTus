import AvalonSlave::*;
import InterruptSender::*;

typedef 2 AvalonAddrSize;
typedef 32 AvalonDataSize;

interface AvalonTop;
	(* prefix="" *)
	interface InterruptSenderWires irqWires;
	(* prefix="" *)
	interface AvalonSlaveWires#(AvalonAddrSize, AvalonDataSize) avalonWires;
endinterface

(* synthesize, clock_prefix="clk", reset_prefix="reset_n" *)
module mkAvalonTop(AvalonTop);
	AvalonSlave#(AvalonAddrSize, AvalonDataSize) avalon <- mkAvalonSlave;

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
endmodule
