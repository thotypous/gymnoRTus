import PAClib::*;
import FIFOF::*;
import BUtils::*;
import StmtFSM::*;
import GetPut::*;
import ClientServer::*;
import FixedPoint::*;
import MultiCircularBuffer::*;
import Vector::*;
import DualAD::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import SysConfig::*;

typedef 16 CoefISize;
typedef 16 CoefFSize;
typedef FixedPoint#(CoefISize, CoefFSize) Coef;
typedef Coef FiltSample;
typedef Tuple2#(ChNum, FiltSample) ChFiltSample;

// Folded Linear Filter
// b: numerator
// a: denominator (excluding the first "1")
module [Module] mkFoldedLFilter#(
				Vector#(nb, Coef) b,
				Vector#(na, Coef) a,
				PipeOut#(OffsetSubtractor::ChSample) pipein
		) (PipeOut#(ChFiltSample))
		provisos (
			// make bsc happy
			Add#(a__, TLog#(nb), TLog#(TAdd#(nb, 1))),

			NumAlias#(TAdd#(na, 1), na1)
		);

	MultiCircularBuffer#(NumChannels, nb,  Sample) inbuf <- mkMultiCircularBuffer;
	MultiCircularBuffer#(NumChannels, na1, Coef)  outbuf <- mkMultiCircularBuffer;

	Reg#(ChNum) curChannel <- mkRegU;
	Array#(Reg#(FiltSample)) outSample <- mkCRegU(2);

	FIFOF#(Tuple2#(Coef, Coef)) multIn <- mkFIFOF;

	Reg#(LBit#(na)) i <- mkRegU;
	Reg#(LBit#(nb)) j <- mkRegU;

	FIFOF#(ChFiltSample) fifoOut <- mkFIFOF;

	rule multiply;
		match {.a, .b} <- toGet(multIn).get;
		outSample[0] <= outSample[0] + a*b;
	endrule

	function multCoef(circbuf, adapt, coef, isLast, nextOff) = action
		let inElem <- circbuf.query.response.get;
		multIn.enq(tuple2(coef, adapt(inElem)));
		if (!isLast)
			circbuf.query.request.put(tuple2(curChannel, truncate(nextOff)));
	endaction;

	function toCoef(sample);
		Int#(CoefISize) xs = extend(sample);
		return fromInt(xs);
	endfunction

	mkAutoFSM(seq
		while (True) seq
			action
				let ch = tpl_1(pipein.first);
				curChannel <= ch;
				outSample[1] <= 0;

				inbuf.head.put(pipein.first);
				pipein.deq;

				i <= 0;
				outbuf.query.request.put(tuple2(ch, 1));
			endaction

			while (i < fromInteger(valueOf(na))) action
				multCoef(outbuf, id, a[i], i == fromInteger(valueOf(na) - 1), i + 2);
				i <= i + 1;
			endaction

			action
				j <= 0;
				inbuf.query.request.put(tuple2(curChannel, 0));
			endaction

			while (j < fromInteger(valueOf(nb))) action
				multCoef(inbuf, toCoef, b[j], j == fromInteger(valueOf(nb) - 1), j + 1);
				j <= j + 1;
			endaction

			action
				await(!multIn.notEmpty);
				outbuf.head.put(tuple2(curChannel, outSample[0]));
				fifoOut.enq(tuple2(curChannel, outSample[0]));

				if (curChannel == lastEnabledChannel) begin
					inbuf.incHead;
					outbuf.incHead;
				end
			endaction
		endseq
	endseq);

	return f_FIFOF_to_PipeOut(fifoOut);
endmodule