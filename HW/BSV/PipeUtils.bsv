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

	rule makeDecision (in.notEmpty && out.notFull);
		in.deq;
		let condValue <- cond(in.first);
		(*nosplit*)
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


// Based on PAClib implementation
module mkClearableUnfunnel
		#(PulseWire clear, PipeOut #(Vector #(m,a))  po_in)
		(PipeOut #(Vector #(mk, a)))

		provisos (Bits #(a, sa),
				Add #(ignore_1, 1, mk),          // assert mk > 0
				Add #(ignore_2, 1, m),           // assert m > 0
				Add #(ignore_3, m, mk),          // assert m <= mk
				Mul #(m, k, mk),                 // derive k
				Log #(k, logk),                  // derive log(k)
				Add #(logk, 1, logk_plus_1));    // derive log(k)+1

	Vector #(k, Reg #(Vector #(m, a)))   values <- replicateM (mkRegU);
	Array #(Reg #(UInt #(logk_plus_1)))  index  <- mkCReg (3, 0);

	UInt #(logk_plus_1) k = fromInteger (valueof(k));

	rule rl_receive (index[1] != k);
		values [index[1]] <= po_in.first ();
		po_in.deq ();
		index[1] <= index[1] + 1;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule rl_clear (clear);
		index[2] <= 0;
	endrule

	return (interface PipeOut;
		method Vector #(mk, a) first () if (index[0] == k);
			Vector #(k, Vector #(m,a)) ys = readVReg (values);
			Vector #(mk, a) result = concat (ys);
			return  result;
		endmethod

		method Action deq () if (index[0] == k);
			index[0] <= 0;
		endmethod

		method Bool notEmpty ();
			return (index[0] == k);
		endmethod
	endinterface);
endmodule


function Vector#(1,a) vecBind(a elem) = Vector::cons(elem, Vector::nil);

function a vecUnbind(Vector#(1,a) vec) = vec[0];
