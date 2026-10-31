#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Logic Synthesis
# and the Standard-Cell Library" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_synthesis_lib.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_synthesis_lib}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
LEF=$D/lef/sg13cmos5l_stdcell.lef
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in synthesis_lib verification sv_crashcourse; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
C=$W/content/synthesis_lib/code
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

attr() {  # attr <lib> <cell> <attribute>: first value inside the cell
  awk -v c="cell (sg13cmos5l_$2)" -v a="$3" '
    index($0, c) == 3 { on = 1; next }
    on && /^  cell \(/ { exit }
    on && $1 == a { gsub(/[";]/, "", $3); print $3; exit }' "$1"
}

width() {  # width <cell>: width in um from the LEF
  awk -v m="MACRO sg13cmos5l_$1" '$0 == m { on = 1 }
    on && $1 == "SIZE" { print $2; exit }' "$LEF"
}

cells() {  # cells <log>: the total cell count of the last stat
  grep -E '^ +[0-9]+ +([0-9.E+]+ +)?cells$' "$1" | tail -1 | awk '{print $1}'
}

ctype() {  # ctype <log> <type>: count of one cell type in the last stat
  grep -E "^ +[0-9]+ +[0-9.E+]* *\\\$?$2\$" "$1" | tail -1 | awk '{print $1}'
}

area() {  # area <log>: the chip area of the last stat -liberty
  grep -oE 'Chip area for (top )?module .*: [0-9.]+' "$1" | tail -1 \
    | awk '{print $NF}'
}

dcalc() {  # dcalc <log> <arc> <Delay|Slew>: value of report_dcalc
  awk -v arc="$2" -v k="$3 =" '$0 == arc { on = 1 }
    on && index($0, k) == 1 { print $3; exit }' "$1"
}

synth_bs() {  # synth_bs <abc command> <log>: barrel shifter, WIDTH 32
  yosys -p "read_verilog -sv \
    ../../../verification/code/barrel_shift/rtl/barrel_shift.sv; \
    chparam -set WIDTH 32 barrel_shift; synth -top barrel_shift; \
    $1; opt_clean; \
    stat -liberty $LIB; write_verilog -noattr barrel_shift.nl.v" > "$2" 2>&1
}

arrival() {  # arrival [corner]: the arrival time of the slowest output
  CORNER=${1:-typ_1p20V_25C} TOP=barrel_shift sta -no_init -exit comb_sta.tcl \
    | awk '/^data_o/ {print $4; exit}'
}

echo "== Versions"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "EQY in the image" "$(command -v eqy > /dev/null && echo yes)" "yes"
check "kepler-formal in the image" "$(command -v kepler-formal > /dev/null && echo yes)" "yes"
check "kepler-formal modes" "$(kepler-formal --help 2>&1 | grep -c -- '-v <lec|sec>')" "1"

echo "== Library views"
for f in lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib lef/sg13cmos5l_stdcell.lef \
  gds/sg13cmos5l_stdcell.gds verilog/sg13cmos5l_stdcell.v \
  cdl/sg13cmos5l_stdcell.cdl spice/sg13cmos5l_stdcell.spice \
  doc/sg13cmos5l_stdcell_typ_1p20V_25C.pdf sch/xschem sym/xschem; do
  check "view $f" "$([ -e "$D/$f" ] && echo yes)" "yes"
done
check "corners" "$(ls "$D"/lib/*.lib | sed 's/.*stdcell_//; s/\.lib//' | tr '\n' ' ')" \
  "fast_1p32V_m40C fast_1p65V_m40C slow_1p08V_125C slow_1p35V_125C typ_1p20V_25C typ_1p50V_25C "

echo "== Cells"
grep -oE '^  cell \(sg13cmos5l_[a-z0-9_]+' "$LIB" | sed 's/.*sg13cmos5l_//' > names.txt
check "cells in the library" "$(wc -l < names.txt)" "84"
n() { grep -cE "$1" names.txt; }
check "flip-flops" "$(n '^s?df')" "9"
check "latches" "$(n '^dl[hl]')" "5"
check "clock gates" "$(n '^s?lgcp')" "2"
check "tri-state drivers" "$(n '^e(buf|inv)n')" "6"
check "delay cells" "$(n '^dlygate')" "3"
check "tie cells" "$(n '^tie')" "2"
check "physical cells" "$(n '^(fill|decap|antenna)')" "7"
check "bus holder" "$(n '^sighold$')" "1"
check "combinational logic" \
  "$(grep -cvE '^(s?df|dl[hl]|s?lgcp|e(buf|inv)n|dlygate|tie|fill|decap|antenna|sighold)' names.txt)" "49"
check "flip-flop groups without clear" \
  "$(grep -A1 -E '^ +ff \(' "$LIB" | grep -cE '^ +(next_state|clocked_on)')" "0"
check "site" "$(awk '/^SITE +CoreSite/ {on = 1} on && $1 == "SIZE" {print $2, $4; exit}' "$LEF")" "0.48 3.78"
for c in inv_1:1.44 nand2_1:1.92 a21oi_1:2.4 xor2_1:3.84 mux2_1:4.8 \
  dfrbpq_1:12.96 fill_1:0.48 fill_2:0.96 decap_4:1.92; do
  check "width of ${c%%:*}" "$(width "${c%%:*}")" "${c##*:}"
done
check "height of every cell" "$(grep -E '^ +SIZE .* BY ' "$LEF" | awk '{print $4}' | sort -u | tr '\n' ' ')" "3.78 "
for c in inv_1:5.4432 nand2_1:7.2576 mux4_1:38.1024 dfrbpq_1:48.9888; do
  check "area of ${c%%:*}" "$(attr "$LIB" "${c%%:*}" area)" "${c##*:}"
done
ge() { awk -v a="$(attr "$LIB" "$1" area)" -v n="$(attr "$LIB" nand2_1 area)" 'BEGIN {print a / n}'; }
check "GE of inv_1, mux4_1, dfrbpq_1" "$(ge inv_1) $(ge mux4_1) $(ge dfrbpq_1)" "0.75 5.25 6.75"
check "inv_4: area, GE, capacitance of A, max_capacitance" \
  "$(attr "$LIB" inv_4 area) $(ge inv_4) $(attr "$LIB" inv_4 capacitance) $(attr "$LIB" inv_4 max_capacitance)" \
  "10.8864 1.5 0.0112211 1.2"
check "inv_4/inv_1: capacitance ratio" \
  "$(awk -v a="$(attr "$LIB" inv_4 capacitance)" -v b="$(attr "$LIB" inv_1 capacitance)" 'BEGIN {printf "%.1f", a / b}')" "3.9"

echo "== Liberty file"
for a in "delay_model : table_lookup;" 'time_unit : "1ns";' "capacitive_load_unit (1,pf);" \
  'leakage_power_unit : "1pW";' "nom_process : 1;" "nom_temperature : 25;" "nom_voltage : 1.2;" \
  "input_threshold_pct_rise : 50;" "output_threshold_pct_rise : 50;" \
  "slew_lower_threshold_pct_rise : 20;" "slew_upper_threshold_pct_rise : 80;"; do
  check "header: $a" "$(grep -cxF "  $a" "$LIB")" "1"
done
check "no CCS tables" "$(grep -c 'output_current_' "$LIB")" "0"
check "inv_1 leakage" "$(attr "$LIB" inv_1 cell_leakage_power)" "63.0032"
check "inv_1 function" "$(attr "$LIB" inv_1 function)" "!(A)"
check "inv_1 max_capacitance" "$(attr "$LIB" inv_1 max_capacitance)" "0.3"
check "inv_1 capacitance of A" "$(attr "$LIB" inv_1 capacitance)" "0.00286745"
check "inv_1 timing_sense" "$(attr "$LIB" inv_1 timing_sense)" "negative_unate"
check "inv_1 cell_rise row 1" \
  "$(grep -m1 -A4 'cell_rise (TIMING_DELAY_7x7ds1)' <(sed -n '/cell (sg13cmos5l_inv_1)/,$p' "$LIB") | sed -n 5p | tr -d ' "\\' | cut -d, -f1-3)" \
  "0.0205647,0.0848969,0.128137"
check "dfrbpq_1 ff group" \
  "$(sed -n '/cell (sg13cmos5l_dfrbpq_1)/,/cell (sg13cmos5l_dfrbpq_2)/p' "$LIB" | grep -A3 ' ff (' | tr '\n' ' ' | tr -s ' ')" \
  " ff (IQ,IQN) { clear : \"!RESET_B\"; clocked_on : \"CLK\"; next_state : \"D\"; "
check "dfrbpq_1 function of Q" "$(attr "$LIB" dfrbpq_1 function)" "IQ"
check "dfrbpq_1 timing types" \
  "$(sed -n '/cell (sg13cmos5l_dfrbpq_1)/,/cell (sg13cmos5l_dfrbpq_2)/p' "$LIB" | grep -o 'timing_type : [a-z_]*' | awk '{print $3}' | sort -u | tr '\n' ' ')" \
  "clear hold_rising min_pulse_width recovery_rising removal_rising rising_edge setup_rising "
check "constraint table variables" \
  "$(grep -A2 'lu_table_template (CONSTRAINT_4x4)' "$LIB" | grep -o 'variable_[12] : [a-z_]*' | awk '{print $3}' | tr '\n' ' ')" \
  "constrained_pin_transition related_pin_transition "

echo "== Delay calculation"
cd "$C/dcalc"
sta -no_init -exit dcalc.tcl > typ.log 2>&1
check "rise delay" "$(dcalc typ.log 'A v -> Y ^' Delay)" "0.2775"
check "rise slew" "$(dcalc typ.log 'A v -> Y ^' Slew)" "0.2408"
check "fall delay" "$(dcalc typ.log 'A ^ -> Y v' Delay)" "0.2574"
check "fall slew" "$(dcalc typ.log 'A ^ -> Y v' Slew)" "0.1981"
check "table excerpt" "$(grep -A8 'A v -> Y ^' typ.log | sed -n 7,8p | tr -s ' ' | tr '\n' ' ')" \
  "0.1740 | 0.2112 0.2860 0.3294 | 0.2764 0.3633 "
check "no violation at 0.05 pF" "$(grep -c VIOLATED typ.log)" "0"
# Bilinear interpolation by hand, from the full-precision entries
check "interpolation by hand" "$(awk 'BEGIN {
  u = (0.05 - 0.039) / (0.0648 - 0.039); t = (0.25 - 0.174) / (0.3294 - 0.174)
  r1 = 0.211237 + u * (0.285953 - 0.211237); r2 = 0.276414 + u * (0.363301 - 0.276414)
  f1 = 0.196172 + u * (0.259858 - 0.196172); f2 = 0.259958 + u * (0.33725 - 0.259958)
  printf "%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", u, t, r1, r2, r1 + t * (r2 - r1), f1, f2, f1 + t * (f2 - f1) }')" \
  "0.4264 0.4891 0.2431 0.3135 0.2775 0.2233 0.2929 0.2574"
check "inv_1 cell_fall entries" \
  "$(sed -n '/cell (sg13cmos5l_inv_1)/,$p' "$LIB" | grep -m1 -A11 'cell_fall (' | sed -n '7,8p' | tr -d ' "\\' | cut -d, -f3,4 | tr '\n' ' ')" \
  "0.196172,0.259858 0.259958,0.33725 "
LOAD=0.4 sta -no_init -exit dcalc.tcl > big.log 2>&1
check "rise delay at 0.4 pF" "$(dcalc big.log 'A v -> Y ^' Delay)" "1.2563"
check "columns used at 0.4 pF" "$(grep -A4 'A v -> Y ^' big.log | sed -n 5p | tr -s ' ')" "| 0.1800 0.3000"
check "max capacitance violation" "$(grep 'u1/Y' big.log | tr -s ' ')" "u1/Y 0.30 0.40 -0.10 (VIOLATED)"
cp one_inv.v one_inv_1.v
sed -i 's/inv_1/inv_4/' one_inv.v
LOAD=0.2 sta -no_init -exit dcalc.tcl > inv4.log 2>&1
check "inv_4 at 0.2 pF: fall and rise delay" \
  "$(dcalc inv4.log 'A ^ -> Y v' Delay) $(dcalc inv4.log 'A v -> Y ^' Delay)" "0.2578 0.2771"
mv one_inv_1.v one_inv.v
for c in fast_1p32V_m40C:0.1966:0.2047 typ_1p20V_25C:0.2574:0.2775 slow_1p08V_125C:0.3529:0.3759 \
  fast_1p65V_m40C:0.1451:0.1543 typ_1p50V_25C:0.1877:0.2083 slow_1p35V_125C:0.2593:0.2761; do
  IFS=: read -r corner fall rise <<< "$c"
  CORNER=$corner sta -no_init -exit dcalc.tcl > "$corner.log" 2>&1
  check "fall and rise delay, $corner" \
    "$(dcalc "$corner.log" 'A ^ -> Y v' Delay) $(dcalc "$corner.log" 'A v -> Y ^' Delay)" "$fall $rise"
done
check "slow/fast at 1.2 V, fall and rise" \
  "$(awk 'BEGIN {printf "%.2f %.2f", 0.3529 / 0.1966, 0.3759 / 0.2047}')" "1.80 1.84"
# Wire-load model: one inverter driving eight inverters
cat > wl.v << 'EOF'
module wl (input a, output [7:0] y);
  wire n;
  sg13cmos5l_inv_1 d (.A(a), .Y(n));
EOF
for i in 0 1 2 3 4 5 6 7; do
  echo "  sg13cmos5l_inv_1 l$i (.A(n), .Y(y[$i]));" >> wl.v
done
echo "endmodule" >> wl.v
cat > wl.tcl << EOF
read_liberty $LIB
read_verilog wl.v
link_design wl
report_net -digits 4 n
set_wire_load_model -name 1k
report_net -digits 4 n
EOF
sta -no_init -exit wl.tcl > wl.log 2>&1
check "wire-load models" "$(grep -c '^  wire_load (' "$LIB")" "12"
check "default wire-load model" "$(grep -o 'default_wire_load : "[^"]*"' "$LIB")" 'default_wire_load : "1k"'
check "wire capacitance, no model and 1k, 8 loads" \
  "$(grep 'Wire capacitance' wl.log | awk '{print $3}' | tr '\n' ' ')" "0.0000 0.0182-0.0182 "

echo "== Synthesis"
check "stages of synth" "$(yosys -p 'help synth' | grep -oE '^ +[a-z]+:' | tr -d ' ' | tr '\n' ' ')" \
  "begin: coarse: fine: check: "
cd "$W/content/sv_crashcourse/code/mux4"
yosys -p "read_verilog -sv rtl/mux4.sv; synth -top mux4; stat" > generic.log 2>&1
check "mux4 generic cells" "$(cells generic.log)" "67"
check "mux4 generic NAND, AND, NOR, ANDNOT" \
  "$(ctype generic.log '_NAND_') $(ctype generic.log '_AND_') $(ctype generic.log '_NOR_') $(ctype generic.log '_ANDNOT_')" \
  "40 20 5 2"
yosys -p "read_verilog -sv rtl/mux4.sv; synth -top mux4; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
  stat -liberty $LIB" > mapped.log 2>&1
check "mux4 mapped cells" "$(cells mapped.log)" "11"
check "mux4 mux4_1, nor4_1, and2_1" \
  "$(ctype mapped.log sg13cmos5l_mux4_1) $(ctype mapped.log sg13cmos5l_nor4_1) $(ctype mapped.log sg13cmos5l_and2_1)" "8 2 1"
check "mux4 area" "$(area mapped.log)" "335.664000"
cd "$C/lec"
yosys -p "read_verilog -sv \
  ../../../verification/code/fifo/rtl/fifo.sv; synth -top fifo; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
  stat -liberty $LIB; write_verilog -noattr fifo.nl.v" > fifo_syn.log 2>&1
check "FIFO cells" "$(cells fifo_syn.log)" "103"
check "FIFO area" "$(area fifo_syn.log)" "3008.275200"
check "FIFO GE" "$(awk -v a="$(area fifo_syn.log)" 'BEGIN {printf "%.1f", a / 7.2576}')" "414.5"
check "LibreLane SYNTH_STRATEGY default" \
  "$(grep -A16 '"SYNTH_STRATEGY",' "$(python3 -c 'import librelane.steps.pyosys as p; print(p.__file__)')" \
    | grep -o 'default="[^"]*"')" 'default="AREA 0"'
cd "$C/synth"
check "abc -constr adds buffering and sizing" \
  "$(yosys -h abc | grep -c 'dnsize {D}; stime -p')" "1"
check "abc set_load unit" "$(yosys -h abc | grep -o 'sets the load in')$(yosys -h abc | grep -o ' femtofarads')" \
  "sets the load in femtofarads"
check "abc.constr" "$(tr '\n' ' ' < abc.constr)" "set_driving_cell sg13cmos5l_inv_2 set_load 10 "
SLOW=slow_1p08V_125C
synth_bs "abc -liberty $LIB" def.log
check "barrel shifter, default: cells area typ slow" \
  "$(cells def.log) $(area def.log) $(arrival) $(arrival $SLOW)" "747 9399.007800 2.51 3.87"
synth_bs "abc -D 1000 -liberty $LIB" d1000_noconstr.log
check "barrel shifter, -D 1000 without -constr: cells area delay" \
  "$(cells d1000_noconstr.log) $(area d1000_noconstr.log) $(arrival)" "747 9399.007800 2.51"
synth_bs "abc -D 1000 -constr abc.constr -liberty $LIB" d1000.log
check "barrel shifter, -D 1000: cells area typ slow" \
  "$(cells d1000.log) $(area d1000.log) $(arrival) $(arrival $SLOW)" "818 10030.419000 1.50 2.33"
synth_bs "abc -liberty $LIB -script +strash;dch,-f;amap;topo" amap.log
check "barrel shifter, amap: cells area typ slow" \
  "$(cells amap.log) $(area amap.log) $(arrival) $(arrival $SLOW)" "765 7305.530400 4.81 7.36"
synth_bs "abc -D 3000 -constr abc.constr -liberty $LIB" d3000.log
check "barrel shifter, -D 3000: cells area delay" \
  "$(cells d3000.log) $(area d3000.log) $(arrival)" "818 9914.297400 1.88"
synth_bs "abc -D 500 -constr abc.constr -liberty $LIB" d500.log
check "barrel shifter, -D 500: cells area delay" \
  "$(cells d500.log) $(area d500.log) $(arrival)" "818 10030.419000 1.50"
synth_bs "abc -constr abc.constr -liberty $LIB" constr.log
check "barrel shifter, -constr without -D: cells area delay" \
  "$(cells constr.log) $(area constr.log) $(arrival)" "818 10030.419000 1.50"
check "area -D 1000 / amap, delay amap / -D 1000, saving of amap, saving of -D 3000" \
  "$(awk 'BEGIN {printf "%.2f %.1f %.0f %.0f", 10030.419 / 7305.5304, 4.81 / 1.50, 100 * (1 - 7305.5304 / 9399.0078), 10030.419 - 9914.2974}')" \
  "1.37 3.2 22 116"
check "margin at 250 MHz, slow corner: -D 1000, default" \
  "$(awk 'BEGIN {printf "%.2f %.2f", 4 - 2.33, 4 - 3.87}')" "1.67 0.13"

echo "== Equivalence checking"
cd "$C/lec"
ln -sf "$LIB" stdcell.lib
check "read_liberty without -ignore_miss_func" \
  "$(yosys -p 'read_liberty stdcell.lib' 2>&1 | grep -o 'Missing function on output [A-Za-z_]* of cell [a-z0-9_]*' | head -1)" \
  "Missing function on output int_GATE of cell sg13cmos5l_lgcp_1"
printf 'module t (input a, b, output y);\n  sg13cmos5l_lgcp_1 u (.CLK(a), .GATE(b), .GCLK(y));\nendmodule\n' > lgcp.v
check "hierarchy -check rejects a skipped cell" \
  "$(yosys -p 'read_liberty -ignore_miss_func stdcell.lib; read_verilog lgcp.v; hierarchy -check -top t' 2>&1 | grep -c 'is not part of the design')" "1"
start=$(date +%s)
eqy -d fifo_eqy fifo.eqy > fifo.log 2>&1; rc=$?
secs=$(( $(date +%s) - start ))
check "FIFO: exit status" "$rc" "0"
check "FIFO: messages" "$(grep -oE 'Successfully proved designs equivalent|DONE \(PASS, rc=0\)' fifo.log | tr '\n' ' ')" \
  "Successfully proved designs equivalent DONE (PASS, rc=0) "
check "FIFO: below 10 s (measured about 3 s)" "$([ "$secs" -lt 10 ] && echo yes)" "yes"
check "FIFO: partitions" "$(awk '{print $2}' fifo_eqy/partition.list | tr '\n' ' ')" "fifo.empty_o fifo.full_o fifo.data_o "
check "FIFO: matched.ids" "$([ -s fifo_eqy/matched.ids ] && echo yes)" "yes"
sed '/^\[collect/,/^bind empty_o/d' fifo.eqy > nocollect.eqy
eqy -d nc nocollect.eqy > nc.log 2>&1; rc=$?
check "FIFO without [collect *]: exit status" "$rc" "2"
check "FIFO without [collect *]: partitions" "$(wc -l < nc/partition.list)" "9"
check "FIFO without [collect *]: failed" \
  "$(grep -o 'Failed to prove equivalence of partition fifo\.[a-z_.0-9]*' nc.log | awk '{print $NF}' | sort | tr '\n' ' ')" \
  "fifo.mem_q.1 fifo.mem_q.2 fifo.mem_q.3 fifo.rd_ptr_q fifo.wr_ptr_q "
cat > vcd.py << 'EOF'
"""vcd.py <vcd> <step|last> <name...>: top-level values at a step"""
import sys
lines = open(sys.argv[1]).read().splitlines()
ids, vals, rows, scope = {}, {}, [], []
for line in lines:
    tok = line.split()
    if tok[:1] == ["$scope"]:
        scope.append(tok[2])
    elif tok[:1] == ["$upscope"]:
        scope.pop()
    elif tok[:1] == ["$var"] and len(scope) == 1:
        ids[tok[3]] = tok[4]
    elif line.startswith("#"):
        rows.append(dict(vals))
    elif line[:1] == "b" and tok[1] in ids:
        vals[ids[tok[1]]] = tok[0][1:]
    elif line[:1] in "01xz" and line[1:] in ids:
        vals[ids[line[1:]]] = line[0]
rows.append(dict(vals))
step = sys.argv[2]  # two time stamps per step, or the last one
row = rows[-1] if step == "last" else rows[2 * int(step) + 1]
print(" ".join(row.get(n, "?") for n in sys.argv[3:]))
EOF
T=nc/strategies/fifo.wr_ptr_q/sby/fifo.wr_ptr_q/engine_0/trace.vcd
check "wr_ptr_q counterexample, free inputs" \
  "$(grep -o '__pi_[a-z_]*' "$T" | sort -u | tr '\n' ' ')" "__pi_clk_i __pi_full_o __pi_push_i __pi_rd_ptr_q __pi_rst_ni "
check "wr_ptr_q counterexample, step 1: rst, push, full, rd_ptr, wr_ptr" \
  "$(python3 vcd.py "$T" 1 __pi_rst_ni __pi_push_i __pi_full_o __pi_rd_ptr_q __po_wr_ptr_q__gold)" "1 1 0 100 000"
check "wr_ptr_q counterexample, step 2: gold, gate" \
  "$(python3 vcd.py "$T" 2 __po_wr_ptr_q__gold __po_wr_ptr_q__gate)" "001 000"
mkdir -p m3/rtl && cp ../../../verification/code/fifo/rtl/fifo.sv m3/rtl/
sed -i 's/push_i \&\& !full_o/push_i \&\& (!full_o || pop_i)/' m3/rtl/fifo.sv
check "M3 applied" "$(grep -c '(!full_o || pop_i)' m3/rtl/fifo.sv)" "1"
sed 's#../../../verification/code/fifo/rtl/fifo.sv#m3/rtl/fifo.sv#' fifo.eqy > m3.eqy
eqy -d m3_eqy m3.eqy > m3.log 2>&1; rc=$?
check "stale RTL (M3): exit status" "$rc" "2"
check "stale RTL (M3): failed partition" \
  "$(grep -o 'Failed to prove equivalence of partition [a-z_.0-9]*' m3.log | awk '{print $NF}' | tr '\n' ' ')" "fifo.full_o "
# EQY compares only the states that the RTL reaches after reset
mkdir -p unreach && cd unreach
cat > gold.sv << 'EOF'
module cnt (input logic clk_i, rst_ni, output logic [1:0] q_o);
  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) q_o <= '0;
    else q_o <= (q_o == 2'd2) ? 2'd0 : q_o + 2'd1;
endmodule
EOF
printf '[gold]\nread_verilog -sv gold.sv\nprep -top cnt\n\n[gate]\nread_verilog -sv gate.sv\nprep -top cnt\n\n[strategy sby]\nuse sby\nengine abc pdr\n' > cnt.eqy
sed 's/else q_o <=/else if (q_o == 2'"'"'d3) q_o <= 2'"'"'d2;\n    else q_o <=/' gold.sv > gate.sv
eqy -d unreach cnt.eqy > unreach.log 2>&1
check "mod-3 counter, difference in the unreachable state 3: EQY" "$(grep -o 'DONE ([A-Z]*, rc=[0-9])' unreach.log)" "DONE (PASS, rc=0)"
sed 's/else q_o <=/else if (q_o == 2'"'"'d1) q_o <= 2'"'"'d3;\n    else q_o <=/' gold.sv > gate.sv
eqy -d reach cnt.eqy > reach.log 2>&1
check "mod-3 counter, difference in the reachable state 1: EQY" "$(grep -o 'DONE ([A-Z]*, rc=[0-9])' reach.log)" "DONE (FAIL, rc=2)"
cd ..
# Exercise: the barrel shifter
yosys -p "read_verilog -sv \
  ../../../verification/code/barrel_shift/rtl/barrel_shift.sv; \
  chparam -set WIDTH 32 barrel_shift; synth -top barrel_shift; \
  abc -liberty $LIB; opt_clean; \
  stat -liberty $LIB; write_verilog -noattr barrel_shift.nl.v" > bs_syn.log 2>&1
check "barrel shifter netlist for EQY: cells" "$(cells bs_syn.log)" "747"
start=$(date +%s)
eqy -d bs_eqy barrel_shift.eqy > bs.log 2>&1; rc=$?
secs=$(( $(date +%s) - start ))
check "barrel shifter: exit status" "$rc" "0"
check "barrel shifter: below 10 s (measured about 3 s)" "$([ "$secs" -lt 10 ] && echo yes)" "yes"
check "barrel shifter: partitions" "$(cat bs_eqy/partition.list | tr -s ' ')" "barrel_shift barrel_shift.data_o : data_o[31:0]"
cp barrel_shift.nl.v barrel_shift_good.nl.v
sed -i '0,/sg13cmos5l_a21oi_1 /s//sg13cmos5l_o21ai_1 /' \
  barrel_shift.nl.v
check "mutant: one cell changed" "$(diff barrel_shift_good.nl.v barrel_shift.nl.v | grep -c '^>')" "1"
eqy -d bs_mut barrel_shift.eqy > bs_mut.log 2>&1; rc=$?
check "mutant: exit status" "$rc" "2"
check "mutant: message" "$(grep -o 'Failed to prove equivalence of partition [a-z_.0-9]*' bs_mut.log)" \
  "Failed to prove equivalence of partition barrel_shift.data_o"
T=$(ls bs_mut/strategies/*/sby/*/engine_0/trace.vcd)
read -r d s m gold gate <<< "$(python3 vcd.py "$T" last __pi_data_i __pi_shamt_i __pi_mode_i __po_data_o__gold __po_data_o__gate)"
hex() { printf '%08X' "$((2#$1))"; }
check "counterexample: data, shamt, mode" "$(hex "$d") $((2#$s)) $m" "57C45344 8 10"
check "counterexample: gold, gate" "$(hex "$gold") $(hex "$gate")" "C4534457 C4524457"
check "counterexample: differing bit" "$(awk -v x=$((2#$gold ^ 2#$gate)) 'BEGIN {print log(x) / log(2)}')" "16"
check "counterexample: gold is the rotation by 8" \
  "$(printf '%08X' $(( ((0x57C45344 << 8) | (0x57C45344 >> 24)) & 0xFFFFFFFF )))" "C4534457"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all results match the chapter"
else
  echo "FAIL: $fails result(s) differ from the chapter"
  exit 1
fi
