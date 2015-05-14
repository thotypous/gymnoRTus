import AvalonSlave::*;
import InterruptSender::*;

typedef 2 AvalonAddrSize;
typedef 32 AvalonDataSize;

interface AvalonTop;
	(* prefix="" *)
	interface InterruptSenderWires irqWires;
	(* prefix="" *)
	interface AvalonSlaveWires#(AvalonAddrSize, AvalonDataSize) avalonWires;
	(* always_ready, result="irqflagtap" *)
	method Bool irqFlagTap;
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
			// Register @0x00: Write data to ireg and produce IRQ echo
			tagged AvalonRequest{addr: 0, data: .x, command: Write}:
				action
					ireg <= x;
					irqFlag <= True;
				endaction
			// Register @0x04: Read ireg and clear the IRQ
			tagged AvalonRequest{addr: 1, data: .*, command: Read}:
				action
					avalon.busClient.response.put(ireg);
					irqFlag <= False;
				endaction
			tagged AvalonRequest{addr: .*, data: .*, command: Read}:
				avalon.busClient.response.put(32'hBADC0FFE);
		endcase
	endrule

	interface irqWires = irqSender(irqFlag);
	interface avalonWires = avalon.slaveWires;
	method Bool irqFlagTap = irqFlag;
endmodule
