import PAClib::*;
import FIFOF::*;
import Vector::*;
import Clocks::*;

function PipeOut#(a) f_SyncFIFOIfc_to_PipeOut(SyncFIFOIfc#(a) sync);
	return (interface PipeOut;
			method a first ();
				return sync.first;
			endmethod
			method Action deq ();
				sync.deq;
			endmethod
			method Bool notEmpty ();
				return sync.notEmpty ();
			endmethod
		endinterface);
endfunction

module mkPipeFilter#(function Bool cond(a x), PipeOut#(a) in) (PipeOut#(a))
		provisos (Bits#(a, sa));
	FIFOF#(a) out <- mkFIFOF;

	rule makeDecision;
		in.deq;
		if (cond(in.first))
			out.enq(in.first);
	endrule

	return f_FIFOF_to_PipeOut(out);
endmodule

function Vector#(1,a) vecBind(a elem) = Vector::cons(elem, Vector::nil);
function a vecUnbind(Vector#(1,a) vec) = vec[0];
