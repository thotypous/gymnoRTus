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
import Connectable::*;
import DistMinimizer::*;
import LowpassHaar::*;

(*synthesize*)
module [Module] mkDistMinEmu(Empty);
	FIFOF#(ChSample) acqfifo <- mkFIFOF;
	Reg#(LUInt#(NumEnabledChannels)) chIndex <- mkReg(0);

	Reg#(Bit#(32)) i <- mkReg(0);
	FIFOF#(SpikesInWin) fdbkFifo <- mkFIFOF;

	let wmaker <- mkWindowMaker(f_FIFOF_to_PipeOut(acqfifo));

	let winFork <- mkFork(duplicate, wmaker.out);
	let winPipe  = tpl_1(winFork);
	let winHaar <- mkLowpassHaar(tpl_2(winFork));
	let distMin <- mkDistMinimizer(winHaar);

	mkConnection(toGet(fdbkFifo), distMin.feedback);

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

	rule makeFeedback (winPipe.first matches tagged EndMarker .wininfo);
		winPipe.deq;
		SpikesInWin curFdbk = i == 0 ? OnlyA : i == 1 ? OnlyB : Both;
		fdbkFifo.enq(curFdbk);
		$display("curFdbk: ", fshow(curFdbk));
		i <= i + 1;
	endrule

	rule consumeSample (winPipe.first matches tagged ChSample .*);
		winPipe.deq;
	endrule

	rule showResult;
		let x <- toGet(distMin.result).get;
		$display(fshow(x));
	endrule
endmodule
