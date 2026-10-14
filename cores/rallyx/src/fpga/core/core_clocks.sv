`default_nettype none

// The core's clocks and resets, and every crossing out of clk_74a. core_constraints.sdc holds the
// matching clock constraints.
//   - The PLL makes clk_core_12288 and clk_core_12288_90deg from clk_74a.
//   - pll_core_locked is the PLL's lock, synchronized to clk_74a.
//   - reset_n_12288 is reset_n from the host command handler, synchronized to clk_core_12288 and
//     held low until the PLL locks. Use it as a synchronous reset in that domain. The synchronizer
//     runs on clk_core_12288, so a lost lock resets the domain only while that clock still
//     toggles. A template accepts this: clk_74a comes from a fixed oscillator and nothing resets
//     the PLL, so lock shouldn't drop after boot, and the demo video recovers in a frame anyway.
//     A core whose state must not survive a lost lock should hold reset_n_12288 low for a count
//     of clk_core_12288 cycles after lock returns.
//   - Each bit of level_74a reaches level_12288 through a three-register synchronizer. Each bit
//     must be a level on its own. Never cross a multi-bit value this way.
//   - Each bit of pulse_74a is a one-cycle event, and reaches pulse_12288 through a toggle
//     synchronizer. Space events at least 4 clk_core_12288 cycles (25 clk_74a cycles) apart.
// A value that holds still between events, such as a slot id next to its update pulse, is safe to
// read in clk_core_12288 once the event arrives.
module core_clocks #(
    parameter int unsigned LEVEL_WIDTH = 1,
    parameter int unsigned PULSE_WIDTH = 1
) (
    input wire logic clk_74a,
    input wire logic reset_n,

    output wire logic clk_core_12288,
    output wire logic clk_core_12288_90deg,
    output wire logic pll_core_locked,
    output wire logic reset_n_12288,

    input  wire logic [LEVEL_WIDTH-1:0] level_74a,
    output wire logic [LEVEL_WIDTH-1:0] level_12288,
    input  wire logic [PULSE_WIDTH-1:0] pulse_74a,
    output wire logic [PULSE_WIDTH-1:0] pulse_12288
);
  wire logic pll_locked;
  var logic  run_74a;

  // The template leaves outclk_2 to outclk_4 (133.12 MHz) unused, so Quartus removes them.
  mf_pllbase pll (
      .refclk(clk_74a),
      .rst(1'b0),
      .outclk_0(clk_core_12288),
      .outclk_1(clk_core_12288_90deg),
      .outclk_2(),
      .outclk_3(),
      .outclk_4(),
      .locked(pll_locked)
  );

  synch_3 lock_sync (
      .i(pll_locked),
      .o(pll_core_locked),
      .clk(clk_74a),
      .rise(),
      .fall()
  );

  // clk_core_12288 logic runs once the host releases reset and the PLL has locked. Registering
  // the AND keeps logic out of the synchronizer's input.
  always_ff @(posedge clk_74a) begin
    run_74a <= reset_n && pll_core_locked;
  end

  synch_3 reset_sync (
      .i(run_74a),
      .o(reset_n_12288),
      .clk(clk_core_12288),
      .rise(),
      .fall()
  );

  genvar i;
  generate
    for (i = 0; i < LEVEL_WIDTH; i = i + 1) begin : g_level
      synch_3 sync (
          .i(level_74a[i]),
          .o(level_12288[i]),
          .clk(clk_core_12288),
          .rise(),
          .fall()
      );
    end

    for (i = 0; i < PULSE_WIDTH; i = i + 1) begin : g_pulse
      sync_pulse sync (
          .clk_src  (clk_74a),
          .pulse_src(pulse_74a[i]),
          .clk_dst  (clk_core_12288),
          .pulse_dst(pulse_12288[i])
      );
    end
  endgenerate
endmodule

`default_nettype wire
