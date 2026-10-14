`default_nettype none

// Carries one-cycle events from clk_src to clk_dst with a toggle synchronizer. Each cycle that
// pulse_src is high toggles a register in clk_src, and pulse_dst is high for one clk_dst cycle per
// toggle. Space events at least 4 clk_dst cycles apart, or two of them cancel out.
module sync_pulse (
    input  wire logic clk_src,
    input  wire logic pulse_src,
    input  wire logic clk_dst,
    output wire logic pulse_dst
);
  // A power-up value instead of a reset: resetting either side alone would fake an event.
  var logic  toggle = 1'b0;
  wire logic rise;
  wire logic fall;

  always_ff @(posedge clk_src) begin
    toggle <= toggle ^ pulse_src;
  end

  synch_3 sync (
      .i  (toggle),
      .o  (),
      .clk(clk_dst),
      .rise,
      .fall
  );

  assign pulse_dst = rise || fall;
endmodule

`default_nettype wire
