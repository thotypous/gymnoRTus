import PAClib::*;
import BRAM::*;
import BRAMUtils::*;
import BUtils::*;
import Connectable::*;
import ClientServer::*;
import GetPut::*;
import FIFOF::*;

interface CircularBurstQueue#(numeric type sz, type a);
	method Put#(a) in;
	method Action deqBurst;
	interface PipeOut#(a) out;
endinterface

module mkCircularBurstQueue(CircularBurstQueue#(sz, a))
		provisos (
			Bits#(a, sa),
			NumAlias#(TLog#(sz), addrsz),
			Add#(TExp#(addrsz), 0, sz),
			Alias#(Bit#(addrsz), addr)
		);

	BRAM1Port#(addr, a) bram <- mkBRAM1Server(defaultValue);
	FIFOF#(a) fifoOut <- mkFIFOF;
	Reg#(LBit#(sz)) remaining <- mkReg(0);
	Reg#(addr) ptr <- mkRegU;

	mkConnection(bram.portA.response, toPut(fifoOut));

	(* fire_when_enabled *)
	rule readReq (remaining != 0);
		bram.portA.request.put(makeReq(False, ptr, ?));
		ptr <= ptr + 1;
		remaining <= remaining - 1;
	endrule

	interface Put in;
		method Action put(a x) if (remaining == 0);
			bram.portA.request.put(makeReq(True, ptr, x));
			ptr <= ptr + 1;
		endmethod
	endinterface

	method Action deqBurst if (remaining == 0);
		remaining <= fromInteger(valueOf(sz));
	endmethod

	interface out = f_FIFOF_to_PipeOut(fifoOut);
endmodule
