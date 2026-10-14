`default_nettype none

// Null synch_3 for `verilator --lint-only`: the ports of the APF synchronizer in apf/common.v and
// no logic, so lint covers only our RTL. Lint only. Never add it to the Quartus project or a
// simulation.
module synch_3 #(
    parameter int WIDTH = 1
) (
    input  wire logic [WIDTH-1:0] i,
    output wire logic [WIDTH-1:0] o,
    input  wire logic             clk,
    output wire logic             rise,
    output wire logic             fall
);
  wire logic unused = ^{i, clk};

  assign o = '0;
  assign rise = 1'b0;
  assign fall = 1'b0;
endmodule

`default_nettype wire
