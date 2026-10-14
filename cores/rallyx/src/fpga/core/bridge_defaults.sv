`default_nettype none

// Default responder: the answers core_bridge gets from a core that doesn't use data slots,
// savestates, target commands, or the datatable. It acks and accepts every data slot request,
// reports savestates unsupported and fails any start or load at once, issues no target commands,
// and leaves the datatable's core port idle. Replace an output with real logic when the core
// starts to use that part of the bridge.
module bridge_defaults
  import bridge_pkg::*;
(
    output var dataslot_from_core_t dataslot_from_core,
    output var savestate_from_core_t savestate_from_core,
    output var target_request_t target_request,
    output var datatable_from_core_t datatable_from_core
);
  always_comb begin
    dataslot_from_core = '0;
    dataslot_from_core.requestread_ack = 1'b1;
    dataslot_from_core.requestread_ok = 1'b1;
    dataslot_from_core.requestwrite_ack = 1'b1;
    dataslot_from_core.requestwrite_ok = 1'b1;

    savestate_from_core = '0;
    savestate_from_core.start_ack = 1'b1;
    savestate_from_core.start_err = 1'b1;
    savestate_from_core.load_ack = 1'b1;
    savestate_from_core.load_err = 1'b1;

    target_request = '0;
    datatable_from_core = '0;
  end
endmodule

`default_nettype wire
