`default_nettype none

// Types and constants for the APF bridge. The bridge map half is bridge_map's: it is the only
// module that decodes bridge addresses. The command half holds the APF command codes, magic words,
// and the ports between the command modules and the core. All of it is on clk_74a.
package bridge_pkg;

  // Bridge map. Regions by address:
  //   0x10xxxxxx             user region, for the core's own devices
  //   0xF8xx00xx             host command registers
  //   0xF8xx10xx             target command registers
  //   0xF8xx2000-0xF8xx23FC  datatable, 256 words
  // Other addresses read 0 and ignore writes. The framework reserves all of 0xF8xxxxxx.
  typedef enum logic [2:0] {
    REGION_NONE,
    REGION_USER,
    REGION_HOST,
    REGION_TARGET,
    REGION_DATATABLE
  } bridge_region_t;

  localparam logic [7:0] USER_PREFIX = 8'h10;  // bridge_addr[31:24]
  localparam logic [7:0] APF_PREFIX = 8'hF8;  // bridge_addr[31:24]
  localparam logic [7:0] HOST_PAGE = 8'h00;  // bridge_addr[15:8]
  localparam logic [7:0] TARGET_PAGE = 8'h10;  // bridge_addr[15:8]
  localparam logic [5:0] DATATABLE_PAGE = 6'b0010_00;  // bridge_addr[15:10]

  // Register byte offsets in the host and target pages.
  localparam logic [7:0] REG_COMMAND = 8'h00;  // magic word in [31:16], command or result in [15:0]
  localparam logic [7:0] REG_PARAM_POINTER = 8'h04;  // reads the offset of the parameter words
  localparam logic [7:0] REG_RESPONSE_POINTER = 8'h08;  // reads the offset of the response words
  localparam logic [7:0] REG_PARAM0 = 8'h20;  // four parameter words, 0x20-0x2C
  localparam logic [7:0] REG_RESPONSE0 = 8'h40;  // four response words, 0x40-0x4C

  // One APF register region as bridge_map presents it. rd and wr last one cycle. addr is the byte
  // offset in the host and target pages, and the word index in the datatable. The region returns
  // read data for addr, and bridge_map registers it on rd.
  typedef struct packed {
    logic rd;
    logic wr;
    logic [7:0] addr;
    logic [31:0] wr_data;
  } apf_bus_t;

  // Magic words in the command register. APF writes "CM", the core answers "BU" while busy and
  // "OK" with a result code. Target commands use the lower-case words in the other direction.
  localparam logic [15:0] HOST_MAGIC_COMMAND = 16'h434D;  // "CM"
  localparam logic [15:0] HOST_MAGIC_BUSY = 16'h4255;  // "BU"
  localparam logic [15:0] HOST_MAGIC_OK = 16'h4F4B;  // "OK"
  localparam logic [15:0] TARGET_MAGIC_COMMAND = 16'h636D;  // "cm"
  localparam logic [15:0] TARGET_MAGIC_BUSY = 16'h6275;  // "bu"
  localparam logic [15:0] TARGET_MAGIC_OK = 16'h6F6B;  // "ok"

  // A host command, as host_cmd offers it to the concept modules. start is high for the first
  // cycle of the command and active until it finishes. param holds words 0x20-0x2C.
  typedef struct packed {
    logic start;
    logic active;
    logic [15:0] command;
    logic [3:0][31:0] param;
  } host_request_t;

  // A concept module's answer. claim says the module handles request.command, and is all zeros
  // otherwise, so host_cmd can OR the answers together. done ends the command with result, and
  // response goes to words 0x40-0x4C.
  typedef struct packed {
    logic claim;
    logic done;
    logic [15:0] result;
    logic [3:0][31:0] response;
  } host_response_t;

  // Data slot requests, from dataslot_requests. requestread and requestwrite stay high until the
  // matching ack. update is high for one cycle. allcomplete stays high from "all complete" until
  // the next request. The ids and sizes hold until the next command of their kind.
  typedef struct packed {
    logic requestread;
    logic [15:0] requestread_id;
    logic requestwrite;
    logic [15:0] requestwrite_id;
    logic [31:0] requestwrite_size;
    logic update;
    logic [15:0] update_id;
    logic [31:0] update_size;
    logic allcomplete;
  } dataslot_to_core_t;

  // Clear ok to refuse a request.
  typedef struct packed {
    logic requestread_ack;
    logic requestread_ok;
    logic requestwrite_ack;
    logic requestwrite_ok;
  } dataslot_from_core_t;

  // Savestate requests, from savestate. Each stays high until the matching ack.
  typedef struct packed {
    logic start;
    logic load;
  } savestate_to_core_t;

  // Hold busy while a savestate runs, then ok or err until the next start or load.
  typedef struct packed {
    logic supported;
    logic [31:0] addr;
    logic [31:0] size;
    logic [31:0] maxloadsize;
    logic start_ack;
    logic start_busy;
    logic start_ok;
    logic start_err;
    logic load_ack;
    logic load_busy;
    logic load_ok;
    logic load_err;
  } savestate_from_core_t;

  // From rtc_osnotify. rtc_valid is high for one cycle per RTC update, and the RTC words hold until
  // the next one. osnotify_inmenu is high while the Pocket menu is open.
  typedef struct packed {
    logic rtc_valid;
    logic [31:0] rtc_epoch_seconds;
    logic [31:0] rtc_date_bcd;
    logic [31:0] rtc_time_bcd;
    logic osnotify_inmenu;
  } rtc_osnotify_to_core_t;

  // Target command codes. The parameter words for each:
  //   DATASLOT_READ, DATASLOT_WRITE: slot id, slot offset, bridge address, length
  //   DATASLOT_GETFILE: slot id, bridge address of the response struct, which APF fills with the
  //     file name
  //   DATASLOT_OPENFILE: slot id, bridge address of the parameter struct, which holds the file
  //     name, flags, and size
  // The core maps the struct buffers in its own region. target_cmd sends READY_TO_RUN itself.
  localparam logic [15:0] TARGET_READY_TO_RUN = 16'h0140;
  localparam logic [15:0] TARGET_DATASLOT_READ = 16'h0180;
  localparam logic [15:0] TARGET_DATASLOT_WRITE = 16'h0184;
  localparam logic [15:0] TARGET_DATASLOT_GETFILE = 16'h0190;
  localparam logic [15:0] TARGET_DATASLOT_OPENFILE = 16'h0192;

  // Hold valid, command, and param until target_response_t.ready.
  typedef struct packed {
    logic valid;
    logic [15:0] command;
    logic [3:0][31:0] param;
  } target_request_t;

  // ready accepts a request this cycle. ack is high while APF works on the command. done rises
  // when it finishes, with the result in err (0 is OK), and stays high until the next command.
  typedef struct packed {
    logic ready;
    logic ack;
    logic done;
    logic [2:0] err;
  } target_response_t;

  // The core's port on the datatable RAM. q follows addr by two cycles.
  typedef struct packed {
    logic [7:0] addr;
    logic wren;
    logic [31:0] data;
  } datatable_from_core_t;

endpackage

`default_nettype wire
