#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Modeling
# Guidelines for Synthesizable RTL" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_modeling.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_modeling}
LIB=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
CELLS=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog
SRAM=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/lef
fails=0

rm -rf "$W" && mkdir -p "$W" && cp -r "$REPO/content/modeling/code/." "$W/"
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

synth() {  # synth <top> <files...>: generic synthesis, map onto SG13CMOS5L, write <top>.nl.v
  local top=$1; shift
  yosys -q -l "$top.syn.log" -p "read_verilog -sv $*; synth -top $top; \
    dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB; \
    write_verilog -noattr $top.nl.v" > /dev/null
}

area() { grep "Chip area" "$1.syn.log" | tail -1 | awk '{print $NF}'; }
ncells() { sed -n '/Chip area/q;p' "$1.syn.log" | awk '/ cells$/ {n=$1} END {print n}'; }
ncell() { sed -n '/Chip area/q;p' "$1.syn.log" | awk -v c="$2" '$NF==c {n=$1} END {print n+0}'; }

echo "== Versions"
check "Verilator" "$(verilator --version | awk '{print $2}')" "5.052"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "cocotb" "$(python3 -c 'import cocotb; print(cocotb.__version__)')" "2.1.0"

echo "== Lint of every rtl/ file (no warning or error with -Wall)"
for f in */rtl/*.sv; do
  out=$(verilator --lint-only -Wall "$f" 2>&1 | grep -c -E "%Warning|%Error")
  check "lint $f" "$out" "0"
done

echo "== ctrl_fsm_noreset: the missing reset"
cd ctrl_fsm_noreset
iverilog -g2012 -o rtl.vvp rtl/ctrl_fsm_noreset.sv testbenches/verilog/ctrl_fsm_noreset_tb.sv
vvp -n rtl.vvp | grep cycle > icarus.txt
check "Icarus RTL cycle 0" "$(sed -n 1p icarus.txt)" "cycle 0: state_q=xx busy_o=0 done_o=0"
check "Icarus RTL cycle 1" "$(sed -n 2p icarus.txt)" "cycle 1: state_q=00 busy_o=0 done_o=0"
check "Icarus RTL cycle 5" "$(sed -n 6p icarus.txt)" "cycle 5: state_q=10 busy_o=0 done_o=1"
verilator --binary --timing --timescale 1ns/1ps -Mdir obj_v --top-module ctrl_fsm_noreset_tb \
  rtl/ctrl_fsm_noreset.sv testbenches/verilog/ctrl_fsm_noreset_tb.sv > verilator.log 2>&1
check "Verilator build warnings" "$(grep -c '%Warning' verilator.log)" "0"
check "Verilator cycle 0" "$(./obj_v/Vctrl_fsm_noreset_tb | grep 'cycle 0')" "cycle 0: state_q=00 busy_o=0 done_o=0"
# --x-initial unique is the default: the same build gives random start values with +verilator+rand+reset+2
for s in 1 2 3 4 5 6 7 8 9 10; do
  ./obj_v/Vctrl_fsm_noreset_tb +verilator+rand+reset+2 +verilator+seed+$s | grep cycle > rand$s.txt
done
check "Verilator start states of seeds 1 to 10" \
  "$(for s in 1 2 3 4 5 6 7 8 9 10; do sed -n 1p rand$s.txt | sed 's/.*state_q=\(..\).*/\1/'; done | tr '\n' ' ')" \
  "00 11 01 01 11 01 01 01 10 00 "
check "Verilator random seed 3, busy_o in cycles 0 to 5" \
  "$(sed -n 1,6p rand3.txt | sed 's/.*busy_o=\(.\).*/\1/' | tr -d '\n')" "111110"
check "Verilator random seed 9, done_o in cycles 0 to 7" \
  "$(sed 's/.*done_o=\(.\).*/\1/' rand9.txt | tr -d '\n')" "10000100"
check "Verilator random seeds identical from cycle 5 on" \
  "$(for s in 1 2 3 4 5 6 7 8 9 10; do sed -n 6,8p rand$s.txt | md5sum; done | sort -u | wc -l)" "1"
sed 's/typedef enum logic \[1:0\]/typedef enum bit [1:0]/' rtl/ctrl_fsm_noreset.sv > bitenum.sv
iverilog -g2012 -o bit.vvp bitenum.sv testbenches/verilog/ctrl_fsm_noreset_tb.sv > /dev/null 2>&1
check "Icarus with bit [1:0], cycle 0" "$(vvp -n bit.vvp | grep 'cycle 0')" "cycle 0: state_q=00 busy_o=0 done_o=0"
check "Icarus with bit [1:0], no x at all" "$(vvp -n bit.vvp | grep -c 'x')" "0"
synth ctrl_fsm_noreset rtl/ctrl_fsm_noreset.sv
check "netlist cells" "$(ncells ctrl_fsm_noreset)" "8"
check "dfrbpq_1 flip-flops" "$(ncell ctrl_fsm_noreset sg13cmos5l_dfrbpq_1)" "2"
check "RESET_B tied high" "$(grep -c "RESET_B(1'h1)" ctrl_fsm_noreset.nl.v)" "2"
check "Yosys keeps the binary encoding" "$(grep -A1 'Not marking ctrl_fsm_noreset.state_q' ctrl_fsm_noreset.syn.log | tail -1 | xargs)" \
  "Circuit seems to be self-resetting."
check "Yosys ABC warning" "$(grep -c 'ABC: Warning: The network is combinational' ctrl_fsm_noreset.syn.log)" "2"
iverilog -g2012 -gno-specify -DGL -o gl.vvp "$CELLS/sg13cmos5l_udp.v" "$CELLS/sg13cmos5l_stdcell.v" \
  ctrl_fsm_noreset.nl.v testbenches/verilog/ctrl_fsm_noreset_tb.sv > gl_compile.log 2>&1
check "Icarus 'sorry: ifnone' messages for the cell models" "$(grep -c 'sorry: ifnone' gl_compile.log)" "68"
vvp -n gl.vvp | grep cycle > gl.txt
check "GL busy_o in cycles 0 to 7" "$(sed 's/.*busy_o=\(.\).*/\1/' gl.txt | tr -d '\n')" "xxx11000"
check "GL done_o in cycles 0 to 7" "$(sed 's/.*done_o=\(.\).*/\1/' gl.txt | tr -d '\n')" "x0000100"
cd "$W"

echo "== xprop: x in if, case, ?:, and AND"
cd xprop
iverilog -g2012 -o x.vvp testbenches/verilog/xprop_tb.sv && vvp -n x.vvp | grep sel > icarus.txt
check "Icarus a=0 b=1" "$(sed -n 1p icarus.txt)" "sel=x a=0 b=1: if=0 case=x ?:=x and=0"
check "Icarus a=1 b=1" "$(sed -n 2p icarus.txt)" "sel=x a=1 b=1: if=1 case=x ?:=1 and=x"
verilator --binary --timing -Mdir obj testbenches/verilog/xprop_tb.sv > verilator.log 2>&1
check "Verilator build warnings" "$(grep -c '%Warning' verilator.log)" "0"
./obj/Vxprop_tb | grep sel > verilator.txt
check "Verilator a=0 b=1" "$(sed -n 1p verilator.txt)" "sel=x a=0 b=1: if=0 case=0 ?:=0 and=0"
check "Verilator a=1 b=1" "$(sed -n 2p verilator.txt)" "sel=x a=1 b=1: if=1 case=1 ?:=1 and=0"
cat > mux_gl_tb.sv <<'EOF'
module mux_gl_tb;
  logic s = 1'bx, a0 = 1'b0, a1 = 1'b1; wire x;
  sg13cmos5l_mux2_1 u_mux (.A0(a0), .A1(a1), .S(s), .X(x));
  initial begin
    #1 $display("A0=0 A1=1: %b", x);
    a0 = 1'b1; #1 $display("A0=1 A1=1: %b", x);
  end
endmodule
EOF
iverilog -g2012 -gno-specify -o m.vvp "$CELLS/sg13cmos5l_udp.v" "$CELLS/sg13cmos5l_stdcell.v" mux_gl_tb.sv > /dev/null 2>&1
check "mux2_1 cell, S=x" "$(vvp -n m.vvp | grep A0 | tr '\n' ' ')" "A0=0 A1=1: x A0=1 A1=1: 1 "
cd "$W"

echo "== led_blink: FPGA habits"
cd led_blink
check "lint of the FPGA version (PROCASSINIT warnings)" \
  "$(verilator --lint-only -Wall exercise/led_blink_fpga.sv 2>&1 | grep -c '%Warning-PROCASSINIT')" "3"
for top in led_blink led_blink_fpga; do
  (cd testbenches/cocotb && TOPLEVEL=$top python3 led_blink_tb.py > $top.log 2>&1)
  check "cocotb $top (Icarus)" "$(grep -o 'TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]*' testbenches/cocotb/$top.log)" "TESTS=1 PASS=1 FAIL=0"
done
(cd testbenches/cocotb && rm -rf sim_build && SIM=verilator python3 led_blink_tb.py > verilator.log 2>&1)
check "cocotb led_blink (Verilator)" "$(grep -o 'TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]*' testbenches/cocotb/verilator.log)" "TESTS=1 PASS=1 FAIL=0"
yosys -q -l fpga.syn.log -p "read_verilog -sv exercise/led_blink_fpga.sv; chparam -set DIV 4 led_blink_fpga; \
  synth -top led_blink_fpga; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB; \
  write_verilog -noattr led_blink_fpga.nl.v" > /dev/null
check "Yosys warnings about the dropped initial values" "$(grep -c -i 'warning.*init' fpga.syn.log)" "0"
check "init attributes left in the netlist" "$(grep -c 'init' led_blink_fpga.nl.v)" "0"
cat > gl_tb.sv <<'EOF'
`timescale 1ns / 1ps
module gl_tb;
  logic clk = 1'b0; wire led;
  led_blink_fpga dut (.clk_i(clk), .led_o(led));
  always #10 clk = ~clk;
  initial begin
    repeat (40) @(negedge clk);
    $display("led_o after 40 cycles: %b", led);
    $finish;
  end
endmodule
EOF
iverilog -g2012 -gno-specify -o gl.vvp "$CELLS/sg13cmos5l_udp.v" "$CELLS/sg13cmos5l_stdcell.v" \
  led_blink_fpga.nl.v gl_tb.sv > /dev/null 2>&1
check "GL of the FPGA version" "$(vvp -n gl.vvp | grep led_o)" "led_o after 40 cycles: x"
gstat() {  # gstat <top> <file> <cell type>: count of a generic cell type after synth
  yosys -q -l "g_$1.log" -p "read_verilog -sv $2; synth -top $1; stat" > /dev/null
  sed -n '/Printing statistics/,$p' "g_$1.log" | awk -v c="$3" '$2==c {n=$1} END {print n+0}'
}
check "FPGA version: counter flip-flops with sync reset" "$(gstat led_blink_fpga exercise/led_blink_fpga.sv '$_SDFF_PP0_')" "24"
check "FPGA version: slow_clk_q flip-flop with enable" "$(gstat led_blink_fpga exercise/led_blink_fpga.sv '$_DFFE_PP_')" "1"
check "FPGA version: LED flip-flop" "$(gstat led_blink_fpga exercise/led_blink_fpga.sv '$_DFF_P_')" "1"
check "FPGA version: cells" "$(gstat led_blink_fpga exercise/led_blink_fpga.sv cells)" "108"
yosys -q -p "read_verilog -sv exercise/led_blink_fpga.sv; synth -top led_blink_fpga; write_verilog -noattr g_fpga.v" > /dev/null
check "FPGA version: LED clocked by slow_clk_q" "$(grep -c 'always @(posedge slow_clk_q)' g_fpga.v)" "1"
check "ASIC version: counter flip-flops" "$(gstat led_blink rtl/led_blink.sv '$_DFF_PN0_')" "24"
check "ASIC version: phase and LED flip-flops with enable" "$(gstat led_blink rtl/led_blink.sv '$_DFFE_PN0P_')" "2"
check "ASIC version: cells" "$(gstat led_blink rtl/led_blink.sv cells)" "117"
sed 's/always_ff @(posedge clk_i or negedge rst_ni) begin/always_ff @(posedge clk_i) begin/' rtl/led_blink.sv > led_blink_sync.sv
check "ASIC version without rst_ni: cells" "$(gstat led_blink led_blink_sync.sv cells)" "110"
cd "$W"

echo "== excl_cnt: architecture case study (typical corner, 10 fF load, ideal clock)"
cd excl_cnt
declare -A exp_cells=([excl_cnt_bin]=22 [excl_cnt_ring]=28 [excl_cnt_ring_for]=28 [excl_cnt_johnson]=24)
declare -A exp_ff=([excl_cnt_bin]=3 [excl_cnt_ring]=8 [excl_cnt_ring_for]=8 [excl_cnt_johnson]=4)
declare -A exp_area=([excl_cnt_bin]=308.448000 [excl_cnt_ring]=553.165200 [excl_cnt_ring_for]=553.165200 [excl_cnt_johnson]=368.323200)
declare -A exp_out=([excl_cnt_bin]=0.49 [excl_cnt_ring]=0.23 [excl_cnt_ring_for]=0.23 [excl_cnt_johnson]=0.35)
declare -A exp_reg=([excl_cnt_bin]=0.52 [excl_cnt_ring]=0.31 [excl_cnt_ring_for]=0.31 [excl_cnt_johnson]=0.35)
for top in excl_cnt_bin excl_cnt_ring excl_cnt_ring_for excl_cnt_johnson; do
  (cd testbenches/cocotb && rm -rf sim_build && TOPLEVEL=$top python3 excl_cnt_tb.py > $top.log 2>&1)
  check "cocotb $top" "$(grep -o 'TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]*' testbenches/cocotb/$top.log)" "TESTS=3 PASS=3 FAIL=0"
  synth $top rtl/$top.sv
  check "$top cells" "$(ncells $top)" "${exp_cells[$top]}"
  check "$top flip-flops" "$(ncell $top sg13cmos5l_dfrbpq_1)" "${exp_ff[$top]}"
  check "$top area" "$(area $top)" "${exp_area[$top]}"
  TOP=$top sta -no_init -exit syn/sta.tcl > $top.sta.log 2>&1
  check "$top clock to output (ns)" "$(grep '(output)' $top.sta.log | awk '{print $(NF-2)}')" "${exp_out[$top]}"
  check "$top register to register (ns)" "$(grep 'dfrbpq_1)' $top.sta.log | awk '{print $(NF-2)}')" "${exp_reg[$top]}"
done
check "dfrbpq_1 cell area (um2)" "$(awk '/cell \(sg13cmos5l_dfrbpq_1\)/ {f=1} f && /area/ {print $3; exit}' "$LIB" | tr -d ';')" "48.9888"
check "nor3_1 cell area (um2)" "$(awk '/cell \(sg13cmos5l_nor3_1\)/ {f=1} f && /area/ {print $3; exit}' "$LIB" | tr -d ';')" "9.072"
check "flip-flop types of the library" "$(awk '/^[[:space:]]*cell \(/ {c=$2} /^[[:space:]]*ff \(/ {print c}' "$LIB" | tr -d '()"' | sed 's/_[12]$//' | sort -u | tr '\n' ' ')" \
  "sg13cmos5l_dfrbp sg13cmos5l_dfrbpq sg13cmos5l_sdfbbp sg13cmos5l_sdfrbp sg13cmos5l_sdfrbpq "
# The Johnson counter: its unused states form a second cycle of eight, with several outputs high
check "Johnson counter: second cycle" "$(python3 -c '
s, seq = 0b0010, []
for _ in range(8):
    seq.append(format(s, "04b")); s = ((s << 1) & 0b1110) | (1 - (s >> 3))
print(" ".join(seq), format(s, "04b"))')" "0010 0101 1011 0110 1101 1010 0100 1001 0010"
cd "$W"

echo "== ram_ff: flip-flops against an SRAM macro"
cd ram_ff
yosys -q -l ram.syn.log -p "read_verilog -sv rtl/ram_ff.sv; synth -top ram_ff; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB" > /dev/null
check "256x8 flip-flop memory area (um2)" "$(area ram)" "165742.945200"
check "256x8 flip-flops" "$(ncell ram sg13cmos5l_dfrbpq_1)" "2056"
check "256x8 mux2_1 cells" "$(ncell ram sg13cmos5l_mux2_1)" "2074"
check "256x8 mux4_1 cells" "$(ncell ram sg13cmos5l_mux4_1)" "368"
check "SRAM 256x8 macro size (um)" "$(grep -m1 -E '^\s*SIZE' $SRAM/RM_IHPSG13_1P_256x8_c3_bm_bist.lef | awk '{print $2, $4}')" "236.8 74.1"
yosys -q -l ram32.syn.log -p "read_verilog -sv rtl/ram_ff.sv; chparam -set DEPTH 32 ram_ff; synth -top ram_ff; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB" > /dev/null
check "32x8 flip-flop memory area (um2)" "$(area ram32)" "20943.694800"
check "smallest SRAM macro, 64x16 (um)" "$(grep -m1 -E '^\s*SIZE' $SRAM/RM_IHPSG13_1P_64x16_c2.lef | awk '{print $2, $4}')" "236.8 64.36"
check "smallest SRAM macro by area" "$(for f in $SRAM/*.lef; do grep -m1 -E '^\s*SIZE' "$f" | awk -v n="$(basename "$f" .lef)" '{print $2*$4, n}'; done | sort -g | head -1 | awk '{print $2}')" \
  "RM_IHPSG13_1P_64x16_c2"
cd "$W"

echo "== pitfalls/bus_tri: internal tri-state bus"
cd pitfalls
check "Verilator lint warnings" "$(verilator --lint-only -Wall bus_tri.sv 2>&1 | grep -c '%Warning')" "0"
yosys -q -l tri.log -p "read_verilog -sv bus_tri.sv; synth -top bus_tri" > /dev/null 2>&1
check "Yosys synth exit status" "$?" "1"
check "Yosys error" "$(grep -c 'already driven' tri.log)" "1"
yosys -q -l tri2.log -p "read_verilog -sv bus_tri.sv; proc; tribuf; synth -top bus_tri; stat" > /dev/null 2>&1
check "Yosys with tribuf: tri-state buffers" "$(sed -n '/Printing statistics/,$p' tri2.log | awk '$2=="$_TBUF_" {print $1}' | tail -1)" "16"
# As LibreLane does with the SYNTH_TRISTATE_MAP of the PDK
TMAP=$PDK_ROOT/ihp-sg13cmos5l/libs.tech/librelane/sg13cmos5l_stdcell/tribuff_map.v
yosys -q -l tri3.log -p "read_verilog -sv bus_tri.sv; proc; tribuf; synth -top bus_tri; techmap -map $TMAP; stat" > /dev/null 2>&1
check "LibreLane-style mapping onto ebufn_2" "$(sed -n '/Printing statistics/,$p' tri3.log | awk '$2=="sg13cmos5l_ebufn_2" {print $1}' | tail -1)" "16"
cd "$W"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all results match the chapter"
else
  echo "FAIL: $fails result(s) differ from the chapter"
  exit 1
fi
