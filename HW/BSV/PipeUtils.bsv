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

module mkPipeFilterWithSideEffect#(function ActionValue#(Bool) cond(a x), PipeOut#(a) in) (PipeOut#(a))
		provisos (Bits#(a, sa));
	FIFOF#(a) out <- mkFIFOF;

	rule makeDecision;
		in.deq;
		let condValue <- cond(in.first);
		if (condValue)
			out.enq(in.first);
	endrule

	return f_FIFOF_to_PipeOut(out);
endmodule

module mkPipeFilter#(function Bool cond(a x), PipeOut#(a) in) (PipeOut#(a))
		provisos (Bits#(a, sa));
	function ActionValue#(Bool) liftedCond(a x) = actionvalue return cond(x); endactionvalue;
	(*hide*) let m <- mkPipeFilterWithSideEffect(liftedCond, in);
	return m;
endmodule

function Vector#(1,a) vecBind(a elem) = Vector::cons(elem, Vector::nil);
function a vecUnbind(Vector#(1,a) vec) = vec[0];
