import SysConfig::*;

interface InterruptSenderWires;
	(* always_ready, prefix="", result="ins" *)
	method Bit#(1) ins;
endinterface

interface InterruptSender;
	(* always_ready *)
	method Action resetCounter;
	(* always_ready *)
	method Action send;
	(* always_ready *)
	method ActionValue#(PciBarData) ack;
	
	interface InterruptSenderWires wires;
endinterface

module mkInterruptSender(InterruptSender);
	Array#(Reg#(PciBarData)) counter <- mkCRegU(2);
	Array#(Reg#(Bool)) irqFlag <- mkCReg(2, False);

	method Action resetCounter;
		counter[1] <= 0;
	endmethod

	method Action send;
		counter[0] <= counter[0] + 1;
		irqFlag[1] <= True;
	endmethod

	method ActionValue#(PciBarData) ack;
		irqFlag[0] <= False;
		return counter[0];
	endmethod

	interface InterruptSenderWires wires;
		method Bit#(1) ins = irqFlag[0] ? 1 : 0;
	endinterface
endmodule
