import PAClib::*;
export PAClib::*;
import FIFOF::*;

export mkPipeFilter;

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