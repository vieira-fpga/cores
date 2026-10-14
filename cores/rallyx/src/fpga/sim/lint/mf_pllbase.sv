`default_nettype none

// Null mf_pllbase for `verilator --lint-only`: the ports of the Quartus PLL IP and no logic. Lint
// only. Never add it to the Quartus project or a simulation.
module mf_pllbase (
    input  wire logic refclk,
    input  wire logic rst,
    output wire logic outclk_0,
    output wire logic outclk_1,
    output wire logic outclk_2,
    output wire logic outclk_3,
    output wire logic outclk_4,
    output wire logic locked
);
  wire logic unused = refclk ^ rst;

  assign outclk_0 = 1'b0;
  assign outclk_1 = 1'b0;
  assign outclk_2 = 1'b0;
  assign outclk_3 = 1'b0;
  assign outclk_4 = 1'b0;
  assign locked   = 1'b0;
endmodule

`default_nettype wire
