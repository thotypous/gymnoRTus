module de4_pcie_top(
        input OSC_50_BANK2,

        input PCIE_PREST_n,
        input PCIE_REFCLK_p,
        input [3:0] PCIE_RX_p,
        output [3:0] PCIE_TX_p,

        output [7:0] LED,
        output [1:0] DIGITAL_OUT,

        input AD_DOUT0,
        input AD_SSTRB0,
        input AD_DOUT1,
        input AD_SSTRB1,
        output AD_DIN,
        output AD_SCLK
);

    wire [16:0] pcie_reconfig_fromgxb_0_data;
    wire [ 3:0] pcie_reconfig_togxb_data;

    altgx_reconfig gxreconf0 (
        .reconfig_clk(OSC_50_BANK2),
        .reconfig_fromgxb(pcie_reconfig_fromgxb_0_data),
        .reconfig_togxb(pcie_reconfig_togxb_data)
    );

    de4_pcie u0 (
        .clk_clk                                 (OSC_50_BANK2),
        .reset_reset_n                           (1'b1),

        .pcie_pcie_rstn_export                   (PCIE_PREST_n),
        .pcie_refclk_export                      (PCIE_REFCLK_p),
        .pcie_rx_in_rx_datain_0                  (PCIE_RX_p[0]),
        .pcie_rx_in_rx_datain_1                  (PCIE_RX_p[1]),
        .pcie_rx_in_rx_datain_2                  (PCIE_RX_p[2]),
        .pcie_rx_in_rx_datain_3                  (PCIE_RX_p[3]),
        .pcie_tx_out_tx_dataout_0                (PCIE_TX_p[0]),
        .pcie_tx_out_tx_dataout_1                (PCIE_TX_p[1]),
        .pcie_tx_out_tx_dataout_2                (PCIE_TX_p[2]),
        .pcie_tx_out_tx_dataout_3                (PCIE_TX_p[3]),

        .adc_ad_dout0                            (AD_DOUT0),
        .adc_ad_sstrb0                           (AD_SSTRB0),
        .adc_ad_dout1                            (AD_DOUT1),
        .adc_ad_sstrb1                           (AD_SSTRB1),
        .adc_ad_din                              (AD_DIN),
        .adc_ad_sclk_clk                         (AD_SCLK),

        .led_led                                 (LED),
        .digital_out_digital_out                 (DIGITAL_OUT),

        .pcie_reconfig_gxbclk_clk                (OSC_50_BANK2),
        .pcie_reconfig_fromgxb_0_data            (pcie_reconfig_fromgxb_0_data),
        .pcie_reconfig_togxb_data                (pcie_reconfig_togxb_data),
    );

endmodule
