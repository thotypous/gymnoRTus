import Vector::*;

module [Module] mkVec#(Vector#(n, Module#(a)) vec) (Vector#(n, a));
	Vector#(n, a) result;
	for (Integer i = 0; i < valueOf(n); i = i + 1)
		result[i] <- vec[i];
	return result;
endmodule