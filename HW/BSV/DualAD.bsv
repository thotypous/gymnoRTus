import GetPut::*;
export GetPut::*;
import Clocks::*;
import Reserved::*;
import Connectable::*;
import Vector::*;
import DefaultValue::*;
import MIMO::*;

export DualAD(..);
export DualADWires(..);
export Sample(..);
export mkDualAD;

typedef Bit#(12) Sample;

interface DualADWires;
	(* always_ready, result="AD_DIN" *)
	method Bit#(1) getData;
	(* always_ready, enable="AD_SSTRB0", prefix="" *)
	method Action putStrobe0;
	(* always_ready, enable="AD_SSTRB1", prefix="" *)
	method Action putStrobe1;
	(* always_ready, always_enabled, prefix="" *)
	method Action putData0((*port="AD_DOUT0"*)Bit#(1) v);
	(* always_ready, always_enabled, prefix="" *)
	method Action putData1((*port="AD_DOUT1"*)Bit#(1) v);
endinterface

interface DualAD;
	interface DualADWires wires;
	interface Get#(Sample) acq;
endinterface

interface DualADInternal;
	interface DualADWires wires;
	interface Get#(Tuple2#(Sample, Sample)) acq;
endinterface

typedef enum {
	Bipolar  = 1'b0,
	Unipolar = 1'b1
} UniBip deriving (Eq, Bits);

typedef enum {
	Differential = 1'b0,
	SingleEnded  = 1'b1
} SglDif deriving (Eq, Bits);

typedef enum {
	FullPowerDown   = 2'b00,
	FastPowerDown   = 2'b01,
	ReducedPower    = 2'b10,
	NormalOperation = 2'b11
} OperatingMode deriving (Eq, Bits);

// See MAX1280 datasheet p. 14, Table 1
typedef struct {
	ReservedOne#(1) start;
	Bit#(3) sel;
	UniBip unibip;
	SglDif sgldif;
	OperatingMode opmode;
} ControlByte deriving (Eq, Bits);

function Bit#(8) makeControlByte(Bit#(3) sel);
	ControlByte ctrl;
	ctrl.sel = sel;
	ctrl.unibip = Unipolar;
	ctrl.sgldif = SingleEnded;
	ctrl.opmode = NormalOperation;
	return pack(ctrl);
endfunction

module mkDualADInternal(DualADInternal);
	Reg#(Bit#(1)) din <- mkReg(0);
	Array#(Reg#(Bit#(4))) cnt <- mkCReg(3, 0);
	Wire#(Bit#(1)) dout0 <- mkWire;
	Wire#(Bit#(1)) dout1 <- mkWire;
	Reg#(Sample) shiftReg0 <- mkRegU;
	Reg#(Sample) shiftReg1 <- mkRegU;
	Reg#(Bit#(8)) ctrl <- mkRegU;

	// Number of the cycle during which the SSTRB pulse should occur.
	// See MAX1280 datasheet p. 13, Figure 6
	let cycleAfterStrobe = 4'd10;

	// Adjusts the value above considering that there will be an output
	// delay of 2 cycles because of writes to the cnt and din registers.
	let cycleAfterStrobeAdjusted = cycleAfterStrobe + 4'd2;

	rule dinFeed;
		(*split*)
		if (cnt[0] < 8) begin
			din <= ctrl[7];
			ctrl <= ctrl << 1;
		end else begin
			din <= 0;
		end
		cnt[0] <= cnt[0] + 1;
	endrule

	let doutBit = cnt[0] - cycleAfterStrobeAdjusted;

	rule doutHandle(doutBit < 12);
		shiftReg0 <= (shiftReg0 << 1) | extend(dout0);
		shiftReg1 <= (shiftReg1 << 1) | extend(dout1);
	endrule

	interface DualADWires wires;
		method Bit#(1) getData = din;
		method Action putStrobe0;  cnt[1] <= cycleAfterStrobeAdjusted; endmethod
		method Action putStrobe1;  cnt[2] <= cycleAfterStrobeAdjusted; endmethod
		method Action putData0(v); dout0 <= v; endmethod
		method Action putData1(v); dout1 <= v; endmethod
	endinterface

	interface Get acq;
		method ActionValue#(Tuple2#(Sample, Sample)) get if (doutBit == 12);
			return tuple2(shiftReg0, shiftReg1);
		endmethod
	endinterface
endmodule

module mkDualAD(Clock sClk, DualAD ifc);
	Reset sRst <- mkAsyncResetFromCR(1, sClk);
	let m <- mkDualADInternal(clocked_by sClk, reset_by sRst);

	SyncFIFOIfc#(Tuple2#(Sample, Sample)) sync <- mkSyncFIFOToCC(2, sClk, sRst);
	MIMO#(2, 1, 2, Sample) mimo <- mkMIMO(defaultValue);

	mkConnection(m.acq, toPut(sync));

	function tupleToVector(tuple) = cons(tpl_1(tuple), cons(tpl_2(tuple), nil));

	rule mimoPut;
		let data <- toGet(sync).get;
		mimo.enq(2, tupleToVector(data));
	endrule

	interface wires = m.wires;
	interface Get acq;
		method ActionValue#(Sample) get;
			mimo.deq(1);
			return mimo.first[0];
		endmethod
	endinterface
endmodule