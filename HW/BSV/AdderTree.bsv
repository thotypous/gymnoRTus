// inspired on http://bluespec.com/forum/viewtopic.php?p=1076
import Vector::*;

typedef Bit#(b) NumT#(numeric type b);


typedef NumT#(TAdd#(TLog#(n), b))
		NumTLev#(numeric type n, numeric type b);

typedef ReadOnly#(NumTLev#(n, b))
		AdderN#(numeric type n, numeric type b);

typeclass Adder#(numeric type n, numeric type b);
	module mkAdderN#(Vector#(n, NumT#(b)) in) (AdderN#(n, b));
endtypeclass

instance Adder#(1, b);
	module mkAdderN#(Vector#(1, NumT#(b)) in) (AdderN#(1, b));
		method _read = in[0];
	endmodule
endinstance

instance Adder#(n, b)
		provisos (
			Div#(n, 2, hn),
			Add#(hn, hn, n),
			Add#(TLog#(hn), 1, TLog#(n)),
			Adder#(hn, b)
		);

	module mkAdderN#(Vector#(n, NumT#(b)) in) (AdderN#(n, b));
		AdderN#(hn, b) a1 <- mkAdderN(take(in));
		AdderN#(hn, b) a2 <- mkAdderN(drop(in));
		Reg#(NumTLev#(n, b)) r <- mkRegU;

		(* fire_when_enabled, no_implicit_conditions *)
		rule add;
			r <= extend(a1) + extend(a2);
		endrule

		method _read = r;
	endmodule

endinstance
