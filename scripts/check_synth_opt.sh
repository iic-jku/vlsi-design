#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Synthesis
# Optimizations and Low-Power Design" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_synth_opt.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_synth_opt}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
CELLS=$D/verilog
LL=$(python3 -c "import librelane, os; print(os.path.dirname(librelane.__file__))")
PDKLL=$PDK_ROOT/ihp-sg13cmos5l/libs.tech/librelane
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in synth_opt sequential verification synthesis_lib; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
S=$W/content/synth_opt/code
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

attr() {  # attr <cell> <attribute>: first value inside the cell
  awk -v c="cell (sg13cmos5l_$1)" -v a="$2" '
    index($0, c) == 3 { on = 1; next }
    on && /^  cell \(/ { exit }
    on && $1 == a { gsub(/[";]/, "", $3); print $3; exit }' "$LIB"
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

onpath() {  # onpath <log>: cells between the start and the end flip-flop
  awk '/^Path Group: clk/ { on = 1 } on && /data arrival time/ { exit }
       on && /\(sg13cmos5l_/ { n++ } END { print n - 3 }' "$1"
}

pw() {  # pw <log> <group> <column>: a column of report_power
  awk -v g="$2" -v c="$3" '$1 == g { print $c; exit }' "$1"
}

flops() {  # flops <netlist>: the number of dfrbpq_1 instances
  grep -c 'sg13cmos5l_dfrbpq_1 ' "$1"
}

echo "== Versions"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"

echo "== Yosys and LibreLane"
Y=$(yosys-config --datdir)
check "default adder of techmap.v" "$(grep -c 'module _90_lcu_brent_kung' "$Y/techmap.v")" "1"
check "prefix adders in choices" "$(ls "$Y/choices" | tr '\n' ' ')" "han-carlson.v kogge-stone.v sklansky.v "
check "synth -extra-map" "$(yosys -h synth | grep -c 'techmap -map +/techmap.v -map <inject>')" "1"
check "synth runs arith_tree and booth only on request" \
  "$(yosys -h synth | grep -E '^ +(arith_tree|booth) +\(if' | awk '{print $1}' | tr '\n' ' ')" "booth arith_tree "
check "abc -dff passes flip-flops without reset" \
  "$(yosys -h abc | grep -c 'also pass \$_DFF_?_ and \$_DFFE_??_ cells through ABC')" "1"
check "default scripts run dretime" "$(yosys -h abc | grep -c 'scorr; dc2; dretime; strash;')" "5"
for v in "SYNTH_ADDER_TYPE YOSYS" "SYNTH_ARITH_TREE True" "SYNTH_MUL_BOOTH True" \
         "SYNTH_ABC_DFF False" "SYNTH_STRATEGY AREA 0"; do
  set -- $v; n=$1; shift
  check "LibreLane default of $n" "$(python3 -c "
from librelane.steps.pyosys import SynthesisCommon
from librelane.steps.yosys import YosysStep
vs = {x.name: x for x in SynthesisCommon.config_vars + YosysStep.config_vars}
print(vs['$n'].default)" 2>/dev/null)" "$*"
done
check "LibreLane runs clockgate" "$(grep -c '"clockgate",' "$LL/scripts/pyosys/synthesize.py")" "1"
check "DELAY 4 repeats its sequence 5 times" \
  "$(grep -A30 'strategy == "DELAY 4"' "$LL/scripts/pyosys/construct_abc_script.py" | grep -c 'range(5)')" "1"
check "SG13CMOS5L config sets no ICG" "$(grep -rc 'CLOCKGATE' "$PDKLL" | awk -F: '{s += $2} END {print s}')" "0"
check "SG13CMOS5L excludes the clock gates from synthesis" \
  "$(grep -c 'lgcp_1' "$PDKLL/sg13cmos5l_stdcell/synth_exclude.cells")" "2"
check "maximum fanout of SG13CMOS5L" "$(grep MAX_FANOUT_CONSTRAINT "$PDKLL/sg13cmos5l_stdcell/config.tcl" | awk '{print $NF}')" "10"

echo "== Cells"
check "area of mux2_1, lgcp_1, slgcp_1" "$(attr mux2_1 area) $(attr lgcp_1 area) $(attr slgcp_1 area)" "18.144 27.216 30.8448"
check "lgcp_1 is a clock gate" "$(attr lgcp_1 clock_gating_integrated_cell)" "latch_posedge"
check "slgcp_1 is a clock gate with scan enable" "$(attr slgcp_1 clock_gating_integrated_cell)" "latch_posedge_precontrol"
check "pins of slgcp_1" \
  "$(sed -n '/cell (sg13cmos5l_slgcp_1)/,/^  }/p' "$LIB" | grep -oE 'pin \([A-Z]+\)' | tr -d '()' | awk '{print $2}' | sort | tr '\n' ' ')" \
  "CLK GATE GCLK SCE "

echo "== Exercise: Ripple or Prefix?"
cd "$S/adder"
for f in add_reg add_ripple add_pipe; do
  check "lint of $f" "$(verilator --lint-only -Wall rtl/$f.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
done
synth() {  # synth <top> <synth options> <abc options> <log>
  yosys -p "read_verilog -sv rtl/$1.sv; synth -top $1 $2; \
    dfflibmap -liberty $LIB; abc $3 -liberty $LIB; opt_clean; \
    stat -liberty $LIB; write_verilog -noattr $1.nl.v" > "$4" 2>&1
  TOP=$1 sta -no_init -exit ../syn/sta.tcl > "${4%.log}.sta" 2>&1
}
KS="-extra-map +/choices/kogge-stone.v"
DELAY="-script ../syn/delay.abc -constr $CONSTR"
synth add_ripple "" "-constr $CONSTR" ripple.log
check "ripple: cells, area" "$(cells ripple.log) $(area ripple.log)" "254 6462.892800"
check "ripple: period, cells on the path" "$(period ripple.sta 1) $(onpath ripple.sta)" "4.74 211.08 32"
synth add_reg "" "-constr $CONSTR" bk.log
check "Brent-Kung: cells, area" "$(cells bk.log) $(area bk.log)" "264 6448.377600"
check "Brent-Kung: period, cells on the path" "$(period bk.sta 1) $(onpath bk.sta)" "3.83 261.31 32"
check "flip-flops of add_reg" "$(flops add_reg.nl.v)" "97"
synth add_reg "$KS" "-constr $CONSTR" ks.log
check "Kogge-Stone: cells, area" "$(cells ks.log) $(area ks.log)" "293 6752.970000"
check "Kogge-Stone: period, cells on the path" "$(period ks.sta 1) $(onpath ks.sta)" "3.30 303.24 27"
synth add_ripple "" "$DELAY" ripple_d.log
check "ripple, delay script: cells, area" "$(cells ripple_d.log) $(area ripple_d.log)" "370 7580.336400"
check "ripple, delay script: period, cells on the path" "$(period ripple_d.sta 1) $(onpath ripple_d.sta)" "2.03 493.69 10"
synth add_reg "" "$DELAY" bk_d.log
check "Brent-Kung, delay script: cells, area" "$(cells bk_d.log) $(area bk_d.log)" "379 7741.704600"
check "Brent-Kung, delay script: period, cells on the path" "$(period bk_d.sta 1) $(onpath bk_d.sta)" "2.78 359.55 17"
synth add_reg "$KS" "$DELAY" ks_d.log
check "Kogge-Stone, delay script: cells, area" "$(cells ks_d.log) $(area ks_d.log)" "363 7516.908000"
check "Kogge-Stone, delay script: period, cells on the path" "$(period ks_d.sta 1) $(onpath ks_d.sta)" "2.06 485.64 12"
check "flip-flop area of the adders" "$(awk 'BEGIN {printf "%.2f", 97 * 48.9888}')" "4751.91"
ltpl() {  # ltpl <top> <synth options>: longest path through the generic gates
  yosys -p "read_verilog -sv rtl/$1.sv; synth -top $1 $2; ltp -noff" 2>&1 | grep -o 'length=[0-9]*' | tail -1 | cut -d= -f2
}
check "longest path, synth -noabc: ripple, Brent-Kung, Kogge-Stone" \
  "$(ltpl add_ripple -noabc) $(ltpl add_reg -noabc) $(ltpl add_reg "$KS -noabc")" "63 18 11"
check "longest path, synth: ripple, Brent-Kung, Kogge-Stone" \
  "$(ltpl add_ripple "") $(ltpl add_reg "") $(ltpl add_reg "$KS")" "63 62 42"
check "keep.abc is the -constr script without its first steps" \
  "$(grep -v '^#' ../syn/keep.abc | tr '\n' ' ')" "strash &get -n &dch -f &nf &put buffer upsize dnsize stime -p "
per() { period "$1" 1 | cut -d' ' -f1; }
KEEP="-script ../syn/keep.abc -constr $CONSTR"
synth add_ripple "-noabc" "$KEEP" ripple_k.log
check "ripple, keep: cells, area, period, cells on the path" \
  "$(cells ripple_k.log) $(area ripple_k.log) $(per ripple_k.sta) $(onpath ripple_k.sta)" "239 6372.172800 4.78 32"
synth add_reg "-noabc" "$KEEP" bk_k.log
check "Brent-Kung, keep: cells, area, period, cells on the path" \
  "$(cells bk_k.log) $(area bk_k.log) $(per bk_k.sta) $(onpath bk_k.sta)" "294 6809.367600 2.11 10"
synth add_reg "$KS -noabc" "$KEEP" ks_k.log
check "Kogge-Stone, keep: cells, area, period, cells on the path" \
  "$(cells ks_k.log) $(area ks_k.log) $(per ks_k.sta) $(onpath ks_k.sta)" "413 7923.447000 1.45 7"
check "Kogge-Stone over ripple with keep.abc: speed, logic areas" \
  "$(awk 'BEGIN {printf "%.1f %.0f %.0f", 4.78 / 1.45, 7923.447 - 4751.91, 6372.1728 - 4751.91}')" "3.3 3172 1620"
synth add_reg "-noabc" "-constr $CONSTR" bk_nd.log
synth add_reg "$KS -noabc" "-constr $CONSTR" ks_nd.log
check "synth -noabc with -constr: Brent-Kung, Kogge-Stone" "$(per bk_nd.sta) $(per ks_nd.sta)" "3.73 3.45"
synth add_ripple "-noabc" "$DELAY" ripple_nd.log
synth add_reg "-noabc" "$DELAY" bk_ndd.log
synth add_reg "$KS -noabc" "$DELAY" ks_ndd.log
check "synth -noabc with delay.abc: ripple, Brent-Kung, Kogge-Stone" \
  "$(per ripple_nd.sta) $(per bk_ndd.sta) $(per ks_ndd.sta)" "2.21 1.86 2.00"
check "dretime retimes for minimum area by default" "$(yosys-abc -c 'dretime -h' 2>&1 | grep -c 'default = min-area')" "1"
check "abc -D adds a delay-oriented retime" "$(yosys -h abc | grep -c "replaces 'dretime' with 'dretime; retime -o {D}'")" "1"
check "maccmap builds the sum of four operands" \
  "$(printf 'module s(input [15:0] a,b,c,d, output [17:0] y); assign y = a+b+c+d; endmodule\n' > s4.v; \
     yosys -p 'read_verilog s4.v; synth -top s' 2>&1 | grep -c 'Using extmapper maccmap for cells of type \$macc_v2')" "1"
check "SG13CMOS5L provides no adder maps for LibreLane" \
  "$(grep -c 'FA_MAP\|RCA_MAP\|CSA_MAP' "$PDKLL/config.tcl" "$PDKLL/sg13cmos5l_stdcell/config.tcl" | awk -F: '{s += $2} END {print s}')" "0"
pathcells() {  # pathcells <sta log>: cell types on the worst clk path
  awk '/^Path Group: clk/ { on = 1 } on && /data arrival time/ { exit }
       on && /\(sg13cmos5l_/ { print $NF }' "$1" | sort | uniq -c | awk '{printf "%s %s ", $1, $2}'
}
check "ripple: cells on the path" "$(pathcells ripple.sta)" \
  "15 (sg13cmos5l_a21oi_2) 3 (sg13cmos5l_dfrbpq_1) 1 (sg13cmos5l_nand2_2) 16 (sg13cmos5l_o21ai_1) "
check "Brent-Kung: nand3_1 on the path" "$(pathcells bk.sta | grep -o '[0-9]* (sg13cmos5l_nand3_1)')" "15 (sg13cmos5l_nand3_1)"
check "ripple, delay script: wide gates on the path" \
  "$(pathcells ripple_d.sta | grep -o '1 (sg13cmos5l_nor4_1)\|1 (sg13cmos5l_or4_1)' | tr '\n' ' ')" \
  "1 (sg13cmos5l_nor4_1) 1 (sg13cmos5l_or4_1) "
lg() { awk -v a="$1" 'BEGIN {printf "%.0f", a - 4751.91}'; }
check "adder logic: ripple, Brent-Kung, Kogge-Stone" "$(lg 6462.8928) $(lg 6448.3776) $(lg 6752.97)" "1711 1696 2001"
check "adder logic with the delay script" "$(lg 7580.3364) $(lg 7741.7046) $(lg 7516.908)" "2828 2990 2765"
check "Kogge-Stone over Brent-Kung, ripple slower than Brent-Kung" \
  "$(awk 'BEGIN {printf "%.0f %.0f", (2001.06 / 1696.47 - 1) * 100, (4.74 / 3.83 - 1) * 100}')" "18 24"
check "growth of the adder logic with the delay script" \
  "$(awk 'BEGIN {printf "%.0f %.0f %.0f", (2828.43/1710.98-1)*100, (2989.79/1696.47-1)*100, (2765.0/2001.06-1)*100}')" "65 76 38"
check "operators and levels of 8, 16, 32 bits: Brent-Kung" \
  "$(for n in 8 16 32; do awk -v n=$n 'BEGIN {l = log(n)/log(2); printf "%d/%d ", 2*n-2-l, 2*l-1}'; done)" "11/5 26/7 57/9 "
check "operators and levels of 8, 16, 32 bits: Kogge-Stone" \
  "$(for n in 8 16 32; do awk -v n=$n 'BEGIN {l = log(n)/log(2); printf "%d/%d ", n*l-n+1, l}'; done)" "17/3 49/4 129/5 "
check "overhead of a pipeline stage" "$(awk 'BEGIN {printf "%.3f", 0.207 + 0.127 + 0.1}')" "0.434"

echo "== Exercise: Pipeline the Adder"
iverilog -g2012 -o sim.vvp rtl/add_pipe.sv tb/tb_add_pipe.sv > /dev/null 2>&1
check "testbench of add_pipe" "$(vvp -n sim.vvp | grep sums)" "1000 sums, 0 errors"
sed 's/ + lo_q\[H\];/;/' rtl/add_pipe.sv > nocarry.sv
iverilog -g2012 -o nocarry.vvp nocarry.sv tb/tb_add_pipe.sv > /dev/null 2>&1
check "testbench without the carry" "$(vvp -n nocarry.vvp | grep sums)" "1000 sums, 489 errors"
sed 's/      sum_o  <= {hi, lo_q\[H-1:0\]};/      sum_o  <= {a_hi_q + b_hi_q + lo_q[H], lo_q[H-1:0]};/' rtl/add_pipe.sv > concat.sv
check "concatenation mutant differs" "$(diff rtl/add_pipe.sv concat.sv | grep -c '^>')" "1"
iverilog -g2012 -o concat.vvp concat.sv tb/tb_add_pipe.sv > /dev/null 2>&1
check "testbench with the sum inside the concatenation" "$(vvp -n concat.vvp | grep sums | grep -c ' 0 errors')" "0"
synth add_pipe "" "-constr $CONSTR" pipe.log
check "add_pipe: cells, area, flip-flops" "$(cells pipe.log) $(area pipe.log) $(flops add_pipe.nl.v)" "303 8852.457600 146"
check "add_pipe: period, with port paths" "$(period pipe.sta 1) $(period pipe.sta 2)" "2.34 427.29 2.78 359.30"
check "add_reg (Brent-Kung): period with port paths" "$(period bk.sta 2)" "3.83 261.31"
cat > pipe_rst.tcl <<'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog add_pipe.nl.v
link_design add_pipe
read_sdc ../syn/block.sdc
report_checks -path_group asynchronous -fields {fanout} -digits 3
EOF
sta -no_init -exit pipe_rst.tcl > pipe_rst.log 2>&1
check "add_pipe: fanout and delay of rst_ni, recovery time" \
  "$(awk '/rst_ni \(in\)/ {print $1, $2; exit}' pipe_rst.log) $(awk '/library recovery time/ {print $1; exit}' pipe_rst.log)" \
  "146 1.225 -0.458"
check "area increase of add_pipe" "$(awk 'BEGIN {printf "%.0f", (8852.4576 / 6448.3776 - 1) * 100}')" "37"
ep=$(awk '/^Endpoint:/ {print $2; exit}' pipe.sta)
check "add_pipe: worst endpoint, cells on the path, arrival" \
  "$(grep -A4 "sg13cmos5l_dfrbpq_1 $ep " add_pipe.nl.v | grep -o '\.Q([^)]*)') $(onpath pipe.sta) $(awk '/data arrival time/ {print $1; exit}' pipe.sta)" \
  ".Q(lo_q[16]) 17 2.127"
check "add_reg: arrival on the worst path" "$(awk '/data arrival time/ {print $1; exit}' bk.sta)" "3.629"
check "period predicted for two stages" "$(awk 'BEGIN {printf "%.2f", (3.83 - 0.434) / 2 + 0.434}')" "2.13"
cat > pipe_s2.tcl <<'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog add_pipe.nl.v
link_design add_pipe
read_sdc ../syn/block.sdc
set d {}
foreach c [get_cells -filter "ref_name == sg13cmos5l_dfrbpq_1"] {
  set q [get_pins -of_objects $c -filter "name == Q"]
  if {[string match "sum_o*" [get_full_name [get_nets -of_objects $q]]]} {
    lappend d [get_pins -of_objects $c -filter "name == D"]
  }
}
report_checks -path_delay max -to $d -format end -digits 3
EOF
sta -no_init -exit pipe_s2.tcl > pipe_s2.log 2>&1
check "add_pipe: worst arrival in the second stage" "$(awk '/\(MET\)|\(VIOLATED\)/ {print $4; exit}' pipe_s2.log)" "2.102"
check "logic delay of 16 and half of 32 bits" "$(awk 'BEGIN {printf "%.2f %.2f", 2.127 - 0.229, (3.629 - 0.229) / 2}')" "1.90 1.70"
synth add_reg "" "-constr $CONSTR" bk2.log
sed 's/add_pipe/add_reg/g' pipe_rst.tcl > reg_rst.tcl
sta -no_init -exit reg_rst.tcl > reg_rst.log 2>&1
check "add_reg: reset path with port delay" \
  "$(awk '/rst_ni \(in\)/ {d = $2} /library recovery time/ {r = -$1} END {printf "%.1f", 1.0 + d + r + 0.1}' reg_rst.log)" "2.3"

echo "== Resource sharing"
cd "$S/share"
for f in mul_sel mul_sel_shared; do
  check "lint of $f" "$(verilator --lint-only -Wall rtl/$f.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
done
yosys -p "read_verilog -sv rtl/mul_sel.sv; synth -top mul_sel -run :fine; stat" > coarse.log 2>&1
check "mul_sel after alumacc: \$macc_v2, \$mul" "$(ctype coarse.log '$macc_v2') $(ctype coarse.log '$mul')" "2 "
yosys -p "read_verilog -sv rtl/mul_sel.sv; synth -top mul_sel -noalumacc -run :fine; stat" > coarse_noalu.log 2>&1
check "mul_sel without alumacc: \$mul, \$mux" "$(ctype coarse_noalu.log '$mul') $(ctype coarse_noalu.log '$mux')" "1 2"
check "share finds nothing after alumacc" "$(grep -c 'Analyzing resource sharing' coarse.log)" "0"
synths() {  # synths <top> <synth options> <log>
  yosys -p "read_verilog -sv rtl/$1.sv; synth -top $1 $2; \
    dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; \
    opt_clean; stat -liberty $LIB; write_verilog -noattr $1.nl.v" > "$3" 2>&1
  TOP=$1 sta -no_init -exit ../syn/sta.tcl > "${3%.log}.sta" 2>&1
}
synths mul_sel "" two.log
check "two multipliers: area, period" "$(area two.log) $(period two.sta 1)" "35237.084400 5.25 190.31"
synths mul_sel "-noalumacc" noalu.log
check "shared by Yosys without alumacc: area, period" "$(area noalu.log) $(period noalu.sta 1)" "20251.463400 5.40 185.16"
synths mul_sel_shared "" hand.log
check "shared in the RTL: area, period" "$(area hand.log) $(period hand.sta 1)" "20282.383800 5.38 185.84"
check "area saved by sharing" "$(awk 'BEGIN {printf "%.0f", (1 - 20282.3838 / 35237.0844) * 100}')" "42"
check "flip-flops of mul_sel" "$(flops mul_sel_shared.nl.v)" "97"

echo "== Power of bs_reg"
cd "$W/content/sequential/code/bs_reg"
yosys -p "read_verilog -sv \
  ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
  rtl/bs_reg.sv; synth -top bs_reg; flatten; \
  dfflibmap -liberty $LIB; \
  abc -constr ../../../synthesis_lib/code/synth/abc.constr \
  -liberty $LIB; opt_clean; \
  stat -liberty $LIB; write_verilog -noattr bs_reg.nl.v" > bs.log 2>&1
check "bs_reg netlist: cells, area" "$(cells bs.log) $(area bs.log)" "915 15276.340800"
P=../../../synth_opt/code/syn/power.tcl
TOP=bs_reg sta -no_init -exit $P > p12.log 2>&1
TOP=bs_reg CORNER=typ_1p50V_25C sta -no_init -exit $P > p15.log 2>&1
check "1.2 V: sequential, combinational, total" \
  "$(pw p12.log Sequential 5) $(pw p12.log Combinational 5) $(pw p12.log Total 5)" "1.156e-03 5.629e-04 1.719e-03"
check "1.2 V: shares of sequential and combinational" \
  "$(pw p12.log Sequential 6) $(pw p12.log Combinational 6)" "67.2% 32.8%"
check "1.2 V: internal, switching, leakage" \
  "$(pw p12.log Total 2) $(pw p12.log Total 3) $(pw p12.log Total 4)" "1.455e-03 2.637e-04 1.915e-07"
check "1.5 V: sequential, combinational, total" \
  "$(pw p15.log Sequential 5) $(pw p15.log Combinational 5) $(pw p15.log Total 5)" "1.859e-03 9.195e-04 2.778e-03"
check "1.5 V: leakage" "$(pw p15.log Total 4)" "5.594e-07"
check "power ratio 1.5 V / 1.2 V, voltage ratio squared" \
  "$(awk 'BEGIN {printf "%.2f %.2f", 2.778 / 1.719, (1.5 / 1.2)^2}')" "1.62 1.56"
CORNER=typ_1p50V_25C sta -no_init -exit syn/sta.tcl > sta15.log 2>&1
check "1.5 V: minimum period" "$(period sta15.log 1)" "1.17 857.10"
check "power per flip-flop at 1.2 V" "$(awk 'BEGIN {printf "%.1f", 1.156e-3 / 71 * 1e6}')" "16.3"

echo "== Exercise: Gate the Clock"
cd "$S/clock_gate"
check "lint of cg_reg" "$(verilator --lint-only -Wall rtl/cg_reg.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
synthc() {  # synthc <clockgate command> <log>
  yosys -p "read_verilog -sv rtl/cg_reg.sv; synth -top cg_reg; $1 \
    dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; \
    opt_clean; stat -liberty $LIB; write_verilog -noattr cg_reg.nl.v" > "$2" 2>&1
}
simc() {  # simc <EVERY> <log>
  iverilog -g2012 -gno-specify -P tb_cg_reg.EVERY=$1 -o sim.vvp \
    $CELLS/sg13cmos5l_udp.v $CELLS/sg13cmos5l_stdcell.v cg_reg.nl.v \
    tb/tb_cg_reg.sv > "$2.comp" 2>&1
  vvp -n sim.vvp > "$2" 2>&1
  TOP=cg_reg VCD=cg_reg.vcd sta -no_init -exit ../syn/power.tcl > "$2.pwr" 2>&1
}
synthc "" nocg.log
check "without clock gating: cells, area" "$(cells nocg.log) $(area nocg.log)" "67 2222.640000"
check "without clock gating: dfrbpq_1, mux2_1, mux2_2, buf_8" \
  "$(ctype nocg.log sg13cmos5l_dfrbpq_1) $(ctype nocg.log sg13cmos5l_mux2_1) $(ctype nocg.log sg13cmos5l_mux2_2) $(ctype nocg.log sg13cmos5l_buf_8)" \
  "32 30 2 3"
simc 16 nocg16
check "Icarus messages of the cell models" "$(grep -c 'sorry: ifnone' nocg16.comp)" "68"
check "simulation without clock gating" "$(grep cycles nocg16)" "1600 cycles, en_i in 1 of 16, 0 errors"
check "annotated pins without clock gating" "$(awk '/^vcd/ {print $2}' nocg16.pwr) $(awk '/^unannotated/ {print $2}' nocg16.pwr)" "329 0"
check "no gating, 1 of 16: sequential, combinational, clock, total" \
  "$(pw nocg16.pwr Sequential 5) $(pw nocg16.pwr Combinational 5) $(pw nocg16.pwr Clock 5) $(pw nocg16.pwr Total 5)" \
  "4.744e-04 1.604e-05 0.000e+00 4.904e-04"
simc 1 nocg1
check "no gating, every cycle: sequential, combinational, clock, total" \
  "$(pw nocg1.pwr Sequential 5) $(pw nocg1.pwr Combinational 5) $(pw nocg1.pwr Clock 5) $(pw nocg1.pwr Total 5)" \
  "6.314e-04 4.138e-05 0.000e+00 6.728e-04"
sta -no_init -exit <(printf '%s\n' "read_liberty $LIB" "read_verilog cg_reg.nl.v" "link_design cg_reg" \
  "read_sdc ../syn/block.sdc" "report_checks -path_delay max -path_group clk -digits 3") > nocg_sta.log 2>&1
synthc "clockgate -pos sg13cmos5l_lgcp_1 GATE:CLK:GCLK -min_net_size 4;" cg.log
check "with clock gating: cells, area" "$(cells cg.log) $(area cg.log)" "33 1594.857600"
check "with clock gating: dfrbpq_1, lgcp_1" "$(ctype cg.log sg13cmos5l_dfrbpq_1) $(ctype cg.log sg13cmos5l_lgcp_1)" "32 1"
check "area saved by clock gating" "$(awk 'BEGIN {printf "%.0f", (1 - 1594.8576 / 2222.64) * 100}')" "28"
simc 16 cg16
check "simulation with clock gating" "$(grep cycles cg16)" "1600 cycles, en_i in 1 of 16, 0 errors"
check "gating, 1 of 16: sequential, combinational, clock, total" \
  "$(pw cg16.pwr Sequential 5) $(pw cg16.pwr Combinational 5) $(pw cg16.pwr Clock 5) $(pw cg16.pwr Total 5)" \
  "8.245e-05 0.000e+00 7.118e-06 8.957e-05"
check "gating, 1 of 16: clock internal, switching" "$(pw cg16.pwr Clock 2) $(pw cg16.pwr Clock 3)" "4.840e-06 2.278e-06"
simc 1 cg1
check "gating, every cycle: sequential, clock, total" \
  "$(pw cg1.pwr Sequential 5) $(pw cg1.pwr Clock 5) $(pw cg1.pwr Total 5)" "6.214e-04 4.385e-05 6.653e-04"
check "gating, every cycle: clock internal, switching" "$(pw cg1.pwr Clock 2) $(pw cg1.pwr Clock 3)" "7.418e-06 3.643e-05"
sed 's/      data = \$urandom;/      if (i % EVERY == 0) data = $urandom;/' tb/tb_cg_reg.sv > tb_hold.sv
check "testbench with held data" "$(grep -c 'if (i % EVERY == 0) data = \$urandom;' tb_hold.sv)" "1"
iverilog -g2012 -gno-specify -o hold.vvp $CELLS/sg13cmos5l_udp.v $CELLS/sg13cmos5l_stdcell.v   cg_reg.nl.v tb_hold.sv > /dev/null 2>&1
vvp -n hold.vvp > hold.log 2>&1
TOP=cg_reg VCD=cg_reg.vcd sta -no_init -exit ../syn/power.tcl > hold.pwr 2>&1
check "gating, held data, 1 of 16: sequential" "$(pw hold.pwr Sequential 5)" "3.957e-05"
check "power saved, 1 of 16" "$(awk 'BEGIN {printf "%.0f", (1 - 89.57 / 490.4) * 100}')" "82"
check "fair total without gating, every cycle" "$(awk 'BEGIN {printf "%.0f", 672.8 + 36.43}')" "709"
check "fair totals: saving every cycle, total 1 of 16"   "$(awk 'BEGIN {printf "%.0f %.0f", (1 - 665.3 / 709.23) * 100, 490.4 + 36.43}')" "6 527"
check "capacitance of CLK of lgcp_1, its clock power"   "$(awk '/cell \(sg13cmos5l_lgcp_1\)/ {f = 1} f && /pin \(CLK\)/ {g = 1} g && /capacitance :/ {gsub(/;/, ""); print $3; exit}' "$LIB") $(awk 'BEGIN {printf "%.1f", 0.5 * 2 * 4.93856e-15 * 1.44 * 250e6 * 1e6}')" "0.00493856 1.8"
check "fair gated totals: every cycle, 1 of 16, saving"   "$(awk 'BEGIN {printf "%.0f %.0f %.0f", 665.3 + 1.78, 89.57 + 1.78, (1 - 667.08 / 709.23) * 100}')" "667 91 6"
cat > cg_sta.tcl <<'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog cg_reg.nl.v
link_design cg_reg
read_sdc ../syn/block.sdc
check_setup -verbose
set icg [get_cells -filter "ref_name == sg13cmos5l_lgcp_1"]
report_checks -path_delay max -to [get_pins -of_objects $icg -filter "name == GATE"] -digits 3
report_checks -path_delay min -to [get_pins -of_objects $icg -filter "name == GATE"] -digits 3
EOF
sta -no_init -exit cg_sta.tcl > cg_sta.log 2>&1
check "check_setup with the clock gate" "$(grep -c -i 'unclocked\|unconstrained' cg_sta.log)" "0"
check "clock gating check" "$(grep -c 'clock gating-check end-point' cg_sta.log)" "2"
check "clock gating setup and hold time, setup slack" \
  "$(awk '/library setup time/ {print $1}' cg_sta.log) $(awk '/library hold time/ {print $1}' cg_sta.log) $(awk '/slack/ {print $1; exit}' cg_sta.log)" \
  "-0.070 -0.003 2.826"

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
