import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import DualAD::*;
import OffsetSubtractor::*;
import SysConfig::*;

interface WindowMaker;
	interface Get#(PciDmaAddrData) dmaReq;
endinterface

module [Module] mkWindowMaker#(PipeOut#(DualAD::ChSample) acq) (WindowMaker);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;

	rule test;
		$display(fshow(acq.first));
		acq.deq;
	endrule

	interface dmaReq = toGet(dmaOut);
endmodule