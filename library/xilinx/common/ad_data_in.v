// ***************************************************************************
// ***************************************************************************
// Copyright 2014 - 2022 (c) Analog Devices, Inc. All rights reserved.
//
// In this HDL repository, there are many different and unique modules, consisting
// of various HDL (Verilog or VHDL) components. The individual modules are
// developed independently, and may be accompanied by separate and unique license
// terms.
//
// The user should read each of these license terms, and understand the
// freedoms and responsibilities that he or she has by using this source/core.
//
// This core is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE.
//
// Redistribution and use of source or resulting binaries, with or without modification
// of this file, are permitted under one of the following two license terms:
//
//   1. The GNU General Public License version 2 as published by the
//      Free Software Foundation, which can be found in the top level directory
//      of this repository (LICENSE_GPL2), and also online at:
//      <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
//
// OR
//
//   2. An ADI specific BSD license, which can be found in the top level directory
//      of this repository (LICENSE_ADIBSD), and also on-line at:
//      https://github.com/analogdevicesinc/hdl/blob/master/LICENSE_ADIBSD
//      This will allow to generate bit files and not release the source code,
//      as long as it attaches to an ADI device.
//
// ***************************************************************************
// ***************************************************************************

`timescale 1ns/100ps

module ad_data_in #(

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   SINGLE_ENDED = 0,
  parameter   IDDR_CLK_EDGE = "SAME_EDGE",
  // for 7 series devices
  parameter   IDELAY_TYPE = "VAR_LOAD",
  // for ultrascale devices
  parameter   DELAY_FORMAT = "COUNT",
  parameter   US_DELAY_TYPE = "VAR_LOAD",
  // for all
  parameter   IODELAY_ENABLE = 1,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // data interface

  input               rx_clk,
  input               rx_data_in_p,
  input               rx_data_in_n,
  output              rx_data_p,
  output              rx_data_n,

  // delay-data interface

  input               up_clk,
  input               up_dld,
  input       [ 4:0]  up_dwdata,
  output      [ 4:0]  up_drdata,

  // delay-cntrl interface

  input               delay_clk,
  input               delay_rst,
  output              delay_locked
);

  // internal parameters

  localparam NONE = -1;
  localparam SEVEN_SERIES = 1;
  localparam ULTRASCALE = 2;
  localparam ULTRASCALE_PLUS = 3;

  // do not instantiate an IDELAYCTRL if no IDELAY is wanted
  localparam IODELAY_CTRL_ENABLED = (IODELAY_ENABLE == 1) ? IODELAY_CTRL : 0;
  localparam IODELAY_CTRL_SIM_DEVICE = (FPGA_TECHNOLOGY == ULTRASCALE_PLUS) ? "ULTRASCALE" :
    (FPGA_TECHNOLOGY == ULTRASCALE) ? "ULTRASCALE" : "7SERIES";

  localparam IODELAY_FPGA_TECHNOLOGY = (IODELAY_ENABLE == 1) ? FPGA_TECHNOLOGY : NONE;
  localparam IODELAY_SIM_DEVICE = (FPGA_TECHNOLOGY == ULTRASCALE_PLUS) ? "ULTRASCALE_PLUS" :
    (FPGA_TECHNOLOGY == ULTRASCALE) ? "ULTRASCALE" : "7SERIES";

/*
* For 7 series, IDELAYCTRL is enabled ALWAYS, meaning in the following situations:
  * when IDELAY_TYPE = FIXED
  * when IDELAY_TYPE = VARIABLE
  * when IDELAY_TYPE = VAR_LOAD
**/

/*
 * For UltraScale/UltraScale+:
   * when DELAY_FORMAT = TIME:
     * IDELAYCTRL must be used
     * REFCLK_FREQUENCY must reflect the clock frequency of REF_CLK applied to
      the IDELAYCTRL component
     * DELAY_VALUE attribute represents an amount in ps
     * The total delay through the IDELAYE3 is the align delay + DELAY_VALUE
     * EN_VTC depends on DELAY_TYPE attribute:
       * when FIXED mode: EN_VTC = 1
       * It must be actively manipulated when the delay line is used in
        VARIABLE or VAR_LOAD mode
        (this section is NOT IMPLEMENTED! More details in UG571, DELAY_TYPE = VAR_LOAD mode and VARIABLE mode)

   * when DELAY_FORMAT = COUNT:
     * DO NOT use an IDELAYCTRL
     * REFCLK_FREQUENCY must be set to default frequency (300MHz)
     * Delay line represents an amount of taps (512 taps available)
     * CNTVALUEIN/OUT[8:0] values represent the amount of taps the delay line
      is set to
     * EN_VTC = 0
   **/

  // internal signals

  wire          rx_data_ibuf_s;
  wire          rx_data_idelay_s;
  wire  [ 8:0]  up_drdata_s;

  // internal registers

  reg           en_vtc;

  // determine EN_VTC (VAR_LOAD and VARIABLE modes not implemented as in UG571)

  always @(posedge rx_clk) begin
    if (DELAY_FORMAT == "TIME") begin
      if (US_DELAY_TYPE == "FIXED") begin
        en_vtc <= 1'b1;
      end else begin // "VAR_LOAD", "VARIABLE"
        en_vtc <= ~up_dld;
      end
    end else begin // "COUNT"
      en_vtc <= 1'b0;
    end
  end

  // delay controller

  generate
  if (IODELAY_CTRL_ENABLED) begin
    (* IODELAY_GROUP = IODELAY_GROUP *)
    IDELAYCTRL #(
      .SIM_DEVICE (IODELAY_CTRL_SIM_DEVICE)
    ) i_delay_ctrl (
      .RST (delay_rst),
      .REFCLK (delay_clk),
      .RDY (delay_locked));
  end else begin
    assign delay_locked = 1'b1;
  end
  endgenerate

  // receive data interface, ibuf -> idelay -> iddr

  // ibuf

  generate
  if (SINGLE_ENDED) begin
    IBUF i_rx_data_ibuf (
      .I (rx_data_in_p),
      .O (rx_data_ibuf_s));
  end else begin
    IBUFDS i_rx_data_ibuf (
      .I (rx_data_in_p),
      .IB (rx_data_in_n),
      .O (rx_data_ibuf_s));
  end
  endgenerate

  // bypass IDELAY

  generate
  if (IODELAY_ENABLE == 0) begin
    assign rx_data_idelay_s = rx_data_ibuf_s;
    assign up_drdata = 5'd0;
  end
  endgenerate

  // idelay

  generate
  if (IODELAY_FPGA_TECHNOLOGY == SEVEN_SERIES) begin
    if (IODELAY_ENABLE) begin
      (* IODELAY_GROUP = IODELAY_GROUP *)
      IDELAYE2 #(
        .CINVCTRL_SEL ("FALSE"),              // Enable dynamic clock inversion (FALSE, TRUE)
        .DELAY_SRC ("IDATAIN"),               // Delay input (IDATAIN, DATAIN)
        .HIGH_PERFORMANCE_MODE ("FALSE"),     // Reduced jitter ("TRUE"), Reduced power ("FALSE")
        .IDELAY_TYPE (IDELAY_TYPE),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
        .IDELAY_VALUE (0),                    // Input delay tap setting (0-31)
        .PIPE_SEL ("FALSE"),                  // Select pipelined mode, FALSE, TRUE
        .REFCLK_FREQUENCY (REFCLK_FREQUENCY), // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0)
        .SIGNAL_PATTERN ("DATA")              // DATA, CLOCK input signal
      ) i_rx_data_idelay (
        .CE (1'b0),                  // 1-bit input: Active high enable increment/decrement input
        .INC (1'b0),                 // 1-bit input: Increment / Decrement tap delay input
        .DATAIN (1'b0),              // 1-bit input: Internal delay data input
        .LDPIPEEN (1'b0),            // 1-bit input: Enable PIPELINE register to load data input
        .CINVCTRL (1'b0),            // 1-bit input: Dynamic clock inversion input
        .REGRST (1'b0),              // 1-bit input: Active-high reset tap-delay input
        .C (up_clk),                 // 1-bit input: Clock input
        .IDATAIN (rx_data_ibuf_s),   // 1-bit input: Data input from the I/O
        .DATAOUT (rx_data_idelay_s), // 1-bit output: Delayed data output
        .LD (up_dld),                // 1-bit input: Load IDELAY_VALUE input
        .CNTVALUEIN (up_dwdata),     // 5-bit input: Counter value input
        .CNTVALUEOUT (up_drdata));   // 5-bit output: Counter value output
    end
  end
  endgenerate

  generate
  if ((IODELAY_FPGA_TECHNOLOGY == ULTRASCALE) || (IODELAY_FPGA_TECHNOLOGY == ULTRASCALE_PLUS)) begin
    if (IODELAY_ENABLE) begin
      assign up_drdata = up_drdata_s[8:4];

      (* IODELAY_GROUP = IODELAY_GROUP *)
      IDELAYE3 #(
        .CASCADE ("NONE"),                    // Cascade setting  (MASTER, NONE, SLAVE_END, SLAVE_MIDDLE)
        .DELAY_FORMAT (DELAY_FORMAT),         // Units of the DELAY_VALUE  (COUNT, TIME)
        .DELAY_SRC ("IDATAIN"),               // Delay input  (DATAIN, IDATAIN)
        .DELAY_TYPE (US_DELAY_TYPE),          // Set the type of tap delay line  (FIXED, VARIABLE, VAR_LOAD)
        .DELAY_VALUE (0),                     // Input delay value setting
        .IS_CLK_INVERTED (1'b0),              // Optional inversion for CLK
        .IS_RST_INVERTED (1'b0),              // Optional inversion for RST
        .REFCLK_FREQUENCY (REFCLK_FREQUENCY), // IDELAYCTRL clock input frequency in MHz  (200.0-800.0)
        .SIM_DEVICE (IODELAY_SIM_DEVICE),     // Set the device version for simulation functionality
        .UPDATE_MODE ("ASYNC")                // Determines when updates to the delay will take effect  (ASYNC, MANUAL, SYNC)
      ) i_rx_data_idelay (
        .CASC_RETURN (1'b0),              // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
        .CASC_IN (1'b0),                  // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
        .CASC_OUT (),                     // 1-bit output: Cascade delay output to ODELAY input cascade
        .CE (1'b0),                       // 1-bit input: Active-High enable increment/decrement input
        .CLK (up_clk),                    // 1-bit input: Clock input
        .INC (1'b0),                      // 1-bit input: Increment / Decrement tap delay input
        .LOAD (up_dld),                   // 1-bit input: Load DELAY_VALUE input
        .CNTVALUEIN ({up_dwdata, 4'd0}),  // 9-bit input: Counter value input
        .CNTVALUEOUT (up_drdata_s),       // 9-bit output: Counter value output
        .DATAIN (1'b0),                   // 1-bit input: Data input from the logic
        .IDATAIN (rx_data_ibuf_s),        // 1-bit input: Data input from the IOBUF
        .DATAOUT (rx_data_idelay_s),      // 1-bit output: Delayed data output
        .RST (1'b0),                      // 1-bit input: Asynchronous Reset to the DELAY_VALUE
        .EN_VTC (en_vtc));                // 1-bit input: Keep delay constant over VT
    end
  end
  endgenerate

  // iddr

  generate
  if (FPGA_TECHNOLOGY == SEVEN_SERIES) begin
    IDDR #(
      .DDR_CLK_EDGE (IDDR_CLK_EDGE), // "OPPOSITE_EDGE", "SAME_EDGE", "SAME_EDGE_PIPELINED"
      .INIT_Q1 (1'b0),               // Initial value of Q1: 1'b0 or 1'b1
      .INIT_Q2 (1'b0),               // Initial value of Q2: 1'b0 or 1'b1
      .SRTYPE ("SYNC")               // Set/Reset type: "SYNC" or "ASYNC"
    ) i_rx_data_iddr (
      .CE (1'b1),            // 1-bit clock enable input
      .R (1'b0),             // 1-bit reset
      .S (1'b0),             // 1-bit set
      .C (rx_clk),           // 1-bit clock input
      .D (rx_data_idelay_s), // 1-bit DDR data input
      .Q1 (rx_data_p),       // 1-bit output for positive edge of clock
      .Q2 (rx_data_n));      // 1-bit output for negative edge of clock
  end
  endgenerate

  generate
  if ((FPGA_TECHNOLOGY == ULTRASCALE) || (FPGA_TECHNOLOGY == ULTRASCALE_PLUS)) begin
    IDDRE1 #(
      .DDR_CLK_EDGE (IDDR_CLK_EDGE), // IDDRE1 mode (OPPOSITE_EDGE, SAME_EDGE, SAME_EDGE_PIPELINED)
      .IS_CB_INVERTED (1'b0),        // Optional inversion for CB
      .IS_C_INVERTED (1'b0)          // Optional inversion for C
    ) i_rx_data_iddr (
      .R (1'b0),             // 1-bit output: Registered parallel output 1
      .C (rx_clk),           // 1-bit output: Registered parallel output 2
      .CB (~rx_clk),         // 1-bit input: High-speed clock
      .D (rx_data_idelay_s), // 1-bit input: Inversion of High-speed clock C
      .Q1 (rx_data_p),       // 1-bit input: Serial Data Input
      .Q2 (rx_data_n));      // 1-bit input: Active-High Async Reset
  end
  endgenerate

endmodule
