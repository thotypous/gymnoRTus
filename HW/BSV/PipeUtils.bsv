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


//
// mkFunnel and mkFunnel_Indexed implementations from the PAClib package,
// fixed for working correctly with "-aggressive-conditions" by specifying
// an "if" predicate for the "deq" method.

// ----------------------------------------------------------------
// Funnel an mk-vector down to a k-stream of m-vector slices

module mkFunnel
				#(PipeOut #(Vector #(mk, a)) po_in)
				(PipeOut #(Vector #(m, a)))

		provisos (Bits #(a, sa),
				Add #(ignore_1, 1, mk),   // mk > 0           (assert)
				Add #(ignore_2, 1, m),    // m > 0            (assert)
				Add #(ignore_3, m, mk),   // m <= mk          (assert)
				Mul #(m, k, mk),          // m * k == mk      (derive k)
				Log #(k, logk),           // log (k) == logk  (derive logk)

				// The following two provisos are redundant, but currently required by bsc
				// TODO: recheck periodically if bsc improvements make these redundant
				Mul #(mk, sa, TMul #(k, TMul #(m, sa)))
			);

	UInt #(logk)                k_minus_1   = fromInteger (valueof(k) - 1);
	Reg #(UInt #(logk))         index_k    <- mkReg (0);
	Vector #(k, Vector #(m, a)) values      = unpack (pack (po_in.first));

	return (interface PipeOut;
				method Vector #(m,a) first ();
					return values [index_k];
				endmethod

				method Action deq () if (po_in.notEmpty);
					if (index_k == k_minus_1) begin
						index_k <= 0;
						po_in.deq ();
					end else
						index_k <= index_k + 1;
				endmethod

				method Bool notEmpty ();
					return  po_in.notEmpty ();
				endmethod
			endinterface);
endmodule: mkFunnel

// ----------------------------------------------------------------
// Funnel an mk-vector down to a k-stream of m-vector slices accompanied by their indexes

module mkFunnel_Indexed
				#(PipeOut #(Vector #(mk, a)) po_in)
				(PipeOut #(Vector #(m, Tuple2 #(a, UInt #(logmk)))))

		provisos (Bits #(a, sa),
				Add #(ignore_1, 1, mk),  // mk > 0             (assert)
				Add #(ignore_2, 1, m),   // m > 0              (assert)
				Add #(ignore_3, m, mk),  // m <= mk            (assert)
				Log #(mk, logmk),        // log (mk) == logmk  (derive logmk)
				Mul #(m, k, mk),         // m * k == mk        (derive k)
				Log #(k, logk),          // log (k) == logk    (derive logk)

				// The following two provisos are redundant, but currently required by bsc
				Bits #(Vector #(k, Vector #(m, a)), TMul #(mk, sa)),
				Bits #(Vector #(mk, a), TMul #(mk, sa)));

	UInt #(logk) k_minus_1 = fromInteger (valueof(k) - 1);

	// This function pairs each input vector element with an index, starting from base
	function Vector #(n, Tuple2 #(a, UInt #(logmk)))
			attach_indexes_from_base (UInt #(logmk) base, Vector #(n, a)  xs);

		function UInt #(logmk) add_base (Integer j) = (base + fromInteger (j));

		let indexes	 = genWith (add_base);    // {base,base+1,...,base+n-1}
		let x_index_vec = zip (xs, indexes);  // {(x0,base),(x1,base+11),...,(xmk-1,base+n-1)}
		return x_index_vec;
	endfunction: attach_indexes_from_base

	Reg #(UInt #(logk))  index_k   <- mkReg (0);
	Reg #(UInt #(logmk)) index_mk  <- mkReg (0);

	return (interface PipeOut;
				method Vector #(m, Tuple2 #(a, UInt #(logmk))) first ();
					Vector #(k, Vector #(m, a)) k_vec_m_vec = unpack (pack (po_in.first ()));
					return attach_indexes_from_base (index_mk, k_vec_m_vec [index_k]);
				endmethod

				method Action deq () if (po_in.notEmpty);
					if (index_k == k_minus_1) begin
						po_in.deq ();
						index_k <= 0;
						index_mk <= 0;
					end else begin
						index_k <= index_k + 1;
						index_mk <= index_mk + fromInteger (valueof (m));
					end
				endmethod

				method Bool notEmpty ();
					return po_in.notEmpty ();
				endmethod
			endinterface);
endmodule: mkFunnel_Indexed


function Vector#(1,a) vecBind(a elem) = Vector::cons(elem, Vector::nil);

function a vecUnbind(Vector#(1,a) vec) = vec[0];

typedef Tuple2#(a,a) Pair#(type a);

function Pair#(a) duplicate(a x) = tuple2(x,x);
