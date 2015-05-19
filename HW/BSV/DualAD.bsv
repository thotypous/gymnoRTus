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
endinterface

module mkDualAD(Clock adsclk, DualAD ifc);
	interface DualADWires wires;
		method Bit#(1) getData = 0;
		method Action putStrobe0 = noAction;
		method Action putStrobe1 = noAction;
		method Action putData0(v) = noAction;
		method Action putData1(v) = noAction;
	endinterface
endmodule