import PAClib::*;
import FIFOF::*;
import Vector::*;

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
