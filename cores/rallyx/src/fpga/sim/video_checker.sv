`default_nettype none

// Checks the scaler's video timing rules from the openFPGA bus docs on every pixel clock:
//   - vs and hs last one clock.
//   - The first hs comes at least 3 clocks after vs.
//   - At least one clock separates hs from the rise of de, and the fall of de from the next hs.
//   - de rises once per line and stays high for exactly H_ACTIVE clocks.
//   - rgb is 0 whenever de is low.
// Bind it to the module that drives the video, with every port on that module's pixel clock.
// reset_n is the video logic's synchronous reset: a reset cuts the current line short, so the
// checker skips clocks while it's low. Each failure stops the run with $error. Keep this file out
// of the Quartus project.
module video_checker #(
    parameter int unsigned H_ACTIVE = 320
) (
    input wire logic clk,
    input wire logic reset_n,
    input wire logic [23:0] rgb,
    input wire logic de,
    input wire logic hs,
    input wire logic vs
);
  localparam int unsigned VS_TO_HS = 3;

  logic hs_q = 1'b0;
  logic vs_q = 1'b0;
  logic de_q = 1'b0;
  logic seen_vs = 1'b0;
  int unsigned since_vs = 0;  // clocks since the last vs, 1 on the clock after it
  int unsigned de_rises = 0;  // since the last hs
  int unsigned de_width = 0;  // clocks of the current or last de pulse

  var logic de_rise;
  var logic de_fall;

  always_comb begin
    de_rise = de && !de_q;
    de_fall = !de && de_q;
  end

  always @(posedge clk) begin
    hs_q <= hs;
    vs_q <= vs;
    de_q <= de;

    if (vs) begin
      seen_vs  <= 1'b1;
      since_vs <= 1;
    end else if (since_vs < VS_TO_HS) begin
      since_vs <= since_vs + 1;
    end

    if (hs) begin
      de_rises <= 0;
    end else if (de_rise) begin
      de_rises <= de_rises + 1;
    end

    if (de) begin
      de_width <= de_rise ? 1 : de_width + 1;
    end

    if (reset_n) begin
      assert (!(vs && vs_q))
      else begin
        $error("ERROR video_vs_width: vs high for more than one clock");
      end
      assert (!(hs && hs_q))
      else begin
        $error("ERROR video_hs_width: hs high for more than one clock");
      end
      assert (!(hs && seen_vs && (vs || since_vs < VS_TO_HS)))
      else begin
        $error("ERROR video_vs_to_hs: hs %0d clocks after vs, needs %0d", vs ? 0 : since_vs,
               VS_TO_HS);
      end
      assert (!(de_rise && (hs || hs_q)))
      else begin
        $error("ERROR video_hs_to_de: de rose less than 2 clocks after hs");
      end
      assert (!(hs && (de || de_q)))
      else begin
        $error("ERROR video_de_to_hs: hs came less than 2 clocks after de fell");
      end
      assert (!(de_rise && de_rises != 0))
      else begin
        $error("ERROR video_de_once: de rose twice in one line");
      end
      assert (!(de_fall && de_width != H_ACTIVE))
      else begin
        $error("ERROR video_de_width: de high for %0d clocks, expected %0d", de_width, H_ACTIVE);
      end
      assert (de || rgb == '0)
      else begin
        $error("ERROR video_rgb_blank: rgb is %06h while de is low", rgb);
      end
    end
  end
endmodule

`default_nettype wire
