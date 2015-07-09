import PAClib::*;
import FIFOF::*;
import GetPut::*;
import FixedPoint::*;
import MultiCircularBuffer::*;
import Vector::*;
import DualAD::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import SysConfig::*;

typedef FixedPoint#(16,16) Coef;
typedef Coef FiltSample;
typedef Tuple2#(ChNum, FiltSample) ChFiltSample;

// Folded Linear Filter
// b: numerator
// a: denominator (excluding the first "1")
module [Module] mkFoldedLFilter#(
				Vector#(nb, Coef) b,
				Vector#(na, Coef) a,
				PipeOut#(OffsetSubtractor::ChSample) pipein
		) (PipeOut#(ChFiltSample));


endmodule