import PAClib::*;
import PipeUtils::*;
import DualAD::*;
import Vector::*;

// Choose which AD channels will be used by the fish-related signal processing pipe
// i.e. which channels are plugged to aquarium electrodes
typedef 7 NumEnabledChannels;
Integer numEnabledChannels = valueOf(NumEnabledChannels);
ChNum enabledChannelsArray[numEnabledChannels] = {
	4'b0000,
	4'b1000,
	4'b0001,
	4'b1001,
	4'b0010,
	4'b1010,
	4'b0011
};

Vector#(NumEnabledChannels, ChNum) enabledChannels = arrayToVector(enabledChannelsArray);

module mkChannelFilter#(PipeOut#(ChSample) acq) (PipeOut#(ChSample));
	function Bool filterFunc(ChSample chsample);
		return isValid(Vector::findElem(tpl_1(chsample), enabledChannels));
	endfunction

	(*hide*) let m <- mkPipeFilter(filterFunc, acq);
	return m;
endmodule