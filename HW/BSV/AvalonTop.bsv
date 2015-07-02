import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;
import MockAD::*;
import ContinuousAcq::*;
import OffsetSubtractor::*;
import ChannelFilter::*;
import WindowMaker::*;
import WindowDMA::*;
import PipeUtils::*;
import MonadUtils::*;
import SysConfig::*;
import Vector::*;
import Connectable::*;
import Arbiter::*;

typedef AvalonRequest#(PciDmaAddrSize, PciDmaDataSize) DmaReq;

interface AvalonTop;
	(* prefix="" *)
	interface InterruptSenderWires irqWires;
	(* prefix="" *)
	interface AvalonSlaveWires#(PciBarAddrSize, PciBarDataSize) barWires;
	(* prefix="dma" *)
	interface AvalonMasterWires#(PciDmaAddrSize, PciDmaDataSize) dmaWires;
	(* prefix="" *)
	interface DualADWires adWires;
	(* always_ready, result="LED" *)
	method Bit#(8) getLed;
endinterface

(* synthesize, clock_prefix="clk", reset_prefix="reset_n" *)
module [Module] mkAvalonTop(Clock adsclk, Clock slowclk, AvalonTop ifc);

	AvalonSlave#(PciBarAddrSize, PciBarDataSize) pcibar <- mkAvalonSlave;
	AvalonMaster#(PciDmaAddrSize, PciDmaDataSize) pcidma <- mkAvalonMaster;
	InterruptSender#(2) irqSender <- mkInterruptSender;


	DualAD adc <- mkDualAD(adsclk);
	MockAD adcMock <- mkMockAD;

	Reg#(Bool) adcMocked <- mkReg(False);
	let adcMux <- mkPipeMux(adcMocked, adcMock.acq, adc.acq);
	let adcFork <- mkFork(duplicate, adcMux);

	ContinuousAcq continuousAcq <- mkContinuousAcq(tpl_1(adcFork), irqSender.irq[0]);

	let filteredPipe <- mkChannelFilter(tpl_2(adcFork));
	OffsetSubtractor offsetSub <- mkOffsetSubtractor(filteredPipe);
	let winPipe <- mkWindowMaker(offsetSub.out);
	WindowDMA winDma <- mkWindowDMA(winPipe, irqSender.irq[1]);


	function avalonWriteReq(req) = AvalonRequest{
		command: Write,
		addr: tpl_1(req),
		data: tpl_2(req)
	};

	function avalonReadReq(req) = AvalonRequest{
		command: Read,
		addr: req,
		data: ?
	};

	Module#(PipeOut#(DmaReq)) dmaReqArr[3] = {
		// Read request source: there should be only one, since we
		// did not implement an "origin of pending request" FIFO
		mkFn_to_Pipe(avalonReadReq, adcMock.dmaReadReq),

		// Write request sources
		mkFn_to_Pipe(avalonWriteReq, continuousAcq.dmaWriteReq),
		mkFn_to_Pipe(avalonWriteReq, winDma.dmaWriteReq)
	};

	Vector#(3, PipeOut#(DmaReq)) dmaReqVec <- mkVec(arrayToVector(dmaReqArr));
	let dmaReqArb <- mkPipeArbiter(mkArbiter(False), dmaReqVec);


	rule handleCmd;
		let cmd <- pcibar.busClient.request.get;
		(*split*)
		case (cmd.command)
		Write:
			(*split*)
			case (cmd.addr) matches
			14'd0:
				action
					irqSender.resetCounter[0].send;
					continuousAcq.start(cmd.data);
				endaction
			14'd1:
				action
					continuousAcq.stop;
				endaction
			14'd2:
				action
					adcMocked <= True;
					adcMock.start(cmd.data);
				endaction
			14'd3:
				action
					adcMocked <= cmd.data != 0;
				endaction
			14'd4:
				action
					irqSender.resetCounter[1].send;
					// TODO: start winDma here
				endaction
			14'h1?:
				action
					offsetSub.setOffset(cmd.addr[3:0], truncate(cmd.data));
				endaction
			endcase
		Read:
			(*split*)
			case (cmd.addr) matches
			14'd0:
				action
					let counter <- irqSender.ack[0].get;
					pcibar.busClient.response.put(counter);
				endaction
			14'd2:
				action
					pcibar.busClient.response.put(adcMock.isBusy ? 1 : 0);
				endaction
			14'd4:
				action
					let counter <- irqSender.ack[1].get;
					pcibar.busClient.response.put(counter);
				endaction
			default:
				action
					pcibar.busClient.response.put(32'hBADC0FFE);
				endaction
			endcase
		endcase
	endrule

	mkConnection(pcidma.busServer.request, toGet(dmaReqArb));
	mkConnection(pcidma.busServer.response, adcMock.dmaReadResp);


	interface irqWires = irqSender.wires;
	interface barWires = pcibar.slaveWires;
	interface dmaWires = pcidma.masterWires;
	interface adWires  = adc.wires;

	method Bit#(8) getLed = ~extend({
		pack(continuousAcq.isSyncing),
		pack(continuousAcq.isRunning),
		pack(adcMock.isBusy),
		pack(adcMocked)
	});

endmodule
