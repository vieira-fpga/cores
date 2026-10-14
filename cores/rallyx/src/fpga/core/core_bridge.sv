`default_nettype none

// The APF bridge side of the core: the bridge map, the host and target command handlers, and the
// datatable RAM. All ports are on clk (clk_74a). Each group of core-facing ports belongs to one
// module, which documents its handshake: dataslot_requests, savestate, rtc_osnotify, and
// target_cmd. core_top connects them to the core, or to bridge_defaults where the core doesn't
// use them. User region devices answer user_rd and user_wr, and return data as bridge_map
// describes.
module core_bridge
  import bridge_pkg::*;
(
    input  wire logic clk,
    output wire logic reset_n,

    input wire logic bridge_endian_little,
    input wire logic [31:0] bridge_addr,
    input wire logic bridge_rd,
    output wire logic [31:0] bridge_rd_data,
    input wire logic bridge_wr,
    input wire logic [31:0] bridge_wr_data,

    output wire logic user_rd,
    output wire logic user_wr,
    input wire logic [31:0] user_rd_data,

    input wire logic status_boot_done,
    input wire logic status_setup_done,
    input wire logic status_running,

    output var dataslot_to_core_t dataslot_to_core,
    input var dataslot_from_core_t dataslot_from_core,
    output var savestate_to_core_t savestate_to_core,
    input var savestate_from_core_t savestate_from_core,
    output var rtc_osnotify_to_core_t rtc_osnotify_to_core,
    input var target_request_t target_request,
    output var target_response_t target_response,
    input var datatable_from_core_t datatable_from_core,
    output wire logic [31:0] datatable_q
);
  var apf_bus_t host_bus;
  var apf_bus_t target_bus;
  var apf_bus_t datatable_bus;
  wire logic [31:0] host_rd_data;
  wire logic [31:0] target_rd_data;
  wire logic [31:0] datatable_rd_data;

  // Reading the datatable has no side effects.
  wire logic unused = datatable_bus.rd;

  var host_request_t host_request;
  var host_response_t host_response;
  var host_response_t dataslot_response;
  var host_response_t savestate_response;
  var host_response_t rtc_osnotify_response;

  bridge_map map (
      .clk,
      .bridge_endian_little,
      .bridge_addr,
      .bridge_rd,
      .bridge_rd_data,
      .bridge_wr,
      .bridge_wr_data,
      .user_rd,
      .user_wr,
      .user_rd_data,
      .host_bus,
      .host_rd_data,
      .target_bus,
      .target_rd_data,
      .datatable_bus,
      .datatable_rd_data
  );

  host_cmd host (
      .clk,
      .reset_n,
      .bus(host_bus),
      .rd_data(host_rd_data),
      .status_boot_done,
      .status_setup_done,
      .status_running,
      .request(host_request),
      .response(host_response)
  );

  // Each concept module answers only the commands it claims, and zeros otherwise.
  always_comb begin
    host_response = dataslot_response | savestate_response | rtc_osnotify_response;
  end

  // Two claims would OR two answers together. Quartus builds nothing from the assertion.
  always_ff @(posedge clk) begin
    assert ($onehot0(
        {dataslot_response.claim, savestate_response.claim, rtc_osnotify_response.claim}
    ))
    else begin
      $error("ERROR host_claim: more than one concept module claimed command %04h",
             host_request.command);
    end
  end

  dataslot_requests dataslot (
      .clk,
      .request  (host_request),
      .response (dataslot_response),
      .to_core  (dataslot_to_core),
      .from_core(dataslot_from_core)
  );

  savestate savestate (
      .clk,
      .request  (host_request),
      .response (savestate_response),
      .to_core  (savestate_to_core),
      .from_core(savestate_from_core)
  );

  rtc_osnotify rtc_osnotify (
      .clk,
      .request (host_request),
      .response(rtc_osnotify_response),
      .to_core (rtc_osnotify_to_core)
  );

  target_cmd target (
      .clk,
      .bus(target_bus),
      .rd_data(target_rd_data),
      .status_setup_done,
      .request(target_request),
      .response(target_response)
  );

  // Port a is the core's, port b the bridge's. apf/build_id_gen.tcl writes the build ID into
  // words 0xE0-0xE2 at compile time.
  mf_datatable datatable (
      .address_a(datatable_from_core.addr),
      .address_b(datatable_bus.addr),
      .clock_a(clk),
      .clock_b(clk),
      .data_a(datatable_from_core.data),
      .data_b(datatable_bus.wr_data),
      .wren_a(datatable_from_core.wren),
      .wren_b(datatable_bus.wr),
      .q_a(datatable_q),
      .q_b(datatable_rd_data)
  );
endmodule

`default_nettype wire
