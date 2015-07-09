import BRAM::*;

function BRAMRequest#(addr_t, data_t) makeReq(Bool write, addr_t addr, data_t data) =
		BRAMRequest{
			write: write,
			responseOnWrite: False,
			address: addr,
			datain: data
		};