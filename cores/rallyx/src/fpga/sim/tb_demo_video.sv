`default_nettype none

// Tests demo_video on its own: the frame and line totals, the strobes, a reset in the middle of
// active video, and each frame's pixels. video_checker, bound to demo_video, checks the scaler's
// timing rules on every clock.
//
// Each frame's pixels hash to a CRC-32 over their R, G, and B bytes in raster order, as zlib.crc32
// computes it. A frame that doesn't match APPROVED_FRAME_CRC is written to
// sim/build/tb_demo_video_frame<n>.ppm. Look at the image before you approve a new hash. Run from
// src/fpga.
module tb_demo_video;
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned H_ACTIVE = 320;
  localparam int unsigned V_ACTIVE = 240;
  localparam int unsigned H_TOTAL = 400;
  localparam int unsigned V_TOTAL = 512;
  localparam int unsigned FRAMES = 3;
  localparam int unsigned WATCHDOG_CYCLES = (FRAMES + 2) * H_TOTAL * V_TOTAL;

  // Approved by looking at the frame: a uniform gray of 0x3C3C3C.
  localparam logic [31:0] APPROVED_FRAME_CRC = 32'h4E74_71C8;

  var logic clk;
  var logic reset_n = 1'b0;

  wire logic frame_start;
  wire logic line_start;
  wire logic [23:0] rgb;
  wire logic de;
  wire logic hs;
  wire logic vs;

  int unsigned checks = 0;
  int unsigned errors = 0;

  demo_video dut (
      .clk,
      .reset_n,
      .frame_start,
      .line_start,
      .rgb,
      .de,
      .hs,
      .vs
  );

  bind demo_video video_checker #(
      .H_ACTIVE(320)
  ) video_check (
      .clk,
      .reset_n,
      .rgb,
      .de,
      .hs,
      .vs
  );

  clocking cb @(posedge clk);
    default input #1step output #2ns;
    output reset_n;
    input reset_n_sampled = reset_n;
    input frame_start, line_start, rgb, de, hs, vs;
  endclocking

  // 12.288 MHz.
  initial begin
    clk <= 1'b0;
    forever begin
      #40.690ns clk <= ~clk;
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

  function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] data);
    logic [31:0] next;

    next = crc ^ 32'(data);
    for (int i = 0; i < 8; i++) begin
      next = next[0] ? (next >> 1) ^ 32'hEDB8_8320 : next >> 1;
    end

    return next;
  endfunction

  function automatic logic [31:0] crc32_pixel(input logic [31:0] crc, input logic [23:0] pixel);
    return crc32_byte(crc32_byte(crc32_byte(crc, pixel[23:16]), pixel[15:8]), pixel[7:0]);
  endfunction

  task automatic write_ppm(input int unsigned frame, input logic [23:0] pixels[$]);
    string path;
    int fd;

    path = $sformatf("sim/build/tb_demo_video_frame%0d.ppm", frame);
    fd   = $fopen(path, "wb");
    if (fd == 0) begin
      $error("ERROR frame_dump: can't open %s", path);
      return;
    end

    $fwrite(fd, "P6\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
    foreach (pixels[i]) begin
      $fwrite(fd, "%c%c%c", pixels[i][23:16], pixels[i][15:8], pixels[i][7:0]);
    end
    $fclose(fd);
    $display("Wrote %s", path);
  endtask

  // The frame dump. A frame runs from one vs to the next. A reset drops the frame it cuts short.
  int unsigned frames_done = 0;
  logic in_frame = 1'b0;
  logic [31:0] frame_crc;
  logic [23:0] frame_pixels[$];

  always @(cb) begin
    if (!cb.reset_n_sampled) begin
      in_frame = 1'b0;
    end

    if (cb.vs) begin
      if (in_frame) begin
        frame_crc = ~frame_crc;
        check("frame_pixels", frame_pixels.size() == H_ACTIVE * V_ACTIVE, $sformatf(
              "frame %0d has %0d pixels", frames_done, frame_pixels.size()));
        check("frame_crc", frame_crc == APPROVED_FRAME_CRC, $sformatf(
              "frame %0d hashes to %08h, approved %08h", frames_done, frame_crc, APPROVED_FRAME_CRC
              ));
        if (frame_crc != APPROVED_FRAME_CRC) begin
          write_ppm(frames_done, frame_pixels);
        end
        frames_done++;
      end

      in_frame  = 1'b1;
      frame_crc = '1;
      frame_pixels.delete();
    end

    if (in_frame && cb.de) begin
      frame_crc = crc32_pixel(frame_crc, cb.rgb);
      frame_pixels.push_back(cb.rgb);
    end
  end

  // Counts clocks and lines from one frame_start to the next, and checks the strobes against
  // vs and hs: frame_start comes with vs, and hs 3 clocks after line_start. Outputs are skipped
  // while reset is held, and a reset drops the period it cuts short.
  int unsigned frame_clocks = 0;
  int unsigned frame_lines = 0;
  int unsigned periods_checked = 0;
  logic [2:0] line_start_q = '0;

  always @(cb) begin
    line_start_q <= {line_start_q[1:0], cb.line_start};

    if (!cb.reset_n_sampled) begin
      frame_clocks = 0;
    end else begin
      if (cb.frame_start != cb.vs) begin
        check("frame_start_with_vs", 1'b0, $sformatf("frame_start %b, vs %b", cb.frame_start, cb.vs
              ));
      end
      if (cb.hs != line_start_q[2]) begin
        check("hs_after_line_start", 1'b0, $sformatf(
              "hs %b, line_start 3 clocks before %b", cb.hs, line_start_q[2]));
      end

      if (cb.frame_start) begin
        if (frame_clocks != 0) begin
          check("frame_clocks", frame_clocks == H_TOTAL * V_TOTAL, $sformatf(
                "frame took %0d clocks", frame_clocks));
          check("frame_lines", frame_lines == V_TOTAL, $sformatf("%0d lines", frame_lines));
          periods_checked++;
        end
        frame_clocks = 1;
        frame_lines  = 1;
      end else if (frame_clocks != 0) begin
        frame_clocks++;
        frame_lines += int'(cb.line_start);
      end
    end
  end

  // Holds reset for `cycles` clocks and checks that every output stays low.
  task automatic hold_reset(input int unsigned cycles);
    cb.reset_n <= 1'b0;
    repeat (2) @(cb);
    for (int i = 0; i < cycles; i++) begin
      @(cb);
      if ({cb.frame_start, cb.line_start, cb.rgb, cb.de, cb.hs, cb.vs} != '0) begin
        check("idle_in_reset", 1'b0, "an output is high in reset");
      end
    end
    cb.reset_n <= 1'b1;
  endtask

  initial begin
    hold_reset(8);

    // The first clock after reset starts a frame.
    @(cb);
    @(cb);
    check("frame_after_reset", cb.vs && cb.frame_start, "no vs on the first clock after reset");

    wait (frames_done == FRAMES);

    // Reset in the middle of a line's active video. The beam restarts at the top of a frame.
    @(cb iff cb.de);
    repeat (100) @(cb);
    hold_reset(H_TOTAL);
    @(cb);
    @(cb);
    check("frame_after_mid_line_reset", cb.vs && cb.frame_start,
          "no vs on the first clock after reset");
    wait (frames_done == FRAMES + 1);

    check("frame_periods", periods_checked >= FRAMES - 1, $sformatf(
          "only %0d frame periods measured", periods_checked));

    $display("SUMMARY tb_demo_video checks=%0d errors=%0d", checks, errors);
    if (errors != 0) begin
      $fatal(1, "tb_demo_video failed");
    end
    $finish;
  end
endmodule

`default_nettype wire
