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
// serial data output interface: serdes(x8)
// for more details about I/OSERDES, check UG471 for 7 series, and UG571 for
// UltraScale/UltraScale+

`timescale 1ps/1ps

module ad_serdes_out #(

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   CMOS_LVDS_N = 0,
  parameter   DDR_OR_SDR_N = 1,
  parameter   SERDES_FACTOR = 8,
  parameter   DATA_WIDTH = 16
) (

  // reset and clocks

  input                       rst,
  input                       clk,
  input                       div_clk,

  // data interface

  input                       data_oe,
  input   [(DATA_WIDTH-1):0]  data_s0,   // 1st bit to be transmitted
  input   [(DATA_WIDTH-1):0]  data_s1,
  input   [(DATA_WIDTH-1):0]  data_s2,
  input   [(DATA_WIDTH-1):0]  data_s3,
  input   [(DATA_WIDTH-1):0]  data_s4,
  input   [(DATA_WIDTH-1):0]  data_s5,
  input   [(DATA_WIDTH-1):0]  data_s6,
  input   [(DATA_WIDTH-1):0]  data_s7,   // last bit to be transmitted

  output  [(DATA_WIDTH-1):0]  data_out_se,

  output  [(DATA_WIDTH-1):0]  data_out_p,
  output  [(DATA_WIDTH-1):0]  data_out_n
);

  localparam SEVEN_SERIES = 1;
  localparam ULTRASCALE = 2;
  localparam ULTRASCALE_PLUS = 3;
  localparam DR_OQ_DDR = DDR_OR_SDR_N == 1'b1 ? "DDR": "SDR";

  localparam SIM_DEVICE = FPGA_TECHNOLOGY == SEVEN_SERIES ? "7SERIES" :
                          FPGA_TECHNOLOGY == ULTRASCALE ? "ULTRASCALE" :
                          FPGA_TECHNOLOGY == ULTRASCALE_PLUS ? "ULTRASCALE_PLUS" :
                          "UNSUPPORTED";

  // internal registers

  reg [6:0] serdes_rst_seq;

  // internal signals

  wire  [(DATA_WIDTH-1):0]  data_out_s;
  wire  [(DATA_WIDTH-1):0]  serdes_shift1_s;
  wire  [(DATA_WIDTH-1):0]  serdes_shift2_s;
  wire  [(DATA_WIDTH-1):0]  data_t;
  wire  buffer_disable;
  wire  serdes_rst = serdes_rst_seq [6];

  // connections

  assign data_out_se = data_out_s;
  assign buffer_disable = ~data_oe;

  // instantiations

  always @(posedge div_clk) begin
    if (rst) begin
      serdes_rst_seq [6:0] <= 7'b0001110;
    end else begin
      serdes_rst_seq [6:0] <= {serdes_rst_seq [5:0], 1'b0};
    end
  end

  // transmit data path: oserdes -> obuf

  genvar l_inst;
  generate
  for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: g_data

    // oserdes

    if (FPGA_TECHNOLOGY == SEVEN_SERIES) begin
      OSERDESE2 #(
        .DATA_RATE_OQ (DR_OQ_DDR),   // DDR, SDR
        .DATA_RATE_TQ ("SDR"),       // DDR, BUF, SDR
        .DATA_WIDTH (SERDES_FACTOR), // Parallel data width (2-8,10,14)
        .TRISTATE_WIDTH (1),         // 3-state converter width (1,4)
        .SERDES_MODE ("MASTER")      // MASTER, SLAVE
      ) i_oserdes (
        // D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
        .D1 (data_s0[l_inst]),
        .D2 (data_s1[l_inst]),
        .D3 (data_s2[l_inst]),
        .D4 (data_s3[l_inst]),
        .D5 (data_s4[l_inst]),
        .D6 (data_s5[l_inst]),
        .D7 (data_s6[l_inst]),
        .D8 (data_s7[l_inst]),
        // T1 - T4: 1-bit (each) input: Parallel 3-state inputs
        .T1 (buffer_disable),
        .T2 (buffer_disable),
        .T3 (buffer_disable),
        .T4 (buffer_disable),
        // SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
        .SHIFTIN1 (1'b0),
        .SHIFTIN2 (1'b0),
        // SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),
        .OCE (1'b1),              // 1-bit input: Output data clock enable
        .CLK (clk),               // 1-bit input: High speed clock
        .CLKDIV (div_clk),        // 1-bit input: Divided clock
        .OQ (data_out_s[l_inst]), // 1-bit output: Data path output
        .TQ (data_t[l_inst]),     // 1-bit output: 3-state control
        .OFB (),                  // 1-bit output: Feedback path for data
        .TFB (),                  // 1-bit output: 3-state control
        .TBYTEIN (1'b0),          // 1-bit input: Byte group tristate
        .TBYTEOUT (),             // 1-bit output: Byte group tristate
        .TCE (1'b1),              // 1-bit input: 3-state clock enable
        .RST (serdes_rst));       // 1-bit input: Reset
    end

    if (FPGA_TECHNOLOGY == ULTRASCALE || FPGA_TECHNOLOGY == ULTRASCALE_PLUS) begin
      OSERDESE3 #(
        .DATA_WIDTH (SERDES_FACTOR), // Parallel Data Width (4-8)
        .INIT (1'b0),                // Initialization value of the OSERDES flip-flops
        .IS_CLKDIV_INVERTED (1'b0),  // Optional inversion for CLKDIV
        .IS_CLK_INVERTED (1'b0),     // Optional inversion for CLK
        .IS_RST_INVERTED (1'b0),     // Optional inversion for RST
        .SIM_DEVICE (SIM_DEVICE)     // Set the device version for simulation functionality
      ) i_oserdes (
        // 8-bit input: Parallel Data Input
        .D ({data_s7[l_inst],
             data_s6[l_inst],
             data_s5[l_inst],
             data_s4[l_inst],
             data_s3[l_inst],
             data_s2[l_inst],
             data_s1[l_inst],
             data_s0[l_inst]}),
        .T (buffer_disable),       // 1-bit input: Tristate input from fabric
        .CLK (clk),                // 1-bit input: High-speed clock
        .CLKDIV (div_clk),         // 1-bit input: Divided Clock
        .OQ (data_out_s[l_inst]),  // 1-bit output: Serial Output Data
        .T_OUT (data_t[l_inst]),   // 1-bit output: 3-state control output to IOB
        .RST (serdes_rst));        // 1-bit input: Asynchronous Reset
    end

    // obuf

    if (CMOS_LVDS_N == 0) begin
      OBUFTDS i_obuftds (
        .T (data_t[l_inst]),
        .I (data_out_s[l_inst]),
        .O (data_out_p[l_inst]),
        .OB (data_out_n[l_inst]));
    end else begin
      OBUFT i_obuft (
        .T (data_t[l_inst]),
        .I (data_out_s[l_inst]),
        .O (data_out_p[l_inst]));
    end
  end
  endgenerate

endmodule
