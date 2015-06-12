import AvalonSlave::*;
import AvalonMaster::*;
import InterruptSender::*;
import DualAD::*;
import MockAD::*;
import ContinuousAcq::*;
import PipeUtils::*;
import SysConfig::*;
import Vector::*;
import Connectable::*;

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
	InterruptSender irqSender <- mkInterruptSender;

	DualAD adc <- mkDualAD(adsclk);
	MockAD adcMock <- mkMockAD;
	Reg#(Bool) arbMockPrio <- mkRegU;

	Reg#(Bool) adcMocked <- mkReg(False);
	PipeOut#(ChSample) adcMux = adcMocked ? adcMock.acq : adc.acq;

	ContinuousAcq continuousAcq <- mkContinuousAcq(adcMux);

	rule handleCmd;
		let cmd <- pcibar.busClient.request.get;
		(*split*)
		case (cmd.command)
		Write:
			(*split*)
			case (cmd.addr)
			0:
				action
					irqSender.resetCounter;
					continuousAcq.start(cmd.data);
				endaction
			1:
				action
					continuousAcq.stop;
				endaction
			2:
				action
					adcMocked <= True;
					adcMock.start(cmd.data);
				endaction
			3:
				action
					adcMocked <= False;
				endaction
			endcase
		Read:
			(*split*)
			case (cmd.addr)
			0:
				action
					let counter <- irqSender.ack;
					pcibar.busClient.response.put(counter);
				endaction
			2:
				action
					pcibar.busClient.response.put(adcMock.isBusy ? 1 : 0);
				endaction
			default:
				action
					pcibar.busClient.response.put(32'hBADC0FFE);
				endaction
			endcase
		endcase
	endrule

	rule arbMockRoundRobin;
		arbMockPrio <= !arbMockPrio;
	endrule
	let mockDmaTurn = adcMocked && arbMockPrio;

	rule continuousAcqDmaWrite (!mockDmaTurn);
		match {.addr, .data} <- continuousAcq.dmaReq.get;
		pcidma.busServer.request.put(AvalonRequest{
			command:Write,
			addr: addr,
			data: data
		});
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule continuousAcqIrq (continuousAcq.levelAlert);
		irqSender.send;
	endrule

	rule mockDmaRead (mockDmaTurn);
		let addr <- adcMock.dmaCli.request.get;
		pcidma.busServer.request.put(AvalonRequest{
			command: Read,
			addr: addr,
			data: ?
		});
	endrule

	mkConnection(pcidma.busServer.response, adcMock.dmaCli.response);

	interface irqWires = irqSender.wires;
	interface barWires = pcibar.slaveWires;
	interface dmaWires = pcidma.masterWires;
	interface adWires  = adc.wires;
	method Bit#(8) getLed = ~extend(1'b0);

endmodule
