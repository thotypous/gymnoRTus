import PAClib::*;
export PAClib::*;
import GetPut::*;
import Connectable::*;
import Clocks::*;
import Reserved::*;
import Vector::*;
import PipeUtils::*;

export DualAD(..);
export DualADWires(..);
export Sample(..);
export ChNum(..);
export ChSel(..);
export ChSample(..);
export mkDualAD;

typedef Bit#(12) Sample;
typedef Bit#(4) ChNum;
typedef Bit#(3) ChSel;
typedef Bit#(8) Byte;

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

typedef Tuple2#(ChNum, Sample) ChSample;

// External interface
interface DualAD;
	interface DualADWires wires;
	interface PipeOut#(ChSample) acq;
endinterface

// Internal interface (before clock domain conversion)
typedef Tuple2#(ChSel, Vector#(2, Sample)) InternalTuple;
interface DualADInternal;
	interface DualADWires wires;
	interface Get#(InternalTuple) acq;
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
	ChSel sel;
	UniBip unibip;
	SglDif sgldif;
	OperatingMode opmode;
} ControlByte deriving (Eq, Bits);

function Byte makeControlByte(ChSel sel);
	ControlByte ctrl;
	ctrl.sel = sel;
	ctrl.unibip = Unipolar;
	ctrl.sgldif = SingleEnded;
	ctrl.opmode = NormalOperation;
	return pack(ctrl);
endfunction

module mkDualADInternal(DualADInternal);
	// State machine counter
	Array#(Reg#(Bit#(4))) cnt <- mkCReg(3, 0);

	// I/O related
	Reg#(Bit#(1)) din <- mkReg(0);
	Wire#(Bit#(1)) dout0 <- mkBypassWire;
	Wire#(Bit#(1)) dout1 <- mkBypassWire;
	Reg#(Sample) shiftReg0 <- mkRegU;
	Reg#(Sample) shiftReg1 <- mkRegU;

	// Channel and control byte
	Reg#(ChSel) ch <- mkReg(0);
	Reg#(Byte) ctrl <- mkReg(makeControlByte(0));

	// Number of the cycle during which the SSTRB pulse should occur.
	// See MAX1280 datasheet p. 13, Figure 6
	let cycleAfterStrobe = 4'd10;

	// Adjusts the value above considering that there will be an output
	// delay of 2 cycles because of writes to the cnt and din registers.
	let cycleAfterStrobeAdjusted = cycleAfterStrobe + 4'd2;

	(* no_implicit_conditions, fire_when_enabled *)
	rule dinFeed;
		(*split*)
		if (cnt[0] < 8) begin
			// Time to send a bit of the control byte
			din <= ctrl[7];
			ctrl <= ctrl << 1;
		end else begin
			// Time to be quiet
			din <= 0;

			if (cnt[0] == 4'b1111) begin
				// Construct the next control byte
				let nextChannel = ch + 1;
				ctrl <= makeControlByte(nextChannel);
				ch <= nextChannel;
			end
		end
		cnt[0] <= cnt[0] + 1;
	endrule

	let doutBit = cnt[0] - cycleAfterStrobeAdjusted;

	(* no_implicit_conditions, fire_when_enabled *)
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
		method ActionValue#(InternalTuple) get if (doutBit == 12);
			// At the end of the conversion, ch will already be incremented.
			// See MAX1280 datasheet p. 16, Figure 8
			Sample arr[2] = { shiftReg0, shiftReg1 };
			return tuple2(ch - 1, arrayToVector(arr));
		endmethod
	endinterface
endmodule

module [Module] mkDualAD(Clock sClk, DualAD ifc);
	Reset sRst <- mkAsyncResetFromCR(2, sClk);
	(*hide*) let m <- mkDualADInternal(clocked_by sClk, reset_by sRst);

	SyncFIFOIfc#(InternalTuple) sync <- mkSyncFIFOToCC(2, sClk, sRst);
	// Be warned that samples will be discarded if no space is left in the FIFO
	mkConnection(m.acq, toPut(sync));

	function makeFunnelInput(tuple);
		match {.chsel, .samples} = tuple;
		function copyChSel(sample) = tuple2(chsel, sample);
		return Vector::map(copyChSel, samples);
	endfunction

	PipeOut#( Vector#(1, Tuple2#(Tuple2#(ChSel, Sample), UInt#(1)) ) )
			funnelOutput <- mkCompose(
					mkFn_to_Pipe(makeFunnelInput),
					PipeUtils::mkFunnel_Indexed,
					f_SyncFIFOIfc_to_PipeOut(sync));

	function makeToAcq(vec);
		match {{.chsel, .sample}, .index} = vec[0];
		return tuple2({pack(index), chsel}, sample);
	endfunction

	let toAcq <- mkFn_to_Pipe(makeToAcq, funnelOutput);

	interface wires = m.wires;
	interface acq = toAcq;
endmodule
