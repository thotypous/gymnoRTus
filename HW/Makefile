QUARTUS_ROOTDIR ?= /opt/altera/14.1/quartus
BLUESPECHOME ?= /opt/bluespec/Bluespec-2014.07.A

BSCFLAGS=-no-lift -aggressive-conditions -opt-undetermined-vals -unspecified-to X

all: output_files/de4_pcie.sof

output_files/de4_pcie.sof: de4_pcie/synthesis/de4_pcie.qip de4_pcie.qsf
	$(QUARTUS_ROOTDIR)/bin/quartus_sh --flow compile de4_pcie

%.qsf: %.qsftpl
	sed 's,$${BLUESPECHOME},$(BLUESPECHOME),g' $< > $@

de4_pcie/synthesis/de4_pcie.qip: de4_pcie.qsys mkAvalonTop.v
	$(QUARTUS_ROOTDIR)/sopc_builder/bin/qsys-generate --synthesis=VERILOG $<

mkAvalonTop.v: $(wildcard BSV/*.bsv)
	bsc $(BSCFLAGS) -u -verilog -vdir . -bdir BSV  BSV/AvalonTop.bsv

clean:
	rm -f BSV/*.bo mkAvalonTop.v
	rm -rf de4_pcie de4_pcie.sopcinfo
	rm -f de4_pcie.qsf
	rm -rf db incremental_db output_files
	rm -f PLLJ_PLLSPE_INFO.txt
	rm -f de4_pcie_assignment_defaults.qdf
