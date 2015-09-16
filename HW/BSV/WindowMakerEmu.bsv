import WindowMaker::*;
import WindowDMABuffer::*;
import PAClib::*;
import FIFOF::*;
import GetPut::*;
import Assert::*;
import BUtils::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import SysConfig::*;

(*synthesize*)
module [Module] mkWindowMakerEmu(Empty);
	FIFOF#(ChSample) acqfifo <- mkFIFOF;
	Reg#(LUInt#(NumEnabledChannels)) chIndex <- mkReg(0);

	let wmaker <- mkWindowMaker(f_FIFOF_to_PipeOut(acqfifo));
	let wbuf <- mkWindowDMABuffer(wmaker);

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
		dynamicAssert(extend(sample) == unpack(word), "Information loss in sample conversion during simulation!");
		return sample;
	endactionvalue;

	rule feedSample;
		let sample <- readSample;
		acqfifo.enq(tuple2(enabledChannels[chIndex], sample));
		chIndex <= (chIndex + 1) % fromInteger(numEnabledChannels);
	endrule

	rule showBufOut;
		let bufout <- toGet(wbuf).get;
		$display(fshow(bufout));
	endrule
endmodule
