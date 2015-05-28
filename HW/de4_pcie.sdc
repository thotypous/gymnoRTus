#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3


#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {alt_cal_edge_detect_ff0_clk} -period 20.000 -waveform { 0.000 10.000 } [get_pins -compatibility_mode {*|*pd*_det|alt_edge_det_ff0|clk}]
create_clock -name {alt_cal_edge_detect_ff0q_clk} -period 20.000 -waveform { 0.000 10.000 } [get_pins -compatibility_mode {*|*pd*_det|alt_edge_det_ff0|q}]
create_clock -name {alt_cal_edge_detect_ff1_clk} -period 20.000 -waveform { 0.000 10.000 } [get_pins -compatibility_mode {*|*pd*_det|alt_edge_det_ff1|clk}]
create_clock -name {alt_cal_edge_detect_ff1q_clk} -period 20.000 -waveform { 0.000 10.000 } [get_pins -compatibility_mode {*|*pd*_det|alt_edge_det_ff1|q}]
create_clock -name {OSC_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {OSC_50_*}]
create_clock -period "100 MHz" -name {refclk_pci_express} [get_ports {PCIE_REFCLK_p}]


#**************************************************************
# Create Generated Clock
#**************************************************************

derive_pll_clocks -create_base_clocks


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {OSC_50}] -rise_to [get_clocks {OSC_50}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {OSC_50}] -fall_to [get_clocks {OSC_50}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {OSC_50}] -rise_to [get_clocks {OSC_50}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {OSC_50}] -fall_to [get_clocks {OSC_50}]  0.060  

derive_clock_uncertainty


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff0_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff0q_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff1_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff1q_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff0_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff0q_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff1_clk}] 
set_clock_groups -asynchronous -group [get_clocks {alt_cal_edge_detect_ff1q_clk}] 
set_clock_groups -exclusive -group [get_clocks { *central_clk_div0* }] -group [get_clocks { *_hssi_pcie_hip* }] 
set_clock_groups -exclusive -group [get_clocks { *central_clk_div0* }] -group [get_clocks { *_hssi_pcie_hip* }] 


#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_cells -compatibility_mode {*|alt_cal_channel[*]}] 
set_false_path -from [get_cells -compatibility_mode {*|alt_cal_busy}] 
set_false_path -from [get_registers {*altera_avalon_st_clock_crosser:*|in_data_buffer*}] -to [get_registers {*altera_avalon_st_clock_crosser:*|out_data_buffer*}]
set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
set_false_path -to [get_pins -nocase -compatibility_mode {*|alt_rst_sync_uq1|altera_reset_synchronizer_int_chain*|clrn}]
set_false_path -to [get_keepers {*tx_digitalreset_reg0c[0]}]
set_false_path -to [get_keepers {*rx_digitalreset_reg0c[0]}]

# Bluespec SyncFIFO synchronizers
set_false_path -from [get_keepers {*|SyncFIFO:*|dGDeqPtr*}] -to [get_keepers {*|SyncFIFO:*|sSyncReg*}]
set_false_path -from [get_keepers {*|SyncFIFO:*|sGEnqPtr*}] -to [get_keepers {*|SyncFIFO:*|dSyncReg*}]
set_false_path -from [get_keepers {*|SyncFIFO:*|fifoMem*}] -to [get_keepers {*|SyncFIFO:*|dDoutReg*}]

# Bluespec SyncResetA synchronizers
set_false_path -to [get_keepers {*|SyncResetA:*|reset_hold*}]
set_false_path -from [get_keepers {*|SyncResetA:*|reset_hold*}]


#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -setup -end -from [get_keepers {*tl_cfg_ctl_wr*}] 2
set_multicycle_path -hold -end -from [get_keepers {*tl_cfg_ctl_wr*}] 1
set_multicycle_path -setup -end -from [get_keepers {*tl_cfg_ctl[*]}] 3
set_multicycle_path -hold -end -from [get_keepers {*tl_cfg_ctl[*]}] 2


#**************************************************************
# tsu/th constraints
#**************************************************************

set AD_SCLK [get_clocks {u0|altpll_0|sd1|pll7|clk[0]}]

set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -max 86.25ns [get_ports {AD_DOUT0}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -min 8.000ns [get_ports {AD_DOUT0}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -max 86.25ns [get_ports {AD_DOUT1}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -min 8.000ns [get_ports {AD_DOUT1}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -max 86.25ns [get_ports {AD_SSTRB0}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -min 8.000ns [get_ports {AD_SSTRB0}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -max 86.25ns [get_ports {AD_SSTRB1}]
set_input_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -min 8.000ns [get_ports {AD_SSTRB1}]


#**************************************************************
# tco constraints
#**************************************************************

set_output_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -max 41.25ns [get_ports {AD_DIN}]
set_output_delay -clock $AD_SCLK -reference_pin [get_ports {AD_SCLK}] -min -8.000ns [get_ports {AD_DIN}]
set_false_path -to [get_ports {AD_SCLK}]

set_false_path -to [get_ports {LED[*]}]
set_false_path -from [get_ports {PCIE_PREST_n}]
