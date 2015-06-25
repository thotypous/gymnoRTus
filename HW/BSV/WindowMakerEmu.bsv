import WindowMaker::*;
import PAClib::*;
import FIFOF::*;
import TieOff::*;
import GetPut::*;
import PipeUtils::*;
import DualAD::*;
import SysConfig::*;

export GetPut::*; // silences nonsense T0127 warning

instance TieOff#(Get#(t))
		provisos (Bits#(t,st), FShow#(t));
	module mkTieOff#(Get#(t) ifc) (Empty);
		rule getSink (True);
			t val <- ifc.get;
			$display("Get tieoff %m", fshow(val));
		endrule
	endmodule
endinstance

(*synthesize*)
module [Module] mkWindowMakerEmu(Empty);
	FIFOF#(ChSample) acqfifo <- mkFIFOF;
	WindowMaker wmaker <- mkWindowMaker(f_FIFOF_to_PipeOut(acqfifo));

	mkTieOff(wmaker.dmaReq);
endmodule