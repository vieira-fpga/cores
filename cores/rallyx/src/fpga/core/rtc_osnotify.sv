`default_nettype none

// RTC and OS notify host commands. Neither waits for the core, so both finish at once. Connect
// request and response to host_cmd, and to_core to the core. All ports are on clk (clk_74a).
//   0x0090 RTC: to_core.rtc_valid is high for one cycle with new epoch seconds, BCD date, and BCD
//     time from parameter words 0 to 2. Every update gives a new rising edge.
//   0x00B0 menu state: to_core.osnotify_inmenu follows parameter bit 0.
module rtc_osnotify
  import bridge_pkg::*;
(
    input wire logic clk,
    input var host_request_t request,
    output var host_response_t response,
    output var rtc_osnotify_to_core_t to_core
);
  localparam logic [15:0] CMD_RTC = 16'h0090;
  localparam logic [15:0] CMD_MENU_STATE = 16'h00B0;

  // Part of the bridge, which runs before the core leaves reset: starts from power-up values.
  var rtc_osnotify_to_core_t notify = '0;

  var logic is_rtc;
  var logic is_menu_state;

  always_comb begin
    is_rtc = request.active && request.command == CMD_RTC;
    is_menu_state = request.active && request.command == CMD_MENU_STATE;

    response = '0;
    response.claim = is_rtc || is_menu_state;
    response.done = is_rtc || is_menu_state;
  end

  always_ff @(posedge clk) begin
    notify.rtc_valid <= 1'b0;

    if (request.start && is_rtc) begin
      notify.rtc_valid <= 1'b1;
      notify.rtc_epoch_seconds <= request.param[0];
      notify.rtc_date_bcd <= request.param[1];
      notify.rtc_time_bcd <= request.param[2];
    end

    if (request.start && is_menu_state) begin
      notify.osnotify_inmenu <= request.param[0][0];
    end
  end

  always_comb begin
    to_core = notify;
  end
endmodule

`default_nettype wire
