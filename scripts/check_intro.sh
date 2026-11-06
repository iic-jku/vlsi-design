#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Tests the gaps of the open-source tools that tbl-tools-gaps
# in the chapter "Introduction" states for image 2026.10, where a run in
# the IIC-OSIC-TOOLS container can test them. Run from the repository root:
#   bash scripts/check_intro.sh
# A failure after an image update means that a row may be stale, not that
# the gap is closed: OpenSTA's crosstalk analysis needs CCS library models.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_intro}
LIB=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib
fails=0

rm -rf "$W" && mkdir -p "$W"
cp -r "$REPO/content/cdc/code" "$W/cdc"
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

echo "== Versions"
check "Verilator" "$(verilator --version | awk '{print $2}')" "5.052"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "Fault" "$(fault --version)" "0.9.4"
check "OpenCDC" "$(opencdc --version | head -1)" "OpenCDC v0.4.1"

echo "== Lint"
check "Verible has a configurable naming rule" \
  "$(verible-verilog-lint --help_rules=signal-name-style 2>&1 | grep -c 'style_regex')" "1"

echo "== Simulation"
cat > t.sv <<'EOF'
module t;
  initial $sdf_annotate("t.sdf");
endmodule
EOF
check "Verilator: --fourstate is still under development" \
  "$(verilator --lint-only --fourstate t.sv 2>&1 | grep -c 'under development')" "1"
check "Verilator: \$sdf_annotate is ignored" \
  "$(verilator --lint-only -Wno-fatal t.sv 2>&1 | grep -c '^%Warning.*sdf_annotate')" "1"
cat > tc.v <<'EOF'
module tc (input clk, input d, output reg q);
  specify
    $setup(d, posedge clk, 1);
  endspecify
  always @(posedge clk) q <= d;
endmodule
EOF
check "Icarus Verilog: no timing checks" \
  "$(iverilog -gspecify -o tc.vvp tc.v 2>&1 | grep -c 'Timing checks are not supported')" "1"

echo "== OpenSTA"
cat > s.tcl <<'EOF'
puts "report_power: [llength [info commands report_power]]"
puts "noise: [llength [info commands annotate_noise_delays]]"
exit
EOF
check "report_power exists, no crosstalk delay analysis" \
  "$(sta -no_init -no_splash s.tcl 2>&1 | grep -E '^(report_power|noise):' | tr '\n' ' ')" "report_power: 1 noise: 0 "
check "SG13CMOS5L libraries with CCS tables, of 6" \
  "$(ls "$LIB"/*.lib | wc -l) $(cat "$LIB"/*.lib | grep -c 'output_current_')" "6 0"

echo "== OpenROAD"
cat > o.tcl <<'EOF'
puts "read_upf: [llength [info commands read_upf]]"
puts "supply: [llength [info commands create_supply_net]]"
puts "retention: [llength [info commands set_retention]]"
exit
EOF
openroad -no_init -no_splash -exit o.tcl > o.log 2>&1
check "read_upf exists, for a subset of UPF" \
  "$(grep -E '^(read_upf|supply|retention):' o.log | tr '\n' ' ')" "read_upf: 1 supply: 0 retention: 0 "
printf 'help analyze_power_grid\nexit\n' > p.tcl
openroad -no_init -no_splash -exit p.tcl > p.log 2>&1
check "analyze_power_grid exists, with no activity or time step option" \
  "$(grep -c 'analyze_power_grid -net' p.log) $(grep -c -i -E 'dynamic|vcd|saif|time_step' p.log)" "1 0"

echo "== OpenCDC"
S=$W/cdc
cd "$S/fifo" || exit 1
opencdc_report() {  # opencdc_report <top> <files>: the text report
  opencdc check "${@:2}" --top "$1" --format text 2>&1
}
opencdc_errors() {  # opencdc_errors <top> <files>: rule and source of each error
  opencdc_report "$@" | awk '$1 == "error" {print $2, $3}' | sort | tr '\n' ' '
}
SYNC=../sync/rtl/sync_2ff.sv
opencdc_report async_fifo rtl/async_fifo.sv $SYNC > opencdc_fifo.log
check "OpenCDC: async_fifo, one error per Gray pointer" \
  "$(awk '$1 == "error" {print $2, $3}' opencdc_fifo.log | sort | tr '\n' ' ')" \
  "[CDC001] async_fifo.rgray_q [CDC001] async_fifo.wgray_q "
check "OpenCDC: async_fifo, the reset wrst_ni as the domain of wgray_q" \
  "$(grep -c '^error \[CDC001\] async_fifo.wgray_q (wrst_ni)' opencdc_fifo.log)" "1"
check "OpenCDC: async_fifo, outputs data_o not listed" "$(grep -c 'data_o' opencdc_fifo.log)" "0"
cat > opencdc_cases.sv <<'EOF'
module raw_bit (input logic clk_i, rst_ni, d_i, output logic q_o);
  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) q_o <= 1'b0;
    else         q_o <= d_i;
endmodule
module one_bit_raw (
  input  logic clk_a_i, rst_a_ni, d_i, clk_b_i, rst_b_ni,
  output logic q_o
);
  logic a_q;
  always_ff @(posedge clk_a_i or negedge rst_a_ni)
    if (!rst_a_ni) a_q <= 1'b0;
    else           a_q <= d_i;
  always_ff @(posedge clk_b_i or negedge rst_b_ni)
    if (!rst_b_ni) q_o <= 1'b0;
    else           q_o <= a_q;
endmodule
module two_children (
  input  logic clk_a_i, rst_a_ni, d_i, clk_b_i, rst_b_ni,
  output logic q_o
);
  logic a_q;
  raw_bit u_a (clk_a_i, rst_a_ni, d_i, a_q);
  raw_bit u_b (clk_b_i, rst_b_ni, a_q, q_o);
endmodule
module one_bit_sync (
  input  logic clk_a_i, rst_a_ni, d_i, clk_b_i, rst_b_ni,
  output logic q_o
);
  logic a_q;
  always_ff @(posedge clk_a_i or negedge rst_a_ni)
    if (!rst_a_ni) a_q <= 1'b0;
    else           a_q <= d_i;
  sync_2ff #(.WIDTH(1)) u_sync (clk_b_i, rst_b_ni, a_q, q_o);
endmodule
module two_bit_sync (
  input  logic clk_a_i, rst_a_ni, clk_b_i, rst_b_ni,
  input  logic [1:0] d_i,
  output logic [1:0] q_o
);
  logic [1:0] a_q;
  always_ff @(posedge clk_a_i or negedge rst_a_ni)
    if (!rst_a_ni) a_q <= '0;
    else           a_q <= d_i;
  sync_2ff #(.WIDTH(2)) u_sync (clk_b_i, rst_b_ni, a_q, q_o);
endmodule
module in_loop (
  input  logic clk_a_i, rst_a_ni, clk_b_i, rst_b_ni,
  input  logic [1:0] d_i,
  output logic [1:0] q_o
);
  logic [1:0] a_q;
  always_ff @(posedge clk_a_i or negedge rst_a_ni)
    if (!rst_a_ni) a_q <= '0;
    else           a_q <= d_i;
  for (genvar i = 0; i < 2; i++) begin : g_bit
    raw_bit u_b (clk_b_i, rst_b_ni, a_q[i], q_o[i]);
  end
endmodule
module no_loop (
  input  logic clk_a_i, rst_a_ni, clk_b_i, rst_b_ni,
  input  logic [1:0] d_i,
  output logic [1:0] q_o
);
  logic [1:0] a_q;
  always_ff @(posedge clk_a_i or negedge rst_a_ni)
    if (!rst_a_ni) a_q <= '0;
    else           a_q <= d_i;
  raw_bit u_b0 (clk_b_i, rst_b_ni, a_q[0], q_o[0]);
  raw_bit u_b1 (clk_b_i, rst_b_ni, a_q[1], q_o[1]);
endmodule
EOF
check "OpenCDC: a single-bit crossing without a synchronizer, CDC001" \
  "$(opencdc_errors one_bit_raw opencdc_cases.sv $SYNC | grep -c '\[CDC001\]')" "1"
# The same design with sync_2ff at one and at two bits: the cause of the Gray pointer errors.
check "OpenCDC: sync_2ff accepted at one bit" \
  "$(opencdc_report one_bit_sync opencdc_cases.sv $SYNC | grep -c '^info \[CDC001\].*\[SAFE\]')" "1"
check "OpenCDC: sync_2ff rejected at two bits" \
  "$(opencdc_report two_bit_sync opencdc_cases.sv $SYNC | grep -c '^error \[CDC001\].*\[UNSAFE\]')" "1"
# The same crossing as one_bit_raw, with both flip-flops in instances.
check "OpenCDC: crossing between two instances, no findings" \
  "$(opencdc_report two_children opencdc_cases.sv $SYNC | tail -1)" "analysis_status=complete findings=0"
# The same crossing with and without the generate loop.
check "OpenCDC: crossing into an instance in a generate loop, no findings" \
  "$(opencdc_report in_loop opencdc_cases.sv $SYNC | tail -1)" "analysis_status=complete findings=0"
check "OpenCDC: the same crossing without the loop is found" \
  "$(opencdc_errors no_loop opencdc_cases.sv $SYNC | grep -c '\[CDC001\]')" "1"
cd "$S/gray"
check "OpenCDC: binary counter, multi-bit crossing, CDC002" \
  "$(opencdc_errors cnt_cross_bin rtl/cnt_cross_bin.sv $SYNC | grep -c '\[CDC002\] cnt_cross_bin.cnt_a_q')" "1"
cd "$S/sync"
check "OpenCDC: pulse_sync, separate resets, CDC009" \
  "$(opencdc_errors pulse_sync rtl/pulse_sync.sv rtl/sync_2ff.sv)" "[CDC009] pulse_sync.tgl_a_q "

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
