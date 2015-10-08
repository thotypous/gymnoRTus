import PAClib::*;
import DistMinimizer::*;
import WindowDMA::*;
import LowpassHaar::*;
import GetPut::*;
import FIFOF::*;

module [Module] mkDistMinimizerSync#(PipeOut#(OutItem) inPipe, PipeOut#(WinDMASync) sync) (DistMinimizer);
	FIFOF#(Result) resultFifo <- mkFIFOF;
	FIFOF#(SpikesInWin) feedbackFifo <- mkFIFOF;
	(*hide*) let dmin <- mkDistMinimizer(inPipe);
	let syncResultPipe <- mkJoin(tuple2, sync, dmin.result);

	(* descending_urgency = "discardResult, feedbackFromFifo" *)
	rule feedbackFromFifo;
		let x <- toGet(feedbackFifo).get;
		dmin.feedback.put(x);
	endrule

	rule discardResult (tpl_1(syncResultPipe.first) == DiscardedWin);
		dmin.feedback.put(Both);  // arbitrary feedback
		syncResultPipe.deq;
	endrule

	(* fire_when_enabled *)
	rule acceptResult (tpl_1(syncResultPipe.first) == AcceptedWin);
		resultFifo.enq(tpl_2(syncResultPipe.first));
		syncResultPipe.deq;
	endrule

	interface result = f_FIFOF_to_PipeOut(resultFifo);
	interface feedback = toPut(feedbackFifo);
endmodule
