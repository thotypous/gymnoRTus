import LowpassHaar::*;
import WindowMaker::*;
import ChannelFilter::*;
import PAClib::*;
import StmtFSM::*;
import FIFOF::*;

(*synthesize*)
module [Module] mkLowpassHaarTb(Empty);
	FIFOF#(WindowMaker::OutItem) fifo <- mkFIFOF;
	let lp <- mkLowpassHaar(f_FIFOF_to_PipeOut(fifo));

	mkAutoFSM(
		seq
			fifo.enq(tagged ChSample tuple2(0, 4));
			fifo.enq(tagged ChSample tuple2(1, 8));
			fifo.enq(tagged ChSample tuple2(lastEnabledChannel, 7));
			fifo.enq(tagged ChSample tuple2(0, 10));
			fifo.enq(tagged ChSample tuple2(1, 4));
			fifo.enq(tagged ChSample tuple2(lastEnabledChannel, 3));
			fifo.enq(tagged EndMarker WindowInfo {timestamp: 100, size: 2, reference: 1});
			delay(50);
		endseq);

	function dfshow(x) = $display(fshow(x));
	mkSink_to_fa(dfshow, lp);
endmodule
