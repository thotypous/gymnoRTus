import PAClib::*;
export PAClib::*;

export mkDiscardImplicitCond;
export mkPipeFilter;

module mkDiscardImplicitCond#(b returnIfReady, b defaultVal) (ReadOnly#(b))
		provisos (Bits#(b, sb));
	Wire#(b) out <- mkDWire(defaultVal);
	rule updateOut;
		out <= returnIfReady;
	endrule
	method b _read = out;
endmodule

module mkPipeFilter#(function Bool cond(a x), PipeOut#(a) in) (PipeOut#(a));
	ReadOnly#(Bool) condSatisfied <- mkDiscardImplicitCond(cond(in.first), False);

	rule discardElement (!condSatisfied);
		in.deq;
	endrule

	method a first if (condSatisfied);
		return in.first;
	endmethod
	method Action deq if (condSatisfied);
		in.deq;
	endmethod
	method Bool notEmpty;
		return in.notEmpty && condSatisfied;
	endmethod
endmodule