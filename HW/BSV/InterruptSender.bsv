import Vector::*;
import GetPut::*;
import SysConfig::*;

interface InterruptSenderWires;
	(* always_ready, prefix="", result="ins" *)
	method Bit#(1) ins;
endinterface

interface InterruptSender#(numeric type ports);
	interface Vector#(ports, PulseWire) resetCounter;
	interface Vector#(ports, PulseWire) irq;
	interface Vector#(ports, Get#(PciBarData)) ack;

	interface InterruptSenderWires wires;
endinterface

module mkInterruptSender(InterruptSender#(ports));
	let n = valueOf(ports);
	Vector#(ports, Array#(Reg#(PciBarData))) counter <- replicateM(mkCRegU(2));
	Array#(Reg#(Bool)) irqFlag <- mkCReg(2*n, False);

	Vector#(ports, PulseWire) resetVec <- replicateM(mkPulseWire);
	Vector#(ports, PulseWire) irqVec <- replicateM(mkPulseWireOR);
	Vector#(ports, Get#(PciBarData)) ackVec;

	for (Integer i = 0; i < n; i = i + 1)
		(* fire_when_enabled, no_implicit_conditions *)
		rule handleReset (resetVec[i]);
			counter[i][1] <= 0;
		endrule

	for (Integer i = 0; i < n; i = i + 1)
		(* fire_when_enabled, no_implicit_conditions *)
		rule handleIrq (irqVec[i]);
			counter[i][0] <= counter[i][0] + 1;
			irqFlag[n+i] <= True;
		endrule

	for (Integer i = 0; i < n; i = i + 1)
		ackVec[i] = (interface Get#(PciBarData);
			method ActionValue#(PciBarData) get;
				irqFlag[i] <= False;
				return counter[i][0];
			endmethod
		endinterface);

	interface resetCounter = resetVec;
	interface irq = irqVec;
	interface ack = ackVec;

	interface InterruptSenderWires wires;
		method Bit#(1) ins = irqFlag[0] ? 1 : 0;
	endinterface
endmodule
