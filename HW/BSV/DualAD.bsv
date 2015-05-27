import GetPut::*;
export GetPut::*;
import Clocks::*;
import Reserved::*;

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

module mkDualADInternal(DualAD);
	Reg#(Bit#(1))          din <- mkReg(0);
	Array#(Reg#(Bit#(4)))  cnt <- mkCReg(2, 0);
	Wire#(Bit#(1))        dout <- mkWire;
	Reg#(Sample)      shiftReg <- mkRegU;
	Reg#(ControlByte)     ctrl <- mkRegU;

	interface DualADWires wires;
		method Bit#(1) getData = 0;
		method Action putStrobe0 = noAction;
		method Action putStrobe1 = noAction;
		method Action putData0(v) = noAction;
		method Action putData1(v) = noAction;
	endinterface

	interface Get acq;
		method ActionValue#(Sample) get;
			return 0;
		endmethod
	endinterface
endmodule

module mkDualAD(Clock sClk, DualAD ifc);
	Reset mRst <- exposeCurrentReset;
	Reset sRst <- mkAsyncReset(1, mRst, sClk);

	let m <- mkDualADInternal(clocked_by sClk, reset_by sRst);

	return m;
endmodule