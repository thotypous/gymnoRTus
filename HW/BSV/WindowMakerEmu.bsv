import WindowMaker::*;
import PAClib::*;
import FIFOF::*;
import TieOff::*;
import GetPut::*;
import BUtils::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
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
	Reg#(LUInt#(NumEnabledChannels)) chIndex <- mkReg(0);

	WindowMaker wmaker <- mkWindowMaker(f_FIFOF_to_PipeOut(acqfifo));

	function ActionValue#(Sample) readSample = actionvalue
		Bit#(16) word = 0;
		for (Integer i = 0; i < getSizeOf(word)/8; i = i + 1) begin
			let c <- $fgetc(stdin);
			if (c == -1)
				$finish();
			Bit#(8) b = truncate(pack(c));
			word = zExtendLSB(b) | (word >> 8);
		end
		Sample sample = truncate(unpack(word));
		if (extend(sample) != unpack(word)) begin
			$display("Information loss in sample conversion during simulation!");
			$finish(1);
		end
		return sample;
	endactionvalue;

	rule feedSample;
		let sample <- readSample;
		acqfifo.enq(tuple2(enabledChannels[chIndex], sample));
		chIndex <= (chIndex + 1) % fromInteger(numEnabledChannels);
	endrule

	mkTieOff(wmaker.dmaReq);
endmodule
