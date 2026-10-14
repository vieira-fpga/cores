`default_nettype none

// Host command handler. Owns the host command registers at 0xF8xx00xx and generates the core's
// reset_n. All ports are on clk, which must be clk_74a straight from its pin: the handler reports
// PLL lock, so it can't run from a PLL output.
//
// APF starts a command by writing "CM" and the command code to the command register, then polls
// the register until "OK" and a result code replace them. host_cmd answers status (0x0000) and
// reset enter and exit (0x0010, 0x0011) itself. It offers every other command to the concept
// modules on request, and waits for the module that claims it to finish. A command nobody claims
// gets result 0xFFFF.
module host_cmd
  import bridge_pkg::*;
(
    input  wire logic clk,
    output wire logic reset_n,

    input var apf_bus_t bus,
    output var logic [31:0] rd_data,

    input wire logic status_boot_done,  // the PLLs have locked and the logic is ready
    input wire logic status_setup_done,  // the core is happy with what APF has loaded
    input wire logic status_running,  // the core is out of reset and running

    output var host_request_t  request,
    input var  host_response_t response
);
  localparam logic [15:0] CMD_STATUS = 16'h0000;
  localparam logic [15:0] CMD_RESET_ENTER = 16'h0010;
  localparam logic [15:0] CMD_RESET_EXIT = 16'h0011;

  localparam logic [15:0] RESULT_OK = 16'h0000;
  localparam logic [15:0] RESULT_UNKNOWN = 16'hFFFF;
  localparam logic [15:0] STATUS_BOOTING = 16'h0001;
  localparam logic [15:0] STATUS_SETUP = 16'h0002;
  localparam logic [15:0] STATUS_IDLE = 16'h0003;
  localparam logic [15:0] STATUS_RUNNING = 16'h0004;

  typedef enum logic {
    ST_IDLE,
    ST_RUN
  } state_t;

  // This module generates reset_n, so nothing resets it. Its registers start from these values.
  var state_t state = ST_IDLE;
  var logic reset_n_q = 1'b0;
  var logic pending = 1'b0;
  var logic start = 1'b0;
  var logic [15:0] command = '0;
  var logic [31:0] command_reg = '0;
  var logic [3:0][31:0] param = '0;
  var logic [3:0][31:0] response_reg = '0;

  // Reading these registers has no side effects.
  wire logic unused = bus.rd;

  var logic command_write;
  var logic [15:0] status;
  var logic finish;
  var logic [15:0] result;

  always_comb begin
    command_write = bus.wr && bus.addr == REG_COMMAND;

    status = STATUS_BOOTING;
    if (status_boot_done) begin
      status = STATUS_SETUP;
      if (status_setup_done) begin
        status = STATUS_IDLE;
      end else if (status_running) begin
        status = STATUS_RUNNING;
      end
    end

    finish = 1'b0;
    result = RESULT_OK;
    if (state == ST_RUN) begin
      if (command == CMD_STATUS) begin
        finish = 1'b1;
        result = status;
      end else if (command == CMD_RESET_ENTER || command == CMD_RESET_EXIT) begin
        finish = 1'b1;
      end else if (!response.claim) begin
        finish = 1'b1;
        result = RESULT_UNKNOWN;
      end else if (response.done) begin
        finish = 1'b1;
        result = response.result;
      end
    end
  end

  always_ff @(posedge clk) begin
    start <= 1'b0;

    for (int i = 0; i < 4; i++) begin
      if (bus.wr && bus.addr == REG_PARAM0 + 8'(i * 4)) begin
        param[i] <= bus.wr_data;
      end
    end

    // A command written while one runs waits here. APF waits for "OK" before the next one.
    if (command_write && bus.wr_data[31:16] == HOST_MAGIC_COMMAND) begin
      pending <= 1'b1;
    end else if (state == ST_IDLE) begin
      pending <= 1'b0;
    end

    if (state == ST_RUN) begin
      command_reg <= finish ? {HOST_MAGIC_OK, result} : {HOST_MAGIC_BUSY, command};
    end else if (command_write) begin
      command_reg <= bus.wr_data;
    end

    if (state == ST_RUN && command == CMD_RESET_ENTER) begin
      reset_n_q <= 1'b0;
    end else if (state == ST_RUN && command == CMD_RESET_EXIT) begin
      reset_n_q <= 1'b1;
    end

    if (state == ST_RUN && response.claim && response.done) begin
      response_reg <= response.response;
    end

    unique case (state)
      ST_IDLE: begin
        if (pending) begin
          command <= command_reg[15:0];
          start   <= 1'b1;
          state   <= ST_RUN;
        end
      end
      ST_RUN: begin
        if (finish) begin
          state <= ST_IDLE;
        end
      end
      default: state <= ST_IDLE;
    endcase
  end

  always_comb begin
    rd_data = '0;

    unique case (bus.addr)
      REG_COMMAND: rd_data = command_reg;
      REG_PARAM_POINTER: rd_data = 32'(REG_PARAM0);
      REG_RESPONSE_POINTER: rd_data = 32'(REG_RESPONSE0);
      REG_RESPONSE0: rd_data = response_reg[0];
      REG_RESPONSE0 + 8'h04: rd_data = response_reg[1];
      REG_RESPONSE0 + 8'h08: rd_data = response_reg[2];
      REG_RESPONSE0 + 8'h0C: rd_data = response_reg[3];
      default: rd_data = '0;
    endcase
  end

  assign reset_n = reset_n_q;

  always_comb begin
    request.start   = start;
    request.active  = state == ST_RUN;
    request.command = command;
    request.param   = param;
  end
endmodule

`default_nettype wire
