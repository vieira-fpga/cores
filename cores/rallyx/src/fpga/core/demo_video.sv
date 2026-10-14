`default_nettype none

// The template's demo: a gray 320x240 screen at 60 Hz. It stands in for a core's game logic, so
// it uses no openFPGA signals, and core_top wires its outputs to the scaler. Replace it with the
// core's own top module.
//
// All ports are on clk, the 12.288 MHz pixel clock, one clock per pixel. reset_n is synchronous.
// While it's low, every output is low. On release, a frame starts at once.
//
// Each line takes 400 clocks and each frame 512 lines: 204,800 clocks, or 60 Hz. The beam counts
// in signed coordinates, with blanking at negative x and y and the first visible pixel at (0, 0).
// frame_start and line_start are one-cycle strobes for per-frame and per-line logic, high on the
// first clock of each frame and line. vs and hs pulse for one clock, as the scaler needs: vs with
// frame_start, and hs 3 clocks after line_start, so the first hs comes 3 clocks after vs. de is
// high for each visible pixel, and rgb is 0 whenever de is low. All outputs are registered
// together, one clock after the beam.
module demo_video (
    input wire logic clk,
    input wire logic reset_n,

    output var logic frame_start,
    output var logic line_start,

    output var logic [23:0] rgb,
    output var logic de,
    output var logic hs,
    output var logic vs
);
  localparam int H_ACTIVE = 320;
  localparam int H_TOTAL = 400;
  localparam int V_ACTIVE = 240;
  localparam int V_TOTAL = 512;
  localparam logic [23:0] GRAY = 24'h3C3C3C;

  typedef logic signed [9:0] coord_t;

  localparam coord_t X_START = coord_t'(H_ACTIVE - H_TOTAL);
  localparam coord_t X_LAST = coord_t'(H_ACTIVE - 1);
  localparam coord_t Y_START = coord_t'(V_ACTIVE - V_TOTAL);
  localparam coord_t Y_LAST = coord_t'(V_ACTIVE - 1);
  localparam coord_t HS_X = coord_t'(H_ACTIVE - H_TOTAL + 3);  // 3 clocks after line start

  var coord_t x;
  var coord_t y;

  var logic   at_line_start;
  var logic   at_frame_start;
  var logic   visible;

  always_comb begin
    at_line_start = x == X_START;
    at_frame_start = at_line_start && y == Y_START;
    visible = x >= 0 && y >= 0;
  end

  always_ff @(posedge clk) begin
    if (!reset_n) begin
      x <= X_START;
      y <= Y_START;
    end else if (x == X_LAST) begin
      x <= X_START;
      y <= y == Y_LAST ? Y_START : y + coord_t'(1);
    end else begin
      x <= x + coord_t'(1);
    end
  end

  always_ff @(posedge clk) begin
    frame_start <= 1'b0;
    line_start <= 1'b0;
    vs <= 1'b0;
    hs <= 1'b0;
    de <= 1'b0;
    rgb <= '0;

    if (reset_n) begin
      frame_start <= at_frame_start;
      line_start <= at_line_start;
      vs <= at_frame_start;
      hs <= x == HS_X;
      de <= visible;
      rgb <= visible ? GRAY : '0;
    end
  end
endmodule

`default_nettype wire
