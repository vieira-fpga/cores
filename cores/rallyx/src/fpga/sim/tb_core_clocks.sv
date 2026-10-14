`default_nettype none

// Tests core_clocks with the PLL model: reset_n_12288 stays low until the PLL locks, changes only
// on clk_core_12288 edges, and follows reset_n both ways. Also checks that a level and a pulse
// reach clk_core_12288. Run with the altera_lnsim_ver library.
module tb_core_clocks;
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned WATCHDOG_CYCLES = 200_000;
  localparam int unsigned MAX_LATENCY = 6;  // clk_core_12288 cycles for any crossing

  var logic clk_74a;
  var logic reset_n = 1'b1;
  var logic level_74a = 1'b0;
  var logic pulse_74a = 1'b0;

  wire logic clk_core_12288;
  wire logic pll_core_locked;
  wire logic reset_n_12288;
  wire logic level_12288;
  wire logic pulse_12288;

  int unsigned checks = 0;
  int unsigned errors = 0;

  core_clocks dut (
      .clk_74a,
      .reset_n,
      .clk_core_12288,
      .clk_core_12288_90deg(),
      .pll_core_locked,
      .reset_n_12288,
      .level_74a,
      .level_12288,
      .pulse_74a,
      .pulse_12288
  );

  // The testbench drives the clk_74a inputs through cb and samples the outputs through core_cb.
  clocking cb @(posedge clk_74a);
    default input #1step output #2ns;
    output reset_n, level_74a, pulse_74a;
  endclocking

  clocking core_cb @(posedge clk_core_12288);
    default input #1step output #2ns;
    input reset_n_12288, level_12288, pulse_12288;
  endclocking

  initial begin
    clk_74a <= 1'b0;
    forever begin
      #6.734ns clk_74a <= ~clk_74a;
    end
  end

  initial begin
    repeat (WATCHDOG_CYCLES) @(cb);
    $fatal(1, "ERROR watchdog: test did not finish in %0d cycles", WATCHDOG_CYCLES);
  end

  task automatic check(input string name, input logic ok, input string detail);
    checks++;
    if (!ok) begin
      errors++;
      $error("ERROR %s: %s", name, detail);
    end
  endtask

  // Every change of reset_n_12288 must land on a clk_core_12288 rising edge.
  realtime last_core_edge = -1ns;
  int unsigned pulses = 0;

  always @(posedge clk_core_12288) begin
    last_core_edge = $realtime;
  end

  always @(core_cb) begin
    if (core_cb.pulse_12288 === 1'b1) begin
      pulses++;
    end
  end

  always @(reset_n_12288) begin
    if ($realtime > 0) begin
      check("reset_on_core_edge", $realtime == last_core_edge, $sformatf(
            "changed at %t, last clk_core_12288 edge at %t", $realtime, last_core_edge));
    end
  end

  always @(posedge reset_n_12288) begin
    check("reset_waits_for_lock", pll_core_locked === 1'b1,
          "reset_n_12288 rose before the PLL locked");
  end

  typedef enum {
    RESET,
    LEVEL
  } output_t;

  function automatic logic sample (input output_t which);
    return which == RESET ? core_cb.reset_n_12288 : core_cb.level_12288;
  endfunction

  // Waits up to MAX_LATENCY clk_core_12288 cycles for an output to equal value.
  task automatic expect_within(input string name, input output_t which, input logic value);
    int unsigned cycles = 0;

    @(core_cb);
    while (sample (
        which
    ) !== value && cycles < MAX_LATENCY) begin
      @(core_cb);
      cycles++;
    end
    check(name, sample (which) === value, $sformatf(
          "%s still %b after %0d clk_core_12288 cycles", which.name(), sample (which), MAX_LATENCY
          ));
  endtask

  initial begin
    // reset_n is already high: the domain must still wait for lock.
    wait (pll_core_locked === 1'b1);
    check("held_in_reset_before_lock", reset_n_12288 !== 1'b1, "out of reset before lock");
    expect_within("release_after_lock", RESET, 1'b1);

    @(cb);
    cb.reset_n <= 1'b0;
    expect_within("reset_enter", RESET, 1'b0);
    repeat ($urandom_range(3, 40)) @(cb);
    cb.reset_n <= 1'b1;
    expect_within("reset_exit", RESET, 1'b1);

    @(cb);
    cb.level_74a <= 1'b1;
    expect_within("level_rise", LEVEL, 1'b1);
    @(cb);
    cb.level_74a <= 1'b0;
    expect_within("level_fall", LEVEL, 1'b0);

    @(cb);
    cb.pulse_74a <= 1'b1;
    @(cb);
    cb.pulse_74a <= 1'b0;
    repeat (MAX_LATENCY + 1) @(core_cb);
    check("pulse_once", pulses == 1, $sformatf("got %0d pulses for 1 event", pulses));

    $display("SUMMARY tb_core_clocks checks=%0d errors=%0d", checks, errors);
    if (errors != 0) begin
      $fatal(1, "tb_core_clocks failed");
    end
    $finish;
  end
endmodule

`default_nettype wire
