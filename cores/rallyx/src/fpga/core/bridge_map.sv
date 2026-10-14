`default_nettype none

// The bridge address map. Decodes the bridge bus into the regions listed in bridge_pkg and owns
// the read timing. All ports are on clk (clk_74a).
//
// Each region gets one-cycle rd and wr strobes for its own addresses. Reads follow the APF rule
// in apf/io_bridge_peripheral.v: the bridge samples bridge_rd_data just before its next read
// strobe, so data has until then to arrive. bridge_map registers which region each bridge_rd hit,
// and returns that region's data until the next strobe.
//   - The host, target, and datatable regions return data for their bus addr, and bridge_map
//     registers it on rd. The bridge holds the address for 4 cycles before rd, which covers the
//     datatable RAM's 2-cycle read.
//   - User region devices register their own data on user_rd and hold it until the next user_rd.
// When bridge_endian_little is set, the APF regions see byte-swapped write data, and their read
// data is swapped back.
module bridge_map
  import bridge_pkg::*;
(
    input wire logic clk,
    input wire logic bridge_endian_little,
    input wire logic [31:0] bridge_addr,
    input wire logic bridge_rd,
    output var logic [31:0] bridge_rd_data,
    input wire logic bridge_wr,
    input wire logic [31:0] bridge_wr_data,

    output var logic user_rd,
    output var logic user_wr,
    input wire logic [31:0] user_rd_data,

    output var apf_bus_t host_bus,
    input wire logic [31:0] host_rd_data,
    output var apf_bus_t target_bus,
    input wire logic [31:0] target_rd_data,
    output var apf_bus_t datatable_bus,
    input wire logic [31:0] datatable_rd_data
);
  // No region decodes bits 23:16. The APF regions repeat through them, and user region devices
  // read bridge_addr themselves.
  wire logic unused = ^bridge_addr[23:16];

  var bridge_region_t region;
  var logic [31:0] apf_wr_data;
  var logic [31:0] apf_rd_data;

  // The bridge runs before the core leaves reset, so these start from their power-up values.
  var logic rd_user = 1'b0;
  var logic [31:0] apf_rd_data_q = '0;

  function automatic logic [31:0] swap_bytes(input logic [31:0] word);
    return {word[7:0], word[15:8], word[23:16], word[31:24]};
  endfunction

  always_comb begin
    region = REGION_NONE;

    if (bridge_addr[31:24] == USER_PREFIX) begin
      region = REGION_USER;
    end else if (bridge_addr[31:24] == APF_PREFIX) begin
      if (bridge_addr[15:8] == HOST_PAGE) begin
        region = REGION_HOST;
      end else if (bridge_addr[15:8] == TARGET_PAGE) begin
        region = REGION_TARGET;
      end else if (bridge_addr[15:10] == DATATABLE_PAGE) begin
        region = REGION_DATATABLE;
      end
    end
  end

  always_comb begin
    apf_wr_data = bridge_endian_little ? swap_bytes(bridge_wr_data) : bridge_wr_data;

    user_rd = bridge_rd && region == REGION_USER;
    user_wr = bridge_wr && region == REGION_USER;

    host_bus.rd = bridge_rd && region == REGION_HOST;
    host_bus.wr = bridge_wr && region == REGION_HOST;
    host_bus.addr = bridge_addr[7:0];
    host_bus.wr_data = apf_wr_data;

    target_bus.rd = bridge_rd && region == REGION_TARGET;
    target_bus.wr = bridge_wr && region == REGION_TARGET;
    target_bus.addr = bridge_addr[7:0];
    target_bus.wr_data = apf_wr_data;

    datatable_bus.rd = bridge_rd && region == REGION_DATATABLE;
    datatable_bus.wr = bridge_wr && region == REGION_DATATABLE;
    datatable_bus.addr = bridge_addr[9:2];
    datatable_bus.wr_data = apf_wr_data;
  end

  always_comb begin
    unique case (region)
      REGION_HOST: apf_rd_data = host_rd_data;
      REGION_TARGET: apf_rd_data = target_rd_data;
      REGION_DATATABLE: apf_rd_data = datatable_rd_data;
      default: apf_rd_data = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (bridge_rd) begin
      rd_user <= region == REGION_USER;
      apf_rd_data_q <= bridge_endian_little ? swap_bytes(apf_rd_data) : apf_rd_data;
    end
  end

  always_comb begin
    bridge_rd_data = rd_user ? user_rd_data : apf_rd_data_q;
  end
endmodule

`default_nettype wire
