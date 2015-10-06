import DistMinimizer::*;
import LowpassHaar::*;
import ChannelFilter::*;
import BUtils::*;
import PAClib::*;
import StmtFSM::*;
import FIFOF::*;
import GetPut::*;

(* synthesize *)
module mkDistMinimizerTb(Empty);
	FIFOF#(OutItem) fifo <- mkFIFOF;
	let dmin <- mkDistMinimizer(f_FIFOF_to_PipeOut(fifo));

	Reg#(LBit#(NumEnabledChannels)) ch <- mkReg(0);
	Reg#(Bit#(32)) i <- mkReg(0);
	Reg#(Bit#(32)) cycles <- mkReg(0);

	rule incCycles;
		cycles <= cycles + 1;
	endrule

	function dispResult = action
		let x <- toGet(dmin.result).get;
		$display("@", cycles, " -> ", fshow(x));
	endaction;

	function endMarker(sz) = action
		$display("@", cycles, " -> sent an EndMarker");
		fifo.enq(tagged EndMarker sz);
	endaction;

	Stmt gibberish = seq
		for (i <= 0; i < 1024; i <= i + 1)
			for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
				fifo.enq(tagged ChSample tuple2(enabledChannels[ch], unpack(truncate(i))));
	endseq;

	mkAutoFSM(
		seq
			gibberish;

			for (i <= 0; i < 30; i <= i + 1)
				for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
					fifo.enq(tagged ChSample tuple2(enabledChannels[ch], 0));
			for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
				fifo.enq(tagged ChSample tuple2(enabledChannels[ch], unpack(extend(ch) + 1)));
			endMarker(31);
			dispResult;
			dmin.feedback.put(OnlyA);

			gibberish;

			for (i <= 0; i < 15; i <= i + 1)
				for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
					fifo.enq(tagged ChSample tuple2(enabledChannels[ch], 0));
			for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
				fifo.enq(tagged ChSample tuple2(enabledChannels[ch], unpack(extend(ch) + 16)));
			endMarker(16);
			dispResult;
			dmin.feedback.put(OnlyB);

			gibberish;

			for (i <= 0; i < 2; i <= i + 1)
				for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
					fifo.enq(tagged ChSample tuple2(enabledChannels[ch], 0));
			for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
				fifo.enq(tagged ChSample tuple2(enabledChannels[ch], unpack(extend(ch) + 16)));
			for (ch <= 0; ch < fromInteger(numEnabledChannels); ch <= ch + 1)
				fifo.enq(tagged ChSample tuple2(enabledChannels[ch], unpack(extend(ch) + 1)));
			endMarker(4);
			dispResult;
			dmin.feedback.put(Both);
		endseq);
endmodule
