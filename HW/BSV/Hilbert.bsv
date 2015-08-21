import PAClib::*;
import FIFOF::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;
import Assert::*;
import BUtils::*;
import PipeUtils::*;
import FixedPoint::*;
import OffsetSubtractor::*;
import StreamDelayer::*;
import LFilter::*;
import SquareRoot::*;
import SysConfig::*;

typedef Tuple2#(ChNum, UInt#(CoefISize)) ChHilbSample;

module [Module] mkHilbert#(PipeOut#(ChSample) pipein) (PipeOut#(ChHilbSample));
	Real arrB[5] = {-0.127838238013738, -0.122122430298337, -0.207240989159078, -0.741109041690890,  1.329553577868309};
	Real arrA[4] = {-0.445897866413142, -0.101209607292324, -0.047938888781208, -0.037189007185997};

	Vector#(5, Coef) b = Vector::map(fromReal, arrayToVector(arrB));
	Vector#(4, Coef) a = Vector::map(fromReal, arrayToVector(arrA));

	let inFork <- mkFork(duplicate, pipein);
	let pipeReal <- mkStreamDelayer(4'd0, tpl_2(inFork));
	let pipeImagFxpt <- mkFoldedLFilter(b, a, tpl_1(inFork));

	function transform_2(f, tup) = tuple2(tpl_1(tup), f(tpl_2(tup)));
	function Int#(ri) fxptRound(FixedPoint#(ri,rf) x);
		FixedPoint#(ri,0) rounded = fxptTruncateRound(Rnd_Plus_Inf, x);
		return fxptGetInt(rounded);
	endfunction
	let pipeImag <- mkFn_to_Pipe(transform_2(fxptRound), pipeImagFxpt);

	function signedSquare(x) = signedMul(x, x);
	let pipeImagSq <- mkFn_to_Pipe_Buffered(False, transform_2(signedSquare), True, pipeImag);
	let pipeRealSq <- mkFn_to_Pipe_Buffered(False, transform_2(signedSquare), True, pipeReal);
	let pipeImagRealSq <- mkJoin(tuple2, pipeImagSq, pipeRealSq);

	let pipeHilbSq <- mkSource_from_fav(actionvalue
		match {{.ci, .i}, {.cr, .r}} <- toGet(pipeImagRealSq).get;
		dynamicAssert(ci == cr, "Hilbert imaginary part unsynced from the real part");
		UInt#(TMul#(2, CoefISize)) res = cExtend(i + extend(r));
		return tuple2(ci, res);
	endactionvalue);

	let pipeHilb <- mkPipeTransform_2(mkPipeSqrt(1), 16, pipeHilbSq);
	return pipeHilb;
endmodule


module [Module] mkPipeSqrt#(Integer n, PipeOut#(UInt#(m)) pipein)
		(PipeOut#(UInt#(TDiv#(m,2))))
		provisos (
			// make bsc happy
			Add#(a__, 2, m),
			Add#(b__, TDiv#(m, 2), m),
			Log#(TAdd#(1, m), TLog#(TAdd#(m, 1)))
		);
	Server#(UInt#(m),Tuple2#(UInt#(m),Bool)) sqrt <- mkSquareRooter(n);
	FIFOF#(UInt#(TDiv#(m, 2))) fifoOut <- mkLFIFOF;

	rule putRequest;
		let req <- toGet(pipein).get;
		sqrt.request.put(req);
	endrule
	rule getResponse;
		let resp <- sqrt.response.get;
		fifoOut.enq(truncate(tpl_1(resp)));
	endrule
	return f_FIFOF_to_PipeOut(fifoOut);
endmodule