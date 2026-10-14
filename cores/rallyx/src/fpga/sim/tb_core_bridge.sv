`default_nettype none

// Tests core_bridge through the bridge bus and its core-facing ports: the host command handshakes
// of each concept module, target commands, status and reset, user region reads and writes, and
// the endian swap. The testbench plays the core, so it can delay acks and pick results, and a
// user region device that answers USER_LATENCY cycles after user_rd, like a slow memory. Run with
// the altera_mf_ver library.
module tb_core_bridge;
  timeunit 1ns; timeprecision 1ps;

  import bridge_pkg::*;

  localparam logic [31:0] TARGET_CMD = 32'hF800_1000;
  localparam logic [31:0] TARGET_PARAM0 = 32'hF800_1020;
  localparam logic [31:0] HOST_CMD = 32'hF800_0000;
  localparam logic [31:0] HOST_PARAM0 = 32'hF800_0020;
  localparam logic [31:0] HOST_PARAM_POINTER = 32'hF800_0004;
  localparam logic [31:0] DATATABLE = 32'hF800_2000;
  localparam int unsigned USER_LATENCY = 10;
  localparam int unsigned WATCHDOG_CYCLES = 1_000_000;

  var logic clk;
  var logic bridge_endian_little = 1'b0;

  wire logic reset_n;
  wire logic [31:0] bridge_addr;
  wire logic bridge_rd;
  wire logic [31:0] bridge_rd_data;
  wire logic bridge_wr;
  wire logic [31:0] bridge_wr_data;

  wire logic user_rd;
  wire logic user_wr;
  var logic [31:0] user_rd_data = '0;

  var logic status_boot_done = 1'b0;
  var logic status_setup_done = 1'b0;
  var logic status_running = 1'b0;

  var dataslot_to_core_t dataslot_to_core;
  var dataslot_from_core_t dataslot_from_core = '0;
  var savestate_to_core_t savestate_to_core;
  var savestate_from_core_t savestate_from_core = '0;
  var rtc_osnotify_to_core_t rtc_osnotify_to_core;
  var target_request_t target_request = '0;
  var target_response_t target_response;

  int unsigned checks = 0;
  int unsigned errors = 0;

  core_bridge dut (
      .clk,
      .reset_n,
      .bridge_endian_little,
      .bridge_addr,
      .bridge_rd,
      .bridge_rd_data,
      .bridge_wr,
      .bridge_wr_data,
      .user_rd,
      .user_wr,
      .user_rd_data,
      .status_boot_done,
      .status_setup_done,
      .status_running,
      .dataslot_to_core,
      .dataslot_from_core,
      .savestate_to_core,
      .savestate_from_core,
      .rtc_osnotify_to_core,
      .target_request,
      .target_response,
      .datatable_from_core('0),
      .datatable_q()
  );

  apf_bridge_model host (
      .clk,
      .bridge_addr,
      .bridge_rd,
      .bridge_rd_data,
      .bridge_wr,
      .bridge_wr_data
  );

  // The testbench drives the core side through this clocking block.
  clocking cb @(posedge clk);
    default input #1step output #2ns;
    input dataslot_to_core, savestate_to_core, rtc_osnotify_to_core, target_response;
    input bridge_addr, user_rd, user_wr;
    output bridge_endian_little, user_rd_data;
    output status_boot_done, status_setup_done, status_running;
    output dataslot_from_core, savestate_from_core;
    inout target_request;
  endclocking

  initial begin
    clk <= 1'b0;
    forever begin
      #6.734ns clk <= ~clk;
    end
  end

  initial begin
    repeat (WATCHDOG_CYCLES) @(posedge clk);
    $fatal(1, "ERROR watchdog: test did not finish in %0d cycles", WATCHDOG_CYCLES);
  end

  // The user region device: latches the address on user_rd, answers USER_LATENCY cycles later, and
  // holds the data until the next read.
  initial begin
    forever begin
      logic [31:0] addr;

      @(cb iff cb.user_rd);
      addr = cb.bridge_addr;
      repeat (USER_LATENCY) @(cb);
      cb.user_rd_data <= {8'hD4, addr[23:0]};
    end
  end

  int unsigned user_writes = 0;

  always @(cb) begin
    user_writes += int'(cb.user_wr);
  end

  // Counts the rising edges and high cycles of the one-cycle outputs.
  int unsigned rtc_edges = 0;
  int unsigned rtc_high_cycles = 0;
  int unsigned update_edges = 0;
  int unsigned update_high_cycles = 0;
  logic rtc_valid_q = 1'b0;
  logic update_q = 1'b0;

  always @(cb) begin
    rtc_valid_q <= cb.rtc_osnotify_to_core.rtc_valid;
    update_q <= cb.dataslot_to_core.update;
    if (cb.rtc_osnotify_to_core.rtc_valid) begin
      rtc_high_cycles++;
      if (!rtc_valid_q) begin
        rtc_edges++;
      end
    end
    if (cb.dataslot_to_core.update) begin
      update_high_cycles++;
      if (!update_q) begin
        update_edges++;
      end
    end
  end

  task automatic check(input string name, input logic ok, input string detail);
    checks++;
    if (!ok) begin
      errors++;
      $error("ERROR %s: %s", name, detail);
    end
  endtask

  task automatic command(input logic [15:0] cmd, input logic [3:0][31:0] params,
                         output logic [15:0] result);
    logic timed_out;

    host.host_command(cmd, params, result, timed_out);
    check($sformatf("command_%04h_finishes", cmd), !timed_out, "no OK from the host handler");
  endtask

  task automatic expect_result(input string name, input logic [15:0] actual,
                               input logic [15:0] expected);
    check(name, actual == expected, $sformatf("expected result %04h, got %04h", expected, actual));
  endtask

  // Status follows the template's order: booting, setup, then idle or running.
  task automatic test_status_and_reset();
    logic [15:0] result;

    command(16'h0000, '0, result);
    expect_result("status_booting", result, 16'h0001);

    cb.status_boot_done <= 1'b1;
    command(16'h0000, '0, result);
    expect_result("status_setup", result, 16'h0002);

    cb.status_running <= 1'b1;
    command(16'h0000, '0, result);
    expect_result("status_running", result, 16'h0004);

    cb.status_setup_done <= 1'b1;
    command(16'h0000, '0, result);
    expect_result("status_idle", result, 16'h0003);

    check("reset_n_starts_low", reset_n == 1'b0, "reset_n is high before reset exit");
    command(16'h0011, '0, result);
    check("reset_exit", reset_n == 1'b1, "reset_n stays low after reset exit");
    command(16'h0010, '0, result);
    check("reset_enter", reset_n == 1'b0, "reset_n stays high after reset enter");

    command(16'h1234, '0, result);
    expect_result("unknown_command", result, 16'hFFFF);
  endtask

  // Each RTC update gives a one-cycle rtc_valid, so every update has a rising edge.
  task automatic test_rtc_and_menu();
    logic [15:0] result;

    command(16'h0090, '{0: 32'h6000_0001, 1: 32'h2026_1013, 2: 32'h0012_3456, default: '0},
            result);
    expect_result("rtc_first_result", result, 16'h0000);
    check("rtc_first_values",
          rtc_osnotify_to_core.rtc_epoch_seconds == 32'h6000_0001 &&
          rtc_osnotify_to_core.rtc_date_bcd == 32'h2026_1013 &&
          rtc_osnotify_to_core.rtc_time_bcd == 32'h0012_3456,
          "RTC words don't match parameter words 0 to 2");

    command(16'h0090, '{0: 32'h6000_0002, default: '0}, result);
    check("rtc_edge_per_update", rtc_edges == 2, $sformatf(
          "expected 2 rtc_valid rising edges, got %0d", rtc_edges));
    check("rtc_valid_one_cycle", rtc_high_cycles == 2, $sformatf(
          "rtc_valid was high for %0d cycles over 2 updates", rtc_high_cycles));
    check("rtc_second_value", rtc_osnotify_to_core.rtc_epoch_seconds == 32'h6000_0002,
          "second update didn't replace epoch seconds");

    command(16'h00B0, '{0: 32'h1, default: '0}, result);
    check("menu_open", rtc_osnotify_to_core.osnotify_inmenu == 1'b1, "osnotify_inmenu low");
    command(16'h00B0, '0, result);
    check("menu_closed", rtc_osnotify_to_core.osnotify_inmenu == 1'b0, "osnotify_inmenu high");
  endtask

  // The core acks a request read late and refuses a request write.
  task automatic test_dataslot_requests();
    logic [15:0] result;
    logic held;

    command(16'h008F, '0, result);
    check("allcomplete_set", dataslot_to_core.allcomplete == 1'b1, "allcomplete low");

    fork
      command(16'h0080, '{0: 32'h0000_0007, default: '0}, result);
      begin
        wait (dataslot_to_core.requestread === 1'b1);
        check("request_read_id", dataslot_to_core.requestread_id == 16'h0007, $sformatf(
              "id %04h", dataslot_to_core.requestread_id));
        check("request_clears_allcomplete", dataslot_to_core.allcomplete == 1'b0,
              "allcomplete still high");
        repeat (20) @(cb);
        held = dataslot_to_core.requestread;
        cb.dataslot_from_core.requestread_ok  <= 1'b1;
        cb.dataslot_from_core.requestread_ack <= 1'b1;
        wait (dataslot_to_core.requestread === 1'b0);
        cb.dataslot_from_core <= '0;
      end
    join
    check("request_read_held_until_ack", held == 1, "requestread fell before the core acked");
    expect_result("request_read_accepted", result, 16'h0000);

    cb.dataslot_from_core.requestwrite_ack <= 1'b1;
    cb.dataslot_from_core.requestwrite_ok  <= 1'b0;
    command(16'h0082, '{0: 32'h0000_0002, 1: 32'h0000_8000, default: '0}, result);
    expect_result("request_write_refused", result, 16'h0002);
    check("request_write_params",
          dataslot_to_core.requestwrite_id == 16'h0002 &&
          dataslot_to_core.requestwrite_size == 32'h0000_8000,
          "id or size doesn't match");
    cb.dataslot_from_core <= '0;

    command(16'h008A, '{0: 32'h0000_0003, 1: 32'h0000_1234, default: '0}, result);
    check("update_one_cycle", update_edges == 1 && update_high_cycles == 1, $sformatf(
          "update rose %0d times, high %0d cycles", update_edges, update_high_cycles));
    check("update_params",
          dataslot_to_core.update_id == 16'h0003 && dataslot_to_core.update_size == 32'h1234,
          "id or size doesn't match");
  endtask

  task automatic test_savestate();
    logic [15:0] result;
    logic [31:0] word;
    logic held;

    cb.savestate_from_core <= '{
        supported: 1'b1,
        addr: 32'h1000_0000,
        size: 32'h0000_4000,
        maxloadsize: 32'h0000_5000,
        start_busy: 1'b1,
        default: 1'b0
    };
    command(16'h00A0, '0, result);
    expect_result("savestate_query_busy", result, 16'h0001);
    check("savestate_query_no_start", savestate_to_core.start == 1'b0, "query started a save");
    host.read_response(0, word);
    check("savestate_supported_word", word == 32'h1, $sformatf("word 0x40 %08h", word));
    host.read_response(1, word);
    check("savestate_addr_word", word == 32'h1000_0000, $sformatf("word 0x44 %08h", word));
    host.read_response(2, word);
    check("savestate_size_word", word == 32'h0000_4000, $sformatf("word 0x48 %08h", word));

    // Start: start stays high until the core acks, then the result reports ok.
    cb.savestate_from_core.start_busy <= 1'b0;
    cb.savestate_from_core.start_ok   <= 1'b1;
    fork
      command(16'h00A0, '{0: 32'h1, default: '0}, result);
      begin
        wait (savestate_to_core.start === 1'b1);
        repeat (10) @(cb);
        held = savestate_to_core.start;
        cb.savestate_from_core.start_ack <= 1'b1;
        wait (savestate_to_core.start === 1'b0);
        cb.savestate_from_core.start_ack <= 1'b0;
      end
    join
    check("savestate_start_held_until_ack", held == 1, "start fell before the core acked");
    expect_result("savestate_start_ok", result, 16'h0002);

    cb.savestate_from_core.load_ack <= 1'b1;
    cb.savestate_from_core.load_err <= 1'b1;
    command(16'h00A4, '{0: 32'h1, default: '0}, result);
    expect_result("savestate_load_err", result, 16'h0003);
    host.read_response(2, word);
    check("savestate_maxloadsize_word", word == 32'h0000_5000, $sformatf("word 0x48 %08h", word));
    cb.savestate_from_core <= '0;
  endtask

  // APF's side of a target command: read the command, answer "bu", then "ok" with a result.
  task automatic apf_answer_target(input logic [15:0] expected_cmd, input logic [2:0] err,
                                   input string name);
    logic [31:0] word;

    host.read_word(TARGET_CMD, word);
    check({name, "_command"}, word == {TARGET_MAGIC_COMMAND, expected_cmd}, $sformatf(
          "target command register %08h", word));
    host.write_word(TARGET_CMD, {TARGET_MAGIC_BUSY, expected_cmd});
    host.write_word(TARGET_CMD, {TARGET_MAGIC_OK, 13'h0, err});
  endtask

  // Holds request until target_cmd accepts it: the first edge where valid and ready are both high.
  task automatic issue_target(input target_request_t request);
    cb.target_request <= request;
    @(cb);
    while (!(cb.target_request.valid && cb.target_response.ready)) begin
      @(cb);
    end
    cb.target_request <= '0;
  endtask

  task automatic test_target_commands();
    logic [31:0] word;

    // status_setup_done rose in test_status_and_reset, so ready to run is outstanding. The core's
    // request waits for it.
    fork
      issue_target(
          '{valid: 1'b1, command: TARGET_DATASLOT_READ,
          param: '{3: 32'h0000_0100, 2: 32'h1000_0000, 1: 32'h0000_0040, 0: 32'h0000_0005}});
      begin
        repeat (4) @(cb);
        check("target_waits_for_ready_to_run", cb.target_response.ready == 1'b0,
              "ready while ready to run is pending");
        apf_answer_target(TARGET_READY_TO_RUN, 3'd0, "ready_to_run");
      end
    join
    check("ready_to_run_no_done", target_response.done == 1'b0, "done set by ready to run");

    host.read_word(TARGET_PARAM0, word);
    check("target_param_slot_id", word == 32'h5, $sformatf("word 0x20 %08h", word));
    host.read_word(TARGET_PARAM0 + 32'hC, word);
    check("target_param_length", word == 32'h100, $sformatf("word 0x2C %08h", word));

    host.read_word(TARGET_CMD, word);
    check("target_read_command", word == {TARGET_MAGIC_COMMAND, TARGET_DATASLOT_READ}, $sformatf(
          "target command register %08h", word));
    host.write_word(TARGET_CMD, {TARGET_MAGIC_BUSY, TARGET_DATASLOT_READ});
    check("target_ack_on_busy", target_response.ack == 1'b1 && target_response.done == 1'b0,
          "ack low or done high while APF is busy");
    host.write_word(TARGET_CMD, {TARGET_MAGIC_OK, 16'h0003});
    check("target_done_with_err",
          target_response.done == 1'b1 && target_response.err == 3'd3 && !target_response.ack,
          $sformatf(
          "done %b err %0d ack %b", target_response.done, target_response.err, target_response.ack
          ));

    // A new command clears done and err.
    issue_target('{valid: 1'b1, command: TARGET_DATASLOT_OPENFILE, default: '0});
    @(cb);
    check("target_new_command_clears_done", !target_response.done && target_response.err == 0,
          "done or err left over from the last command");
    apf_answer_target(TARGET_DATASLOT_OPENFILE, 3'd0, "openfile");
    check("target_openfile_done", target_response.done && target_response.err == 0,
          "openfile didn't finish with err 0");
  endtask

  // A read returns its own region's data while the next transaction already addresses another
  // region, and each user region write strobes user_wr once.
  task automatic test_user_region();
    logic [31:0] data;
    int unsigned writes;

    host.read_word(32'h1000_0200, data, HOST_PARAM_POINTER);
    check("user_read_then_host", data == 32'hD400_0200, $sformatf("read %08h", data));
    host.read_word(HOST_PARAM_POINTER, data, 32'h1000_0100);
    check("host_read_then_user", data == 32'h0000_0020, $sformatf("read %08h", data));
    host.write_word(DATATABLE + 32'h10, 32'h0BAD_F00D);
    host.read_word(DATATABLE + 32'h10, data, 32'h10FF_FFFC);
    check("datatable_read_then_user", data == 32'h0BAD_F00D, $sformatf("read %08h", data));

    writes = user_writes;
    host.write_word(32'h1000_0300, 32'h1234_5678);
    host.write_word(HOST_PARAM0, 32'h0);
    check("user_write_strobe", user_writes - writes == 1, $sformatf(
          "%0d user_wr strobes for one user region write", user_writes - writes));
  endtask

  function automatic logic [31:0] swap_bytes(input logic [31:0] word);
    return {word[7:0], word[15:8], word[23:16], word[31:24]};
  endfunction

  // With bridge_endian_little set, APF writes and reads every word byte-swapped. An RTC command
  // sent that way must reach the core with its words in order, and its answer must read back
  // swapped. The user region sees the bus as it is.
  task automatic test_endian();
    logic [31:0] word;
    logic answered;

    cb.bridge_endian_little <= 1'b1;
    @(cb);

    host.write_word(HOST_PARAM0, swap_bytes(32'h6000_0003));
    host.write_word(HOST_CMD, swap_bytes({HOST_MAGIC_COMMAND, 16'h0090}));
    answered = 1'b0;
    for (int poll = 0; poll < 64 && !answered; poll++) begin
      host.read_word(HOST_CMD, word);
      answered = swap_bytes(word) == {HOST_MAGIC_OK, 16'h0000};
    end
    check("endian_command_answered", answered, $sformatf("command register reads %08h", word));
    check("endian_param_in_order", rtc_osnotify_to_core.rtc_epoch_seconds == 32'h6000_0003,
          $sformatf("epoch seconds %08h", rtc_osnotify_to_core.rtc_epoch_seconds));

    host.read_word(32'h1000_0300, word);
    check("endian_user_unswapped", word == 32'hD400_0300, $sformatf("read %08h", word));

    cb.bridge_endian_little <= 1'b0;
    @(cb);
  endtask

  initial begin
    repeat (10) @(cb);

    test_status_and_reset();
    test_rtc_and_menu();
    test_dataslot_requests();
    test_savestate();
    test_target_commands();
    test_user_region();
    test_endian();

    $display("SUMMARY tb_core_bridge checks=%0d errors=%0d", checks, errors);
    if (errors != 0) begin
      $fatal(1, "tb_core_bridge failed");
    end
    $finish;
  end
endmodule

`default_nettype wire
