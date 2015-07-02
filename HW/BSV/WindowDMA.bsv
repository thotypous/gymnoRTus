import PAClib::*;
import FIFOF::*;
import GetPut::*;
import PipeUtils::*;
import OffsetSubtractor::*;
import WindowMaker::*;
import SysConfig::*;

interface WindowDMA;
	interface PipeOut#(PciDmaAddrData) dmaWriteReq;
endinterface

module [Module] mkWindowDMA#(PipeOut#(OutItem) winPipe) (WindowDMA);
	FIFOF#(PciDmaAddrData) dmaOut <- mkFIFOF;

	rule test;
		$display(winPipe.first);
		winPipe.deq;
	endrule

	interface PipeOut dmaWriteReq = f_FIFOF_to_PipeOut(dmaOut);
endmodule
