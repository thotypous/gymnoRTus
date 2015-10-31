import FIFOF::*;
import GetPut::*;
import BUtils::*;
import SysConfig::*;

typedef 2500 PulseDuration;

typedef LBit#(PulseDuration) PulseRemainingCycles;
PulseRemainingCycles pulseDuration = fromInteger(valueOf(PulseDuration));

interface ProgrammablePulser;
	interface Put#(Timestamp) sched;
	method Action clear;
	method Bit#(1) pulse;
endinterface

module [Module] mkProgrammablePulser#(Timestamp ts) (ProgrammablePulser);
	FIFOF#(Timestamp) scheduledTs <- mkSizedFIFOF(4);
	Array#(Reg#(PulseRemainingCycles)) remaining <- mkCReg(2, 0);
	Reg#(Bit#(1)) pulseBuf <- mkReg(0);

	rule pulseHigh (remaining[0] != 0);
		pulseBuf <= 1;
		remaining[0] <= remaining[0] - 1;
	endrule

	rule pulseLow (remaining[0] == 0);
		pulseBuf <= 0;
	endrule

	rule startPulse (scheduledTs.first == ts);
		scheduledTs.deq;
		remaining[1] <= pulseDuration;
	endrule

	interface sched = toPut(scheduledTs);
	method clear = scheduledTs.clear;
	method pulse = pulseBuf;
endmodule
