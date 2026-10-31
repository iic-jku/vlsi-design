#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Clock Domains,
# Metastability, and Resets" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_cdc.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter. The ngspice
# characterization takes about five minutes.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_cdc}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in cdc sequential verification synthesis_lib; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
S=$W/content/cdc/code
CONSTR=$W/content/synthesis_lib/code/synth/abc.constr
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

lint() {  # lint <files>: number of Verilator warnings and errors
  verilator --lint-only -Wall "$@" 2>&1 | grep -c -E '%Warning|%Error'
}

cells() {  # cells <log>: the total cell count of the last stat
  grep -E '^ +[0-9]+ +([0-9.E+]+ +)?cells$' "$1" | tail -1 | awk '{print $1}'
}

area() {  # area <log>: the chip area of the last stat -liberty
  grep -oE 'Chip area for (top )?module .*: [0-9.]+' "$1" | tail -1 | awk '{print $NF}'
}

ctype() {  # ctype <log> <type>: count of one cell type in the last stat
  awk -v t="$2" '$NF == t { n = $1 } END { print n }' "$1"
}

period() {  # period <log> <n>: the n-th minimum period and fmax
  grep -o 'period_min = [0-9.]* fmax = [0-9.]*' "$1" | sed -n "${2}p" | awk '{print $3, $6}'
}

endslack() {  # endslack <log> <group> <type>: actual delay and slack of a -format end group
  awk -v g="$2" -v t="$3" '$0 ~ t"/.* group "g"$" { on = 1; next }
       on && /\((MET|VIOLATED)\)/ { print $(NF-2), $(NF-1); exit }' "$1"
}

calc() { awk "BEGIN { $1 }"; }

echo "== Versions"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"
check "ngspice" "$(ngspice -v 2>&1 | grep -o 'ngspice-[0-9]*' | head -1)" "ngspice-47"

echo "== Metastability of dfrbpq_1 in ngspice"
cd "$S/meta"
python3 dff_meta.py > typ.log 2>&1
python3 dff_meta.py slow > slow.log 2>&1
CPAR=0 python3 dff_meta.py > typ0.log 2>&1
CPAR=0 python3 dff_meta.py slow > slow0.log 2>&1
row() { awk -v d="$2" '$1 == d { print $2 }' "$1"; }
fit() { grep -o 'tau = .*' "$1"; }
cq0() { grep -o 't_cq0 = [0-9.]*' "$1" | awk '{print $3}'; }
check "internal nodes of dfrbpq_1" "$(python3 -c 'import dff_meta; print(dff_meta.cell(1.5).count("Cp"))')" "15"
check "typical: t_cq0" "$(cq0 typ.log)" "220.4"
check "typical: t_cq at 1e-11 to 1e-18 s" \
  "$(for e in 11 12 13 14 15 16 17 18; do row typ.log 1e-$e; done | tr '\n' ' ')" \
  "297.3 451.5 635.3 828.0 1024.5 1222.5 1421.3 1617.3 "
check "typical: tau, T0" "$(fit typ.log)" "tau = 85.9 ps, T0 = 23.5 ps"
check "slow: t_cq0" "$(cq0 slow.log)" "330.7"
check "slow: t_cq at 1e-14 to 1e-17 s" \
  "$(for e in 14 15 16 17; do row slow.log 1e-$e; done | tr '\n' ' ')" "1550.3 1913.8 2279.7 2646.1 "
check "slow: tau, T0" "$(fit slow.log)" "tau = 158.7 ps, T0 = 43.4 ps"
check "bare schematic, typical: t_cq0, tau, T0" "$(cq0 typ0.log) $(fit typ0.log)" "190.1 tau = 62.0 ps, T0 = 17.0 ps"
check "bare schematic, slow: tau, T0" "$(fit slow0.log)" "tau = 113.6 ps, T0 = 31.9 ps"
check "delay per decade, typical and slow" "$(calc 'printf "%.0f %.0f", 85.9 * log(10), 158.7 * log(10)')" "198 365"
check "window for 1 ns, light in it (nm)" \
  "$(calc 'w = 23.5e-12 * exp(-1000 / 85.9); printf "%.1e %.0f", w, w * 3e8 * 1e9')" "2.1e-16 62"
cp -r "$W/content/sequential/code/ff" "$W/ffs" && cd "$W/ffs"
sed 's/set_clock_transition 0.1/set_clock_transition 0.09/; s/set_input_transition 0.1/set_input_transition 0.09/' ff.tcl > ff09.tcl
sta -no_init -exit ff09.tcl > typ09.log 2>&1
check "library t_cq0 at the edges of the ngspice run" \
  "$(awk '/Arc type: Reg Clk to Q/ {on = 1} on && /^Delay = / {print $3; exit}' typ09.log)" "0.202"
check "t_cq0 against the library, percent" "$(calc 'printf "%+.0f %+.0f", (220.4 / 202 - 1) * 100, (190.1 / 202 - 1) * 100')" "+9 -6"

echo "== MTBF, 250 MHz, 10 MHz data"
CORNER=slow_1p08V_125C sta -no_init -exit ff.tcl > slow.log 2>&1
check "slow corner: clock-to-output, setup time" \
  "$(awk '/Arc type: Reg Clk to Q/ {on = 1} on && /^Delay = / {printf "%s ", $3; n++} n == 2 {exit}' slow.log)$(awk '/Arc type: setup/ {on = 1} on && /^Check = / {printf "%s ", $3; n++} n == 2 {exit}' slow.log)" \
  "0.305 0.302 0.208 0.187 "
mtbf() {  # mtbf <t_r ns> <tau ps> <T0 ps> <f_clk Hz>: MTBF in seconds
  calc "printf \"%.3g\", exp($1 * 1000 / $2) / ($3e-12 * $4 * 10e6)"
}
YEAR=31557600
check "denominators, typical and slow" \
  "$(calc 'printf "%.0f %.0f", 23.5e-12 * 250e6 * 10e6, 43.4e-12 * 250e6 * 10e6')" "58750 108500"
check "typical, 3 ns of logic: t_r, exponential, MTBF (s), failures per second" \
  "$(calc 'printf "%.3f %.2g", 4 - 0.207 - 3 - 0.127, exp(666 / 85.9)') $(mtbf 0.666 85.9 23.5 250e6) $(calc "printf \"%.0f\", 1 / $(mtbf 0.666 85.9 23.5 250e6)")" \
  "0.666 2.3e+03 0.0396 25"
check "slow, 3 ns of logic: t_r, MTBF (s), failures per second" \
  "$(calc 'printf "%.3f", 4 - 0.305 - 3 - 0.208') $(mtbf 0.487 158.7 43.4 250e6) $(calc "printf \"%.0f\", 1 / $(mtbf 0.487 158.7 43.4 250e6)")" \
  "0.487 0.000198 5051"
check "typical, two flip-flops: MTBF (s), years" \
  "$(mtbf 3.666 85.9 23.5 250e6) $(calc "printf \"%.3g\", $(mtbf 3.666 85.9 23.5 250e6) / $YEAR")" "5.83e+13 1.85e+06"
check "slow, two flip-flops: MTBF (s), hours" \
  "$(mtbf 3.487 158.7 43.4 250e6) $(calc "printf \"%.1f\", $(mtbf 3.487 158.7 43.4 250e6) / 3600")" "3.21e+04 8.9"
check "slow, bare schematic, two flip-flops: years" \
  "$(calc "printf \"%.1f\", $(mtbf 3.487 113.6 31.9 250e6) / $YEAR")" "8.5"
check "slow, three flip-flops: factor, years" \
  "$(calc 'printf "%.2g", exp(3487 / 158.7)') $(calc "printf \"%.2g\", $(mtbf 6.974 158.7 43.4 250e6) / $YEAR")" "3.5e+09 3.5e+06"
check "slow, two flip-flops: period and frequency for 100 years" \
  "$(calc "for (t = 4.0; t < 8; t += 0.001) { m = exp((t - 0.305 - 0.208) / 0.1587) * t * 1e-9 / (43.4e-12 * 10e6); if (m >= 100 * $YEAR) break }; printf \"%.3f %.0f\", t, 1000 / t")" "5.767 173"

echo "== Synchronizers"
cd "$S/sync"
check "lint of sync_2ff, pulse_sync" "$(lint rtl/sync_2ff.sv) $(lint rtl/pulse_sync.sv rtl/sync_2ff.sv)" "0 0"
iverilog -g2012 -o p.vvp rtl/pulse_sync.sv rtl/sync_2ff.sv tb/tb_pulse_sync.sv > /dev/null 2>&1
check "pulse synchronizer" "$(vvp -n p.vvp | grep sent)" "1000 pulses sent, 1000 through pulse_sync, 699 plain"
check "pulse spacing against 1.5 periods of clk_b" "$(calc 'printf "%.0f %.0f", 5 * 10, 1.5 * 14.3')" "50 21"

echo "== Exercise: Count Across Clock Domains"
cd "$S/gray"
check "lint of the crossings" \
  "$(lint rtl/cnt_cross_bin.sv ../sync/rtl/sync_2ff.sv) $(lint rtl/cnt_cross_gray.sv ../sync/rtl/sync_2ff.sv)" "0 0"
for d in cnt_cross_bin cnt_cross_gray; do
  iverilog -g2012 -DDUT=$d -o m.vvp rtl/$d.sv ../sync/sim/sync_2ff_meta.sv tb/tb_cnt_cross.sv > /dev/null 2>&1
  vvp -n m.vvp > $d.meta.log 2>&1
  iverilog -g2012 -DDUT=$d -o r.vvp rtl/$d.sv ../sync/rtl/sync_2ff.sv tb/tb_cnt_cross.sv > /dev/null 2>&1
  vvp -n r.vvp > $d.rtl.log 2>&1
done
check "binary, injection: errors, random samples" \
  "$(grep -o '[0-9]* errors' cnt_cross_bin.meta.log) $(grep -o '[0-9]* of 5001' cnt_cross_bin.meta.log)" "224 errors 334 of 5001"
check "binary, first wrong counts" "$(grep 'ns: count' cnt_cross_bin.meta.log | tr '\n' ' ')" \
  "90.0 ns: count 7 after 4 350.4 ns: count 12 after 14 364.1 ns: count 1 after 12 "
check "Gray, injection: errors, random samples" \
  "$(grep -o '[0-9]* errors' cnt_cross_gray.meta.log) $(grep -o '[0-9]* of 5001' cnt_cross_gray.meta.log)" "0 errors 260 of 5001"
sed 's/      if (sample != d_i) n_random++;/      if (sample != d_i) begin n_random++; if ($realtime < 400) $display("%0.2f ns: d_i %b sampled %b", $realtime, d_i, sample); end/' \
  ../sync/sim/sync_2ff_meta.sv > dbg_meta.sv
iverilog -g2012 -DDUT=cnt_cross_bin -o d.vvp rtl/cnt_cross_bin.sv dbg_meta.sv tb/tb_cnt_cross.sv > /dev/null 2>&1
check "binary, random samples before 400 ns" "$(vvp -n d.vvp | grep 'sampled' | tr '\n' ' ')" \
  "75.35 ns: d_i 0110 sampled 0111 335.65 ns: d_i 0000 sampled 1100 "
check "slow: delay per decade" "$(calc 'printf "%.0f", 111.6 * log(10)')" "257"
check "plain RTL synchronizer: binary, Gray" \
  "$(grep -o '[0-9]* errors' cnt_cross_bin.rtl.log) $(grep -o '[0-9]* errors' cnt_cross_gray.rtl.log)" "0 errors 0 errors"
check "Gray code of 0 to 7" \
  "$(for b in 0 1 2 3 4 5 6 7; do calc "printf \"%d \", xor($b, int($b / 2))"; done)" "0 1 3 2 6 7 5 4 "

echo "== The asynchronous FIFO"
cd "$S/fifo"
check "lint of async_fifo" "$(lint rtl/async_fifo.sv ../sync/rtl/sync_2ff.sv)" "0"
iverilog -g2012 -o f.vvp rtl/async_fifo.sv ../sync/sim/sync_2ff_meta.sv tb/tb_async_fifo.sv > /dev/null 2>&1
vvp -n f.vvp > fmeta.log 2>&1
check "with injection" "$(grep pushed fmeta.log)" "9397 pushed, 9395 popped, 0 errors"
check "random samples in both synchronizers" "$(grep -o '[0-9]* of [0-9]*' fmeta.log | tr '\n' ' ')" "481 of 20000 367 of 13986 "
iverilog -g2012 -o r.vvp rtl/async_fifo.sv ../sync/rtl/sync_2ff.sv tb/tb_async_fifo.sv > /dev/null 2>&1
check "with the RTL synchronizer" "$(vvp -n r.vvp | grep pushed)" "9506 pushed, 9504 popped, 0 errors"
yosys -p "read_verilog -sv ../sync/rtl/sync_2ff.sv rtl/async_fifo.sv; \
  synth -top async_fifo; flatten; dfflibmap -liberty $LIB; \
  abc -constr $CONSTR -liberty $LIB; opt_clean; \
  stat -liberty $LIB; write_verilog -noattr async_fifo.nl.v" > y.log 2>&1
check "async_fifo: cells, area, flip-flops" "$(cells y.log) $(area y.log) $(ctype y.log sg13cmos5l_dfrbpq_1)" "134 3978.979200 54"
sta -no_init -exit syn/sta.tcl > nocdc.log 2>&1
check "without CDC constraints: rclk, wclk" \
  "$(endslack nocdc.log rclk max_delay) $(endslack nocdc.log wclk max_delay)" "100.414 -1.414 1330.156 -0.382"
check "edges of the worst crossing path" \
  "$(awk '/clock wclk \(rise edge\)/ {print $2; exit}' nocdc.log) $(awk '/clock rclk \(rise edge\)/ {print $2; exit}' nocdc.log)" "100.000 100.100"
check "startpoint, endpoint of the worst crossing path" \
  "$(awk '/^Startpoint:/ {s = $2} /^Endpoint:/ {print s, $2; exit}' nocdc.log)" "_138_ data_o[0]"
CDC=1 sta -no_init -exit syn/sta.tcl > cdc.log 2>&1
check "with clock groups: crossing paths" "$(grep -c 'No paths found' cdc.log)" "2"
check "with clock groups: rclk, wclk" \
  "$(endslack cdc.log rclk max_delay) $(endslack cdc.log wclk max_delay)" "0.712 12.488 1.632 8.171"
CDC=2 sta -no_init -exit syn/sta.tcl > cdc2.log 2>&1
check "CDC=2: path delay to data_o, to the synchronizer" \
  "$(awk '/group path delay/ {on = 1; next} /group / {on = 0} on && /\(MET\)/ {printf "%s ", $(NF-1)}' cdc2.log)" "8.586 9.618 "
cat > ep.tcl <<'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog async_fifo.nl.v
link_design async_fifo
read_sdc syn/async_fifo.sdc
foreach {a b} {wclk rclk rclk wclk} {
  report_checks -from [get_clocks $a] -to [get_clocks $b] \
    -group_path_count 100 -endpoint_path_count 1 -format end
}
EOF
sta -no_init -exit ep.tcl > ep.log 2>&1
check "crossing endpoints: all, outputs" "$(grep -cE '\((MET|VIOLATED)\)' ep.log) $(grep -c '^data_o' ep.log)" "14 8"
check "crossing endpoints at flip-flops are first synchronizer stages" \
  "$(for f in $(awk '/\/D \(sg13cmos5l/ {sub("/D", "", $1); print $1}' ep.log); do grep -A4 "sg13cmos5l_dfrbpq_1 $f " async_fifo.nl.v | grep -c 'meta_q'; done | sort | uniq -c | awk '{print $1, $2}')" "6 1"
cat > md.tcl <<'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog async_fifo.nl.v
link_design async_fifo
read_sdc syn/async_fifo.sdc
set_max_delay 10.0 -ignore_clock_latency \
  -from [get_clocks wclk] -to [get_clocks rclk]
set_max_delay 10.0 -ignore_clock_latency \
  -from [get_clocks rclk] -to [get_clocks wclk]
report_checks -path_delay max -from [get_clocks wclk] \
  -to [get_clocks rclk] -digits 3
report_checks -path_delay min -from [get_clocks wclk] \
  -to [get_clocks rclk] -digits 3 -format end
set_false_path -hold -from [get_clocks wclk] -to [get_clocks rclk]
set_false_path -hold -from [get_clocks rclk] -to [get_clocks wclk]
report_checks -path_delay min -from [get_clocks wclk] \
  -to [get_clocks rclk] -digits 3 -format end
EOF
sta -no_init -exit md.tcl > md.log 2>&1
check "set_max_delay alone: hold between the clocks, then with false paths" \
  "$(grep -c '(MET)' md.log) $(grep -c 'No paths found' md.log)" "2 1"
check "set_max_delay: group, slack" \
  "$(grep -o 'Path Group: .*' md.log) $(awk '/slack/ {print $1; exit}' md.log)" "Path Group: path delay 8.586"

echo "== Exercise: Release the Reset"
cd "$S/reset"
check "lint of rst_sync" "$(lint rtl/rst_sync.sv)" "0"
iverilog -g2012 -o r.vvp rtl/rst_sync.sv tb/tb_rst_sync.sv > /dev/null 2>&1
vvp -n r.vvp > r.log 2>&1
check "testbench of rst_sync" "$(grep -v finish r.log | tr '\n' ' ')" \
  "42.1 ns: rst_ni low, rst_no = 0 64.8 ns: rst_ni high, rst_no high at 75.0 ns 0 errors "
yosys -p "read_verilog -sv \
  ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
  ../../../sequential/code/bs_reg/rtl/bs_reg.sv \
  rtl/rst_sync.sv rtl/bs_reg_rs.sv; synth -top bs_reg_rs; flatten; \
  dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; \
  opt_clean; stat -liberty $LIB; write_verilog -noattr bs_reg_rs.nl.v" > y.log 2>&1
check "bs_reg_rs: cells, area, flip-flops" "$(cells y.log) $(area y.log) $(grep -c 'sg13cmos5l_dfrbpq_1 ' bs_reg_rs.nl.v)" "927 15343.360200 73"
sta -no_init -exit syn/sta.tcl > s1.log 2>&1
rs=$(awk '/^Startpoint:/ {s = $2; getline; if ($0 ~ /recovery/) {print s; exit}}' s1.log)
check "recovery path starts at the synchronizer" "$(grep -A3 "sg13cmos5l_dfrbpq_1 $rs " bs_reg_rs.nl.v | grep -o '\.Q([^)]*)')" '.Q(\u_bs_reg.rst_ni )'
check "recovery path: fanout, slew, delay, recovery time, slack" \
  "$(awk -v s="$rs" '$0 ~ s"/Q" {print $1, $2, $3; exit}' s1.log) $(awk '/library recovery time/ {print $1; exit}' s1.log) $(awk '/slack/ {print $1; exit}' s1.log)" \
  "71 1.721 1.375 -0.451 2.074"
check "minimum period, with port paths" "$(period s1.log 1) $(period s1.log 2)" "1.93 519.22 1.93 519.22"
check "period from the recovery path" "$(calc 'printf "%.3f", 1.375 + 0.451 + 0.1')" "1.926"
check "max capacitance at the synchronizer" \
  "$(awk -v s="$rs" '$1 == s"/Q" {print $2, $3, $4; exit}' s1.log)" "0.30 0.43 -0.13"
check "check_setup" "$(grep -c -i 'unclocked\|unconstrained\|missing' s1.log)" "0"
check "rst_ni: removal and recovery slack at the synchronizer" \
  "$(awk '/RESET_B/ && /MET/ {print $(NF-1)}' s1.log | head -3 | tr '\n' ' ')" "1.007 2.768 1.007 "
cp syn/bs_reg_rs.sdc syn/bs_reg_rs_rst.sdc
echo "set_false_path -from [get_ports rst_ni]" >> syn/bs_reg_rs_rst.sdc
SDC=syn/bs_reg_rs_rst.sdc sta -no_init -exit syn/sta.tcl > s2.log 2>&1
check "with the false path: rst_ni, worst removal slack" \
  "$(grep -c 'No paths found' s2.log) $(awk '/RESET_B/ && /MET/ {print $(NF-1)}' s2.log | tail -1)" "1 1.341"
check "with the false path: minimum period" "$(period s2.log 2)" "1.93 519.22"

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
