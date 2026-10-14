`default_nettype none

// Target command handler: the core asks APF to act on data slots. Owns the target command
// registers at 0xF8xx10xx. All ports are on clk (clk_74a).
//
// To issue a command, hold request.valid, command, and param until response.ready. The command
// codes and what each parameter word means are in bridge_pkg. response.ack is high while APF works
// on the command. response.done rises when it finishes, with the result in response.err, and
// stays high until the next command starts. A new command code needs no change here.
//
// On each rising edge of status_setup_done, target_cmd sends ready to run (0x0140) ahead of any
// core request. Ready to run doesn't touch ack, done, or err.
module target_cmd
  import bridge_pkg::*;
(
    input wire logic clk,

    input var apf_bus_t bus,
    output var logic [31:0] rd_data,

    input wire logic status_setup_done,

    input var  target_request_t  request,
    output var target_response_t response
);
  typedef enum logic {
    ST_IDLE,
    ST_WAIT
  } state_t;

  // Part of the bridge, which runs before the core leaves reset: starts from power-up values.
  var state_t state = ST_IDLE;
  var logic [31:0] command_reg = '0;
  var logic [3:0][31:0] param = '0;
  var logic setup_done_q = 1'b0;
  var logic ready_to_run_pending = 1'b0;
  var logic from_core = 1'b0;
  var logic ack = 1'b0;
  var logic done = 1'b0;
  var logic [2:0] err = '0;

  // Reading these registers has no side effects.
  wire logic unused = bus.rd;

  var logic [15:0] magic;
  var logic issue_ready_to_run;
  var logic ready;
  var logic accept;

  always_comb begin
    magic = command_reg[31:16];
    issue_ready_to_run = state == ST_IDLE && ready_to_run_pending;
    ready = state == ST_IDLE && !ready_to_run_pending;
    accept = ready && request.valid;
  end

  always_ff @(posedge clk) begin
    setup_done_q <= status_setup_done;

    if (status_setup_done && !setup_done_q) begin
      ready_to_run_pending <= 1'b1;
    end else if (issue_ready_to_run) begin
      ready_to_run_pending <= 1'b0;
    end

    // The core writes "cm" to start a command. APF answers "bu", then "ok" and a result.
    if (issue_ready_to_run) begin
      command_reg <= {TARGET_MAGIC_COMMAND, TARGET_READY_TO_RUN};
    end else if (accept) begin
      command_reg <= {TARGET_MAGIC_COMMAND, request.command};
    end else if (bus.wr && bus.addr == REG_COMMAND) begin
      command_reg <= bus.wr_data;
    end

    if (accept) begin
      param <= request.param;
      done  <= 1'b0;
      err   <= '0;
    end

    unique case (state)
      ST_IDLE: begin
        if (issue_ready_to_run || accept) begin
          from_core <= accept;
          state <= ST_WAIT;
        end
      end
      ST_WAIT: begin
        if (magic == TARGET_MAGIC_BUSY) begin
          ack <= from_core;
        end else if (magic == TARGET_MAGIC_OK) begin
          ack <= 1'b0;
          if (from_core) begin
            done <= 1'b1;
            err  <= command_reg[2:0];
          end
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
      REG_PARAM0: rd_data = param[0];
      REG_PARAM0 + 8'h04: rd_data = param[1];
      REG_PARAM0 + 8'h08: rd_data = param[2];
      REG_PARAM0 + 8'h0C: rd_data = param[3];
      default: rd_data = '0;
    endcase
  end

  always_comb begin
    response.ready = ready;
    response.ack   = ack;
    response.done  = done;
    response.err   = err;
  end
endmodule

`default_nettype wire
