`default_nettype none

// Null mf_datatable for `verilator --lint-only`: the ports of the APF datatable RAM and no logic.
// Lint only. Never add it to the Quartus project or a simulation.
module mf_datatable (
    input  wire logic [ 7:0] address_a,
    input  wire logic [ 7:0] address_b,
    input  wire logic        clock_a,
    input  wire logic        clock_b,
    input  wire logic [31:0] data_a,
    input  wire logic [31:0] data_b,
    input  wire logic        wren_a,
    input  wire logic        wren_b,
    output wire logic [31:0] q_a,
    output wire logic [31:0] q_b
);
  wire logic unused = ^{address_a, address_b, clock_a, clock_b, data_a, data_b, wren_a, wren_b};

  assign q_a = '0;
  assign q_b = '0;
endmodule

`default_nettype wire
