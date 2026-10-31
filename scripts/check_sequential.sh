#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Sequential
# Elements and Static Timing Analysis" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_sequential.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_sequential}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
SLOW=slow_1p08V_125C
FAST=fast_1p32V_m40C
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in sequential verification modeling synthesis_lib; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
S=$W/content/sequential/code
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

attr() {  # attr <cell> <attribute>: first value inside the cell
  awk -v c="cell (sg13cmos5l_$1)" -v a="$2" '
    index($0, c) == 3 { on = 1; next }
    on && /^  cell \(/ { exit }
    on && $1 == a { gsub(/[";]/, "", $3); print $3; exit }' "$LIB"
}

dc() {  # dc <log> <arc type> <n>: the n-th Check or Delay value of an arc type
  awk -v t="Arc type: $2" -v n="$3" '
    index($0, t) == 1 { on = 1; next }
    on && /^Arc type:/ { on = 0 }
    on && /^(Check|Delay) = / { if (++k == n) { print $3; exit } }' "$1"
}

field() {  # field <log> <report n> <regex>: last field of a line in the n-th path report
  awk -v n="$2" -v re="$3" '/^Startpoint:/ { r++ } r == n && $0 ~ re { print $NF ~ /\(/ ? $(NF-1) : $NF; exit }' "$1"
}

col() {  # col <log> <report n> <regex> <field>: a field of a line in the n-th path report
  awk -v n="$2" -v re="$3" -v f="$4" '/^Startpoint:/ { r++ } r == n && $0 ~ re { print $f; exit }' "$1"
}

cells() {  # cells <log>: the total cell count of the last stat
  grep -E '^ +[0-9]+ +([0-9.E+]+ +)?cells$' "$1" | tail -1 | awk '{print $1}'
}

area() {  # area <log>: the chip area of the last stat -liberty
  grep -oE 'Chip area for (top )?module .*: [0-9.]+' "$1" | tail -1 | awk '{print $NF}'
}

ctype() {  # ctype <log> <type>: count of one cell type in the last stat
  grep -E "^ +[0-9]+ +[0-9.E+]* *$2\$" "$1" | tail -1 | awk '{print $1}'
}

period() {  # period <log>: the minimum period and fmax of report_clock_min_period
  grep -o 'period_min = [0-9.]* fmax = [0-9.]*' "$1" | awk '{print $3, $6}'
}

echo "== Versions"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"

echo "== Cells"
check "area of dlhq_1, dfrbpq_1" "$(attr dlhq_1 area) $(attr dfrbpq_1 area)" "30.8448 48.9888"
check "dlhq_1 is transparent while GATE is high" \
  "$(sed -n '/cell (sg13cmos5l_dlhq_1)/,/cell (sg13cmos5l_dlhr_1)/p' "$LIB" | grep -o 'enable : "[A-Z]*"')" 'enable : "GATE"'
check "dllrq_1 is transparent while GATE_N is low" \
  "$(sed -n '/cell (sg13cmos5l_dllrq_1)/,/cell (sg13cmos5l_dlygate4sd1_1)/p' "$LIB" | grep -o 'enable : "[!A-Z_]*"')" 'enable : "!GATE_N"'
check "delay cells" "$(grep -oE 'cell \(sg13cmos5l_dlygate4sd[0-9]_1\)' "$LIB" | tr -d '()' | awk '{print $2}' | tr '\n' ' ')" \
  "sg13cmos5l_dlygate4sd1_1 sg13cmos5l_dlygate4sd2_1 sg13cmos5l_dlygate4sd3_1 "

echo "== Timing parameters of dfrbpq_1"
cd "$S/ff"
sta -no_init -exit ff.tcl > ff.log 2>&1
check "clock-to-output, Q rising and falling" "$(dc ff.log 'Reg Clk to Q' 1) $(dc ff.log 'Reg Clk to Q' 2)" "0.207 0.203"
check "setup, D rising and falling" "$(dc ff.log setup 1) $(dc ff.log setup 2)" "0.127 0.121"
check "hold, D rising and falling" "$(dc ff.log hold 1) $(dc ff.log hold 2)" "-0.072 -0.043"
check "recovery, removal" "$(dc ff.log recovery 1) $(dc ff.log removal 1)" "0.133 -0.114"
check "reset to output" "$(dc ff.log 'Reg Set/Clr' 1)" "0.276"
check "minimum pulse width, CLK high, CLK low, RESET_B low" \
  "$(dc ff.log width 1) $(dc ff.log width 2) $(awk '/^RESET_B v -> RESET_B \^/ {on = 1} on && /^Check = / {print $3; exit}' ff.log)" \
  "0.064 0.104 0.233"
sed 's/set_input_transition 0.1 \[get_ports {d_i rst_ni}\]/set_input_transition 0.042 [get_ports {d_i rst_ni}]/' ff.tcl > ff_fast.tcl
sta -no_init -exit ff_fast.tcl > ff_fast.log 2>&1
check "setup with a data edge of 0.042 ns, D falling" "$(dc ff_fast.log setup 2)" "0.100"
check "T_min for 1 ns of logic" "$(awk 'BEGIN {printf "%.3f", 0.207 + 1 + 0.127}')" "1.334"

echo "== bs_reg with buffering and sizing"
cd "$S/bs_reg"
check "lint of bs_reg" \
  "$(verilator --lint-only -Wall rtl/bs_reg.sv ../../../verification/code/barrel_shift/rtl/barrel_shift.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
synth() {  # synth <abc command> <log>
  yosys -p "read_verilog -sv \
    ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
    rtl/bs_reg.sv; synth -top bs_reg; flatten; \
    dfflibmap -liberty $LIB; $1; opt_clean; \
    stat -liberty $LIB; write_verilog -noattr bs_reg.nl.v" > "$2" 2>&1
}
synth "abc -constr ../../../synthesis_lib/code/synth/abc.constr -liberty $LIB" sized.log
check "cells, area" "$(cells sized.log) $(area sized.log)" "915 15276.340800"
check "flip-flops" "$(grep -c 'sg13cmos5l_dfrbpq_1 ' bs_reg.nl.v)" "71"
check "buffers buf_1, buf_2, buf_4, buf_8" \
  "$(ctype sized.log sg13cmos5l_buf_1) $(ctype sized.log sg13cmos5l_buf_2) $(ctype sized.log sg13cmos5l_buf_4) $(ctype sized.log sg13cmos5l_buf_8)" \
  "74 21 8 1"
sta -no_init -exit syn/sta.tcl > sized_typ.log 2>&1
check "check_setup is clean" "$(grep -c '^Warning' sized_typ.log)" "0"
# Report 1: recovery, 2: setup clk, 3: removal, 4: hold clk
check "setup path: start and end point" \
  "$(grep -A4 'dfrbpq_1 _1719_ (' bs_reg.nl.v | grep -o 'Q([a-z_]*\[[0-9]*\])') $(grep -A4 'dfrbpq_1 _1716_ (' bs_reg.nl.v | grep -o 'Q([a-z_]*\[[0-9]*\])')" \
  "Q(shamt_q[1]) Q(out_q[30])"
check "setup path: start point in the report" "$(awk '/^Startpoint:/ {r++} r == 2 && /^Startpoint/ {print $2; exit}' sized_typ.log)" "_1719_"
check "setup path: clock-to-output" "$(col sized_typ.log 2 '_1719_/Q' 2)" "0.204"
check "setup path: buffers and their fanout" \
  "$(awk '/^Startpoint:/ {r++} r == 2 && /sg13cmos5l_buf_/ {printf "%s ", $1}' sized_typ.log)" "9 10 10 10 "
check "setup path: arrival, uncertainty, setup time, slack" \
  "$(col sized_typ.log 2 'data arrival time' 1) $(col sized_typ.log 2 'clock uncertainty' 1) $(col sized_typ.log 2 'library setup time' 1) $(col sized_typ.log 2 'slack' 1)" \
  "1.491 -0.100 -0.100 2.308"
check "minimum period, fmax" "$(period sized_typ.log)" "1.69 591.16"
check "min period by hand" "$(awk 'BEGIN {printf "%.3f", 1.491 + 0.100 + 0.100}')" "1.691"
cat > ports.tcl << EOF
read_liberty $LIB
read_verilog bs_reg.nl.v
link_design bs_reg
read_sdc syn/bs_reg.sdc
report_clock_min_period -include_port_paths
EOF
check "minimum period with the port paths" "$(sta -no_init -exit ports.tcl 2>&1 | grep -o 'period_min = [0-9.]* fmax = [0-9.]*' | awk '{print $3, $6}')" "2.02 494.37"
check "reset release by hand" "$(awk 'BEGIN {printf "%.3f", 1.0 + 0.599 + 0.323 + 0.1}')" "2.022"
check "hold path: start and end point" \
  "$(awk '/^Startpoint:/ {r++} r == 4 && /^(Startpoint|Endpoint)/ {printf "%s ", $2}' sized_typ.log)" "_1654_ _1702_ "
check "hold path: registers" \
  "$(grep -A4 'dfrbpq_1 _1654_ (' bs_reg.nl.v | grep -o 'Q([a-z_]*\[[0-9]*\])') $(grep -A4 'dfrbpq_1 _1702_ (' bs_reg.nl.v | grep -o 'Q([a-z_]*\[[0-9]*\])')" \
  "Q(data_q[0]) Q(out_q[16])"
check "hold path: arrival, uncertainty, hold time, required, slack" \
  "$(col sized_typ.log 4 'data arrival time' 1) $(col sized_typ.log 4 'clock uncertainty' 1) $(col sized_typ.log 4 'library hold time' 1) $(col sized_typ.log 4 'data required time' 1) $(col sized_typ.log 4 'slack' 1)" \
  "0.328 0.100 -0.019 0.081 0.247"
check "recovery: fanout and delay of rst_ni, recovery time, slack" \
  "$(col sized_typ.log 1 'rst_ni [(]in[)]' 1) $(col sized_typ.log 1 'rst_ni [(]in[)]' 2) $(col sized_typ.log 1 'library recovery time' 1) $(col sized_typ.log 1 'slack' 1)" \
  "71 0.599 -0.323 1.977"
check "removal: slack" "$(col sized_typ.log 3 'slack' 1)" "1.610"
cat > slew.tcl << EOF
read_liberty $LIB
read_verilog bs_reg.nl.v
link_design bs_reg
read_sdc syn/bs_reg.sdc
report_checks -path_delay max -to [get_pins _1654_/RESET_B] -fields {slew} -digits 3
EOF
check "slew of rst_ni at the flip-flops" \
  "$(sta -no_init -exit slew.tcl 2>&1 | awk '/_1654_\/RESET_B/ {print $1; exit}')" "0.872"
check "wns, tns, violators" \
  "$(grep -oE '^(wns|tns) max [-0-9.]+' sized_typ.log | awk '{print $3}' | tr '\n' ' ')$(grep -c VIOLATED sized_typ.log)" "0.000 0.000 0"
CORNER=$SLOW sta -no_init -exit syn/sta.tcl > sized_slow.log 2>&1
check "slow corner: minimum period" "$(period sized_slow.log | awk '{print $1}')" "2.58"
check "slow corner: setup slack between the registers" "$(col sized_slow.log 2 'slack' 1 | awk '{printf "%.2f", $1}')" "1.42"

echo "== bs_reg with the default mapping"
synth "abc -liberty $LIB" default.log
check "cells, area" "$(cells default.log) $(area default.log)" "811 14398.171200"
check "area of the sized netlist against the default one" "$(awk 'BEGIN {printf "%.0f", 100 * (15276.3408 / 14398.1712 - 1)}')" "6"
sta -no_init -exit syn/sta.tcl > default_typ.log 2>&1
check "wns, tns" "$(grep -oE '^(wns|tns) max [-0-9.]+' default_typ.log | awk '{print $3}' | tr '\n' ' ')" "-2.507 -76.407 "
check "minimum period, fmax" "$(period default_typ.log)" "6.51 153.68"
check "worst path start point" "$(awk '/^Startpoint:/ {r++} r == 2 && /^Startpoint/ {print $2; exit}' default_typ.log)" "_1510_"
check "start point drives" "$(grep -A4 'dfrbpq_1 _1510_ (' bs_reg.nl.v | grep -o 'Q([a-z_]*\[[0-9]*\])')" "Q(shamt_q[0])"
check "fanout and delay of the first three cells" \
  "$(awk '/^Startpoint:/ {r++} r == 2 && /(_1510_\/Q|o21ai_1|nand2_1)/ {printf "%s %s ", $1, $2}' default_typ.log)" \
  "116 1.971 35 1.779 48 1.758 "
check "three cells together" "$(awk 'BEGIN {printf "%.1f", 1.971 + 1.779 + 1.758}')" "5.5"
check "arrival, setup time" "$(col default_typ.log 2 'data arrival time' 1) $(col default_typ.log 2 'library setup time' 1)" "6.308 -0.099"
check "min period by hand" "$(awk 'BEGIN {printf "%.3f", 6.308 + 0.099 + 0.100}')" "6.507"
check "max slew violations: count, limit, largest and smallest slew" \
  "$(awk '/^max slew/ {m = 1} /^max capacitance/ {m = 0} m && /VIOLATED/ {n++; l = $2; if (n == 1) hi = $3; lo = $3} END {print n, l, hi, lo}' default_typ.log)" \
  "208 2.51 3.50 2.63"
check "max capacitance violations" \
  "$(awk '/^max capacitance/ {m = 1} m && /VIOLATED/ {printf "%s %s %s ", $1, $2, $3}' default_typ.log)" \
  "_1510_/Q 0.30 0.87 _1511_/Q 0.30 0.65 "
CORNER=$SLOW sta -no_init -exit syn/sta.tcl > default_slow.log 2>&1
check "slow corner: minimum period" "$(period default_slow.log | awk '{print $1}')" "10.14"
check "slow corner against the combinational block of chapter 5" "$(awk 'BEGIN {printf "%.1f", 10.14 / 3.87}')" "2.6"

echo "== Multicycle paths"
synth "abc -constr ../../../synthesis_lib/code/synth/abc.constr -liberty $LIB" sized2.log
sed 's/-period 4.0/-period 1.2/' syn/bs_reg.sdc > fast.sdc
cat > mcp.tcl << EOF
read_liberty $LIB
read_verilog bs_reg.nl.v
link_design bs_reg
read_sdc fast.sdc
if {[info exists ::env(SETUP)]} {
  set_multicycle_path \$::env(SETUP) -setup -from [all_registers] -to [all_registers]
}
if {[info exists ::env(HOLD)]} {
  set_multicycle_path \$::env(HOLD) -hold -from [all_registers] -to [all_registers]
}
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -format end -digits 3
report_checks -path_delay min -from [all_registers -clock_pins] -to [all_registers -data_pins] -format end -digits 3
EOF
slacks() { grep -E 'MET|VIOL' | awk '{print $(NF-1)}' | tr '\n' ' '; }
check "1.2 ns: setup, hold" "$(sta -no_init -exit mcp.tcl 2>&1 | slacks)" "-0.492 0.247 "
check "1.2 ns, setup 2: setup, hold" "$(SETUP=2 sta -no_init -exit mcp.tcl 2>&1 | slacks)" "0.708 -0.953 "
check "1.2 ns, setup 2, hold 1: setup, hold" "$(SETUP=2 HOLD=1 sta -no_init -exit mcp.tcl 2>&1 | slacks)" "0.708 0.247 "

echo "== Generated clocks"
cd "$S/gen_clk"
mv led_blink_fpga.sdc led_blink_fpga_solution.sdc
yosys -p "read_verilog -sv \
  ../../../modeling/code/led_blink/exercise/led_blink_fpga.sv; \
  synth -top led_blink_fpga; dfflibmap -liberty $LIB; \
  abc -liberty $LIB; opt_clean; \
  write_verilog -noattr led_blink_fpga.nl.v" > fpga.log 2>&1
check "flip-flops of the FPGA version" "$(grep -c 'sg13cmos5l_dfrbpq_1 ' led_blink_fpga.nl.v)" "26"
check "flip-flops on clk_i" "$(grep -A1 'sg13cmos5l_dfrbpq_1 ' led_blink_fpga.nl.v | grep -c 'CLK(clk_i)')" "25"
check "count_q width" "$(grep -oE 'wire \[[0-9]+:0\] count_q' led_blink_fpga.nl.v)" "wire [23:0] count_q"
check "the LED flip-flop" "$(grep -A3 'dfrbpq_1 _175_ (' led_blink_fpga.nl.v | grep -oE '\.(CLK|Q)\([a-z_]+\)' | tr '\n' ' ')" ".CLK(slow_clk_q) .Q(led_q) "
printf 'create_clock -name clk -period 20 [get_ports clk_i]\nset_output_delay 0 -clock clk [all_outputs]\nset_load 0.01 [all_outputs]\n' > clk.sdc
TOP=led_blink_fpga SDC=clk.sdc sta -no_init -exit sta.tcl > clk.log 2>&1
check "clk only: warnings" \
  "$(grep -A2 '^Warning' clk.log | grep -v -- '--' | tr -s ' ' | tr '\n' '|')" \
  "Warning: There is 1 unclocked register/latch pin.| _175_/CLK|Warning: There are 2 unconstrained endpoints.| led_o| _175_/D|"
check "clk only: path groups" "$(grep -o 'group [a-z_]*' clk.log | tr '\n' ' ')" "group clk "
cp led_blink_fpga_solution.sdc led_blink_fpga.sdc
TOP=led_blink_fpga SDC=led_blink_fpga.sdc sta -no_init -exit sta.tcl > gen.log 2>&1
check "generated clock: warnings" "$(grep -c '^Warning' gen.log)" "0"
check "generated clock: period and edges" "$(grep '^slow_clk' gen.log | tr -s ' ')" "slow_clk 500000000.00 0.00250000000.00 (generated)"
check "generated clock: path groups" "$(grep -o 'group [a-z_]*' gen.log | tr '\n' ' ')" "group clk group slow_clk "
check "generated clock: endpoint" "$(awk '/group slow_clk/ {on = 1} on && /dfrbpq/ {print $1; exit}' gen.log)" "_175_/D"
yosys -p "read_verilog -sv ../../../modeling/code/led_blink/rtl/led_blink.sv; \
  synth -top led_blink; dfflibmap -liberty $LIB; abc -liberty $LIB; \
  opt_clean; write_verilog -noattr led_blink.nl.v" > asic.log 2>&1
check "flip-flops of the ASIC version, all on clk_i" \
  "$(grep -c 'sg13cmos5l_dfrbpq_1 ' led_blink.nl.v) $(grep -A1 'sg13cmos5l_dfrbpq_1 ' led_blink.nl.v | grep -c 'CLK(clk_i)')" "26 26"
printf 'create_clock -name clk -period 20 [get_ports clk_i]\nset_output_delay 0 -clock clk [all_outputs]\nset_load 0.01 [all_outputs]\n' > asic_nordel.sdc
TOP=led_blink SDC=asic_nordel.sdc sta -no_init -exit sta.tcl > asic_nordel.log 2>&1
check "ASIC version without input delay" "$(grep -A1 '^Warning' asic_nordel.log | tr -s ' ' | tr '\n' '|')" \
  "Warning: There is 1 input port missing set_input_delay.| rst_ni|"
{ cat asic_nordel.sdc; echo 'set_input_delay 0 -clock clk [get_ports rst_ni]'; } > asic.sdc
TOP=led_blink SDC=asic.sdc sta -no_init -exit sta.tcl > asic_sta.log 2>&1
check "ASIC version: warnings, path groups" \
  "$(grep -c '^Warning' asic_sta.log) $(grep -o 'group [a-z_]*' asic_sta.log | tr '\n' ' ')" "0 group asynchronous group clk "

echo "== Hold violations"
cd "$S/hold"
hold() {  # hold <corner> [period]: hold and setup slack of ff1 -> ff2
  PERIOD=${2:-4} CORNER=$1 sta -no_init -exit hold.tcl 2>&1 | grep 'slack' | awk '{print $1}' | tr '\n' ' '
}
check "four buffers: fast" "$(hold $FAST)" "-0.022 3.962 "
check "four buffers: typical" "$(hold typ_1p20V_25C)" "-0.030 3.941 "
check "four buffers: slow" "$(hold $SLOW)" "-0.054 3.897 "
for c in $FAST $SLOW; do
  CORNER=$c sta -no_init -exit hold.tcl > hold_$c.log 2>&1
done
check "fast: clock latency of ff2, clock-to-output of ff1" \
  "$(awk '/Path Type: min/ {on = 1} on && /network delay/ {n++; if (n == 2) {print $1; exit}}' hold_$FAST.log) $(col hold_$FAST.log 1 'ff1/Q' 1)" \
  "0.179 0.137"
check "slow: clock latency of ff2, clock-to-output of ff1" \
  "$(awk '/Path Type: min/ {on = 1} on && /network delay/ {n++; if (n == 2) {print $1; exit}}' hold_$SLOW.log) $(col hold_$SLOW.log 1 'ff1/Q' 1)" \
  "0.388 0.288"
check "period 40 ns, slow" "$(hold $SLOW 40)" "-0.054 39.897 "
cp shift.v shift_orig.v
sed -i 's/  wire q1, ck1, ck2, ck3, ck4;/  wire q1, q1d, ck1, ck2, ck3, ck4;/' shift.v
sed -i 's/  sg13cmos5l_dfrbpq_1 ff2 (.CLK(ck4), .D(q1),/  sg13cmos5l_dlygate4sd1_1 dly (.A(q1), .X(q1d));\n  sg13cmos5l_dfrbpq_1 ff2 (.CLK(ck4), .D(q1d),/' shift.v
check "delay cell inserted" "$(grep -c 'dlygate4sd1_1 dly' shift.v) $(grep -c 'D(q1d)' shift.v)" "1 1"
check "with dlygate4sd1_1: fast" "$(hold $FAST)" "0.067 3.881 "
check "with dlygate4sd1_1: typical" "$(hold typ_1p20V_25C)" "0.105 3.809 "
check "with dlygate4sd1_1: slow" "$(hold $SLOW)" "0.161 3.697 "

echo "== Time borrowing"
cd "$S/borrow"
TOP=borrow_ff sta -no_init -exit borrow.tcl > ff.log 2>&1
TOP=borrow_latch sta -no_init -exit borrow.tcl > latch.log 2>&1
check "falling-edge flip-flop: stage 1, stage 2" "$(grep slack ff.log | awk '{print $1}' | tr '\n' ' ')" "-0.474 1.001 "
check "latch: stage 1, stage 2" "$(grep slack latch.log | awk '{print $1}' | tr '\n' ' ')" "0.000 0.620 "
check "latch: borrowed time" "$(grep 'actual time borrow' latch.log | awk '{print $NF}')" "0.354"
check "latch: given to the second stage" "$(grep 'time given to startpoint' latch.log | awk '{print $1}')" "0.354"
check "dllrq_1: hold of D against the closing (rising) edge of GATE_N" \
  "$(sed -n '/cell (sg13cmos5l_dllrq_1)/,/cell (sg13cmos5l_dlygate4sd1_1)/p' "$LIB" | grep -B2 'timing_type : hold' | grep -o 'related_pin : "[A-Z_]*"\|timing_type : [a-z_]*' | tr '\n' ' ')" \
  'related_pin : "GATE_N" timing_type : hold_rising '

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all results match the chapter"
else
  echo "FAIL: $fails result(s) differ from the chapter"
  exit 1
fi
