`default_nettype none

// Data slot host commands. Connect request and response to host_cmd, and to_core and from_core to
// the core. All ports are on clk (clk_74a).
//   0x0080 request read, 0x0082 request write: to_core.requestread or requestwrite stays high until
//     the core sets the matching ack. The result is 0, or 2 when the core clears ok.
//   0x008A update: to_core.update is high for one cycle with the slot id and size. APF sends it
//     only for slots marked deferload.
//   0x008F all complete: to_core.allcomplete stays high until the next request read or write.
module dataslot_requests
  import bridge_pkg::*;
(
    input wire logic clk,
    input var host_request_t request,
    output var host_response_t response,
    output var dataslot_to_core_t to_core,
    input var dataslot_from_core_t from_core
);
  localparam logic [15:0] CMD_REQUEST_READ = 16'h0080;
  localparam logic [15:0] CMD_REQUEST_WRITE = 16'h0082;
  localparam logic [15:0] CMD_UPDATE = 16'h008A;
  localparam logic [15:0] CMD_ALL_COMPLETE = 16'h008F;

  localparam logic [15:0] RESULT_OK = 16'h0000;
  localparam logic [15:0] RESULT_REFUSED = 16'h0002;

  // Part of the bridge, which runs before the core leaves reset: starts from power-up values.
  var dataslot_to_core_t slot = '0;

  var logic is_read;
  var logic is_write;
  var logic is_update;
  var logic is_all_complete;
  var logic read_done;
  var logic write_done;

  always_comb begin
    is_read = request.active && request.command == CMD_REQUEST_READ;
    is_write = request.active && request.command == CMD_REQUEST_WRITE;
    is_update = request.active && request.command == CMD_UPDATE;
    is_all_complete = request.active && request.command == CMD_ALL_COMPLETE;

    read_done = is_read && slot.requestread && from_core.requestread_ack;
    write_done = is_write && slot.requestwrite && from_core.requestwrite_ack;

    response = '0;
    response.claim = is_read || is_write || is_update || is_all_complete;
    response.done = read_done || write_done || is_update || is_all_complete;

    if (read_done && !from_core.requestread_ok) begin
      response.result = RESULT_REFUSED;
    end else if (write_done && !from_core.requestwrite_ok) begin
      response.result = RESULT_REFUSED;
    end else begin
      response.result = RESULT_OK;
    end
  end

  always_ff @(posedge clk) begin
    slot.update <= 1'b0;
    slot.requestread <= is_read && !read_done;
    slot.requestwrite <= is_write && !write_done;

    if (request.start) begin
      if (is_read) begin
        slot.requestread_id <= request.param[0][15:0];
        slot.allcomplete <= 1'b0;
      end else if (is_write) begin
        slot.requestwrite_id <= request.param[0][15:0];
        slot.requestwrite_size <= request.param[1];
        slot.allcomplete <= 1'b0;
      end else if (is_update) begin
        slot.update <= 1'b1;
        slot.update_id <= request.param[0][15:0];
        slot.update_size <= request.param[1];
      end else if (is_all_complete) begin
        slot.allcomplete <= 1'b1;
      end
    end
  end

  always_comb begin
    to_core = slot;
  end
endmodule

`default_nettype wire
