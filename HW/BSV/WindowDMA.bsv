import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import WindowMaker::*;
import SysConfig::*;

interface WindowDMA;
	interface Get#(PciDmaAddrData) dmaReq;
endinterface

module [Module] mkWindowDMA#(PipeOut#(OutItem) winPipe) (WindowDMA);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;

	rule test;
		$display(winPipe.first);
		winPipe.deq;
	endrule

	interface Get dmaReq = toGet(dmaOut);
endmodule
