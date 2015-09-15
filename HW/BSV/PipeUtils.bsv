import PAClib::*;
import FIFOF::*;
import Vector::*;
import Clocks::*;
import Arbiter::*;


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


module mkPipeMux#(Bool cond, PipeOut#(a) pipeT, PipeOut#(a) pipeF) (PipeOut#(a))
		provisos (Bits#(a, sa));
	FIFOF#(a) out <- mkFIFOF;

	rule chooseT (cond);
		out.enq(pipeT.first);
		pipeT.deq;
	endrule

	rule chooseF (!cond);
		out.enq(pipeF.first);
		pipeF.deq;
	endrule

	return f_FIFOF_to_PipeOut(out);
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


// Based on PAClib implementation
module mkFlushableUnfunnel
		#(PipeOut #(Tuple2 #(Bool, Vector #(m,a)))  po_in)
		(PipeOut #(Vector #(mk, a)))

		provisos (Bits #(a, sa),
				Add #(ignore_1, 1, mk),          // assert mk > 0
				Add #(ignore_2, 1, m),           // assert m > 0
				Add #(ignore_3, m, mk),          // assert m <= mk
				Mul #(m, k, mk),                 // derive k
				Log #(k, logk),                  // derive log(k)
				Add #(logk, 1, logk_plus_1));    // derive log(k)+1

	Vector #(k, Reg #(Vector #(m, a)))   values <- replicateM (mkRegU);
	Array #(Reg #(UInt #(logk_plus_1)))  index  <- mkCReg (2, 0);

	UInt #(logk_plus_1) k = fromInteger (valueof(k));

	rule rl_receive (index[1] != k);
		match {.flush, .value} = po_in.first ();
		values [index[1]] <= value;
		po_in.deq ();
		index[1] <= flush ? k : index[1] + 1;
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


module [Module] mkPipeArbiter
		#(Module#(Arbiter_IFC#(n)) mkArbiter, Vector#(n, PipeOut#(a)) inputs)
		(PipeOut#(a))

		provisos (Bits#(a, sa));

	Arbiter_IFC#(n) arbiter <- mkArbiter;
	FIFOF#(a) fifoOut <- mkFIFOF;

	for (Integer i = 0; i < valueOf(n); i = i + 1)
		rule requestSlot (inputs[i].notEmpty);
			arbiter.clients[i].request;
		endrule

	// Need to help Bluespec scheduler here, as it does not
	// detect that the rules are mutually exclusive just by
	// analyzing their predicate
	Rules spendRules = emptyRules;

	for (Integer i = 0; i < valueOf(n); i = i + 1)
		spendRules = rJoinMutuallyExclusive(spendRules, rules
			rule spendGrant (arbiter.clients[i].grant);
				fifoOut.enq(inputs[i].first);
				inputs[i].deq;
			endrule
		endrules);

	addRules(spendRules);

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule


module [Module] mkPipeTransform_2#(
			Pipe#(a, b) mkPipe,
			Integer stages,
			PipeOut#(Tuple2#(c, a)) pipein
		) (PipeOut#(Tuple2#(c, b)))
		provisos (
			Bits#(a, sa),
			Bits#(b, sb),
			Bits#(c, sc)
		);

		match {.pipe1, .pipe2} <- mkFork(id, pipein);
		let pipe1Buffered <- mkBuffer_n(stages, pipe1);
		let pipe2Transformed <- mkPipe(pipe2);

		(*hide*)
		let m <- mkJoin(tuple2, pipe1Buffered, pipe2Transformed);
		return m;
endmodule


function Vector#(1,a) vecBind(a elem) = Vector::cons(elem, Vector::nil);

function a vecUnbind(Vector#(1,a) vec) = vec[0];

typedef Tuple2#(a,a) Pair#(type a);

function Pair#(a) duplicate(a x) = tuple2(x,x);
