`default_nettype none

// Tests sync_pulse from clk_74a to clk_core_12288, the crossing core_clocks uses, with the
// destination clock at a seeded random phase. Every event must arrive exactly once, as a
// one-cycle pulse, including events at the minimum spacing of 4 destination cycles.
module tb_sync_pulse;
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned EVENTS = 500;
  localparam int unsigned MIN_SPACING = 25;  // clk_74a cycles, just over 4 clk_core_12288 cycles
  localparam int unsigned WATCHDOG_CYCLES = EVENTS * 100;  // clk_74a cycles

  var logic clk_src;
  var logic clk_dst;
  var logic pulse_src = 1'b0;
  wire logic pulse_dst;

  // Pulses count once the synchronizer has flushed its start values. Registers power up at 0 on
  // the FPGA, but Verilator can start synch_3 with any value, which makes a pulse.
  logic counting = 1'b0;
  int unsigned received = 0;
  int unsigned long_pulses = 0;
  logic pulse_dst_q = 1'b0;

  sync_pulse dut (
      .clk_src,
      .pulse_src,
      .clk_dst,
      .pulse_dst
  );

  // The testbench drives pulse_src through src_cb and samples pulse_dst through dst_cb.
  clocking src_cb @(posedge clk_src);
    default input #1step output #2ns;
    output pulse_src;
  endclocking

  clocking dst_cb @(posedge clk_dst);
    default input #1step output #2ns;
    input pulse_dst;
  endclocking

  initial begin
    clk_src <= 1'b0;
    forever begin
      #6.734ns clk_src <= ~clk_src;
    end
  end

  initial begin
    clk_dst <= 1'b0;
    #($urandom_range(1, 80_000) * 1ps);
    forever begin
      #40.690ns clk_dst <= ~clk_dst;
    end
  end

  initial begin
    repeat (WATCHDOG_CYCLES) @(src_cb);
    $fatal(1, "ERROR watchdog: test did not finish in %0d cycles", WATCHDOG_CYCLES);
  end

  always @(dst_cb) begin
    pulse_dst_q <= dst_cb.pulse_dst === 1'b1;
    if (counting && dst_cb.pulse_dst === 1'b1) begin
      received++;
      if (pulse_dst_q) begin
        long_pulses++;
      end
    end
  end

  initial begin
    // Let the synchronizer flush its power-up state.
    repeat (10) @(dst_cb);
    counting = 1'b1;
    @(src_cb);

    for (int i = 0; i < EVENTS; i++) begin
      src_cb.pulse_src <= 1'b1;
      @(src_cb);
      src_cb.pulse_src <= 1'b0;
      // The next event reaches the DUT MIN_SPACING or more clk_74a cycles after this one.
      repeat ((i % 4 == 0 ? MIN_SPACING : $urandom_range(MIN_SPACING, 80)) - 1) @(src_cb);
    end
    repeat (10) @(dst_cb);

    $display("SUMMARY tb_sync_pulse checks=2 errors=%0d",
             int'(received != EVENTS) + int'(long_pulses != 0));
    if (received != EVENTS) begin
      $error("ERROR events: sent %0d, received %0d", EVENTS, received);
    end
    if (long_pulses != 0) begin
      $error("ERROR pulse_width: %0d pulses lasted more than one cycle", long_pulses);
    end
    if (received != EVENTS || long_pulses != 0) begin
      $fatal(1, "tb_sync_pulse failed");
    end
    $finish;
  end
endmodule

`default_nettype wire
