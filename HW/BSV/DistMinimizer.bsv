import PAClib::*;
import FIFOF::*;
import LowpassHaar::*;
import SysConfig::*;

interface DistMinimizer;
endinterface

module [Module] mkDistMinimizer#(PipeOut#(OutItem) winPipe) (DistMinimizer);
	mkSink(winPipe);
endmodule
