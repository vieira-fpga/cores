`default_nettype none

// End-to-end test of core_top as the template ships it: the real PLL model, the default responder,
// and the bridge driven the way apf/io_bridge_peripheral.v drives it. video_checker checks the
// video timing throughout. Run with the altera_mf_ver and altera_lnsim_ver libraries, from
// src/fpga so the datatable finds apf/build_id.mif.
module tb_core_top;
  timeunit 1ns; timeprecision 1ps;

  localparam logic [15:0] RESULT_OK = 16'h0000;
  localparam logic [15:0] RESULT_UNKNOWN = 16'hFFFF;
  localparam logic [15:0] STATUS_IDLE = 16'h0003;
  localparam logic [31:0] DATATABLE = 32'hF800_2000;
  localparam int unsigned WATCHDOG_CYCLES = 2_000_000;

  var logic clk_74a;
  var logic clk_74b;

  wire logic [31:0] bridge_addr;
  wire logic bridge_rd;
  wire logic [31:0] bridge_rd_data;
  wire logic bridge_wr;
  wire logic [31:0] bridge_wr_data;
  wire logic bridge_endian_little;

  wire logic [23:0] video_rgb;
  wire logic video_rgb_clock;
  wire logic video_rgb_clock_90;
  wire logic video_de;
  wire logic video_skip;
  wire logic video_vs;
  wire logic video_hs;

  // Pins the template ties off. The test doesn't check them.
  wire logic [7:0] cart_tran_bank2;
  wire logic [7:0] cart_tran_bank3;
  wire logic [7:0] cart_tran_bank1;
  wire logic [7:4] cart_tran_bank0;
  wire logic cart_tran_pin30;
  wire logic cart_tran_pin31;
  wire logic port_tran_si;
  wire logic port_tran_so;
  wire logic port_tran_sck;
  wire logic port_tran_sd;
  wire logic [15:0] cram0_dq;
  wire logic [15:0] cram1_dq;
  wire logic [15:0] dram_dq;
  wire logic [15:0] sram_dq;
  wire logic aux_sda;

  int unsigned checks = 0;
  int unsigned errors = 0;

  core_top dut (
      .clk_74a,
      .clk_74b,
      .cart_tran_bank2,
      .cart_tran_bank2_dir(),
      .cart_tran_bank3,
      .cart_tran_bank3_dir(),
      .cart_tran_bank1,
      .cart_tran_bank1_dir(),
      .cart_tran_bank0,
      .cart_tran_bank0_dir(),
      .cart_tran_pin30,
      .cart_tran_pin30_dir(),
      .cart_pin30_pwroff_reset(),
      .cart_tran_pin31,
      .cart_tran_pin31_dir(),
      .port_ir_rx(1'b0),
      .port_ir_tx(),
      .port_ir_rx_disable(),
      .port_tran_si,
      .port_tran_si_dir(),
      .port_tran_so,
      .port_tran_so_dir(),
      .port_tran_sck,
      .port_tran_sck_dir(),
      .port_tran_sd,
      .port_tran_sd_dir(),
      .cram0_a(),
      .cram0_dq,
      .cram0_wait(1'b0),
      .cram0_clk(),
      .cram0_adv_n(),
      .cram0_cre(),
      .cram0_ce0_n(),
      .cram0_ce1_n(),
      .cram0_oe_n(),
      .cram0_we_n(),
      .cram0_ub_n(),
      .cram0_lb_n(),
      .cram1_a(),
      .cram1_dq,
      .cram1_wait(1'b0),
      .cram1_clk(),
      .cram1_adv_n(),
      .cram1_cre(),
      .cram1_ce0_n(),
      .cram1_ce1_n(),
      .cram1_oe_n(),
      .cram1_we_n(),
      .cram1_ub_n(),
      .cram1_lb_n(),
      .dram_a(),
      .dram_ba(),
      .dram_dq,
      .dram_dqm(),
      .dram_clk(),
      .dram_cke(),
      .dram_ras_n(),
      .dram_cas_n(),
      .dram_we_n(),
      .sram_a(),
      .sram_dq,
      .sram_oe_n(),
      .sram_we_n(),
      .sram_ub_n(),
      .sram_lb_n(),
      .vblank(1'b0),
      .dbg_tx(),
      .dbg_rx(1'b1),
      .user1(),
      .user2(1'b0),
      .aux_sda,
      .aux_scl(),
      .vpll_feed(),
      .video_rgb,
      .video_rgb_clock,
      .video_rgb_clock_90,
      .video_de,
      .video_skip,
      .video_vs,
      .video_hs,
      .audio_mclk(),
      .audio_adc(1'b0),
      .audio_dac(),
      .audio_lrck(),
      .bridge_endian_little,
      .bridge_addr,
      .bridge_rd,
      .bridge_rd_data,
      .bridge_wr,
      .bridge_wr_data,
      .cont1_key('0),
      .cont2_key('0),
      .cont3_key('0),
      .cont4_key('0),
      .cont1_joy('0),
      .cont2_joy('0),
      .cont3_joy('0),
      .cont4_joy('0),
      .cont1_trig('0),
      .cont2_trig('0),
      .cont3_trig('0),
      .cont4_trig('0)
  );

  // Checks the scaler's timing rules on every pixel clock.
  bind core_top video_checker #(
      .H_ACTIVE(320)
  ) video_check (
      .clk(video_rgb_clock),
      .reset_n(reset_n_12288),
      .rgb(video_rgb),
      .de(video_de),
      .hs(video_hs),
      .vs(video_vs)
  );

  apf_bridge_model host (
      .clk(clk_74a),
      .bridge_addr,
      .bridge_rd,
      .bridge_rd_data,
      .bridge_wr,
      .bridge_wr_data
  );

  // 74.25 MHz, with clk_74b at a seeded random phase.
  initial begin
    clk_74a <= 1'b0;
    forever begin
      #6.734ns clk_74a <= ~clk_74a;
    end
  end

  initial begin
    clk_74b <= 1'b0;
    #($urandom_range(1, 6000) * 1ps);
    forever begin
      #6.734ns clk_74b <= ~clk_74b;
    end
  end

  initial begin
    repeat (WATCHDOG_CYCLES) @(posedge clk_74a);
    $fatal(1, "ERROR watchdog: test did not finish in %0d clk_74a cycles", WATCHDOG_CYCLES);
  end

  // Video events after reset exit, counted on the pixel clock.
  int unsigned vs_count = 0;
  int unsigned hs_count = 0;

  // While expect_idle is set, every pixel clock with any video output active counts as busy.
  var logic expect_idle = 1'b0;
  int unsigned busy_cycles = 0;

  always @(posedge video_rgb_clock) begin
    if (video_vs === 1'b1) begin
      vs_count <= vs_count + 1;
    end
    if (video_hs === 1'b1) begin
      hs_count <= hs_count + 1;
    end

    if (expect_idle && (video_de !== 1'b0 || video_hs !== 1'b0 || video_vs !== 1'b0 ||
                        video_rgb !== '0)) begin
      busy_cycles <= busy_cycles + 1;
    end
  end

  task automatic check(input string name, input logic ok, input string detail);
    checks++;
    if (!ok) begin
      errors++;
      $error("ERROR %s: %s", name, detail);
    end
  endtask

  task automatic run_command(input string name, input logic [15:0] cmd,
                             input logic [3:0][31:0] params, output logic [15:0] result);
    logic timed_out;

    host.host_command(cmd, params, result, timed_out);
    check(name, !timed_out, $sformatf("command %04h got no OK, the host command FSM hangs", cmd));
  endtask

  initial begin
    logic [15:0] result;
    logic [31:0] word;
    int unsigned vs_seen;
    int unsigned hs_seen;

    // The PLL model locks after a few microseconds.
    wait (dut.video_rgb_clock === 1'b1);
    #20us;

    run_command("status_after_lock", 16'h0000, '0, result);
    check("status_after_lock", result == STATUS_IDLE, $sformatf(
          "expected status %0h, got %0h", STATUS_IDLE, result));

    // No video while the core is held in reset.
    #50us;
    check("video_held_in_reset", hs_count == 0 && vs_count == 0, $sformatf(
          "got %0d hs and %0d vs before reset exit", hs_count, vs_count));

    run_command("reset_exit", 16'h0011, '0, result);
    check("reset_exit", result == RESULT_OK, $sformatf("result %04h", result));
    #100us;
    check("video_runs_after_reset", vs_count == 1 && hs_count >= 3, $sformatf(
          "expected 1 vs and 3+ hs, got %0d vs and %0d hs", vs_count, hs_count));

    // A menu reset sends reset enter, then reset exit. Start it as a line's active video begins,
    // so reset lands with video_de high. The video must stay idle for a whole line in reset, then
    // start a new frame on exit.
    @(posedge video_de);
    run_command("menu_reset_enter", 16'h0010, '0, result);
    #1us;
    expect_idle = 1'b1;
    #40us;
    expect_idle = 1'b0;
    check("video_idle_in_reset", busy_cycles == 0, $sformatf(
          "video outputs active for %0d pixel clocks in reset", busy_cycles));

    vs_seen = vs_count;
    hs_seen = hs_count;
    run_command("menu_reset_exit", 16'h0011, '0, result);
    #100us;
    vs_seen = vs_count - vs_seen;
    hs_seen = hs_count - hs_seen;
    check("video_restarts_after_reset", vs_seen == 1 && hs_seen >= 3, $sformatf(
          "expected 1 vs and 3+ hs, got %0d vs and %0d hs", vs_seen, hs_seen));

    run_command("unknown_command", 16'h7777, '0, result);
    check("unknown_command", result == RESULT_UNKNOWN, $sformatf("result %04h", result));

    // The default responder acks data slot requests.
    run_command("dataslot_request_read", 16'h0080, '{default: 32'h0000_0003}, result);
    check("dataslot_request_read", result == RESULT_OK, $sformatf("result %04h", result));
    run_command("dataslot_request_write", 16'h0082, '{default: 32'h0000_0003}, result);
    check("dataslot_request_write", result == RESULT_OK, $sformatf("result %04h", result));

    // Savestates are unsupported, but a start or load request still completes.
    run_command("savestate_start", 16'h00A0, '{0: 32'h1, default: '0}, result);
    host.read_response(0, word);
    check("savestate_start_unsupported", word == '0, $sformatf("supported word %08h", word));
    run_command("savestate_load", 16'h00A4, '{0: 32'h1, default: '0}, result);
    host.read_response(0, word);
    check("savestate_load_unsupported", word == '0, $sformatf("supported word %08h", word));

    // The datatable has 256 words. A write past it must not land on word 0.
    host.write_word(DATATABLE, 32'hA5A5_0001);
    host.write_word(DATATABLE + 32'h400, 32'h5A5A_0002);
    host.read_word(DATATABLE, word);
    check("datatable_no_alias", word == 32'hA5A5_0001, $sformatf(
          "word 0 reads %08h after a write to 0xF8002400", word));
    host.read_word(DATATABLE + 32'h400, word);
    check("datatable_unmapped_reads_zero", word == '0, $sformatf("0xF8002400 reads %08h", word));
    host.write_word(DATATABLE + 32'h3FC, 32'h0000_00FF);
    host.read_word(DATATABLE + 32'h3FC, word);
    check("datatable_last_word", word == 32'h0000_00FF, $sformatf("word 255 reads %08h", word));

    // build_id_gen.tcl puts the build date in word 0xE0.
    host.read_word(DATATABLE + 32'h380, word);
    check("datatable_build_id", word != '0, "build date word 0xE0 reads 0");

    $display("SUMMARY tb_core_top checks=%0d errors=%0d", checks, errors);
    if (errors != 0) begin
      $fatal(1, "tb_core_top failed");
    end
    $finish;
  end
endmodule

`default_nettype wire
