module pianotiles
  (
    CLOCK_50,           //  On Board 50 MHz
    // Your inputs and outputs here
        SW,
 KEY,
    // The ports below are for the VGA output.  Do not change.
    VGA_CLK,              //  VGA Clock
    VGA_HS,             //  VGA H_SYNC
    VGA_VS,             //  VGA V_SYNC
    VGA_BLANK_N,            //  VGA BLANK
    VGA_SYNC_N,           //  VGA SYNC
    VGA_R,              //  VGA Red[9:0]
    VGA_G,              //  VGA Green[9:0]
    VGA_B               //  VGA Blue[9:0]
  );

  input     CLOCK_50;       //  50 MHz
  input   [9:0]   SW;  // SW[9:7] color(r,g,b), SW[6:0] input(x,y) note: 128*128 since x has 7 bits not 8, set msb to 0
  input   [3:0]   KEY; // KEY[0] resetn, KEY[1] draw, KEY[3] load

  // Declare your inputs and outputs here
 
  // Do not change the following outputs
  output      VGA_CLK;          //  VGA Clock
  output      VGA_HS;         //  VGA H_SYNC
  output      VGA_VS;         //  VGA V_SYNC
  output      VGA_BLANK_N;        //  VGA BLANK
  output      VGA_SYNC_N;       //  VGA SYNC
  output  [9:0] VGA_R;          //  VGA Red[9:0]
  output  [9:0] VGA_G;          //  VGA Green[9:0]
  output  [9:0] VGA_B;          //  VGA Blue[9:0]
 
  wire resetn;
  assign resetn = KEY[0];
 
  // Create wires for the colour, the x and y coordinatesand as well as the swriteEn wires that are inputs to the controller.
  wire [2:0] colour_out;
  wire [7:0] x_coord;
  wire [6:0] y_coord;
  wire draw_out;
  wire idle_out, create_out, wait_out, shift_out;

  // Counter wires
  wire [6:0] block_x_counter, block_y_counter, row_counter, col_counter;
  wire [31:0] wait_counter;  

  // Create wires for columns 0 to 3 and rnd
  wire [5:0] col0, col1, col2, col3;
  wire [1:0] rnd;

  // Create an Instance of a VGA controller - there can be only one!
  // Define the number of colours as well as the initial background
  // image file (.MIF) for the controller.
  vga_adapter VGA(
      .resetn(resetn),
      .clock(CLOCK_50),
      .colour(colour_out),
      .x(x_coord),
      .y(y_coord),
      .plot(draw_out),
      /* Signals for the DAC to drive the monitor. */
      .VGA_R(VGA_R),
      .VGA_G(VGA_G),
      .VGA_B(VGA_B),
      .VGA_HS(VGA_HS),
      .VGA_VS(VGA_VS),
      .VGA_BLANK(VGA_BLANK_N),
      .VGA_SYNC(VGA_SYNC_N),
      .VGA_CLK(VGA_CLK));
    defparam VGA.RESOLUTION = "160x120";
    defparam VGA.MONOCHROME = "FALSE";
    defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
    defparam VGA.BACKGROUND_IMAGE = "black.mif";

    // Instansiate datapath
datapath d0(
          .col0(col0),
          .col1(col1),
          .col2(col2),
          .col3(col3),
          .x_coord(x_coord),
          .y_coord(y_coord),
          .colour_out(colour_out),
          .block_x_counter(block_x_counter),
          .block_y_counter(block_y_counter),
          .row_counter(row_counter),
          .col_counter(col_counter),
          .wait_counter(wait_counter)
          );

    // Instansiate FSM control
  control c0(.CLOCK_50(CLOCK_50),
          .reset_n(SW[9]),
          .shift_out(shift_out),
          .create_out(create_out),
          .draw_out(draw_out),
          .wait_out(wait_out),
          .idle_out(idle_out),
          .block_x_counter(block_x_counter),
          .block_y_counter(block_y_counter),
          .row_counter(row_counter),
          .col_counter(col_counter),
          .wait_counter(wait_counter)
          );

    //Instantiate 4 registers
  four_registers fr(.CLOCK_50(CLOCK_50),
                    .reset_n(SW[9]),
                    .KEY(KEY),
                    .next_col(rnd),
                    .create(create_out),
                    .shift(shift_out),
                    .col0(col0),
                    .col1(col1),
                    .col2(col2),
                    .col3(col3)
                    );

    //Instantiate the LFSR
  LFSR lfsr(.CLOCK_50(CLOCK_50),
        .reset_n(SW[9]),
        .increment_counter(increment_counter),
        .rnd(rnd)
        );

  //Instantiate the score
  score s(.CLOCK_50(CLOCK_50),
          .KEY(KEY), 
          .reset_n(SW[9]), 
          .col0(col0),
          .col1(col1),
          .col2(col2),
          .col3(col3) 
          .score_out(score_out);

  //Instantiate the HEX display
   
endmodule

module control(CLOCK_50, reset_n, shift_out, create_out, draw_out, wait_out, idle_out, block_x_counter, block_y_counter, row_counter, col_counter, wait_counter);
  input CLOCK_50, reset_n;
  output reg shift_out, create_out, draw_out, wait_out, idle_out;
  reg [2:0] current_state, next_state;

  // Counters are used to draw a particular box. Block_x_counter determines what is being drawn in the x-coordinate, 
  // block_y_counter determines what is being drawn in the x-coordinate, row_counter determines which row the box is in
  // that is being drawn and col_counter determines which column the box is in that is being drawn. 
  output reg [6:0] block_x_counter;
  output reg [6:0] block_y_counter;
  output reg [6:0] row_counter;
  output reg [6:0] col_counter;
  output reg [31:0] wait_counter;
  reg [31:0] counter_reset;
  initial block_x_counter = 0;
  initial block_y_counter = 0;
  initial row_counter = 0;
  initial col_counter = 0;

  // counter_reset is for testing. Really, wait_counter should be 10'd50000000 which will be the amount of time 
  // a player waits when the boxes are being drawn.
  initial counter_reset = 10'd50000000;
  initial wait_counter = counter_reset;
 
  // States are initialized below
  localparam  
        Shift = 4'd0,
        Create = 4'd1,
        Draw = 4'd2,
        Wait = 4'd3,
        Idle = 4'd4;
         
  // State Table
  // The game is continuous and after every state there will be the next. 
  // It does not loop in the same state as it has in previous labs. 
  always @(*) begin
    case (current_state)
      Shift: next_state = Create;
      Create: next_state = Draw;
      Draw: next_state = Wait;
      Wait: next_state = Shift;
      Idle: next_state = Shift;
    endcase
  end
 
  // Output Logic
  always @(*) begin
    shift_out = 1'b0;
    create_out = 1'b0;
    draw_out = 1'b0;
    wait_out = 1'b0;
    idle_out = 1'b0;
   
    case (current_state)
      Shift: begin
        shift_out = 1;
      end
      Create: begin
        create_out = 1;
      end
      Draw: begin
        draw_out = 1;
      end
      Wait: begin
        wait_out = 1;
      end
      Idle: begin
        idle_out = 1;
      end
    endcase
  end

  // Current State Register
  always @(posedge CLOCK_50) begin
    if (!reset_n) begin
      current_state <= Idle;
    end
    else if (current_state == Draw) begin
      // Checks if everything is drawn and if so sets the counters back to 0
      if(block_x_counter == 10'd39 && block_y_counter == 10'd19 && row_counter == 5 && col_counter == 3) begin
        current_state <= next_state;
        block_x_counter <= 0;
        block_y_counter <= 0;
        row_counter <= 0;
        col_counter <= 0;
      end
      // col_counter < 3 so there are still blocks in the last column that have not been drawn. Reset the counters 
      // and increment col_counter to draw the remaining blocks in the last column
      else if(block_x_counter == 10'd39 && block_y_counter == 10'd19 && row_counter == 5) begin
        block_x_counter <= 0;
        block_y_counter <= 0;
        row_counter <= 0;
        col_counter <= col_counter + 1'b1;
      end
      // col_counter < 3 and row_counter < 5 so there are still blocks in the last column and last row that have not been drawn.
      // Reset the counters and increment col_counter and row_counter to draw the remaining blocks in the last rows and columns
      else if(block_x_counter == 10'd39 && block_y_counter == 10'd19) begin
        block_x_counter <= 0;
        block_y_counter <= 0;
        row_counter <= row_counter + 1'b1;
      end
      // A row has been fully drawn. Move onto the next row by resetting block_x_counter to 0 and incrementing block_y_counter
      else if(block_x_counter == 10'd39) begin
        block_x_counter <= 0;
        block_y_counter <= block_y_counter + 1'b1;
      end
      else begin
      // Increment block_x_counter so to keep drawing the current row of the block that's being drawn
        block_x_counter <= block_x_counter + 1'b1;
      end
    end
    else if(current_state == Wait) begin
      if(wait_counter == 0) begin
        current_state <= next_state;
        wait_counter = counter_reset;
      end
      else begin
        wait_counter <= wait_counter - 1'b1;
      end
    end
    else begin
      current_state <= next_state;
    end
  end
endmodule

module four_registers(CLOCK_50, KEY, reset_n, next_col, create, shift, col0, col1, col2, col3);
  input CLOCK_50, reset_n, shift, create;
  input [3:0] KEY;
  input [1:0] next_col;
  output reg [5:0] col0, col1, col2, col3;
  initial col0 = 1'b0;
  initial col1 = 1'b0;
  initial col2 = 1'b0;
  initial col3 = 1'b0;

  always @(*) begin
    if (!reset_n) begin
      col0 <= 1'b0;
      col1 <= 1'b0;
      col2 <= 1'b0;
      col3 <= 1'b0;
    end
    if (shift) begin
      col0 <= col0 >> 2'b01;
      col1 <= col1 >> 2'b01;
      col2 <= col2 >> 2'b01;
      col3 <= col3 >> 2'b01;
    end
    if (create) begin
      if (next_col == 2'b00) begin
        col0[5] = 1'b1;
      end
      else if (next_col == 2'b01) begin
        col1[5] = 1'b1;
      end
      else if (next_col == 2'b10) begin
        col2[5] = 1'b1;
      end
      else if (next_col == 2'b11) begin
        col3[5] = 1'b1;
      end
    end
  end
endmodule

module datapath(col0, col1, col2, col3, x_coord, y_coord, colour_out, block_x_counter, block_y_counter, row_counter, col_counter, wait_counter);
    input CLOCK_50;
    input [5:0] col0, col1, col2, col3;
    input [6:0] block_x_counter, block_y_counter, row_counter, col_counter, wait_counter;
    output reg [7:0] x_coord;
    output reg [6:0] y_coord;
    output reg [2:0] colour_out;

    // Initialize colours
    localparam
      black = 3'b111,
      blue = 3'b001,
      red = 3'b100,
      yellow = 3'b110,
      green = 3'b010;

    always @(*) begin
      colour_out <= black;
      if(col_counter == 2'd0)begin
        x_coord <= block_x_counter;
        y_coord <= block_y_counter + (row_counter * 5'd20);
        if(col0[5 - row_counter] == 2'b01) begin
          colour_out <= blue;
        end
      end
      else if(col_counter == 2'd1)begin
        x_coord <= 40 + block_x_counter;
        y_coord <= block_y_counter + (row_counter * 5'd20);
        if(col1[5 - row_counter] == 2'b01) begin
          colour_out <= red;
        end
      end
      else if(col_counter == 2'd2)begin
        x_coord <= 80 + block_x_counter;
        y_coord <= block_y_counter + (row_counter * 5'd20);
        if(col2[5 - row_counter] == 2'b01) begin
          colour_out <= yellow;
        end
      end
      else if(col_counter == 2'd3)begin
        x_coord <= 120 + block_x_counter;
        y_coord <= block_y_counter + (row_counter * 5'd20);
        if(col3[5 - row_counter] == 2'b01) begin
          colour_out <= green;
        end
      end
    end

endmodule

module score(CLOCK_50, KEY, reset_n, col0, col1, col2, col3, score_out);
  input CLOCK_50, reset_n;
  input [3:0] KEY;
  input [5:0] col0, col1, col2, col3;
  output [6:0] score_out;

  always @(posedge CLOCK_50) begin
    //Keys are active-low and in decreasing order
    if(KEY[3] == 0 && col0[0] == 1) begin
      score_out <= score_out + 1'b1;
    end
    else if(KEY[2] == 0 && col1[0] == 1) begin 
      score_out <= score_out + 1'b1;
    end 
    else if(KEY[1] == 0 && col2[0] == 1) begin
      score_out <= score_out + 1'b1;
    end 
    else if(KEY[0] == 0 && col3[0] == 1) begin
      score_out <= score_out + 1'b1;
    end 
  end
endmodule

module hex_decoder(hex_digit, segments);
    input [3:0] hex_digit;
    output reg [6:0] segments;
   
    always @(*)
        case (hex_digit)
            4'h0: segments = 7'b100_0000;
            4'h1: segments = 7'b111_1001;
            4'h2: segments = 7'b010_0100;
            4'h3: segments = 7'b011_0000;
            4'h4: segments = 7'b001_1001;
            4'h5: segments = 7'b001_0010;
            4'h6: segments = 7'b000_0010;
            4'h7: segments = 7'b111_1000;
            4'h8: segments = 7'b000_0000;
            4'h9: segments = 7'b001_1000;
            4'hA: segments = 7'b000_1000;
            4'hB: segments = 7'b000_0011;
            4'hC: segments = 7'b100_0110;
            4'hD: segments = 7'b010_0001;
            4'hE: segments = 7'b000_0110;
            4'hF: segments = 7'b000_1110;   
            default: segments = 7'h7f;
        endcase
endmodule
  
// Need to implement random number this is a possible resource. The number is currently set to 1.   
// http://simplefpga.blogspot.com/2013/02/random-number-generator-in-verilog-fpga.html

module LFSR (CLOCK_50, reset_n, increment_counter, rnd);
  input CLOCK_50;
  input reset_n;
  input [31:0] increment_counter;
  output [1:0] rnd;

//  always @(posedge CLOCK_50) begin
//    if (reset_n == 0) begin 
//      increment_counter <= 0; 
//    end 
//    increment_counter <= increment_counter + 1;

//    if (increment_counter % 3 == 0) begin
//      rnd <= 2'b00
//    end 
//    else if (increment_counter % 4 == 0) begin
//      rnd <= 2'b10
//    end 
//    else if (increment_counter % 5 == 0) begin
//    rnd <= 2'b11
//    end 
//   else if (increment_counter % 7 == 0) begin
//       rnd <= 2'b01;
//    end
//    else begin 
//      rnd <= 2'b10;
//    end 
//  end 

// Currently set to 3 for testing.  
  assign rnd = 2'b11;

endmodule

module vga_adapter(
   resetn,
   clock,
   colour,
   x, y, plot,
   /* Signals for the DAC to drive the monitor. */
   VGA_R,
   VGA_G,
   VGA_B,
   VGA_HS,
   VGA_VS,
   VGA_BLANK,
   VGA_SYNC,
   VGA_CLK);
 
 parameter BITS_PER_COLOUR_CHANNEL = 1;
 /* The number of bits per colour channel used to represent the colour of each pixel. A value
  * of 1 means that Red, Green and Blue colour channels will use 1 bit each to represent the intensity
  * of the respective colour channel. For BITS_PER_COLOUR_CHANNEL=1, the adapter can display 8 colours.
  * In general, the adapter is able to use 2^(3*BITS_PER_COLOUR_CHANNEL ) colours. The number of colours is
  * limited by the screen resolution and the amount of on-chip memory available on the target device.
  */
 
 parameter MONOCHROME = "FALSE";
 /* Set this parameter to "TRUE" if you only wish to use black and white colours. Doing so will reduce
  * the amount of memory you will use by a factor of 3. */
 
 parameter RESOLUTION = "160x120";
 /* Set this parameter to "160x120" or "320x240". It will cause the VGA adapter to draw each dot on
  * the screen by using a block of 4x4 pixels ("160x120" resolution) or 2x2 pixels ("320x240" resolution).
  * It effectively reduces the screen resolution to an integer fraction of 640x480. It was necessary
  * to reduce the resolution for the Video Memory to fit within the on-chip memory limits.
  */
 
 parameter BACKGROUND_IMAGE = "background.mif";
 /* The initial screen displayed when the circuit is first programmed onto the DE2 board can be
  * defined useing an MIF file. The file contains the initial colour for each pixel on the screen
  * and is placed in the Video Memory (VideoMemory module) upon programming. Note that resetting the
  * VGA Adapter will not cause the Video Memory to revert to the specified image. */


 /*****************************************************************************/
 /* Declare inputs and outputs.                                               */
 /*****************************************************************************/
 input resetn;
 input clock;
 
 /* The colour input can be either 1 bit or 3*BITS_PER_COLOUR_CHANNEL bits wide, depending on
  * the setting of the MONOCHROME parameter.
  */
 input [((MONOCHROME == "TRUE") ? (0) : (BITS_PER_COLOUR_CHANNEL*3-1)):0] colour;
 
 /* Specify the number of bits required to represent an (X,Y) coordinate on the screen for
  * a given resolution.
  */
 input [((RESOLUTION == "320x240") ? (8) : (7)):0] x;
 input [((RESOLUTION == "320x240") ? (7) : (6)):0] y;
 
 /* When plot is high then at the next positive edge of the clock the pixel at (x,y) will change to
  * a new colour, defined by the value of the colour input.
  */
 input plot;
 
 /* These outputs drive the VGA display. The VGA_CLK is also used to clock the FSM responsible for
  * controlling the data transferred to the DAC driving the monitor. */
 output [9:0] VGA_R;
 output [9:0] VGA_G;
 output [9:0] VGA_B;
 output VGA_HS;
 output VGA_VS;
 output VGA_BLANK;
 output VGA_SYNC;
 output VGA_CLK;

 /*****************************************************************************/
 /* Declare local signals here.                                               */
 /*****************************************************************************/
 
 wire valid_160x120;
 wire valid_320x240;
 /* Set to 1 if the specified coordinates are in a valid range for a given resolution.*/
 
 wire writeEn;
 /* This is a local signal that allows the Video Memory contents to be changed.
  * It depends on the screen resolution, the values of X and Y inputs, as well as
  * the state of the plot signal.
  */
 
 wire [((MONOCHROME == "TRUE") ? (0) : (BITS_PER_COLOUR_CHANNEL*3-1)):0] to_ctrl_colour;
 /* Pixel colour read by the VGA controller */
 
 wire [((RESOLUTION == "320x240") ? (16) : (14)):0] user_to_video_memory_addr;
 /* This bus specifies the address in memory the user must write
  * data to in order for the pixel intended to appear at location (X,Y) to be displayed
  * at the correct location on the screen.
  */
 
 wire [((RESOLUTION == "160x120") ? (16) : (14)):0] controller_to_video_memory_addr;
 /* This bus specifies the address in memory the vga controller must read data from
  * in order to determine the colour of a pixel located at coordinate (X,Y) of the screen.
  */
 
 wire clock_25;
 /* 25MHz clock generated by dividing the input clock frequency by 2. */
 
 wire vcc, gnd;
 
 /*****************************************************************************/
 /* Instances of modules for the VGA adapter.                                 */
 /*****************************************************************************/
 assign vcc = 1'b1;
 assign gnd = 1'b0;
 
 vga_address_translator user_input_translator(
     .x(x), .y(y), .mem_address(user_to_video_memory_addr) );
  defparam user_input_translator.RESOLUTION = RESOLUTION;
 /* Convert user coordinates into a memory address. */

 assign valid_160x120 = (({1'b0, x} >= 0) & ({1'b0, x} < 160) & ({1'b0, y} >= 0) & ({1'b0, y} < 120)) & (RESOLUTION == "160x120");
 //assign valid_320x240 = (({1'b0, x} >= 0) & ({1'b0, x} < 320) & ({1'b0, y} >= 0) & ({1'b0, y} < 240)) & (RESOLUTION == "320x240");
 assign writeEn = (plot) & (valid_160x120 | valid_320x240);
 /* Allow the user to plot a pixel if and only if the (X,Y) coordinates supplied are in a valid range. */
 
 /* Create video memory. */
 altsyncram VideoMemory (
    .wren_a (writeEn),
    .wren_b (gnd),
    .clock0 (clock), // write clock
    .clock1 (clock_25), // read clock
    .clocken0 (vcc), // write enable clock
    .clocken1 (vcc), // read enable clock    
    .address_a (user_to_video_memory_addr),
    .address_b (controller_to_video_memory_addr),
    .data_a (colour), // data in
    .q_b (to_ctrl_colour) // data out
    );
 defparam
  VideoMemory.WIDTH_A = ((MONOCHROME == "FALSE") ? (BITS_PER_COLOUR_CHANNEL*3) : 1),
  VideoMemory.WIDTH_B = ((MONOCHROME == "FALSE") ? (BITS_PER_COLOUR_CHANNEL*3) : 1),
  VideoMemory.INTENDED_DEVICE_FAMILY = "Cyclone II",
  VideoMemory.OPERATION_MODE = "DUAL_PORT",
  VideoMemory.WIDTHAD_A = ((RESOLUTION == "320x240") ? (17) : (15)),
  VideoMemory.NUMWORDS_A = ((RESOLUTION == "320x240") ? (76800) : (19200)),
  VideoMemory.WIDTHAD_B = ((RESOLUTION == "320x240") ? (17) : (15)),
  VideoMemory.NUMWORDS_B = ((RESOLUTION == "320x240") ? (76800) : (19200)),
  VideoMemory.OUTDATA_REG_B = "CLOCK1",
  VideoMemory.ADDRESS_REG_B = "CLOCK1",
  VideoMemory.CLOCK_ENABLE_INPUT_A = "BYPASS",
  VideoMemory.CLOCK_ENABLE_INPUT_B = "BYPASS",
  VideoMemory.CLOCK_ENABLE_OUTPUT_B = "BYPASS",
  VideoMemory.POWER_UP_UNINITIALIZED = "FALSE",
  VideoMemory.INIT_FILE = BACKGROUND_IMAGE;
 
 vga_pll mypll(clock, clock_25);
 /* This module generates a clock with half the frequency of the input clock.
  * For the VGA adapter to operate correctly the clock signal 'clock' must be
  * a 50MHz clock. The derived clock, which will then operate at 25MHz, is
  * required to set the monitor into the 640x480@60Hz display mode (also known as
  * the VGA mode).
  */
 
 vga_controller controller(
   .vga_clock(clock_25),
   .resetn(resetn),
   .pixel_colour(to_ctrl_colour),
   .memory_address(controller_to_video_memory_addr),
   .VGA_R(VGA_R),
   .VGA_G(VGA_G),
   .VGA_B(VGA_B),
   .VGA_HS(VGA_HS),
   .VGA_VS(VGA_VS),
   .VGA_BLANK(VGA_BLANK),
   .VGA_SYNC(VGA_SYNC),
   .VGA_CLK(VGA_CLK)    
  );
  defparam controller.BITS_PER_COLOUR_CHANNEL  = BITS_PER_COLOUR_CHANNEL ;
  defparam controller.MONOCHROME = MONOCHROME;
  defparam controller.RESOLUTION = RESOLUTION;

endmodule

module vga_address_translator(x, y, mem_address);

 parameter RESOLUTION = "320x240";
 /* Set this parameter to "160x120" or "320x240". It will cause the VGA adapter to draw each dot on
  * the screen by using a block of 4x4 pixels ("160x120" resolution) or 2x2 pixels ("320x240" resolution).
  * It effectively reduces the screen resolution to an integer fraction of 640x480. It was necessary
  * to reduce the resolution for the Video Memory to fit within the on-chip memory limits.
  */

 input [((RESOLUTION == "320x240") ? (8) : (7)):0] x;
 input [((RESOLUTION == "320x240") ? (7) : (6)):0] y;
 output reg [((RESOLUTION == "320x240") ? (16) : (14)):0] mem_address;
 
 /* The basic formula is address = y*WIDTH + x;
  * For 320x240 resolution we can write 320 as (256 + 64). Memory address becomes
  * (y*256) + (y*64) + x;
  * This simplifies multiplication a simple shift and add operation.
  * A leading 0 bit is added to each operand to ensure that they are treated as unsigned
  * inputs. By default the use a '+' operator will generate a signed adder.
  * Similarly, for 160x120 resolution we write 160 as 128+32.
  */
 wire [16:0] res_320x240 = ({1'b0, y, 8'd0} + {1'b0, y, 6'd0} + {1'b0, x});
 wire [15:0] res_160x120 = ({1'b0, y, 7'd0} + {1'b0, y, 5'd0} + {1'b0, x});
 
 always @(*)
 begin
  if (RESOLUTION == "320x240")
   mem_address = res_320x240;
  else
   mem_address = res_160x120[14:0];
 end
endmodule

module vga_controller( vga_clock, resetn, pixel_colour, memory_address,
  VGA_R, VGA_G, VGA_B,
  VGA_HS, VGA_VS, VGA_BLANK,
  VGA_SYNC, VGA_CLK);
 
 /* Screen resolution and colour depth parameters. */
 
 parameter BITS_PER_COLOUR_CHANNEL = 1;
 /* The number of bits per colour channel used to represent the colour of each pixel. A value
  * of 1 means that Red, Green and Blue colour channels will use 1 bit each to represent the intensity
  * of the respective colour channel. For BITS_PER_COLOUR_CHANNEL=1, the adapter can display 8 colours.
  * In general, the adapter is able to use 2^(3*BITS_PER_COLOUR_CHANNEL) colours. The number of colours is
  * limited by the screen resolution and the amount of on-chip memory available on the target device.
  */
 
 parameter MONOCHROME = "FALSE";
 /* Set this parameter to "TRUE" if you only wish to use black and white colours. Doing so will reduce
  * the amount of memory you will use by a factor of 3. */
 
 parameter RESOLUTION = "320x240";
 /* Set this parameter to "160x120" or "320x240". It will cause the VGA adapter to draw each dot on
  * the screen by using a block of 4x4 pixels ("160x120" resolution) or 2x2 pixels ("320x240" resolution).
  * It effectively reduces the screen resolution to an integer fraction of 640x480. It was necessary
  * to reduce the resolution for the Video Memory to fit within the on-chip memory limits.
  */
 
 //--- Timing parameters.
 /* Recall that the VGA specification requires a few more rows and columns are drawn
  * when refreshing the screen than are actually present on the screen. This is necessary to
  * generate the vertical and the horizontal syncronization signals. If you wish to use a
  * display mode other than 640x480 you will need to modify the parameters below as well
  * as change the frequency of the clock driving the monitor (VGA_CLK).
  */
 parameter C_VERT_NUM_PIXELS  = 10'd480;
 parameter C_VERT_SYNC_START  = 10'd493;
 parameter C_VERT_SYNC_END    = 10'd494; //(C_VERT_SYNC_START + 2 - 1);
 parameter C_VERT_TOTAL_COUNT = 10'd525;

 parameter C_HORZ_NUM_PIXELS  = 10'd640;
 parameter C_HORZ_SYNC_START  = 10'd659;
 parameter C_HORZ_SYNC_END    = 10'd754; //(C_HORZ_SYNC_START + 96 - 1);
 parameter C_HORZ_TOTAL_COUNT = 10'd800;
 
 /*****************************************************************************/
 /* Declare inputs and outputs.                                               */
 /*****************************************************************************/
 
 input vga_clock, resetn;
 input [((MONOCHROME == "TRUE") ? (0) : (BITS_PER_COLOUR_CHANNEL*3-1)):0] pixel_colour;
 output [((RESOLUTION == "320x240") ? (16) : (14)):0] memory_address;
 output reg [9:0] VGA_R;
 output reg [9:0] VGA_G;
 output reg [9:0] VGA_B;
 output reg VGA_HS;
 output reg VGA_VS;
 output reg VGA_BLANK;
 output VGA_SYNC, VGA_CLK;
 
 /*****************************************************************************/
 /* Local Signals.                                                            */
 /*****************************************************************************/
 
 reg VGA_HS1;
 reg VGA_VS1;
 reg VGA_BLANK1;
 reg [9:0] xCounter, yCounter;
 wire xCounter_clear;
 wire yCounter_clear;
 wire vcc;
 
 reg [((RESOLUTION == "320x240") ? (8) : (7)):0] x;
 reg [((RESOLUTION == "320x240") ? (7) : (6)):0] y;
 /* Inputs to the converter. */
 
 /*****************************************************************************/
 /* Controller implementation.                                                */
 /*****************************************************************************/

 assign vcc =1'b1;
 
 /* A counter to scan through a horizontal line. */
 always @(posedge vga_clock or negedge resetn)
 begin
  if (!resetn)
   xCounter <= 10'd0;
  else if (xCounter_clear)
   xCounter <= 10'd0;
  else
  begin
   xCounter <= xCounter + 1'b1;
  end
 end
 assign xCounter_clear = (xCounter == (C_HORZ_TOTAL_COUNT-1));

 /* A counter to scan vertically, indicating the row currently being drawn. */
 always @(posedge vga_clock or negedge resetn)
 begin
  if (!resetn)
   yCounter <= 10'd0;
  else if (xCounter_clear && yCounter_clear)
   yCounter <= 10'd0;
  else if (xCounter_clear)  //Increment when x counter resets
   yCounter <= yCounter + 1'b1;
 end
 assign yCounter_clear = (yCounter == (C_VERT_TOTAL_COUNT-1));
 
 /* Convert the xCounter/yCounter location from screen pixels (640x480) to our
  * local dots (320x240 or 160x120). Here we effectively divide x/y coordinate by 2 or 4,
  * depending on the resolution. */
 always @(*)
 begin
  if (RESOLUTION == "320x240")
  begin
   x = xCounter[9:1];
   y = yCounter[8:1];
  end
  else
  begin
   x = xCounter[9:2];
   y = yCounter[8:2];
  end
 end
 
 /* Change the (x,y) coordinate into a memory address. */
 vga_address_translator controller_translator(
     .x(x), .y(y), .mem_address(memory_address) );
  defparam controller_translator.RESOLUTION = RESOLUTION;


 /* Generate the vertical and horizontal synchronization pulses. */
 always @(posedge vga_clock)
 begin
  //- Sync Generator (ACTIVE LOW)
  VGA_HS1 <= ~((xCounter >= C_HORZ_SYNC_START) && (xCounter <= C_HORZ_SYNC_END));
  VGA_VS1 <= ~((yCounter >= C_VERT_SYNC_START) && (yCounter <= C_VERT_SYNC_END));
 
  //- Current X and Y is valid pixel range
  VGA_BLANK1 <= ((xCounter < C_HORZ_NUM_PIXELS) && (yCounter < C_VERT_NUM_PIXELS));
 
  //- Add 1 cycle delay
  VGA_HS <= VGA_HS1;
  VGA_VS <= VGA_VS1;
  VGA_BLANK <= VGA_BLANK1;
 end
 
 /* VGA sync should be 1 at all times. */
 assign VGA_SYNC = vcc;
 
 /* Generate the VGA clock signal. */
 assign VGA_CLK = vga_clock;
 
 /* Brighten the colour output. */
 // The colour input is first processed to brighten the image a little. Setting the top
 // bits to correspond to the R,G,B colour makes the image a bit dull. To brighten the image,
 // each bit of the colour is replicated through the 10 DAC colour input bits. For example,
 // when BITS_PER_COLOUR_CHANNEL is 2 and the red component is set to 2'b10, then the
 // VGA_R input to the DAC will be set to 10'b1010101010.
 
 integer index;
 integer sub_index;
 
 always @(pixel_colour)
 begin  
  VGA_R <= 'b0;
  VGA_G <= 'b0;
  VGA_B <= 'b0;
  if (MONOCHROME == "FALSE")
  begin
   for (index = 10-BITS_PER_COLOUR_CHANNEL; index >= 0; index = index - BITS_PER_COLOUR_CHANNEL)
   begin
    for (sub_index = BITS_PER_COLOUR_CHANNEL - 1; sub_index >= 0; sub_index = sub_index - 1)
    begin
     VGA_R[sub_index+index] <= pixel_colour[sub_index + BITS_PER_COLOUR_CHANNEL*2];
     VGA_G[sub_index+index] <= pixel_colour[sub_index + BITS_PER_COLOUR_CHANNEL];
     VGA_B[sub_index+index] <= pixel_colour[sub_index];
    end
   end
  end
  else
  begin
   for (index = 0; index < 10; index = index + 1)
   begin
    VGA_R[index] <= pixel_colour[0:0];
    VGA_G[index] <= pixel_colour[0:0];
    VGA_B[index] <= pixel_colour[0:0];
   end
  end
 end

endmodule

`timescale 1 ps / 1 ps
// synopsys translate_on
module vga_pll (
 clock_in,
 clock_out);

 input   clock_in;
 output   clock_out;

 wire [5:0] clock_output_bus;
 wire [1:0] clock_input_bus;
 wire gnd;
 
 assign gnd = 1'b0;
 assign clock_input_bus = { gnd, clock_in };

 altpll altpll_component (
    .inclk (clock_input_bus),
    .clk (clock_output_bus)
    );
 defparam
  altpll_component.operation_mode = "NORMAL",
  altpll_component.intended_device_family = "Cyclone II",
  altpll_component.lpm_type = "altpll",
  altpll_component.pll_type = "FAST",
  /* Specify the input clock to be a 50MHz clock. A 50 MHz clock is present
   * on PIN_N2 on the DE2 board. We need to specify the input clock frequency
   * in order to set up the PLL correctly. To do this we must put the input clock
   * period measured in picoseconds in the inclk0_input_frequency parameter.
   * 1/(20000 ps) = 0.5 * 10^(5) Hz = 50 * 10^(6) Hz = 50 MHz. */
  altpll_component.inclk0_input_frequency = 20000,
  altpll_component.primary_clock = "INCLK0",
  /* Specify output clock parameters. The output clock should have a
   * frequency of 25 MHz, with 50% duty cycle. */
  altpll_component.compensate_clock = "CLK0",
  altpll_component.clk0_phase_shift = "0",
  altpll_component.clk0_divide_by = 2,
  altpll_component.clk0_multiply_by = 1,  
  altpll_component.clk0_duty_cycle = 50;
 
 assign clock_out = clock_output_bus[0];

endmodule
