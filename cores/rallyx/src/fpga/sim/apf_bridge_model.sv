`default_nettype none

// Model of the APF bridge as apf/io_bridge_peripheral.v drives it, for testbenches. All signals are
// on clk (clk_74a). The address arrives one byte at a time, MSB first. A read holds the address for
// 4 cycles, samples bridge_rd_data, then strobes bridge_rd for one cycle. The sample therefore
// returns the data of the previous read strobe, so read_word() strobes twice and returns the
// second sample. host_command() runs one host command through the 0xF8000000 command registers.
module apf_bridge_model (
    input wire logic clk,
    output var logic [31:0] bridge_addr = '0,
    output var logic bridge_rd = 1'b0,
    input wire logic [31:0] bridge_rd_data,
    output var logic bridge_wr = 1'b0,
    output var logic [31:0] bridge_wr_data = '0
);
  timeunit 1ns; timeprecision 1ps;

  localparam logic [31:0] HOST_CMD = 32'hF800_0000;
  localparam logic [31:0] HOST_PARAM0 = 32'hF800_0020;
  localparam logic [31:0] HOST_RESP0 = 32'hF800_0040;
  localparam int unsigned POLL_LIMIT = 64;

  default clocking cb @(posedge clk);
    default input #1step output #2ns;
    input bridge_rd_data;
    output bridge_addr, bridge_rd, bridge_wr, bridge_wr_data;
  endclocking

  // SPI time between bytes and transactions, in clk cycles.
  task automatic gap(input int unsigned min_cycles);
    repeat (min_cycles + $urandom_range(0, 6)) @(cb);
  endtask

  // The address the model last drove. Clocking block outputs can't be read back.
  logic [31:0] partial = '0;

  task automatic send_address(input logic [31:0] addr);
    for (int i = 3; i >= 0; i--) begin
      partial[i*8+:8] = addr[i*8+:8];
      cb.bridge_addr <= partial;
      gap(2);
    end
  endtask

  // One read transaction. Returns the data of the previous read strobe.
  task automatic read_strobe(input logic [31:0] addr, output logic [31:0] previous);
    send_address(addr);
    repeat (4) @(cb);
    previous = cb.bridge_rd_data;
    cb.bridge_rd <= 1'b1;
    @(cb);
    cb.bridge_rd <= 1'b0;
    gap(8);
  endtask

  // Reads addr. next_addr is the address of the following transaction, which carries the result.
  task automatic read_word(input logic [31:0] addr, output logic [31:0] data,
                           input logic [31:0] next_addr = addr);
    logic [31:0] unused;

    read_strobe(addr, unused);
    read_strobe(next_addr, data);
  endtask

  task automatic write_word(input logic [31:0] addr, input logic [31:0] data);
    send_address(addr);
    gap(8);
    cb.bridge_wr_data <= data;
    @(cb);
    cb.bridge_wr <= 1'b1;
    @(cb);
    cb.bridge_wr <= 1'b0;
    gap(8);
  endtask

  // Writes the parameter words, starts cmd, and polls until the core answers "OK". Sets timed_out
  // when the core doesn't answer within POLL_LIMIT polls.
  task automatic host_command(input logic [15:0] cmd, input logic [3:0][31:0] params,
                              output logic [15:0] result, output logic timed_out);
    logic [31:0] status;

    for (int i = 0; i < 4; i++) begin
      write_word(HOST_PARAM0 + 32'(i * 4), params[i]);
    end
    write_word(HOST_CMD, {16'h434D, cmd});

    timed_out = 1'b1;
    result = '1;
    for (int poll = 0; poll < POLL_LIMIT; poll++) begin
      read_word(HOST_CMD, status);
      if (status[31:16] == 16'h4F4B) begin
        timed_out = 1'b0;
        result = status[15:0];
        break;
      end
    end
  endtask

  task automatic read_response(input int unsigned index, output logic [31:0] data);
    read_word(HOST_RESP0 + 32'(index * 4), data);
  endtask
endmodule

`default_nettype wire
