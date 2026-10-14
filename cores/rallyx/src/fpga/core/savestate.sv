`default_nettype none

// Savestate host commands. Connect request and response to host_cmd, and to_core and from_core to
// the core. All ports are on clk (clk_74a).
//   0x00A0 start or query: response words are supported, addr, and size.
//   0x00A4 load or query: response words are supported, addr, and maxloadsize.
// When parameter bit 0 is set, the command also asks for a start or load: to_core.start or load
// stays high until the core sets the matching ack. The result reports the core's status bits when
// the command finishes: 0 idle, 1 busy, 2 ok, 3 err.
module savestate
  import bridge_pkg::*;
(
    input wire logic clk,
    input var host_request_t request,
    output var host_response_t response,
    output var savestate_to_core_t to_core,
    input var savestate_from_core_t from_core
);
  localparam logic [15:0] CMD_START = 16'h00A0;
  localparam logic [15:0] CMD_LOAD  = 16'h00A4;

  // Part of the bridge, which runs before the core leaves reset: starts from power-up values.
  var savestate_to_core_t requested = '0;

  // A savestate command acts for as long as it's active, so the first cycle needs nothing extra.
  wire logic unused = request.start;

  var logic is_start;
  var logic is_load;
  var logic start_wanted;
  var logic load_wanted;

  function automatic logic [15:0] result_code(input logic busy, input logic ok, input logic err);
    if (err) begin
      return 16'h0003;
    end
    if (ok) begin
      return 16'h0002;
    end
    if (busy) begin
      return 16'h0001;
    end
    return 16'h0000;
  endfunction

  always_comb begin
    is_start = request.active && request.command == CMD_START;
    is_load = request.active && request.command == CMD_LOAD;
    start_wanted = is_start && request.param[0][0];
    load_wanted = is_load && request.param[0][0];

    response = '0;
    if (is_start) begin
      response.claim = 1'b1;
      response.done = !start_wanted || (requested.start && from_core.start_ack);
      response.result = result_code(from_core.start_busy, from_core.start_ok, from_core.start_err);
      response.response[0] = 32'(from_core.supported);
      response.response[1] = from_core.addr;
      response.response[2] = from_core.size;
    end else if (is_load) begin
      response.claim = 1'b1;
      response.done = !load_wanted || (requested.load && from_core.load_ack);
      response.result = result_code(from_core.load_busy, from_core.load_ok, from_core.load_err);
      response.response[0] = 32'(from_core.supported);
      response.response[1] = from_core.addr;
      response.response[2] = from_core.maxloadsize;
    end
  end

  always_ff @(posedge clk) begin
    requested.start <= start_wanted && !response.done;
    requested.load  <= load_wanted && !response.done;
  end

  always_comb begin
    to_core = requested;
  end
endmodule

`default_nettype wire
