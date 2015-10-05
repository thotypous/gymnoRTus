import AdderTree::*;
import Vector::*;
import StmtFSM::*;
import BUtils::*;

typedef 128 VecLen;
typedef LBit#(VecLen) Data;

typedef TMul#(2, TLog#(VecLen)) NumCycles;

(* synthesize *)
module mkAdderTreeTb(Empty) provisos (Bits#(Data, sData));
	Vector#(VecLen, Reg#(Data)) vec <- replicateM(mkRegU);
	AdderN#(VecLen, sData) adderTree <- mkAdderN(readVReg(vec));
	Reg#(LBit#(NumCycles)) j <- mkReg(0);
	Reg#(Bool) enableInc <- mkReg(False);

	rule inc (enableInc);
		vec[0] <= vec[0] + 1;
	endrule

	mkAutoFSM(
		seq
			action
				await(!enableInc);  // silence warning
				for (Integer i = 0; i < valueOf(VecLen); i = i + 1)
					vec[i] <= fromInteger(i + 1);
				j <= j + 1;
				enableInc <= True;
			endaction
			while (j < fromInteger(valueOf(NumCycles))) action
				$display("cycle [%d] -> %d", j, adderTree);
				j <= j + 1;
			endaction
		endseq);
endmodule
