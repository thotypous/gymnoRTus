## Generated SDC file "de4_pcie.sdc"

## Copyright (C) 1991-2015 Altera Corporation. All rights reserved.
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, the Altera Quartus II License Agreement,
## the Altera MegaCore Function License Agreement, or other 
## applicable license agreement, including, without limitation, 
## that your use is for the sole purpose of programming logic 
## devices manufactured by Altera and sold by Altera or its 
## authorized distributors.  Please refer to the applicable 
## agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 15.0.0 Build 145 04/22/2015 SJ Full Version"

## DATE    "Fri May  8 16:01:17 2015"

##
## DEVICE  "EP4SGX230KF40C2"
##


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


#**************************************************************
# Create Generated Clock
#**************************************************************



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


#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -setup -end -from [get_keepers {*tl_cfg_ctl_wr*}] 2
set_multicycle_path -hold -end -from [get_keepers {*tl_cfg_ctl_wr*}] 1
set_multicycle_path -setup -end -from [get_keepers {*tl_cfg_ctl[*]}] 3
set_multicycle_path -hold -end -from [get_keepers {*tl_cfg_ctl[*]}] 2


#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

