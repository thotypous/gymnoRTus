import PAClib::*;
import FIFOF::*;
import BRAMFIFO::*;
import BUtils::*;
import ChannelFilter::*;
import OffsetSubtractor::*;
import Connectable::*;
import PipeUtils::*;
import GetPut::*;
import SysConfig::*;

module [Module] mkStreamDelayer#(Bit#(stages) dummy, PipeOut#(ChSample) pipein) (PipeOut#(ChSample));
	FIFOF#(ChSample) fifoIn <- mkSizedBRAMFIFOF(numEnabledChannels * valueOf(stages));

	Reg#(LUInt#(stages)) countdown <- mkReg(fromInteger(valueOf(stages)));
	Reg#(UInt#(TLog#(NumEnabledChannels))) i <- mkReg(0);

	FIFOF#(ChSample) fifoFilling <- mkFIFOF;

	mkConnection(toGet(pipein), toPut(fifoIn));

	rule genFilling (countdown != 0);
		fifoFilling.enq(tuple2(enabledChannelsArray[i], 0));

		if (i == fromInteger(numEnabledChannels - 1)) begin
			countdown <= countdown - 1;
			i <= 0;
		end else begin
			i <= i + 1;
		end
	endrule

	(*hide*) let m <- mkPipeMux(countdown != 0 || fifoFilling.notEmpty,
			f_FIFOF_to_PipeOut(fifoFilling),
			f_FIFOF_to_PipeOut(fifoIn));
	return m;
endmodule
