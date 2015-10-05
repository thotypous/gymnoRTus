QUARTUS_ROOTDIR ?= /opt/altera/14.1/quartus
BLUESPECHOME ?= /opt/bluespec/Bluespec-2014.07.A

BSCFLAGS=-check-assert \
	-aggressive-conditions \
	-steps-warn-interval 2000000 -steps-max-intervals 6000000 \
	+RTS -K33554432 -RTS \
	-opt-undetermined-vals -unspecified-to X \
	-suppress-warnings G0046
BSCLIBS=altsourceprobe

all: output_files/de4_pcie.sof

output_files/de4_pcie.sof: de4_pcie/synthesis/de4_pcie.qip de4_pcie.qsf
	$(QUARTUS_ROOTDIR)/bin/quartus_sh --flow compile de4_pcie

%.qsf: %.qsftpl
	sed 's,$${BLUESPECHOME},$(BLUESPECHOME),g' $< > $@

de4_pcie/synthesis/de4_pcie.qip: de4_pcie.qsys mkAvalonTop.v
	$(QUARTUS_ROOTDIR)/sopc_builder/bin/qsys-generate --synthesis=VERILOG $<

mkAvalonTop.v: $(wildcard BSV/*.bsv)
	bsc $(BSCFLAGS) -u -verilog -vdir . -bdir BSV -p $(BSCLIBS):+ BSV/AvalonTop.bsv

%.bsim: BSV/%.bsv $(wildcard BSV/*.bsv)
	bsc $(BSCFLAGS) -u -sim -simdir BSV -bdir BSV -p $(BSCLIBS):+ $<
	bsc -sim -o $@ -e mk$(basename $@) -simdir BSV -bdir BSV

clean:
	rm -f BSV/*.bo BSV/*.ba BSV/*.cxx BSV/*.h BSV/*.o
	rm -f *.bsim *.so mkAvalonTop.v
	rm -rf de4_pcie de4_pcie.sopcinfo
	rm -f de4_pcie.qsf de4_pcie.qpf
	rm -rf db incremental_db output_files
	rm -f PLLJ_PLLSPE_INFO.txt
	rm -f de4_pcie_assignment_defaults.qdf
