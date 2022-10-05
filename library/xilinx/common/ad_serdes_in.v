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

`timescale 1ps/1ps

module ad_serdes_in #(

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   CMOS_LVDS_N = 0,
  parameter   DDR_OR_SDR_N = 0,
  parameter   SERDES_FACTOR = 8,
  parameter   DATA_WIDTH = 16,
  parameter   DRP_WIDTH = 5,
  parameter   IODELAY_ENABLE = 1,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // clocks and reset

  input                        clk,
  input                        div_clk,
  input                        rst,

  // data interface

  input   [(DATA_WIDTH-1):0]   data_in_p,
  input   [(DATA_WIDTH-1):0]   data_in_n,

  output  [(DATA_WIDTH-1):0]   data_s0,  // last bit received
  output  [(DATA_WIDTH-1):0]   data_s1,
  output  [(DATA_WIDTH-1):0]   data_s2,
  output  [(DATA_WIDTH-1):0]   data_s3,
  output  [(DATA_WIDTH-1):0]   data_s4,
  output  [(DATA_WIDTH-1):0]   data_s5,
  output  [(DATA_WIDTH-1):0]   data_s6,
  output  [(DATA_WIDTH-1):0]   data_s7,  // 1st bit received

  // delay-data interface

  input                        up_clk,
  input   [(DATA_WIDTH-1):0]   up_dld,
  input   [((DATA_WIDTH*DRP_WIDTH)-1):0]  up_dwdata,
  output  [((DATA_WIDTH*DRP_WIDTH)-1):0]  up_drdata,

  // delay-control interface

  input                        delay_clk,
  input                        delay_rst,
  output                       delay_locked
);

  localparam SEVEN_SERIES = 1;
  localparam ULTRASCALE = 2;
  localparam ULTRASCALE_PLUS = 3;
  localparam DATA_RATE = (DDR_OR_SDR_N) ? "DDR" : "SDR";

  localparam IODELAY_CTRL_ENABLED = (IODELAY_ENABLE == 1) ? IODELAY_CTRL : 0;
  localparam SIM_DEVICE = FPGA_TECHNOLOGY == SEVEN_SERIES ? "7SERIES" :
                          FPGA_TECHNOLOGY == ULTRASCALE ? "ULTRASCALE" :
                          FPGA_TECHNOLOGY == ULTRASCALE_PLUS ? "ULTRASCALE_PLUS" :
                          "UNSUPPORTED";
  // when ULTRASCALE_PLUS, use ULTRASCALE because IDELAYCTRL is the same for both
  // and doesn't know ULTRASCALE_PLUS string
  localparam SIM_DEVICE_IDELAYCTRL = FPGA_TECHNOLOGY == SEVEN_SERIES ? "7SERIES" :
                          FPGA_TECHNOLOGY == ULTRASCALE ? "ULTRASCALE" :
                          FPGA_TECHNOLOGY == ULTRASCALE_PLUS ? "ULTRASCALE" :
                          "UNSUPPORTED";

  // internal registers

  reg [6:0] serdes_rst_seq;

  // internal signals

  wire  [(DATA_WIDTH-1):0]  data_in_ibuf_s;
  wire  [(DATA_WIDTH-1):0]  data_in_idelay_s;
  wire  [(DATA_WIDTH-1):0]  data_shift1_s;
  wire  [(DATA_WIDTH-1):0]  data_shift2_s;
  wire  serdes_rst = serdes_rst_seq [6];

  // delay controller

  generate
  if (!IODELAY_CTRL_ENABLED) begin
    assign delay_locked = 1'b1;
  end else begin
    (* IODELAY_GROUP = IODELAY_GROUP *)
    IDELAYCTRL #(
      .SIM_DEVICE (SIM_DEVICE_IDELAYCTRL)
    ) i_delay_ctrl (
      .RST (delay_rst),
      .REFCLK (delay_clk),
      .RDY (delay_locked));
  end
  endgenerate

  // bypass IDELAY

  generate
  if (!IODELAY_ENABLE) begin
    assign data_in_idelay_s = data_in_ibuf_s;
  end
  endgenerate

  // receive data interface: ibuf -> idelay -> iserdes

  // ibuf

  genvar l_inst;
  generate
  for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: g_io
    if (CMOS_LVDS_N == 0) begin
      IBUFDS i_ibuf (
        .I (data_in_p[l_inst]),
        .IB (data_in_n[l_inst]),
        .O (data_in_ibuf_s[l_inst]));
     end else begin
       IBUF i_ibuf (
        .I (data_in_p[l_inst]),
        .O (data_in_ibuf_s[l_inst]));
     end
  end
  endgenerate

  always @ (posedge div_clk) begin
    if (rst) begin
      serdes_rst_seq [6:0] <= 7'b0001110;
    end else begin
      serdes_rst_seq [6:0] <= {serdes_rst_seq [5:0], 1'b0};
    end
  end

  // idelay

  // 7 series
  generate
  if (FPGA_TECHNOLOGY == SEVEN_SERIES && IODELAY_ENABLE) begin
    for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: for_7series

      (* IODELAY_GROUP = IODELAY_GROUP *)
      IDELAYE2 #(
        .CINVCTRL_SEL ("FALSE"),              // Enable dynamic clock inversion (FALSE, TRUE)
        .DELAY_SRC ("IDATAIN"),               // Delay input (IDATAIN, DATAIN)
        .HIGH_PERFORMANCE_MODE ("FALSE"),     // Reduced jitter ("TRUE"), Reduced power ("FALSE")
        .IDELAY_TYPE ("VAR_LOAD"),            // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
        .IDELAY_VALUE (0),                    // Input delay tap setting (0-31)
        .PIPE_SEL ("FALSE"),                  // Select pipelined mode, FALSE, TRUE
        .REFCLK_FREQUENCY (REFCLK_FREQUENCY), // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0)
        .SIGNAL_PATTERN ("DATA")              // DATA, CLOCK input signal
      ) i_idelay (
        .CE (1'b0),                           // 5-bit output: Counter value output
        .INC (1'b0),                          // 1-bit output: Delayed data output
        .DATAIN (1'b0),                       // 1-bit input: Clock input
        .LDPIPEEN (1'b0),                     // 1-bit input: Active high enable increment/decrement input
        .CINVCTRL (1'b0),                     // 1-bit input: Dynamic clock inversion input
        .REGRST (1'b0),                       // 5-bit input: Counter value input
        .C (up_clk),                          // 1-bit input: Internal delay data input
        .IDATAIN (data_in_ibuf_s[l_inst]),    // 1-bit input: Data input from the I/O
        .DATAOUT (data_in_idelay_s[l_inst]),  // 1-bit input: Increment / Decrement tap delay input
        .LD (up_dld[l_inst]),                 // 1-bit input: Load IDELAY_VALUE input
        // 1-bit input: Enable PIPELINE register to load data input
        .CNTVALUEIN (up_dwdata[DRP_WIDTH*l_inst +: DRP_WIDTH]),
        // 1-bit input: Active-high reset tap-delay input
        .CNTVALUEOUT (up_drdata[DRP_WIDTH*l_inst +: DRP_WIDTH]));
      end /* for_7series */
    end
  endgenerate

  // ultrascale, ultrascale+
  generate
  if ((FPGA_TECHNOLOGY == ULTRASCALE || FPGA_TECHNOLOGY == ULTRASCALE_PLUS) && IODELAY_ENABLE) begin
    for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: for_ultrascale

      wire   div_dld;
      reg [4:0] vtc_cnt = {5{1'b1}};

      sync_event sync_load (
        .in_clk (up_clk),
        .in_event (up_dld[l_inst]),
        .out_clk (div_clk),
        .out_event (div_dld));

      (* IODELAY_GROUP = IODELAY_GROUP *)
      IDELAYE3 #(
        .CASCADE ("NONE"),          // Cascade setting (MASTER, NONE, SLAVE_END, SLAVE_MIDDLE)
        .DELAY_FORMAT ("TIME"),     // Units of the DELAY_VALUE (COUNT, TIME)
        .DELAY_SRC ("IDATAIN"),     // Delay input (DATAIN, IDATAIN)
        .DELAY_TYPE ("VAR_LOAD"),   // Set the type of tap delay line (FIXED, VARIABLE, VAR_LOAD)
        .DELAY_VALUE (0),           // Input delay value setting
        .IS_CLK_INVERTED (1'b0),    // Optional inversion for CLK
        .IS_RST_INVERTED (1'b0),    // Optional inversion for RST
        .REFCLK_FREQUENCY (500.0),  // IDELAYCTRL clock input frequency in MHz (200.0-2667.0)
        .SIM_DEVICE (SIM_DEVICE),   // Set the device version (ULTRASCALE, ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,
                                    // ULTRASCALE_PLUS_ES2)
        .UPDATE_MODE ("ASYNC")      // Determines when updates to the delay will take effect (ASYNC, MANUAL, SYNC)
      ) i_idelay (
        .CASC_OUT (),                                       // 1-bit output: Cascade delay output to ODELAY input cascade
        .CNTVALUEOUT (up_drdata[DRP_WIDTH*l_inst +: DRP_WIDTH]), // 9-bit output: Counter value output
        .DATAOUT (data_in_idelay_s[l_inst]),                // 1-bit output: Delayed data output
        .CASC_IN (1'b0),                                    // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
        .CASC_RETURN (1'b0),                                // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
        .CE (1'b0),                                         // 1-bit input: Active high enable increment/decrement input
        .CLK (div_clk),                                     // 1-bit input: Clock input
        .CNTVALUEIN (up_dwdata[DRP_WIDTH*l_inst +: DRP_WIDTH]),   // 9-bit input: Counter value input
        .DATAIN (1'b0),                                     // 1-bit input: Data input from the logic
        .EN_VTC (en_vtc),                                   // 1-bit input: Keep delay constant over VT
        .IDATAIN (data_in_ibuf_s[l_inst]),                  // 1-bit input: Data input from the IOBUF
        .INC (1'b0),                                        // 1-bit input: Increment / Decrement tap delay input
        .LOAD (ld_cnt),                                     // 1-bit input: Load DELAY_VALUE input
        .RST (rst));                                        // 1-bit input: Asynchronous Reset to the DELAY_VALUE

      always @(posedge div_clk) begin
        if (div_dld) begin
          vtc_cnt <= 'h0;
        end else if (~(&vtc_cnt)) begin
          vtc_cnt <= vtc_cnt + 1;
        end
      end

      assign en_vtc = &vtc_cnt;
      assign ld_cnt = ~vtc_cnt[4] & (&vtc_cnt[3:0]);
    end /* for_ultrascale */
  end
  endgenerate

  // iserdes

  // 7 series
  generate
  if (FPGA_TECHNOLOGY == SEVEN_SERIES) begin
    for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: for_7series
      ISERDESE2 #(
        .DATA_RATE (DATA_RATE),         // DDR, SDR
        .DATA_WIDTH (SERDES_FACTOR),    // Parallel data width (2-8,10,14)
        .DYN_CLKDIV_INV_EN ("FALSE"),   // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
        .DYN_CLK_INV_EN ("FALSE"),      // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
        // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
        .INIT_Q1 (1'b0),
        .INIT_Q2 (1'b0),
        .INIT_Q3 (1'b0),
        .INIT_Q4 (1'b0),
        .INTERFACE_TYPE ("NETWORKING"), // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
        .IOBDELAY ("IFD"),              // NONE, BOTH, IBUF, IFD
        .NUM_CE (2),                    // Number of clock enables (1,2)
        .OFB_USED ("FALSE"),            // Select OFB path (FALSE, TRUE)
        .SERDES_MODE ("MASTER"),        // MASTER, SLAVE
        // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
        .SRVAL_Q1 (1'b0),
        .SRVAL_Q2 (1'b0),
        .SRVAL_Q3 (1'b0),
        .SRVAL_Q4 (1'b0)
      ) i_iserdes (
        .O (),                          // 1-bit output: Combinatorial output
        // Q1 - Q8: 1-bit (each) output: Registered data outputs
        .Q1 (data_s0[l_inst]),
        .Q2 (data_s1[l_inst]),
        .Q3 (data_s2[l_inst]),
        .Q4 (data_s3[l_inst]),
        .Q5 (data_s4[l_inst]),
        .Q6 (data_s5[l_inst]),
        .Q7 (data_s6[l_inst]),
        .Q8 (data_s7[l_inst]),
        // SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),
        .BITSLIP (1'b0),           // 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                   // CLKDIV when asserted (active High). Subsequently, the data seen on the Q1
                                   // to Q8 output ports will shift, as in a barrel-shifter operation, one
                                   // position every time Bitslip is invoked (DDR operation is different from
                                   // SDR)
        // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
        .CE1 (1'b1),
        .CE2 (1'b1),
        .CLKDIVP (1'b0),           // 1-bit input: TBD
        .CLK (clk),                // 1-bit input: High-speed clock
        .CLKB (~clk),              // 1-bit input: High-speed secondary clock
        .CLKDIV (div_clk),         // 1-bit input: Divided clock
        .OCLK (1'b0),              // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
        // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
		    .DYNCLKDIVSEL (1'b0),      // 1-bit input: Dynamic CLKDIV inversion
        .DYNCLKSEL (1'b0),         // 1-bit input: Dynamic CLK/CLKB inversion
		    .D (1'b0),                 // 1-bit input: Data input
        .DDLY (data_in_idelay_s[l_inst]),  // 1-bit input: Serial data from IDELAYE2
        .OFB (1'b0),               // 1-bit input: Data feedback from OSERDESE2
        .OCLKB (1'b0),             // 1-bit input: High speed negative edge output clock
        .RST (serdes_rst),         // 1-bit input: Active high asynchronous reset
        // SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
        .SHIFTIN1 (1'b0),
        .SHIFTIN2 (1'b0));
      end /* for_7series */
    end
  endgenerate

  // ultrascale, ultrascale+
  generate
  if (FPGA_TECHNOLOGY == ULTRASCALE || FPGA_TECHNOLOGY == ULTRASCALE_PLUS) begin
    for (l_inst = 0; l_inst <= (DATA_WIDTH-1); l_inst = l_inst + 1) begin: for_ultrascale

      ISERDESE3 #(
        .DATA_WIDTH (8),            // Parallel data width (4,8)
        .FIFO_ENABLE ("FALSE"),     // Enables the use of the FIFO
        .FIFO_SYNC_MODE ("FALSE"),  // Enables the use of internal 2-stage synchronizers on the FIFO
        .IS_CLK_B_INVERTED (1'b0),  // Optional inversion for CLK_B
        .IS_CLK_INVERTED (1'b0),    // Optional inversion for CLK
        .IS_RST_INVERTED (1'b0),    // Optional inversion for RST
        .SIM_DEVICE (SIM_DEVICE)    // Set the device version (ULTRASCALE, ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,
                                    // ULTRASCALE_PLUS_ES2)
      ) i_iserdes(
        .FIFO_EMPTY (),                // 1-bit output: FIFO empty flag
        .INTERNAL_DIVCLK (),           // 1-bit output: Internally divided down clock used when FIFO is
                                       // disabled (do not connect)
        .Q ({data_s0[l_inst],
             data_s1[l_inst],
             data_s2[l_inst],
             data_s3[l_inst],
             data_s4[l_inst],
             data_s5[l_inst],
             data_s6[l_inst],
             data_s7[l_inst]}),        // 8-bit registered output
        .CLK (clk),                    // 1-bit input: High-speed clock
        .CLKDIV (div_clk),             // 1-bit input: Divided Clock
        .CLK_B (~clk),                 // 1-bit input: Inversion of High-speed clock CLK
        .D (data_in_idelay_s[l_inst]), // 1-bit input: Serial Data Input
        .FIFO_RD_CLK (div_clk),        // 1-bit input: FIFO read clock
        .FIFO_RD_EN (1'b1),            // 1-bit input: Enables reading the FIFO when asserted
        .RST (serdes_rst));            // 1-bit input: Asynchronous Reset
    end /* for_ultrascale */
  end
  endgenerate
endmodule
