`default_nettype none

// Null sound_i2s for `verilator --lint-only`: the ports of the vendored module in
// core/vendor/analogue-pocket-utils and no logic, so lint covers only our RTL. Lint only. Never
// add it to the Quartus project or a simulation.
module sound_i2s #(
    parameter int CHANNEL_WIDTH = 15,
    parameter int SIGNED_INPUT  = 0
) (
    input  wire logic                     clk_74a,
    input  wire logic                     clk_audio,
    input  wire logic [CHANNEL_WIDTH-1:0] audio_l,
    input  wire logic [CHANNEL_WIDTH-1:0] audio_r,
    output wire logic                     audio_mclk,
    output wire logic                     audio_lrck,
    output wire logic                     audio_dac
);
  wire logic unused = ^{clk_74a, clk_audio, audio_l, audio_r, 1'(SIGNED_INPUT)};

  assign audio_mclk = 1'b0;
  assign audio_lrck = 1'b0;
  assign audio_dac  = 1'b0;
endmodule

`default_nettype wire
