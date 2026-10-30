#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Functional
# Verification with cocotb" quotes, inside the IIC-OSIC-TOOLS container
# (image 2026.10). Run from the repository root:
#   bash scripts/check_verification.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter. FULL=1 also runs
# the exhaustive test of the 16-bit barrel shifter (about two minutes).

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_verification}
LIB=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
CELLS=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog
fails=0

rm -rf "$W" && mkdir -p "$W" && cp -r "$REPO/content/verification/code/." "$W/"
cd "$W" || exit 1

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

verdict() {  # verdict <log> <test>: PASS, FAIL or SKIP of one cocotb test
  grep -E "\*\* [a-z_]+\.$2 +(PASS|FAIL|SKIP)" "$1" | awk '{print $3}'
}

summary() {  # summary <log>: the TESTS= line of a cocotb run
  grep -o "TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]* SKIP=[0-9]*" "$1"
}

bins() {  # bins <log> <n>: the coverage bins of the n-th report as a list
  grep -E " (idle|push|pop|push\+pop) when (empty|partial|full) +[0-9]+$" "$1" \
    | awk '{print $NF}' | sed -n "$(( ($2 - 1) * 12 + 1 )),$(( $2 * 12 ))p" | tr '\n' ' '
}

mutate() {  # mutate <n>: apply mutant n to rtl/fifo.sv in the current folder
  case $1 in
    1) sed -i 's/push_i \&\& !full_o/push_i/' rtl/fifo.sv ;;
    2) sed -i 's/pop_i \&\& !empty_o/pop_i/' rtl/fifo.sv ;;
    3) sed -i 's/push_i \&\& !full_o/push_i \&\& (!full_o || pop_i)/' rtl/fifo.sv ;;
    4) sed -i 's/if (push)/if (push_i)/' rtl/fifo.sv ;;
    5) sed -i 's/(wr_ptr_q == rd_ptr_q)/(wr_ptr_q[1:0] == rd_ptr_q[1:0])/' rtl/fifo.sv ;;
    6) sed -i "s/<= '0;/<= '1;/" rtl/fifo.sv ;;
  esac
}

echo "== Versions"
check "Verilator" "$(verilator --version | awk '{print $2}')" "5.052"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "cocotb" "$(python3 -c 'import cocotb; print(cocotb.__version__)')" "2.1.0"
check "pyuvm" "$(python3 -c 'import importlib.metadata as m; print(m.version("pyuvm"))')" "5.0.0"
check "MCY in the image" "$(command -v mcy > /dev/null && echo yes)" "yes"

echo "== Lint of every rtl/ file (no warning or error with -Wall)"
for f in */rtl/*.sv; do
  check "lint $f" "$(verilator --lint-only -Wall "$f" 2>&1 | grep -c -E '%Warning|%Error')" "0"
done
check "lint barrel_shift_bug.sv, WIDTH 8" \
  "$(verilator --lint-only -Wall barrel_shift/exercise/barrel_shift_bug.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
check "lint barrel_shift_bug.sv, WIDTH 32, warnings" \
  "$(verilator --lint-only -Wall -GWIDTH=32 barrel_shift/exercise/barrel_shift_bug.sv 2>&1 | grep -o '%Warning-[A-Z]*' | tr '\n' ' ')" \
  "%Warning-WIDTHTRUNC %Warning-UNUSEDSIGNAL "

echo "== Barrel shifter: exhaustive and random stimulus"
cd barrel_shift/testbenches/cocotb
python3 barrel_shift_tb.py > ic8.log 2>&1
check "Icarus, WIDTH 8" "$(summary ic8.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
check "exhaustive vectors, WIDTH 8" "$(grep -o '[0-9]* vectors,' ic8.log | awk '{print $1}')" "8192"
rate=$(grep -o '[0-9]* vectors/s' ic8.log | awk '{print $1}')
check "Icarus rate above 20,000 vectors/s (measured about 70,000)" "$([ "$rate" -gt 20000 ] && echo yes)" "yes"
check "cocotb prints the seed" "$(grep -c 'Seeding Python random module with' ic8.log)" "1"
SIM=verilator python3 barrel_shift_tb.py > ve8.log 2>&1
check "Verilator, WIDTH 8" "$(summary ve8.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
rate=$(grep -o '[0-9]* vectors/s' ve8.log | awk '{print $1}')
check "Verilator rate above 30,000 vectors/s (measured about 100,000)" "$([ "$rate" -gt 30000 ] && echo yes)" "yes"
WIDTH=32 python3 barrel_shift_tb.py > ic32.log 2>&1
check "Icarus, WIDTH 32" "$(summary ic32.log)" "TESTS=2 PASS=1 FAIL=0 SKIP=1"
check "vectors for WIDTH 16" "$(( (1 << 16) * 16 * 4 ))" "4194304"
check "vectors for WIDTH 32" "$(( (1 << 32) * 32 * 4 ))" "549755813888"
TOPLEVEL=barrel_shift_bug python3 barrel_shift_tb.py > bug8.log 2>&1
check "bug, WIDTH 8" "$(summary bug8.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
TOPLEVEL=barrel_shift_bug WIDTH=32 python3 barrel_shift_tb.py > bug32.log 2>&1
check "bug, WIDTH 32, exit status" "$?" "1"
check "bug, WIDTH 32" "$(summary bug32.log)" "TESTS=2 PASS=0 FAIL=1 SKIP=1"
SIM=verilator TOPLEVEL=barrel_shift_bug WIDTH=32 python3 barrel_shift_tb.py > bug32v.log 2>&1
check "bug, WIDTH 32, Verilator build stops at WIDTHTRUNC" \
  "$(grep -c '%Warning-WIDTHTRUNC' bug32v.log) $(grep -c 'TESTS=' bug32v.log)" "1 0"
check "bug, WIDTH 32, first failure" \
  "$(grep -m1 -o 'data 0x[0-9a-f]*, shamt [0-9]*, mode [0-9]: expected [01]*, got [01]*' bug32.log)" \
  "data 0xffffffff, shamt 31, mode 0: expected 10000000000000000000000000000000, got 11111111111111111111111110000000"
if [ "${FULL:-0}" == "1" ]; then
  sed -i 's/skip=WIDTH > 8/skip=WIDTH > 16/' barrel_shift_tb.py
  WIDTH=16 COCOTB_TEST_FILTER=test_exhaustive python3 barrel_shift_tb.py > ic16.log 2>&1
  check "exhaustive vectors, WIDTH 16" "$(grep -o '[0-9]* vectors,' ic16.log | awk '{print $1}')" "4194304"
  echo "  info  WIDTH 16 run time (s): $(grep -E 'test_exhaustive +PASS' ic16.log | awk '{print $5}') (measured 64)"
fi
cd "$W"

echo "== FIFO: RTL simulation, functional and code coverage"
cd fifo/testbenches/cocotb
COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > ic.log 2>&1
check "Icarus" "$(summary ic.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
check "Icarus messages starting with sorry" "$(grep -c sorry ic.log)" "0"
check "seed 1 is used" "$(grep -c 'Seeding Python random module with 1$' ic.log)" "1"
check "directed test, coverage bins" "$(bins ic.log 1)" "2 0 0 1 3 0 0 3 1 0 0 0 "
check "random test, seed 1, coverage bins" "$(bins ic.log 2)" "51 85 54 16 142 169 126 123 26 47 109 54 "
SIM=verilator COCOTB_TEST_FILTER=test_fill_and_drain python3 fifo_tb.py > vd.log 2>&1
check "Verilator, directed test only" "$(summary vd.log)" "TESTS=1 PASS=1 FAIL=0 SKIP=0"
verilator_coverage --annotate-min 1 --annotate-points --annotate ann_directed sim_build/coverage.dat > covd.txt
check "directed: line coverage" "$(grep -E '^ +line ' covd.txt | sed 's/.*: *//; s/ //g')" "100.0%(3/3)"
check "directed: branch coverage" "$(grep -E '^ +branch ' covd.txt | sed 's/.*: *//; s/ //g')" "100.0%(8/8)"
check "directed: expression coverage" "$(grep -E '^ +expr ' covd.txt | sed 's/.*: *//; s/ //g')" "100.0%(14/14)"
check "directed: toggle coverage" "$(grep -E '^ +toggle ' covd.txt | sed 's/.*: *//; s/ //g')" "50.7%(69/136)"
check "directed: wr_ptr_q[2] never falls" \
  "$(grep -E 'comment=wr_ptr_q\[2\]:1->0' ann_directed/fifo.sv | awk '{print $1}')" "-000000"
COCOTB_RANDOM_SEED=1 SIM=verilator python3 fifo_tb.py > va.log 2>&1
verilator_coverage sim_build/coverage.dat > /dev/null 2>&1
verilator_coverage --annotate-min 1 --annotate ann_all sim_build/coverage.dat > cova.txt
check "both tests: toggle coverage" "$(grep -E '^ +toggle ' cova.txt | sed 's/.*: *//; s/ //g')" "100.0%(136/136)"
cd "$W"

echo "== FIFO: assertions"
cd fifo
check "lint of rtl/ and the checker (no -Wall)" \
  "$(verilator --lint-only --top-module fifo rtl/fifo.sv testbenches/sva/fifo_sva.sv 2>&1 | grep -c -E '%Warning|%Error')" "0"
cd testbenches/cocotb
SIM=verilator SVA=1 COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > sva.log 2>&1
check "Verilator with the checker" "$(summary sva.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
check "cover property c_full_push_pop, seed 1" \
  "$(tr '\001\002' '|=' < sim_build/coverage.dat | grep -a 'o=c_full_push_pop' | awk '{print $NF}')" "54"
cd "$W"
mkdir -p sva_tools && cd sva_tools
cat > conc.sv <<'EOF'
module conc (input logic clk_i, input logic a_i, b_i);
  a1: assert property (@(posedge clk_i) !(a_i && b_i));
endmodule
EOF
iverilog -g2012 -o conc.vvp conc.sv > conc.log 2>&1
check "Icarus, simple concurrent assertion, exit status" "$?" "1"
check "Icarus message" "$(grep -c 'sorry: concurrent_assertion_item not supported' conc.log)" "1"
iverilog -g2012 -gsupported-assertions -o conc.vvp conc.sv > conc2.log 2>&1
check "Icarus with -gsupported-assertions, exit status (dropped silently)" "$?" "0"
SVA=$W/fifo/testbenches/sva/fifo_sva.sv
iverilog -g2012 -gsupported-assertions -o sva.vvp "$SVA" > sva.log 2>&1
check "Icarus with fifo_sva.sv, exit status not 0" "$([ $? -ne 0 ] && echo yes)" "yes"
check "Icarus with fifo_sva.sv, syntax errors at every |=> and at bind" \
  "$(grep -o 'fifo_sva.sv:[0-9]*: syntax error' sva.log | cut -d: -f2 | tr '\n' ' ')" \
  "$(grep -n -E '[|]=>|^bind' "$SVA" | cut -d: -f1 | tr '\n' ' ')"
cat > imm.sv <<'EOF'
module imm;
  logic a = 1'b1, q = 1'b1;
  initial begin
    assert (!(a && q)) else $error("a and q");
    $finish;
  end
endmodule
EOF
iverilog -g2012 -o imm.vvp imm.sv > /dev/null 2>&1 && vvp -n imm.vvp > imm.log 2>&1
check "Icarus, immediate assertion with \$error, exit status" "$?" "0"
check "Icarus prints the error" "$(grep -c '^ERROR: imm.sv' imm.log)" "1"
yosys -q -p "read_verilog -sv conc.sv" > y1.log 2>&1
check "Yosys read_verilog, concurrent assertion" "$(grep -o "syntax error, unexpected '@'" y1.log)" "syntax error, unexpected '@'"
cat > imm_ff.sv <<'EOF'
module imm_ff (input logic clk_i, a_i, output logic q_o);
  always_ff @(posedge clk_i) begin
    q_o <= a_i;
    assert (!(a_i && q_o)) else $error("a and q");
  end
endmodule
EOF
yosys -q -p "read_verilog -sv imm_ff.sv" > y2.log 2>&1
check "Yosys read_verilog, immediate assertion with else" "$(grep -o 'syntax error, unexpected TOK_ELSE' y2.log)" "syntax error, unexpected TOK_ELSE"
yosys -q -p "plugin -i slang; read_slang $W/fifo/rtl/fifo.sv $W/fifo/testbenches/sva/fifo_sva.sv --top fifo" > y3.log 2>&1
check "Yosys slang, the checker" "$(grep -o -m1 'unsupported SVA feature' y3.log)" "unsupported SVA feature"
yosys -q -p "plugin -i slang; read_slang imm_ff.sv --top imm_ff; synth -top imm_ff" > y4.log 2>&1
check "Yosys slang, immediate assertion with else, exit status" "$?" "0"
check "sby in the image" "$(command -v sby > /dev/null && echo yes)" "yes"
cd "$W"

echo "== FIFO: mutants (seed 1)"
for m in 1 2 3 4 5 6; do
  rm -rf "mut$m" && cp -r fifo "mut$m" && cd "mut$m" && mutate $m
  check "M$m differs from the original" "$(diff -q rtl/fifo.sv ../fifo/rtl/fifo.sv > /dev/null || echo yes)" "yes"
  cd testbenches/cocotb
  COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > sb.log 2>&1
  COCOTB_RANDOM_SEED=1 CHECK=0 python3 fifo_tb.py > nochk.log 2>&1
  SIM=verilator SVA=1 CHECK=0 COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > sva.log 2>&1
  case $m in
    1) d=PASS; r=FAIL; a="[1200000] a_room"; e="full_o = 1, 3 entries" ;;
    2) d=PASS; r=FAIL; a="[300000] a_level"; e="empty_o = 0, 0 entries" ;;
    3) d=PASS; r=FAIL; a="[1200000] a_room"; e="full_o = 1, 3 entries" ;;
    4) d=PASS; r=FAIL; a="[2380000] a_head"; e="data_o = 10111011, expected 11011000" ;;
    5) d=FAIL; r=FAIL; a="[120000] a_flags"; e="empty_o = 1, 4 entries" ;;
    6) d=PASS; r=PASS; a=""; e="" ;;
  esac
  check "M$m directed test" "$(verdict sb.log test_fill_and_drain)" "$d"
  check "M$m random test" "$(verdict sb.log test_random)" "$r"
  check "M$m first scoreboard message" "$(grep -m1 -o 'AssertionError: .*' sb.log | sed 's/AssertionError: //')" "$e"
  check "M$m assertions only, first failure" \
    "$(grep -m1 'Assertion failed' sva.log | sed 's/\(\[[0-9]*\]\).*fifo\.u_sva\.\([a-z_]*\):.*/\1 \2/')" "$a"
  check "M$m Icarus without checks" "$(summary nochk.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
  if [ $m -eq 5 ]; then
    check "M5 assertion: SimFailure for both tests, then a traceback" \
      "$(grep -c 'SimFailure: cocotb expected it would shut down the simulation' sva.log) \
$(grep -c '^RuntimeError' sva.log) $(grep -c '^FAIL:' sva.log)" "2 1 0"
  fi
  # Solution of the exercise: three more transactions in the directed test
  python3 - fifo_tb.py <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """    await driver(dut, [(1, v, 0) for v in values]
                 + [(0, 0, 1)] * DEPTH)
"""
new = """    await driver(dut, [(1, v, 0) for v in values]
                 + [(1, 0x55, 0), (1, 0x66, 1)]
                 + [(0, 0, 1)] * DEPTH
                 + [(1, 0x77, 1)])
"""
assert old in s
open(p, "w").write(s.replace(old, new))
EOF
  COCOTB_TEST_FILTER=test_fill_and_drain python3 fifo_tb.py > ext.log 2>&1
  [ $m -eq 6 ] && e=PASS || e=FAIL
  check "M$m extended directed test" "$(verdict ext.log test_fill_and_drain)" "$e"
  cd "$W"
done
check "M4: scoreboard fails in test_random at test time (ns)" \
  "$(grep -E 'test_random +FAIL' mut4/testbenches/cocotb/sb.log | awk '{print $4}')" "2150.00"
check "M4: test_random starts at (ns)" \
  "$(grep -E 'test_fill_and_drain +PASS' mut4/testbenches/cocotb/sb.log | awk '{print $4}')" "220.00"
cd "$W/fifo/testbenches/cocotb"
cp fifo_tb.py fifo_tb.orig
python3 - fifo_tb.py <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """    await driver(dut, [(1, v, 0) for v in values]
                 + [(0, 0, 1)] * DEPTH)
"""
new = """    await driver(dut, [(1, v, 0) for v in values]
                 + [(1, 0x55, 0), (1, 0x66, 1)]
                 + [(0, 0, 1)] * DEPTH
                 + [(1, 0x77, 1)])
"""
open(p, "w").write(s.replace(old, new))
EOF
COCOTB_TEST_FILTER=test_fill_and_drain python3 fifo_tb.py > ext0.log 2>&1
check "extended directed test, original design" "$(verdict ext0.log test_fill_and_drain)" "PASS"
check "extended directed test, coverage bins" "$(bins ext0.log 1)" "0 2 0 1 3 1 1 3 0 1 0 1 "
cp fifo_tb.orig fifo_tb.py
cd "$W"

echo "== FIFO: gate-level simulation"
cd fifo
yosys -q -l syn.log -p "read_verilog -sv rtl/fifo.sv; synth -top fifo; \
  dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB; \
  write_verilog -noattr fifo.nl.v" > /dev/null
check "cells" "$(sed -n '/Chip area/q;p' syn.log | awk '/ cells$/ {n=$1} END {print n}')" "103"
check "flip-flops dfrbpq_1" "$(sed -n '/Chip area/q;p' syn.log | awk '$NF=="sg13cmos5l_dfrbpq_1" {n=$1} END {print n}')" "38"
check "mux2_1" "$(sed -n '/Chip area/q;p' syn.log | awk '$NF=="sg13cmos5l_mux2_1" {n=$1} END {print n}')" "32"
check "mux4_1" "$(sed -n '/Chip area/q;p' syn.log | awk '$NF=="sg13cmos5l_mux4_1" {n=$1} END {print n}')" "8"
check "area (um2)" "$(grep 'Chip area' syn.log | tail -1 | awk '{print $NF}')" "3008.275200"
check "flip-flops with RESET_B tied to 1 (storage)" "$(grep -c "RESET_B(1'h1)" fifo.nl.v)" "32"
cat > x_after_reset.sv <<'EOF'
`timescale 1ns/1ps
module x_after_reset;
  logic clk = 0, rst_n = 0;
  wire [7:0] dout;
  wire full, empty;
  fifo u_fifo (.clk_i(clk), .rst_ni(rst_n), .push_i(1'b0), .data_i(8'h00),
               .pop_i(1'b0), .data_o(dout), .full_o(full), .empty_o(empty));
  always #10 clk = ~clk;
  initial begin
    #35 rst_n = 1;
    #20 $display("empty=%b full=%b data_o=%b", empty, full, dout);
    $finish;
  end
endmodule
EOF
iverilog -g2012 -o rtl_x.vvp rtl/fifo.sv x_after_reset.sv > /dev/null 2>&1
check "RTL after reset" "$(vvp -n rtl_x.vvp | grep empty=)" "empty=1 full=0 data_o=xxxxxxxx"
iverilog -g2012 -gno-specify -o gl_x.vvp $CELLS/sg13cmos5l_udp.v $CELLS/sg13cmos5l_stdcell.v \
  fifo.nl.v x_after_reset.sv > /dev/null 2>&1
check "netlist after reset" "$(vvp -n gl_x.vvp | grep empty=)" "empty=1 full=0 data_o=xxxxxxxx"
cd testbenches/cocotb
GL=1 COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > gl.log 2>&1
check "netlist, zero delay" "$(summary gl.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
check "netlist, Icarus sorry messages of the cell models" "$(grep -c 'sorry: ifnone' gl.log)" "68"
cd "$W/fifo"

echo "== FIFO: static timing analysis and timing simulation"
sta -no_init -exit syn/sta.tcl > sta20.log 2>&1
check "worst slack at 20 ns" "$(grep 'worst slack' sta20.log | awk '{print $NF}')" "8.863"
check "critical path start" "$(awk '/^Startpoint/ {s=$2} /^Path Group: clk/ {print s; exit}' sta20.log)" "push_i"
check "critical path through nor4_1 (ns)" \
  "$(sed -n '/^Startpoint: push_i/,/slack/p' sta20.log | awk '/sg13cmos5l_nor4_1/ {print $1}')" "0.66"
nor4=$(sed -n '/^Startpoint: push_i/,/slack/p' sta20.log | grep -o '_[0-9]*_/Y (sg13cmos5l_nor4_1)' | cut -d/ -f1)
net=$(grep -A6 "sg13cmos5l_nor4_1 $nor4 " fifo.nl.v | grep -o '\.Y([^)]*)' | sed 's/\.Y(\(.*\))/\1/')
check "the nor4_1 drives the select inputs of mux2_1 cells" "$(grep -c "\.S($net)" fifo.nl.v)" "8"
check "critical path arrival (ns)" \
  "$(sed -n '/^Startpoint: push_i/,/slack/p' sta20.log | awk '/data arrival time/ {print $1; exit}')" "11.01"
check "setup time of the flip-flop (ns)" \
  "$(sed -n '/^Startpoint: push_i/,/slack/p' sta20.log | awk '/library setup time/ {print $1}')" "-0.13"
check "SDF: INTERCONNECT entries left" "$(grep -c INTERCONNECT fifo.sdf)" "0"
check "SDF: VOLTAGE line left" "$(grep -c VOLTAGE fifo.sdf)" "0"
check "SDF: cells" "$(grep -c CELLTYPE fifo.sdf)" "103"
echo "  info  SDF of one flip-flop:"
grep -m1 -A16 'CELLTYPE "sg13cmos5l_dfrbpq_1"' fifo.sdf | sed 's/^/        /'
cd testbenches/cocotb
GL=1 SDF=1 COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > sdf20.log 2>&1
check "timing simulation at 20 ns" "$(summary sdf20.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
check "SDF errors" "$(grep -c 'SDF ERROR' sdf20.log)" "0"
check "SDF warnings TIMINGCHECK not supported" "$(grep -c 'TIMINGCHECK not supported' sdf20.log)" "38"
cd "$W/fifo"

# Delay probe: when do empty_o and data_o change after the clock edge?
cat > delay.sv <<'EOF'
`timescale 1ns/1ps
module delay;
  logic clk = 0, rst_n = 0, push = 0;
  wire [7:0] dout;
  wire full, empty;
  realtime t_edge;
  fifo u_fifo (.clk_i(clk), .rst_ni(rst_n), .push_i(push), .data_i(8'ha5),
               .pop_i(1'b0), .data_o(dout), .full_o(full), .empty_o(empty));
  initial $sdf_annotate("fifo.sdf", u_fifo);
  always #10 clk = ~clk;
  always @(posedge clk) t_edge = $realtime;
  always @(negedge empty) $display("empty_o %.3f", $realtime - t_edge);
  initial begin
    #15 rst_n = 1;
    @(negedge clk) push = 1;
    @(negedge clk) push = 0;
    #20 $finish;
  end
endmodule
EOF
iverilog -g2012 -gspecify -o delay.vvp $CELLS/sg13cmos5l_udp.v $CELLS/sg13cmos5l_stdcell.v \
  fifo.nl.v delay.sv > /dev/null 2>&1
check "with typical values: empty_o falls after the edge (ns)" "$(vvp -n delay.vvp 2>/dev/null | grep empty_o)" "empty_o 0.440"
# Without -include_typ, OpenSTA writes (min::max), and Icarus annotates nothing
sed 's/write_sdf -include_typ/write_sdf/' syn/sta.tcl > sta_notyp.tcl
sta -no_init -exit sta_notyp.tcl > /dev/null 2>&1
check "without -include_typ: delay triples" "$(grep -m1 -o 'IOPATH A Y ([0-9.]*::[0-9.]*)' fifo.sdf | grep -c '::')" "1"
check "without -include_typ: empty_o falls after the edge (ns)" "$(vvp -n delay.vvp 2>/dev/null | grep empty_o)" "empty_o 0.000"

for p in 2.28 2.27; do
  CLK_PERIOD_NS=$p sta -no_init -exit syn/sta.tcl > sta_$p.log 2>&1
done
check "worst slack at 2.28 ns" "$(grep 'worst slack' sta_2.28.log | awk '{print $NF}')" "0.003"
check "worst slack at 2.27 ns" "$(grep 'worst slack' sta_2.27.log | awk '{print $NF}')" "-0.002"
cat > out.tcl <<EOF
read_liberty $LIB
read_verilog fifo.nl.v
link_design fifo
create_clock -name clk -period 20 [get_ports clk_i]
set_input_delay 10 -clock clk [delete_from_list [all_inputs] [get_ports clk_i]]
set_output_delay 10 -clock clk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]
report_checks -path_delay max -to [all_outputs] -format end
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -format end
EOF
sta -no_init -exit out.tcl > out.log 2>&1
check "slowest output path (ns)" "$(awk '/\(output\)/ {print $1, $4}' out.log)" "full_o 0.93"
check "slowest register-to-register path (ns)" "$(awk '/\(sg13cmos5l_dfrbpq_1\)/ {print $4}' out.log)" "1.75"
# The critical path in the SDF: STA uses the maximum values and the state-dependent (COND) arc of the
# mux2_1, Icarus the typical values and the default arc
sta -no_init -exit syn/sta.tcl > sta20b.log 2>&1
path=$(sed -n '/^Startpoint: push_i/,/data arrival/p' sta20b.log)
mux=$(echo "$path" | grep -o '_[0-9]*_/X (sg13cmos5l_mux2_1)' | cut -d/ -f1)
check "critical path: inv_1, nor4_1, mux2_1 delays (ns)" \
  "$(echo "$path" | awk '/sg13cmos5l_(inv_1|nor4_1|mux2_1)/ {printf "%s ", $1}')" "0.06 0.66 0.29 "
check "nor4_1 rising input C: min:typ:max" \
  "$(grep -A6 "(INSTANCE $nor4)" fifo.sdf | grep -o 'IOPATH C Y ([0-9.:]*)' | sed 's/IOPATH C Y //')" "(0.507:0.584:0.661)"
check "mux2_1 S to X, default arc: rise and fall" \
  "$(grep -A9 "(INSTANCE $mux)" fifo.sdf | grep '^    (IOPATH S X' | sed 's/^ *//')" \
  "(IOPATH S X (0.122:0.130:0.137) (0.242:0.253:0.265))"
check "mux2_1 S to X, COND A0=1 A1=0: fall" \
  "$(grep -A9 "(INSTANCE $mux)" fifo.sdf | grep -A1 "COND A0 == 1'b1 && A1 == 1'b0" | grep -o '(0[.0-9:]*))' | tail -1)" "(0.268:0.279:0.290))"
check "typical value is the mean of min and max" \
  "$(echo "0.533 0.691" | awk '{printf "%.3f", ($1 + $2) / 2}')" \
  "$(grep -A6 "(INSTANCE $nor4)" fifo.sdf | grep -o 'IOPATH A Y ([0-9.:]*)' | cut -d: -f2)"
# The first push at half periods of 0.85 and 0.90 ns: entry 0 keeps x in the late bits
cat > first_push.sv <<'EOF'
`timescale 1ns/1ps
module first_push;
  parameter real HALF = 0.85;
  logic clk = 0, rst_n = 0, push = 0;
  logic [7:0] din = 0;
  wire [7:0] dout;
  wire full, empty;
  fifo u_fifo (.clk_i(clk), .rst_ni(rst_n), .push_i(push), .data_i(din),
               .pop_i(1'b0), .data_o(dout), .full_o(full), .empty_o(empty));
  initial $sdf_annotate("fifo.sdf", u_fifo);
  always #(HALF) clk = ~clk;
  initial begin
    #(4*HALF) rst_n = 1;
    @(negedge clk) begin push = 1; din = 8'h11; end
    @(negedge clk) push = 0;
    repeat (2) @(negedge clk);
    #(2*HALF - 0.01) $display("data_o=%b", dout);
    $finish;
  end
endmodule
EOF
for h in 0.85 0.90; do
  iverilog -g2012 -gspecify -P first_push.HALF=$h -o fp.vvp $CELLS/sg13cmos5l_udp.v \
    $CELLS/sg13cmos5l_stdcell.v fifo.nl.v first_push.sv > /dev/null 2>&1
  echo "$h $(vvp -n fp.vvp 2>/dev/null | grep data_o)" >> first_push.txt
done
check "first push, half period 0.85 ns, entry 0 two cycles later" "$(grep '^0.85' first_push.txt | cut -d' ' -f2)" "data_o=xxx1xxx1"
check "first push, half period 0.90 ns, entry 0 two cycles later" "$(grep '^0.90' first_push.txt | cut -d' ' -f2)" "data_o=00010001"
sta -no_init -exit syn/sta.tcl > /dev/null 2>&1
cd testbenches/cocotb
for p in 2.2 2.0; do
  GL=1 SDF=1 CLK_PERIOD_NS=$p COCOTB_RANDOM_SEED=1 python3 fifo_tb.py > sdf_$p.log 2>&1
  check "timing simulation at $p ns, seed 1" "$(summary sdf_$p.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
done
for s in 1 2 3 4 5; do
  GL=1 SDF=1 CLK_PERIOD_NS=1.8 COCOTB_RANDOM_SEED=$s python3 fifo_tb.py > sdf18_$s.log 2>&1
  check "timing simulation at 1.8 ns, seed $s" "$(summary sdf18_$s.log)" "TESTS=2 PASS=2 FAIL=0 SKIP=0"
  GL=1 SDF=1 CLK_PERIOD_NS=1.7 COCOTB_RANDOM_SEED=$s python3 fifo_tb.py > sdf17_$s.log 2>&1
  check "timing simulation at 1.7 ns, seed $s, directed test" "$(verdict sdf17_$s.log test_fill_and_drain)" "FAIL"
done
check "timing simulation at 1.7 ns, first error" "$(grep -m1 -o 'AssertionError: .*' sdf17_1.log)" \
  "AssertionError: data_o = XXX1XXX1, expected 00010001"
cd "$W"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all results match the chapter"
else
  echo "FAIL: $fails result(s) differ from the chapter"
  exit 1
fi
