import BRAM::*;
import BRAMUtils::*;
import ClientServer::*;
import GetPut::*;

typedef Bit#(TLog#(n)) Ptr#(numeric type n);

// nbuf coupled circular buffers, each one containing nitems of type a
// every buffer shares the same head pointer
interface MultiCircularBuffer#(numeric type nbuf, numeric type nitems, type a);
	interface Server#(Tuple2#(Ptr#(nbuf), Ptr#(nitems)), a) query;
	interface Put#(Tuple2#(Ptr#(nbuf), a)) head;
	method Action incHead;
endinterface

module mkMultiCircularBuffer(MultiCircularBuffer#(nbuf, nitems, a))
		provisos(
				Bits#(a, sa),
				NumAlias#(TLog#(nitems), itemBits),
				NumAlias#(TLog#(nbuf), bufBits),
				NumAlias#(TAdd#(itemBits, bufBits), addrBits),
				Alias#(Bit#(addrBits), addr)
		);

	BRAM2Port#(addr, a) bram <-mkBRAM2Server(defaultValue);
	Reg#(Ptr#(nitems)) headPtr <- mkReg(0);

	interface Server query;
		interface Put request;
			method Action put(Tuple2#(Ptr#(nbuf), Ptr#(nitems)) req);
				match {.bufn, .itemn} = req;
				bram.portA.request.put(makeReq(False, {bufn, headPtr - itemn}, ?));
			endmethod
		endinterface
		interface response = bram.portA.response;
	endinterface

	interface Put head;
		method Action put(Tuple2#(Ptr#(nbuf), a) req);
			match {.bufn, .data} = req;
			bram.portB.request.put(makeReq(True, {bufn, headPtr}, data));
		endmethod
	endinterface

	method Action incHead;
		headPtr <= headPtr + 1;
	endmethod
endmodule