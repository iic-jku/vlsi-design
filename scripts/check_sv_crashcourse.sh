#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every tool result that the chapter "Hardware
# Description with SystemVerilog" quotes, inside the IIC-OSIC-TOOLS
# container (image 2026.10). Run from the repository root:
#   bash scripts/check_sv_crashcourse.sh
# Works on a copy in /tmp, so the repository stays clean. The counter of
# the AMS chip template is checked only if a clone of the template lies
# next to the repository (or in TEMPLATE_DIR). Exits with 1 if any result
# differs from the value in the chapter.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_sv}
TPL=${TEMPLATE_DIR:-$REPO/../ihp-sg13cmos5l-ams-chip-template}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
fails=0

rm -rf "$W" && mkdir -p "$W" && cp -r "$REPO/content/sv_crashcourse/code/." "$W/"
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

acc() { "$@" > /dev/null 2>&1 && echo accepted || echo rejected; }  # acc <command>

ys() { yosys -l "$1" -p "$2" > /dev/null 2>&1; }  # ys <log> <commands>: exit status of Yosys

gcell() {  # gcell <log> <cell type>: count of a generic cell type in the last stat
  sed -n '/Printing statistics/,$p' "$1" | awk -v c="$2" '$2 == c {n = $1} END {print n + 0}'
}

ncnt() {  # ncnt <log> <regex>: count of all generic cells whose type matches
  sed -n '/Printing statistics/,$p' "$1" | awk -v r="$2" '$2 ~ r {n[$2] = $1} END {s = 0; for (k in n) s += n[k]; print s}'
}

warns() {  # warns <arguments>: names of the Verilator -Wall warnings, sorted
  verilator --lint-only -Wall "$@" 2>&1 | grep -oE '^%Warning-[A-Z]+' | cut -d- -f2 | sort | paste -sd' '
}

msg() { grep -m1 -oF "$2" "$1"; }  # msg <log> <text>: the text if the log contains it

tests() { grep -oE 'TESTS=[0-9]+ PASS=[0-9]+ FAIL=[0-9]+ SKIP=[0-9]+' "$1" | tail -1; }

echo "== Versions"
check "Verilator" "$(verilator --version | awk '{print $2}')" "5.052"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"
check "cocotb" "$(python3 -c 'import cocotb; print(cocotb.__version__)')" "2.1.0"
check "GHDL" "$(ghdl --version | head -1 | awk '{print $2}')" "7.0.0-dev"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"

echo "== Every rtl/ file lints without warnings and synthesizes"
for f in */rtl/*.sv; do
  top=$(basename "$f" .sv)
  n=$(verilator --lint-only -Wall "$f" 2>&1 | grep -c -E '%Warning|%Error')
  ys "$top.syn.log" "read_verilog -sv $f; synth -top $top"
  check "$f: lint messages, Yosys exit status" "$n $?" "0 0"
done

echo "== Every VHDL file analyzes and elaborates with GHDL"
mkdir -p ghdl_ae && cd ghdl_ae
for f in ../*/vhdl/*.vhd; do
  out=$(ghdl -a "$f" 2>&1 && ghdl -e "$(basename "$f" _ea.vhd)" 2>&1 && ghdl -a --std=08 "$f" 2>&1)
  check "${f#../} (93c and 08): exit status, messages" "$? $(printf '%s' "$out" | grep -c .)" "0 0"
done
cd "$W"

echo "== popcount: computing in space"
ys popcount.log "read_verilog -sv popcount/rtl/popcount.sv; synth -top popcount; stat"
check "cells" "$(gcell popcount.log cells)" "26"
check "flip-flops and latches" "$(ncnt popcount.log 'DFF|DLATCH')" "0"
check "XOR, NAND, and ANDNOT among them" \
  "$(for c in '$_XOR_' '$_NAND_' '$_ANDNOT_'; do [ "$(gcell popcount.log "$c")" -gt 0 ] && printf '%s ' "$c"; done)" \
  '$_XOR_ $_NAND_ $_ANDNOT_ '

echo "== Files in a list: \`default_nettype and \`define"
mkdir -p snip && cd snip
cat > a.sv << 'EOF'
`default_nettype none
module a (input logic x_i, output logic y_o);
  assign y_o = x_i;
endmodule
EOF
cat > b.sv << 'EOF'
module b (input logic x_i, output logic y_o);
  assign n = x_i;
  assign y_o = n;
endmodule
EOF
check "Icarus keeps none for the next file" "$(iverilog -g2012 -o ab.vvp a.sv b.sv 2>&1 | grep -o 'Net n is not defined' | head -1)" "Net n is not defined"
check "Verilator resets it (only the IMPLICIT warning)" "$(warns --top-module b a.sv b.sv)" "IMPLICIT"
ys ab.log "read_verilog -sv a.sv b.sv"
check "Yosys resets it (exit status, warning)" "$? $(msg ab.log 'is implicitly declared')" "0 is implicitly declared"
cat > c.sv << 'EOF'
`define ONE 1'b1
module c (output logic y_o);
  assign y_o = 1'b0;
endmodule
EOF
cat > d.sv << 'EOF'
module d (output logic y_o);
  assign y_o = `ONE;
endmodule
EOF
check "a \`define of the first file in the second: Icarus, Verilator, Yosys" \
  "$(acc iverilog -g2012 -o cd.vvp c.sv d.sv) $(acc verilator --lint-only -Wall --top-module d c.sv d.sv) $(acc yosys -p 'read_verilog -sv c.sv d.sv')" \
  "accepted accepted accepted"

echo "== A logic that is never assigned or reset"
cat > x_tb.sv << 'EOF'
module x_tb;
  logic clk = 1'b0, q;
  always_ff @(posedge clk) q <= q;
  always #5 clk = ~clk;
  initial begin
    #12 $display("q=%b", q);
    $finish;
  end
endmodule
EOF
iverilog -g2012 -o x.vvp x_tb.sv
verilator --binary --timing -Mdir obj_x --top-module x_tb x_tb.sv > x_v.log 2>&1
check "Icarus, Verilator, Verilator with random reset (seeds 1 to 5)" \
  "$(vvp -n x.vvp | grep -o 'q=.') $(./obj_x/Vx_tb | grep -o 'q=.') $(for s in 1 2 3 4 5; do ./obj_x/Vx_tb +verilator+rand+reset+2 +verilator+seed+$s | grep -o 'q=.'; done | sort -u | paste -sd' ')" \
  "q=x q=0 q=0 q=1"

echo "== Two drivers of one variable"
cat > md1.sv << 'EOF'
module md1 (input logic a_i, b_i, output logic y_o);
  always_comb y_o = a_i;
  always_comb y_o = b_i;
endmodule
EOF
cat > md2.sv << 'EOF'
module md2 (input logic clk_i, a_i, b_i, output logic y_o);
  always_ff @(posedge clk_i) y_o <= a_i;
  always_ff @(posedge clk_i) y_o <= b_i;
endmodule
EOF
cat > md3.sv << 'EOF'
module md3 (input logic a_i, b_i, output logic y_o);
  assign y_o = a_i;
  always_comb y_o = b_i;
endmodule
EOF
check "Verilator: two always_comb, two always_ff" "$(warns md1.sv | tr ' ' '\n' | sort -u) / $(warns md2.sv)" "MULTIDRIVEN / MULTIDRIVEN"
check "Icarus messages: two always_comb, two always_ff" \
  "$(iverilog -g2012 -o x.vvp md1.sv 2>&1 | grep -c .) $(iverilog -g2012 -o x.vvp md2.sv 2>&1 | grep -c .)" "0 0"
check "Icarus: assign and always_comb" "$(acc iverilog -g2012 -o x.vvp md3.sv)" "rejected"

echo "== Expression widths"
cat > width.sv << 'EOF'
module width (
  input  logic [7:0] a, b,
  input  logic [3:0] count,
  output logic [7:0] sum8,
  output logic [8:0] sum9,
  output logic [3:0] nibble,
  output logic       hit
);
  assign sum8   = a + b;
  assign sum9   = a + b;
  assign nibble = a;
  assign hit    = (count == 20);
endmodule
EOF
check "Verilator: warning:line (sum8 on line 9 without warning)" \
  "$(verilator --lint-only -Wall width.sv 2>&1 | grep -oE '^%Warning-[A-Z]+: width.sv:[0-9]+' | sed 's/%Warning-//; s/: width.sv//' | paste -sd' ')" \
  "WIDTHTRUNC:11 WIDTHEXPAND:12"
cat > width_tb.vhd << 'EOF'
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity width_tb is
end entity width_tb;

architecture sim of width_tb is
  signal a, b   : unsigned(7 downto 0) := x"F0";
  signal sum8   : unsigned(7 downto 0);
  signal sum9   : unsigned(8 downto 0);
  signal nibble : unsigned(3 downto 0);
begin
  nibble <= a;
end architecture sim;
EOF
sed 's/width_tb/width9_tb/g; s/nibble <= a;/sum9 <= a + b;/' width_tb.vhd > width9_tb.vhd
sed 's/width_tb/width8_tb/g; s/nibble <= a;/sum8 <= a + b;/' width_tb.vhd > width8_tb.vhd
check "GHDL analysis: nibble <= a" "$(ghdl -a width_tb.vhd 2>&1 | grep -o "14:13:warning: value constraints don't match target ones")" \
  "14:13:warning: value constraints don't match target ones"
check "GHDL simulation: nibble <= a" "$(ghdl -e width_tb > /dev/null 2>&1; ghdl -r width_tb 2>&1 | grep -o 'bound check failure at width_tb.vhd:14')" \
  "bound check failure at width_tb.vhd:14"
check "GHDL simulation: sum9 <= a + b" "$(ghdl -a width9_tb.vhd && ghdl -e width9_tb && ghdl -r width9_tb 2>&1 | grep -o 'bound check failure')" \
  "bound check failure"
check "GHDL simulation: sum8 <= a + b (the carry is lost silently)" "$(acc sh -c 'ghdl -a width8_tb.vhd && ghdl -e width8_tb && ghdl -r width8_tb')" "accepted"

echo "== Blocking assignments in always_ff: the swap"
cat > swap1.sv << 'EOF'
module swap1 (input logic clk_i, load_i, a_i, b_i, output logic a_q, b_q);
  always_ff @(posedge clk_i) begin
    if (load_i) begin
      a_q = a_i;
      b_q = b_i;
    end else begin
      a_q = b_q;
      b_q = a_q;
    end
  end
endmodule
EOF
cat > swap2.sv << 'EOF'
module swap2 (input logic clk_i, load_i, a_i, b_i, output logic a_q, b_q);
  always_ff @(posedge clk_i) begin
    if (load_i) a_q = a_i;
    else        a_q = b_q;
  end
  always_ff @(posedge clk_i) begin
    if (load_i) b_q = b_i;
    else        b_q = a_q;
  end
endmodule
EOF
cat > swap_tb.sv << 'EOF'
module swap_tb;
  logic clk = 1'b0, load = 1'b1, a1, b1, a2, b2;
  swap1 u1 (.clk_i(clk), .load_i(load), .a_i(1'b1), .b_i(1'b0), .a_q(a1), .b_q(b1));
  swap2 u2 (.clk_i(clk), .load_i(load), .a_i(1'b1), .b_i(1'b0), .a_q(a2), .b_q(b2));
  always #5 clk = ~clk;
  initial begin
    @(negedge clk) load = 1'b0;
    @(negedge clk) $display("one block: a=%b b=%b, two blocks: a=%b b=%b", a1, b1, a2, b2);
    $finish;
  end
endmodule
EOF
# Loaded with a=1 b=0, a real swap gives a=0 b=1
iverilog -g2012 -o swap.vvp swap1.sv swap2.sv swap_tb.sv
check "Icarus" "$(vvp -n swap.vvp | grep block)" "one block: a=0 b=0, two blocks: a=0 b=0"
verilator --binary --timing -Mdir obj_swap --top-module swap_tb swap1.sv swap2.sv swap_tb.sv > swap_v.log 2>&1
check "Verilator" "$(./obj_swap/Vswap_tb | grep block)" "one block: a=0 b=0, two blocks: a=0 b=0"
yosys -q -p "read_verilog -sv swap1.sv swap2.sv; synth; write_verilog -noattr swap_nl.v" > /dev/null 2>&1
iverilog -g2012 -o swap_nl.vvp swap_nl.v swap_tb.sv
check "Yosys netlist" "$(vvp -n swap_nl.vvp | grep block)" "one block: a=0 b=0, two blocks: a=0 b=1"
cd "$W"

echo "== Two-process style: the toggle flip-flop"
mkdir -p toggle && cd toggle
cat > toggle.sv << 'EOF'
module toggle (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic toggle_i,
  output logic state_o
);

  logic state_d, state_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= 1'b0;
    end else begin
      state_q <= state_d;
    end
  end

  always_comb begin
    state_d = state_q;
    if (toggle_i) begin
      state_d = ~state_q;
    end
  end

  assign state_o = state_q;

endmodule
EOF
ys toggle.log "read_verilog -sv toggle.sv; synth -top toggle; stat; write_verilog -noattr -noexpr toggle_nl.v"
check "cells, \$_NOT_, \$_DFFE_PN0P_" "$(gcell toggle.log cells) $(gcell toggle.log '$_NOT_') $(gcell toggle.log '$_DFFE_PN0P_')" "2 1 1"
check "enable of the flip-flop" "$(grep -o '\.E(toggle_i)' toggle_nl.v)" ".E(toggle_i)"
mkdir -p lvl edge nodef
sed 's/negedge rst_ni)/negedge rst_ni or toggle_i)/' toggle.sv > lvl/toggle.sv
sed 's/negedge rst_ni)/negedge rst_ni or posedge toggle_i)/' toggle.sv > edge/toggle.sv
for v in lvl edge; do
  ys $v.log "read_verilog -sv $v/toggle.sv; synth -top toggle"
  check "toggle_i in the event list ($v): Yosys exit status, Verilator warnings" "$? $(warns $v/toggle.sv)" "1 "
done
sed '/    state_d = state_q;/d' toggle.sv > nodef/toggle.sv
check "without the default assignment: Verilator" "$(warns nodef/toggle.sv)" "LATCH"
ys nodef.log "read_verilog -sv nodef/toggle.sv; synth -top toggle"
check "without the default assignment: Yosys" "$? $(msg nodef.log "ERROR: Latch inferred for signal \`\\toggle.\\state_d' from always_comb process")" \
  "1 ERROR: Latch inferred for signal \`\\toggle.\\state_d' from always_comb process"
cd "$W"

echo "== tick_gen: the same hardware in SystemVerilog and VHDL (DIV = 10)"
ys tick_sv.log "read_verilog -sv tick_gen/rtl/tick_gen.sv; synth -top tick_gen; stat"
ys tick_vhdl.log "plugin -i ghdl; ghdl tick_gen/vhdl/tick_gen_ea.vhd -e tick_gen; synth -top tick_gen; stat"
check "SystemVerilog: cells, \$_DFFE_PN0P_, \$_DFF_PN0_" \
  "$(gcell tick_sv.log cells) $(gcell tick_sv.log '$_DFFE_PN0P_') $(gcell tick_sv.log '$_DFF_PN0_')" "17 4 1"
check "VHDL (active-high reset): \$_DFFE_PP0P_, \$_DFF_PP0_" "$(gcell tick_vhdl.log '$_DFFE_PP0P_') $(gcell tick_vhdl.log '$_DFF_PP0_')" "4 1"
comb() { sed -n '/Printing statistics/,$p' "$1" | awk '$2 ~ /^\$_/ && $2 !~ /DFF/ {n[$2] = $1} END {for (k in n) print n[k], k}' | sort -k2 | paste -sd' '; }
check "the same logic cells besides the flip-flops" "$(comb tick_vhdl.log)" "$(comb tick_sv.log)"

echo "== unique case in Icarus Verilog"
cd snip
cat > uq_tb.sv << 'EOF'
module uq_tb;
  logic [1:0] sel;
  logic y, z;
  always_comb begin
    y = 1'b0;
    unique case (sel)
      2'b00: y = 1'b1;
      2'b01: y = 1'b1;
    endcase
  end
  always_comb begin
    z = 1'b0;
    unique case (sel)
      2'b00, 2'b01: z = 1'b1;
      2'b01:        z = 1'b0;
      default:      z = 1'b0;
    endcase
  end
  initial begin
    sel = 2'b01;
    #1 sel = 2'b11;
    #1 $finish;
  end
endmodule
EOF
check "sorry messages" "$(iverilog -g2012 -o uq.vvp uq_tb.sv 2>&1 | grep -c 'sorry: Case unique/unique0 qualities are ignored')" "2"
# sel = 01 matches two items of the second case, sel = 11 no item of the first
check "run-time warnings" "$(vvp -n uq.vvp | grep -o 'uq_tb.sv:[0-9]*: value is unhandled' | paste -sd' ')" "uq_tb.sv:6: value is unhandled"
cd "$W"

echo "== Latches and the library"
check "latch cell sg13cmos5l_dlhq_1" "$(grep -c 'cell (sg13cmos5l_dlhq_1)' "$LIB")" "1"
for c in dfrbp_1 dfrbpq_1; do
  check "$c: clear" "$(sed -n "/cell (sg13cmos5l_$c)/,/^  cell (/p" "$LIB" | grep -m1 -o 'clear : "[^"]*"')" 'clear : "!RESET_B"'
done
check "cell models with primitives and specify blocks" \
  "$(grep -c '^primitive' "$D/verilog/sg13cmos5l_udp.v" | awk '{print ($1 > 0)}') $(grep -c 'specify' "$D/verilog/sg13cmos5l_stdcell.v" | awk '{print ($1 > 0)}')" "1 1"

echo "== lint_me: the exercise file and the corrected version"
lm=$(verilator --lint-only -Wall lint_me/exercise/lint_me.sv 2>&1)
check "Verilator warnings" "$(echo "$lm" | grep -oE '^%Warning-[A-Z]+' | cut -d- -f2 | sort | paste -sd' ')" \
  "BLKSEQ BLKSEQ CASEINCOMPLETE IMPLICIT LATCH UNDRIVEN UNUSEDSIGNAL"
check "signals of IMPLICIT, UNDRIVEN, UNUSEDSIGNAL, LATCH" \
  "$(for w in IMPLICIT UNDRIVEN UNUSEDSIGNAL LATCH; do echo "$lm" | grep "^%Warning-$w" | grep -oE "'[a-z_.]+'" | tail -1; done | paste -sd' ')" \
  "'zero' 'zero_o' 'zero' 'lint_me.alu'"
check "uncovered case value, exit" "$(echo "$lm" | grep -o 'example pattern 0x[0-9]'), $(echo "$lm" | grep -o 'Exiting due to [0-9]* warning(s)')" \
  "example pattern 0x3, Exiting due to 7 warning(s)"
ys lm.log "read_verilog -sv lint_me/exercise/lint_me.sv; synth -top lint_me; stat"
check "Yosys: exit status, warning" "$? $(msg lm.log "Identifier \`\\zero' is implicitly declared")" "1 Identifier \`\\zero' is implicitly declared"
check "Yosys: error" "$(msg lm.log "ERROR: Latch inferred for signal \`\\lint_me.\\alu' from always_comb process")" \
  "ERROR: Latch inferred for signal \`\\lint_me.\\alu' from always_comb process"
ys lm_fix.log "read_verilog -sv lint_me/rtl/lint_me.sv; synth -top lint_me; stat"
check "corrected version: cells, \$_DFF_PN0_" "$(gcell lm_fix.log cells) $(gcell lm_fix.log '$_DFF_PN0_')" "114 8"

echo "== ctrl_fsm and ctrl_fsm_mealy"
ys moore.log "read_verilog -sv ctrl_fsm/rtl/ctrl_fsm.sv; synth -top ctrl_fsm; stat"
check "Moore: one-hot" "$(grep -c 'mapping auto encoding to .one-hot. for this FSM' moore.log)" "1"
check "Moore: cells, flip-flops" "$(gcell moore.log cells) $(ncnt moore.log DFF)" "9 3"
ys mealy.log "read_verilog -sv ctrl_fsm_mealy/rtl/ctrl_fsm_mealy.sv; synth -top ctrl_fsm_mealy; stat"
check "Mealy: cells, flip-flops" "$(gcell mealy.log cells) $(ncnt mealy.log DFF)" "4 1"
mkdir -p cond && sed 's/if (start_i) state_d = StRun;/state_d = start_i ? StRun : StIdle;/' ctrl_fsm/rtl/ctrl_fsm.sv > cond/ctrl_fsm.sv
check "Icarus on state_d = start_i ? StRun : StIdle" "$(grep -c 'start_i ? StRun' cond/ctrl_fsm.sv) $(iverilog -g2012 -o x.vvp cond/ctrl_fsm.sv 2>&1 | grep -o 'error: This assignment requires an explicit cast.')" \
  "1 error: This assignment requires an explicit cast."

echo "== Moore and Mealy controller cycle by cycle (no testbench in the repository, recreated here)"
cat > fsm_tb.py << 'EOF'
"""fsm_tb.py <top> <sources>: the controller for the input sequence of step 4"""
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer
from cocotb_tools.runner import get_runner

NAMES = ["StIdle", "StRun", "StDone"]


@cocotb.test()
async def test_step4(dut):
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    dut.rst_ni.value = 0
    dut.start_i.value = 0
    dut.last_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    state, busy, done = [], "", ""
    for cycle in range(6):
        dut.start_i.value = int(cycle == 0)
        dut.last_i.value = int(cycle == 3)
        await Timer(1, "ns")  # the Mealy done_o follows last_i
        state.append(NAMES[int(dut.state_q.value)])
        busy += str(dut.busy_o.value)
        done += str(dut.done_o.value)
        await FallingEdge(dut.clk_i)
    dut._log.info(f"table: {' '.join(state)} | {busy} | {done}")
    dut.start_i.value = 1
    dut._log.info(f"read right after the write: {dut.start_i.value}")


if __name__ == "__main__":
    top, sim = sys.argv[1], os.getenv("SIM", "icarus")
    runner = get_runner(sim)
    runner.build(sources=sys.argv[2:], hdl_toplevel=top, build_dir=f"b_{top}_{sim}",
                 always=True, timescale=("1ns", "1ps"))
    runner.test(hdl_toplevel=top, test_module=Path(__file__).stem, build_dir=f"b_{top}_{sim}")
EOF
# The VHDL versions have the active-high reset rst_i and the state signal state
sed -e 's/rst_ni.value = 0/rst_i.value = 1/' -e 's/rst_ni.value = 1/rst_i.value = 0/' -e 's/state_q/state/' fsm_tb.py > fsm_vhdl_tb.py
declare -A table=([ctrl_fsm]="StIdle StRun StRun StRun StDone StIdle | 011100 | 000010"
  [ctrl_fsm_mealy]="StIdle StRun StRun StRun StIdle StIdle | 011100 | 000100")
for top in ctrl_fsm ctrl_fsm_mealy; do
  python3 fsm_tb.py $top $top/rtl/$top.sv > $top.icarus.log 2>&1
  SIM=verilator python3 fsm_tb.py $top $top/rtl/$top.sv > $top.verilator.log 2>&1
  SIM=ghdl python3 fsm_vhdl_tb.py $top $top/vhdl/${top}_ea.vhd > $top.ghdl.log 2>&1
  for sim in icarus verilator ghdl; do
    check "$top, $sim: state | busy_o | done_o in cycles 0 to 5" "$(grep -o 'table: .*' $top.$sim.log | cut -c8-)" "${table[$top]}"
  done
done
check "cocotb: a read right after a write returns the old value" "$(grep -o 'read right after the write: .' ctrl_fsm.icarus.log)" \
  "read right after the write: 0"

echo "== Packages: the default Yosys front end against slang, Verilator, and Icarus Verilog"
mkdir -p pkg && cd pkg
cat > alu_pkg.sv << 'EOF'
package alu_pkg;

  localparam int unsigned DATA_WIDTH = 8;

  typedef enum logic [1:0] {
    OpAdd,
    OpSub,
    OpAnd,
    OpOr
  } alu_op_e;

  typedef struct packed {
    alu_op_e               op;
    logic [DATA_WIDTH-1:0] operand;
  } instr_t;

  function automatic logic is_zero(input logic [DATA_WIDTH-1:0] data);
    is_zero = (data == '0);
  endfunction

endpackage
EOF
cat > alu.sv << 'EOF'
module alu (
  input  logic [alu_pkg::DATA_WIDTH-1:0] a_i,
  input  alu_pkg::instr_t                instr_i,
  output logic [alu_pkg::DATA_WIDTH-1:0] result_o,
  output logic                           zero_o
);

  always_comb begin
    unique case (instr_i.op)
      alu_pkg::OpAdd: result_o = a_i + instr_i.operand;
      alu_pkg::OpSub: result_o = a_i - instr_i.operand;
      alu_pkg::OpAnd: result_o = a_i & instr_i.operand;
      default:        result_o = a_i | instr_i.operand;
    endcase
  end

  assign zero_o = alu_pkg::is_zero(result_o);

endmodule
EOF
mkdir -p body hdr pre ret port
# import in the module body (the ports still need pkg::), in the header, and before module
sed -e '7,$ s/alu_pkg:://g' -e '6a\  import alu_pkg::*;' alu.sv > body/alu.sv
sed -e 's/alu_pkg:://g' -e 's/^module alu (/module alu\n  import alu_pkg::*;\n(/' alu.sv > hdr/alu.sv
{ echo 'import alu_pkg::*;'; sed 's/alu_pkg:://g' alu.sv; } > pre/alu.sv
sed "s/is_zero = (data == '0);/return (data == '0);/" alu_pkg.sv > ret/alu_pkg.sv
cat > port/alu.sv << 'EOF'
module alu (
  input  logic [7:0] data_i [4],
  output logic [7:0] sum_o
);
  assign sum_o = data_i[0] + data_i[1] + data_i[2] + data_i[3];
endmodule
EOF
check "variants applied" "$(grep -c import body/alu.sv hdr/alu.sv pre/alu.sv | cut -d: -f2 | paste -sd' ') $(grep -c return ret/alu_pkg.sv)" "1 1 1 1"
declare -A src=([base]="alu_pkg.sv alu.sv" [body]="alu_pkg.sv body/alu.sv" [hdr]="alu_pkg.sv hdr/alu.sv"
  [pre]="alu_pkg.sv pre/alu.sv" [ret]="ret/alu_pkg.sv alu.sv" [port]="port/alu.sv")
declare -A yexp=([base]="accepted" [body]="rejected ERROR: syntax error" [hdr]="rejected ERROR: syntax error"
  [pre]="rejected ERROR: syntax error" [ret]="rejected ERROR:Can't resolve task name \`\\return'." [port]="rejected ERROR: syntax error")
for v in base body hdr pre ret port; do
  s=${src[$v]}
  r=$(acc yosys -l y_$v.log -p "read_verilog -sv $s; synth -top alu")
  check "$v: Yosys" "$(echo $r $(grep -m1 -oE 'ERROR: ?[^,]*' y_$v.log))" "${yexp[$v]}"
  check "$v: slang, Verilator, Icarus" \
    "$(acc yosys -p "plugin -i slang; read_slang $s --top alu; synth -top alu") $(acc verilator --lint-only --top-module alu $s) $(acc iverilog -g2012 -o x.vvp $s)" \
    "accepted accepted accepted"
done
check "Icarus: struct fields in always_comb" "$(iverilog -g2012 -o x.vvp alu_pkg.sv alu.sv 2>&1 | grep -m1 -o "sorry: .*sensitive to all bits in 'instr_i\[9:0\]'" | grep -o 'sensitive to.*')" \
  "sensitive to all bits in 'instr_i[9:0]'"
cd "$W"

echo "== Plain Verilog against SystemVerilog"
mkdir -p vlog && cd vlog
cat > en.sv << 'EOF'
module en (input logic a_i, output logic [1:0] y_o);
  typedef enum logic [1:0] {StIdle, StRun, StDone} state_e;
  state_e s;
  always_comb begin
    s = StIdle;
    if (a_i) s = 2'b01;
  end
  assign y_o = s;
endmodule
EOF
check "enum assigned a plain number: Verilator, Icarus" \
  "$(verilator --lint-only en.sv 2>&1 | grep -m1 -oE '^%Error-[A-Z]+') $(iverilog -g2012 -o x.vvp en.sv 2>&1 | grep -o 'error: This assignment requires an explicit cast.')" \
  "%Error-ENUMVALUE error: This assignment requires an explicit cast."
cat > fc.v << 'EOF'
module fc (sel, a, b, c, y);
  input  [1:0] sel;
  input        a, b, c;
  output       y;
  reg          y;
  always @(*) begin
    case (sel) // synopsys full_case parallel_case
      2'b00: y = a;
      2'b01: y = b;
      2'b10: y = c;
    endcase
  end
endmodule
EOF
mkdir -p nofc && sed 's# // synopsys full_case parallel_case##' fc.v > nofc/fc.v
cat > fc_tb.sv << 'EOF'
module fc_tb;
  logic [1:0] sel;
  logic a = 1'b1, b = 1'b0, c = 1'b0, y;
  fc dut (.sel(sel), .a(a), .b(b), .c(c), .y(y));
  initial begin
    sel = 2'b00; #1 $display("sel=00 y=%b", y);
    a = 1'b0; sel = 2'b11; #1 $display("sel=11 y=%b", y);
    $finish;
  end
endmodule
EOF
# At sel = 11 all data inputs are 0, so y = 1 can only be a held value
check "full_case comment: Verilator warnings with and without it" "$(warns fc.v) / $(warns nofc/fc.v)" " / CASEINCOMPLETE LATCH"
ys fc.log "read_verilog fc.v; synth -top fc; stat; write_verilog -noattr fc_nl.v"
check "with the comment: Yosys exit status, latches" "$? $(ncnt fc.log DLATCH)" "0 0"
iverilog -g2012 -o fc_nl.vvp fc_nl.v fc_tb.sv
check "with the comment: netlist" "$(vvp -n fc_nl.vvp | grep sel | paste -sd' ')" "sel=00 y=1 sel=11 y=0"
ys nofc.log "read_verilog nofc/fc.v; synth -top fc; stat"
check "without it, always @(*): Yosys exit status, warning, latches" "$? $(msg nofc.log 'Warning: Latch inferred') $(ncnt nofc.log DLATCH)" \
  "0 Warning: Latch inferred 1"
iverilog -g2012 -o fc.vvp fc.v fc_tb.sv
check "Icarus ignores the comment and keeps the old value" "$(vvp -n fc.vvp | grep sel | paste -sd' ')" "sel=00 y=1 sel=11 y=1"
verilator --binary --timing -Mdir obj_fc --top-module fc_tb fc.v fc_tb.sv > fc_v.log 2>&1
check "Verilator stops when no item matches" "$(./obj_fc/Vfc_tb 2>&1 | grep -o 'synthesis full_case parallel_case, but non-match found')" \
  "synthesis full_case parallel_case, but non-match found"
cat > uq.sv << 'EOF'
module uq (input logic [1:0] sel_i, input logic a_i, b_i, c_i, output logic y_o);
  always_comb begin
    unique case (sel_i)
      2'b00: y_o = a_i;
      2'b01: y_o = b_i;
      2'b10: y_o = c_i;
    endcase
  end
endmodule
EOF
ys uq.log "read_verilog -sv uq.sv; synth -top uq; stat; write_verilog -noattr uq_nl.v"
check "unique case without default in always_comb: Yosys exit status, latches" "$? $(ncnt uq.log DLATCH)" "0 0"
sed 's/fc dut (.sel(sel), .a(a), .b(b), .c(c), .y(y));/uq dut (.sel_i(sel), .a_i(a), .b_i(b), .c_i(c), .y_o(y));/; s/fc_tb/uq_tb/' fc_tb.sv > uq_tb.sv
iverilog -g2012 -o uq.vvp uq.sv uq_tb.sv > /dev/null 2>&1
iverilog -g2012 -o uq_nl.vvp uq_nl.v uq_tb.sv
check "unique case without default: Icarus, netlist" "$(vvp -n uq.vvp | grep sel | paste -sd' ') / $(vvp -n uq_nl.vvp | grep sel | paste -sd' ')" \
  "sel=00 y=1 sel=11 y=1 / sel=00 y=1 sel=11 y=0"
mkdir -p plain && sed 's/unique case/case/' uq.sv > plain/uq.sv
ys plain.log "read_verilog -sv plain/uq.sv; synth -top uq"
check "the same case without unique: Yosys" "$(msg plain.log 'ERROR: Latch inferred')" "ERROR: Latch inferred"
cat > wa.v << 'EOF'
module wa (a, y);
  input  a;
  output y;
  wire   t;
  always @(*) t = ~a;
  assign y = t;
endmodule
EOF
cat > ra.v << 'EOF'
module ra (a, y);
  input  a;
  output y;
  reg    t;
  assign t = ~a;
  assign y = t;
endmodule
EOF
check "reg driven by assign: Icarus (Verilog-2005), Icarus -g2012, Verilator" \
  "$(acc iverilog -o x.vvp ra.v) $(acc iverilog -g2012 -o x.vvp ra.v) $(acc verilator --lint-only ra.v)" "rejected accepted accepted"
check "internal wire assigned in always: Icarus, Verilator" \
  "$(iverilog -o x.vvp wa.v 2>&1 | grep -m1 -o "'t' is not a valid l-value"), $(verilator --lint-only wa.v 2>&1 | grep -m1 -oE '^%Error-[A-Z]+')" \
  "'t' is not a valid l-value, %Error-PROCASSWIRE"
cp ../popcount/rtl/popcount.sv popcount.v
check "popcount.sv: Icarus without -g2012, read_verilog without -sv, Verilator on a .v copy" \
  "$(acc iverilog -o x.vvp popcount.v) $(acc yosys -p 'read_verilog ../popcount/rtl/popcount.sv') $(acc verilator --lint-only -Wall popcount.v)" \
  "rejected rejected accepted"
cd "$W"

echo "== prio_enc: modernize a Verilog-2001 module"
cd prio_enc
check "prio_enc.v: Verilator" "$(warns verilog/prio_enc.v)" "LATCH WIDTHTRUNC"
ys v.log "read_verilog verilog/prio_enc.v; synth -top prio_enc; stat"
check "prio_enc.v: Yosys exit status, warning" "$? $(msg v.log "Latch inferred for signal \`\\prio_enc.\\idx_next'")" \
  "0 Latch inferred for signal \`\\prio_enc.\\idx_next'"
check "prio_enc.v: cells, \$_DFF_PN0_, \$_DLATCH_N_" "$(gcell v.log cells) $(gcell v.log '$_DFF_PN0_') $(gcell v.log '$_DLATCH_N_')" "23 4 3"
# The translation of step 3: rtl/prio_enc.sv without the default, with and without the cast
mkdir -p cast nocast uns keep
sed "/idx_d   = '0;/d" rtl/prio_enc.sv > cast/prio_enc.sv
sed "s/idx_d = W'(i);/idx_d = i;/" cast/prio_enc.sv > nocast/prio_enc.sv
check "translation: Verilator with and without the cast" "$(warns cast/prio_enc.sv) / $(warns nocast/prio_enc.sv)" "LATCH / LATCH WIDTHTRUNC"
ys cast.log "read_verilog -sv cast/prio_enc.sv; synth -top prio_enc"
check "translation: Yosys" "$(msg cast.log "ERROR: Latch inferred for signal \`\\prio_enc.\\idx_d' from always_comb process")" \
  "ERROR: Latch inferred for signal \`\\prio_enc.\\idx_d' from always_comb process"
sed 's/for (int i = N - 1/for (int unsigned i = N - 1/' rtl/prio_enc.sv > uns/prio_enc.sv
out=$(verilator --lint-only -Wall uns/prio_enc.sv 2>&1)
check "int unsigned: Verilator warnings, internal error" \
  "$(echo "$out" | grep -oE '^%Warning-[A-Z]+' | cut -d- -f2 | sort | paste -sd' '), $(echo "$out" | grep -c '^%Error: Internal Error')" "INFINITELOOP UNSIGNED, 1"
ys fix.log "read_verilog -sv rtl/prio_enc.sv; synth -top prio_enc; stat"
check "fixed: cells, \$_DFF_PN0_, latches" "$(gcell fix.log cells) $(gcell fix.log '$_DFF_PN0_') $(ncnt fix.log DLATCH)" "22 4 0"
sed "s/idx_d   = '0;/idx_d   = idx_q;/" rtl/prio_enc.sv > keep/prio_enc.sv
ys keep.log "read_verilog -sv keep/prio_enc.sv; synth -top prio_enc; stat"
check "default idx_d = idx_q: \$_DFFE_PN0P_, latches" "$(grep -c 'idx_d   = idx_q;' keep/prio_enc.sv) $(gcell keep.log '$_DFFE_PN0P_') $(ncnt keep.log DLATCH)" "1 3 0"
iverilog -g2012 -o prio_enc_tb.vvp rtl/prio_enc.sv testbenches/verilog/prio_enc_tb.sv
out=$(vvp prio_enc_tb.vvp); rc=$?
check "testbench: message, exit status" "$(echo "$out" | grep -o 'PASS: prio_enc_tb') $rc" "PASS: prio_enc_tb 0"
sed 's/^module prio_enc /module prio_enc_v /' verilog/prio_enc.v > prio_enc_v.v
cat > cmp_tb.sv << 'EOF'
module cmp_tb;
  logic       clk = 1'b0, rst_n = 1'b0, valid_v, valid_sv;
  logic [7:0] req = '0;
  logic [2:0] idx_v, idx_sv;
  prio_enc_v dut_v (.clk(clk), .rst_n(rst_n), .req(req), .idx(idx_v), .valid(valid_v));
  prio_enc dut_sv (.clk_i(clk), .rst_ni(rst_n), .req_i(req), .idx_o(idx_sv), .valid_o(valid_sv));
  always #10 clk = ~clk;
  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk) $display("idx before the first request: %b %b", idx_v, idx_sv);
    req = 8'h80;
    @(negedge clk) req = 8'h00;
    @(negedge clk) $display("idx after 0x80 and 0x00: %b %b", idx_v, idx_sv);
    $finish;
  end
endmodule
EOF
iverilog -g2012 -o cmp.vvp prio_enc_v.v rtl/prio_enc.sv cmp_tb.sv
check "idx_o while valid_o is low: original, fixed" "$(vvp -n cmp.vvp | grep idx | sed 's/.*: //' | paste -sd',')" "xxx 000,111 000"
cd "$W"

echo "== tick_gen: testbenches"
cd tick_gen
check "lint: report, exit status" "$(verilator --lint-only -Wall rtl/tick_gen.sv 2>&1 | grep -c 'V e r i l a t i o n   R e p o r t') $(acc verilator --lint-only -Wall rtl/tick_gen.sv)" \
  "1 accepted"
iverilog -g2012 -o testbenches/verilog/tick_gen_tb.vvp rtl/tick_gen.sv testbenches/verilog/tick_gen_tb.sv
out=$(cd testbenches/verilog && vvp tick_gen_tb.vvp); rc=$?
check "Icarus: message, exit status, VCD" "$(echo "$out" | grep -o 'PASS: tick_gen_tb') $rc $(ls testbenches/verilog/*.vcd)" \
  "PASS: tick_gen_tb 0 testbenches/verilog/tick_gen_tb.vcd"
cat > peek.sv << 'EOF'
module peek;
  int last;
  always @(negedge tick_gen_tb.clk) begin
    if (tick_gen_tb.tick) $display("count_q one cycle before the tick: %0d", last);
    last = tick_gen_tb.dut.count_q;
  end
endmodule
EOF
iverilog -g2012 -o peek.vvp rtl/tick_gen.sv testbenches/verilog/tick_gen_tb.sv peek.sv
check "DIV = 5: ticks, count_q one cycle before each tick" "$(vvp -n peek.vvp | grep -c 'before the tick') $(vvp -n peek.vvp | grep 'before the tick' | sort -u | awk '{print $NF}')" "4 4"
verilator --binary --timing --timescale 1ns/1ps --trace --top-module tick_gen_tb -o tick_gen_tb \
  rtl/tick_gen.sv testbenches/verilog/tick_gen_tb.sv > verilator.log 2>&1
out=$(cd testbenches/verilog && ../../obj_dir/tick_gen_tb); rc=$?
check "Verilator: message, exit status" "$(echo "$out" | grep -o 'PASS: tick_gen_tb') $rc" "PASS: tick_gen_tb 0"
(cd testbenches/cocotb && python3 tick_gen_tb.py > icarus.log 2>&1)
check "cocotb with Icarus Verilog: result, files" \
  "$(tests testbenches/cocotb/icarus.log) $(cd testbenches/cocotb && ls sim_build/results.xml sim_build/tick_gen.fst | paste -sd' ')" \
  "TESTS=2 PASS=2 FAIL=0 SKIP=0 sim_build/results.xml sim_build/tick_gen.fst"
(cd testbenches/cocotb && rm -rf sim_build && SIM=verilator python3 tick_gen_tb.py > verilator.log 2>&1)
check "cocotb with Verilator: result, waveform" "$(tests testbenches/cocotb/verilator.log) $(cd testbenches/cocotb && ls sim_build/dump.vcd)" \
  "TESTS=2 PASS=2 FAIL=0 SKIP=0 sim_build/dump.vcd"
mkdir -p race && cp -r rtl testbenches race/
sed -i 's/@(negedge clk)/@(posedge clk)/' race/testbenches/verilog/tick_gen_tb.sv
iverilog -g2012 -o race/i.vvp race/rtl/tick_gen.sv race/testbenches/verilog/tick_gen_tb.sv
verilator --binary --timing --timescale 1ns/1ps --top-module tick_gen_tb -Mdir race/obj \
  race/rtl/tick_gen.sv race/testbenches/verilog/tick_gen_tb.sv > race/verilator.log 2>&1
check "testbench on the rising edge: Icarus, Verilator" \
  "$(vvp -n race/i.vvp 2>&1 | grep -oE '^(PASS|FATAL)' | head -1) $(race/obj/Vtick_gen_tb 2>&1 | grep -oE '^(PASS|%Error)' | head -1)" "FATAL PASS"
sed -i 's/DIV           = 5;/DIV           = 8;/' testbenches/verilog/tick_gen_tb.sv
sed -i 's/^DIV = 5 /DIV = 8 /' testbenches/cocotb/tick_gen_tb.py
iverilog -g2012 -o testbenches/verilog/tick_gen_tb.vvp rtl/tick_gen.sv testbenches/verilog/tick_gen_tb.sv
out=$(cd testbenches/verilog && vvp tick_gen_tb.vvp)
(cd testbenches/cocotb && rm -rf sim_build && python3 tick_gen_tb.py > div8.log 2>&1)
check "DIV = 8: applied, SystemVerilog, cocotb" \
  "$(grep -c 'DIV           = 8;' testbenches/verilog/tick_gen_tb.sv)$(grep -c '^DIV = 8 ' testbenches/cocotb/tick_gen_tb.py) $(echo "$out" | grep -o PASS) $(tests testbenches/cocotb/div8.log)" \
  "11 PASS TESTS=2 PASS=2 FAIL=0 SKIP=0"
sed -i 's/count_q == COUNT_LAST)/count_q == COUNT_LAST - 1)/' rtl/tick_gen.sv
iverilog -g2012 -o testbenches/verilog/tick_gen_tb.vvp rtl/tick_gen.sv testbenches/verilog/tick_gen_tb.sv
out=$(cd testbenches/verilog && vvp tick_gen_tb.vvp 2>&1); rc=$?
check "bug COUNT_LAST - 1, SystemVerilog: applied, FATAL, exit status" "$(grep -c 'COUNT_LAST - 1' rtl/tick_gen.sv) $(echo "$out" | grep -o '^FATAL' | head -1) $rc" "1 FATAL 1"
(cd testbenches/cocotb && rm -rf sim_build && python3 tick_gen_tb.py > bug.log 2>&1); rc=$?
check "bug COUNT_LAST - 1, cocotb: failed test, exit status" \
  "$(grep -oE 'tick_gen_tb\.[a-z_]+ +FAIL' testbenches/cocotb/bug.log | tr -s ' ') $rc" "tick_gen_tb.test_tick_every_div_cycles FAIL 1"
cd "$W"

echo "== pwm"
cd pwm
iverilog -g2012 -o testbenches/verilog/pwm_tb.vvp rtl/pwm.sv testbenches/verilog/pwm_tb.sv
out=$(cd testbenches/verilog && vvp pwm_tb.vvp); rc=$?
check "SystemVerilog testbench: message, exit status" "$(echo "$out" | grep -o 'PASS: pwm_tb') $rc" "PASS: pwm_tb 0"
for sim in icarus verilator; do
  (cd testbenches/cocotb && rm -rf sim_build && SIM=$sim python3 pwm_tb.py > $sim.log 2>&1)
  check "cocotb with $sim" "$(tests testbenches/cocotb/$sim.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
done
cp rtl/pwm.sv pwm.sv.orig
sed -i 's/(count_q < duty_i)/(count_q <= duty_i)/' rtl/pwm.sv
iverilog -g2012 -o testbenches/verilog/pwm_tb.vvp rtl/pwm.sv testbenches/verilog/pwm_tb.sv
out=$(cd testbenches/verilog && vvp pwm_tb.vvp 2>&1); rc=$?
check "< changed to <=: FATAL, message, exit status" "$(echo "$out" | grep -o '^FATAL' | head -1) $(echo "$out" | grep -o 'FAIL: duty 0 gives 1 high cycles') $rc" \
  "FATAL FAIL: duty 0 gives 1 high cycles 1"
mkdir -p err && sed 's/\$fatal(1, /$error(/' testbenches/verilog/pwm_tb.sv > err/pwm_tb.sv
iverilog -g2012 -o err/pwm_tb.vvp rtl/pwm.sv err/pwm_tb.sv
out=$(cd err && vvp pwm_tb.vvp 2>&1); rc=$?
check "the same with \$error: first message, end, exit status" \
  "$(echo "$out" | grep -m1 -o 'FAIL: duty 0 gives 1 high cycles') $(echo "$out" | grep -o 'PASS: pwm_tb') $rc" "FAIL: duty 0 gives 1 high cycles PASS: pwm_tb 0"
cp pwm.sv.orig rtl/pwm.sv
sed -i "s/count_d = count_q + 1'b1;/count_d = (count_q == WIDTH'(2**WIDTH - 2)) ? '0 : count_q + 1'b1;/" rtl/pwm.sv
(cd testbenches/cocotb && rm -rf sim_build && python3 pwm_tb.py > wrap14.log 2>&1)
check "counter wraps at 14: applied, cocotb" "$(grep -c '2\*\*WIDTH - 2' rtl/pwm.sv) $(tests testbenches/cocotb/wrap14.log)" "1 TESTS=2 PASS=0 FAIL=2 SKIP=0"
# The pulse at the end of the period: the same number of high cycles
cp pwm.sv.orig rtl/pwm.sv
sed -i 's/(count_q < duty_i)/(count_q >= 2**WIDTH - duty_i)/' rtl/pwm.sv
(cd testbenches/cocotb && rm -rf sim_build && python3 pwm_tb.py > shift.log 2>&1)
check "shifted pulse: applied, failed tests" "$(grep -c '2\*\*WIDTH - duty_i' rtl/pwm.sv) $(grep -oE 'pwm_tb\.[a-z_]+ +FAIL' testbenches/cocotb/shift.log | tr -s ' ')" \
  "1 pwm_tb.test_against_model FAIL"
cd "$W"

echo "== seq_detect"
cd seq_detect/testbenches/cocotb
for sim in icarus verilator; do
  rm -rf sim_build && SIM=$sim python3 seq_detect_tb.py > $sim.log 2>&1
  check "cocotb with $sim: result, detections" "$(tests $sim.log), $(grep -o '[0-9]* detections in 500 bits' $sim.log)" \
    "TESTS=2 PASS=2 FAIL=0 SKIP=0, 31 detections in 500 bits"
done
check "Icarus: sorry message for unique" "$(grep -m1 -o 'sorry: Case unique/unique0 qualities are ignored' icarus.log)" \
  "sorry: Case unique/unique0 qualities are ignored"
check "occurrences of 1011 in the stream of random.Random(1234)" "$(python3 -c '
import random
rng = random.Random(1234)
s = "".join(str(rng.randint(0, 1)) for _ in range(500))
print(sum(s.startswith("1011", i) for i in range(len(s))))')" "31"
cd "$W"

echo "== The cocotb testbenches on the VHDL versions (GHDL, reset adapted)"
mkdir -p ghdl_tb
for d in tick_gen seq_detect; do
  cp -r "$REPO/content/sv_crashcourse/code/$d" ghdl_tb/
  cd ghdl_tb/$d/testbenches/cocotb
  sed -i -e 's/rst_ni.value = 0/rst_i.value = 1/' -e 's/rst_ni.value = 1/rst_i.value = 0/' \
    -e "s#rtl/$d.sv#vhdl/${d}_ea.vhd#" ${d}_tb.py
  SIM=ghdl python3 ${d}_tb.py > ghdl.log 2>&1
  check "$d: adapted lines, result" "$(grep -c -E 'rst_i.value|_ea.vhd' ${d}_tb.py) $(tests ghdl.log)" "3 TESTS=2 PASS=2 FAIL=0 SKIP=0"
  cd "$W"
done
check "seq_detect (VHDL): detections" "$(grep -o '[0-9]* detections in 500 bits' ghdl_tb/seq_detect/testbenches/cocotb/ghdl.log)" "31 detections in 500 bits"

echo "== The counter of the AMS chip template"
if [ ! -d "$TPL/macros/counter" ]; then
  echo "  skip  no clone of the template at $TPL"
else
  T=$W/template
  mkdir -p "$T/final" && cp -r "$TPL/macros/counter/"{rtl,testbenches,Makefile} "$T/" && cp -r "$TPL/macros/counter/final/nl" "$T/final/"
  rm -rf "$T/testbenches/cocotb/sim_build" "$T"/testbenches/verilog/*.vcd
  cd "$T"
  check "rst_n of the chip core, counter_top.nl.v with dfrbpq_1" \
    "$(grep -c 'input  logic rst_n' "$TPL/rtl/chip_core.sv") $(grep -c 'sg13cmos5l_dfrbpq_1 ' final/nl/counter_top.nl.v | awk '{print ($1 > 0)}')" "1 1"
  check "macros of constants.sv used in counter_top.sv and the testbench" \
    "$(grep -c -E '`define (COUNTER_MAX_DEFAULT|CLK_FREQ_DEFAULT)' rtl/constants.sv) $(grep -c '`COUNTER_MAX_DEFAULT' rtl/counter_top.sv) $(grep -c -E '`(COUNTER_MAX|CLK_FREQ)_DEFAULT' testbenches/verilog/counter_top_tb.sv)" "2 1 2"
  check "lint with constants.sv first, and last" \
    "$(verilator --lint-only -Wall rtl/constants.sv rtl/counter.sv rtl/counter_top.sv 2>&1 | grep -c '^%') $(acc verilator --lint-only -Wall rtl/counter.sv rtl/counter_top.sv rtl/constants.sv)" "0 rejected"
  sim_tpl() {  # sim_tpl <tag>: SystemVerilog and cocotb testbench of the counter
    iverilog -g2012 -o testbenches/verilog/counter_top_tb.vvp rtl/constants.sv rtl/counter.sv rtl/counter_top.sv testbenches/verilog/counter_top_tb.sv
    out=$(cd testbenches/verilog && vvp counter_top_tb.vvp); rc=$?
    sv="$(echo "$out" | grep -o 'PASS: simulation complete.') $rc"
    (cd testbenches/cocotb && rm -rf sim_build && python3 counter_top_tb.py > $1.log 2>&1); rc=$?
    co="$(tests testbenches/cocotb/$1.log) $rc"
  }
  sim_tpl orig
  check "SystemVerilog testbench: message, exit status" "$sv" "PASS: simulation complete. 0"
  check "cocotb testbench: result, exit status, waveform" "$co $(ls testbenches/cocotb/sim_build/counter_top.fst)" \
    "TESTS=4 PASS=4 FAIL=0 SKIP=0 0 testbenches/cocotb/sim_build/counter_top.fst"
  check "checks in the SystemVerilog testbench, tests in the cocotb testbench" \
    "$(grep -c '\$fatal' testbenches/verilog/counter_top_tb.sv) $(grep -c '@cocotb.test()' testbenches/cocotb/counter_top_tb.py)" "2 4"
  cp "$W/counter_2p/rtl/counter.sv" rtl/counter.sv
  sim_tpl twoproc
  check "two-process counter: lint, SystemVerilog, cocotb" \
    "$(verilator --lint-only -Wall rtl/constants.sv rtl/counter.sv rtl/counter_top.sv 2>&1 | grep -c '^%'), $sv, $co" \
    "0, PASS: simulation complete. 0, TESTS=4 PASS=4 FAIL=0 SKIP=0 0"
  sed -i 's/(count_q == CTR_MAX)/(count_q == CTR_MAX - 1)/' rtl/counter.sv
  sim_tpl bug
  check "bug CTR_MAX - 1: applied, SystemVerilog, cocotb" "$(grep -c 'CTR_MAX - 1' rtl/counter.sv), $sv, $co" \
    "1, PASS: simulation complete. 0, TESTS=4 PASS=3 FAIL=1 SKIP=0 0"
  check "bug CTR_MAX - 1: failed test" "$(grep -oE 'counter_top_tb\.[a-z_]+ +FAIL' testbenches/cocotb/bug.log | tr -s ' ')" "counter_top_tb.test_wraps_at_max FAIL"
  check "default PDK of the container" "$(env -u PDK bash -lc 'echo $PDK' 2>/dev/null | tail -1)" "ihp-sg13g2"
  # make -n clean still runs the recursive make of fpga/, which the copy lacks, so only the guard message counts
  check "make help with PDK=ihp-sg13g2, guard messages of help and clean" \
    "$(acc env PDK=ihp-sg13g2 make help) $(env PDK=ihp-sg13g2 make help 2>&1 | grep -c 'PDK is') $(env PDK=ihp-sg13g2 make -n clean 2>&1 | grep -c 'PDK is')" "accepted 0 0"
  check "make -n sim-rtl-verilog with PDK=ihp-sg13g2" "$(PDK=ihp-sg13g2 make -n sim-rtl-verilog 2>&1 | grep -o 'PDK is "ihp-sg13g2", but this macro needs "ihp-sg13cmos5l"')" \
    'PDK is "ihp-sg13g2", but this macro needs "ihp-sg13cmos5l"'
  mk() { PDK=ihp-sg13cmos5l make -n "$@" 2>&1 | grep -v '^make'; }
  check "make -n sim-rtl-verilog" "$(mk sim-rtl-verilog | paste -sd'|')" \
    "iverilog -g2012 -DSIM -o testbenches/verilog/test_counter_top rtl/constants.sv rtl/counter.sv rtl/counter_top.sv testbenches/verilog/counter_top_tb.sv|cd testbenches/verilog && vvp test_counter_top|rm -f testbenches/verilog/test_counter_top"
  check "make -n lint-verilog, CELL=counter" "$(mk lint-verilog) | $(mk lint-verilog CELL=counter)" \
    'verilator --lint-only -I"rtl" rtl/constants.sv rtl/counter.sv rtl/counter_top.sv | verilator --lint-only -I"rtl" rtl/constants.sv rtl/counter.sv'
  check "make -n lint-verilog-all: Verilator runs" "$(mk lint-verilog-all | grep -c '^verilator')" "2"
  check "make -n sim-rtl-cocotb, sim-gl-cocotb" "$(mk sim-rtl-cocotb) | $(mk sim-gl-cocotb)" \
    "cd testbenches/cocotb && python3 counter_top_tb.py | cd testbenches/cocotb && GL=1 python3 counter_top_tb.py"
  check "make -n sim-view-verilog" "$(mk sim-view-verilog | grep -m1 -o 'gtkwave testbenches/verilog/counter_top_tb.vcd testbenches/verilog/counter_top_tb.gtkw')" \
    "gtkwave testbenches/verilog/counter_top_tb.vcd testbenches/verilog/counter_top_tb.gtkw"
  check "make -n sim-view-verilog WAVEFORM_VIEWER=surfer" \
    "$(mk sim-view-verilog WAVEFORM_VIEWER=surfer | grep -m1 -o 'surfer -s testbenches/verilog/counter_top_tb.surf.ron testbenches/verilog/counter_top_tb.vcd')" \
    "surfer -s testbenches/verilog/counter_top_tb.surf.ron testbenches/verilog/counter_top_tb.vcd"
  check "make -n sim-view-cocotb" "$(mk sim-view-cocotb | grep -m1 -o 'gtkwave testbenches/cocotb/sim_build/counter_top.fst testbenches/cocotb/counter_top_tb.gtkw')" \
    "gtkwave testbenches/cocotb/sim_build/counter_top.fst testbenches/cocotb/counter_top_tb.gtkw"
  cd "$W"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all results match the chapter"
else
  echo "FAIL: $fails result(s) differ from the chapter"
  exit 1
fi
