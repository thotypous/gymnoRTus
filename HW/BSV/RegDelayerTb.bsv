import RegDelayer::*;
import StmtFSM::*;
import BUtils::*;

(* synthesize *)
module mkRegDelayerTb(Empty);
	Reg#(LBit#(20)) r <- mkReg(0);
	let delayed <- mkRegDelayer(8'd0, ?, r);

	(* fire_when_enabled, no_implicit_conditions *)
	rule updReg;
		r <= r + 1;
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule disp (r < 20);
		$display("%d, %d", r, delayed);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule finish(r == 20);
		$finish();
	endrule
endmodule
