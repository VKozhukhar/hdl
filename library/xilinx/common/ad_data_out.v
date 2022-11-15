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

module ad_data_out #(

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   SINGLE_ENDED = 0,
  parameter   IDDR_CLK_EDGE ="SAME_EDGE",
  parameter   IODELAY_ENABLE = 0,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // data interface

  input               tx_clk,
  input               tx_data_p,
  input               tx_data_n,
  output              tx_data_out_p,
  output              tx_data_out_n,

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

  localparam  NONE = -1;
  localparam  SEVEN_SERIES = 1;
  localparam  ULTRASCALE = 2;
  localparam  ULTRASCALE_PLUS = 3;

  localparam  IODELAY_CTRL_ENABLED = (IODELAY_ENABLE == 1) ? IODELAY_CTRL : 0;
  localparam  IODELAY_CTRL_SIM_DEVICE = (FPGA_TECHNOLOGY == ULTRASCALE_PLUS) ? "ULTRASCALE" :
    (FPGA_TECHNOLOGY == ULTRASCALE) ? "ULTRASCALE" : "7SERIES";

  localparam  IODELAY_FPGA_TECHNOLOGY = (IODELAY_ENABLE == 1) ? FPGA_TECHNOLOGY : NONE;
  localparam  IODELAY_SIM_DEVICE = (FPGA_TECHNOLOGY == ULTRASCALE_PLUS) ? "ULTRASCALE_PLUS" :
    (FPGA_TECHNOLOGY == ULTRASCALE) ? "ULTRASCALE" : "7SERIES";

  // internal signals

  wire                tx_data_oddr_s;
  wire                tx_data_odelay_s;

  // delay controller

  generate
  if (IODELAY_CTRL_ENABLED == 0) begin
    assign delay_locked = 1'b1;
  end else begin
    (* IODELAY_GROUP = IODELAY_GROUP *)
    IDELAYCTRL #(
      .SIM_DEVICE (IODELAY_CTRL_SIM_DEVICE)
    ) i_delay_ctrl (
      .RST (delay_rst),
      .REFCLK (delay_clk),
      .RDY (delay_locked));
  end
  endgenerate

  // transmit data interface, oddr -> odelay -> obuf

  // oddr

  generate
  if (FPGA_TECHNOLOGY == SEVEN_SERIES) begin
    ODDR #(
      .DDR_CLK_EDGE (IDDR_CLK_EDGE), // "OPPOSITE_EDGE" or "SAME_EDGE"
      .INIT (1'b0),                  // Initial value of Q: 1'b0 or 1'b1
      .SRTYPE ("SYNC")               // Set/Reset type: "SYNC" or "ASYNC"
    ) i_tx_data_oddr (
      .CE (1'b1),           // 1-bit clock enable input
      .R (1'b0),            // 1-bit reset
      .S (1'b0),            // 1-bit set
      .C (tx_clk),          // 1-bit clock input
      .D1 (tx_data_p),      // 1-bit data input (positive edge)
      .D2 (tx_data_n),      // 1-bit data input (negative edge)
      .Q (tx_data_oddr_s)); // 1-bit DDR output
  end
  endgenerate

  generate
  if ((FPGA_TECHNOLOGY == ULTRASCALE_PLUS) || (FPGA_TECHNOLOGY == ULTRASCALE)) begin
    ODDRE1 #(
      .IS_C_INVERTED (1'b0),            // Optional inversion for C
      .IS_D1_INVERTED (1'b0),           // Unsupported, do not use
      .IS_D2_INVERTED (1'b0),           // Unsupported, do not use
      .SIM_DEVICE (IODELAY_SIM_DEVICE), // Set the device version for simulation functionality
      .SRVAL (1'b0)                     // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
    ) i_tx_data_oddr (
      .SR (1'b0),           // 1-bit input: Active-High Async Reset
      .C (tx_clk),          // 1-bit input: High-speed clock input
      .D1 (tx_data_p),      // 1-bit input: Parallel data input 1
      .D2 (tx_data_n),      // 1-bit input: Parallel data input 2
      .Q (tx_data_oddr_s)); // 1-bit output: Data output to IOB
  end
  endgenerate

  // odelay

  generate
  if (IODELAY_FPGA_TECHNOLOGY == SEVEN_SERIES) begin
    (* IODELAY_GROUP = IODELAY_GROUP *)
    ODELAYE2 #(
      .CINVCTRL_SEL ("FALSE"),              // Enable dynamic clock inversion (FALSE, TRUE)
      .DELAY_SRC ("ODATAIN"),               // Delay input (ODATAIN, CLKIN)
      .HIGH_PERFORMANCE_MODE ("FALSE"),     // Reduced jitter ("TRUE"), Reduced power ("FALSE")
      .ODELAY_TYPE ("VAR_LOAD"),            // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
      .ODELAY_VALUE (0),                    // Output delay tap setting (0-31)
      .PIPE_SEL ("FALSE"),                  // Select pipelined mode, FALSE, TRUE
      .REFCLK_FREQUENCY (REFCLK_FREQUENCY), // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0)
      .SIGNAL_PATTERN ("DATA")              // DATA, CLOCK input signal
    ) i_tx_data_odelay (
      .CE (1'b0),                  // 1-bit input: Active high enable increment/decrement input
      .CLKIN (1'b0),               // 1-bit input: Clock delay input
      .INC (1'b0),                 // 1-bit input: Increment / Decrement tap delay input
      .LDPIPEEN (1'b0),            // 1-bit input: Enables the pipeline register to load data
      .CINVCTRL (1'b0),            // 1-bit input: Dynamic clock inversion input
      .REGRST (1'b0),              // 1-bit input: Active-high reset tap-delay input
      .C (up_clk),                 // 1-bit input: Clock input
      .ODATAIN (tx_data_oddr_s),   // 1-bit input: Output delay data input
      .DATAOUT (tx_data_odelay_s), // 1-bit output: Delayed data/clock output
      .LD (up_dld),                // 1-bit input: Loads ODELAY_VALUE tap delay in VARIABLE mode, in VAR_LOAD or
                                   // VAR_LOAD_PIPE mode, loads the value of CNTVALUEIN
      .CNTVALUEIN (up_dwdata),     // 5-bit input: Counter value input
      .CNTVALUEOUT (up_drdata));   // 5-bit output: Counter value output
  end
  endgenerate

  generate
  if (IODELAY_FPGA_TECHNOLOGY == NONE) begin
    assign up_drdata = 5'd0;
    assign tx_data_odelay_s = tx_data_oddr_s;
  end
  endgenerate

  // obuf

  generate
  if (SINGLE_ENDED) begin
    assign tx_data_out_n = 1'b0;
    OBUF i_tx_data_obuf (
      .I (tx_data_odelay_s),
      .O (tx_data_out_p));
  end else begin
    OBUFDS i_tx_data_obuf (
      .I (tx_data_odelay_s),
      .O (tx_data_out_p),
      .OB (tx_data_out_n));
  end
  endgenerate

endmodule
