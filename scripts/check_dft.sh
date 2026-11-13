#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "Design for
# Test (DFT)" quotes, inside the IIC-OSIC-TOOLS container (image
# 2026.10). Run from the repository root:
#   bash scripts/check_dft.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter. The fault
# simulation of all cell pins through the scan chain takes about two
# minutes, the placement of the 32-bit bs_reg about one.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${CHECK_DIR:-/tmp/vlsi_check_dft}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
CELLS=$D/verilog
export SWIFT_DETERMINISTIC_HASHING=1 FAULT_THREADS=4  # as in the chapter
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in dft sequential verification synthesis_lib cdc synth_opt; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
A=$W/content/dft/code/atpg
S=$W/content/dft/code/scan
R=$W/content/dft/code/reset
X=$W/content/dft/code/transistor
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

calc() { awk "BEGIN { $1 }"; }

lint() {  # lint <files>: number of Verilator warnings and errors
  verilator --lint-only -Wall "$@" 2>&1 | grep -c -E '%Warning|%Error'
}

area() {  # area <log>: the chip area of the last stat -liberty
  grep -oE 'Chip area for (top )?module .*: [0-9.]+' "$1" | tail -1 | awk '{print $NF}'
}

ctype() {  # ctype <log> <type>: count of one cell type in the last stat
  awk -v t="$2" '$NF == t { n = $1 } END { print n }' "$1"
}

libarea() {  # libarea <cell>: area of a cell in the typical library
  awk -v c="cell (sg13cmos5l_$1)" 'index($0, c) { on = 1; next }
       on && /area :/ { gsub(";", ""); print $3; exit }' "$LIB"
}

satest() {  # satest <netlist> <top> <pins> <sa>: the test as (a, b, c) or none
  NETLIST=$1 TOP=$2 PINS="$3" SA=$4 yosys -q -c "$A/sat_test.tcl" | awk '
    /NO TEST/ { print "none"; exit }
    / = / { v[$1] = $3; n++ }
    END { if ("a_i" in v) print "(" v["a_i"] ", " v["b_i"] ", " v["c_i"] ")"
          else if (n > 0) print "found" }'
}

uncovered() {  # uncovered <yml> <sa0|sa1>: faults not covered, names without backslash
  python3 - "$1" "$2" << 'EOF'
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
n = lambda s: s.lstrip('\\').strip()
print(' '.join(sorted(set(map(n, y['faultPoints']))
                      - set(map(n, y[sys.argv[2] + 'Covered'])))))
EOF
}

tb() {  # tb <netlist> <iverilog options...>: the two result lines of tb_scan
  local nl=$1; shift
  iverilog -g2012 -gno-specify "$@" -o tb.vvp "$CELLS/sg13cmos5l_udp.v" \
    "$CELLS/sg13cmos5l_stdcell.v" "$nl" "$S/tb/tb_scan.sv" > /dev/null 2>&1
  vvp -n tb.vvp | grep -E '^(chain|scan) test' | tr '\n' ';'
}

echo "== Versions"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "OpenSTA" "$(sta -version)" "3.1.0"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"
check "Fault" "$(fault --version 2>/dev/null)" "0.9.4"
check "ngspice" "$(ngspice -v 2>&1 | grep -o 'ngspice-[0-9]*' | head -1)" "ngspice-47"

echo "== Defect level and the cost of exhaustive and random tests"
check "DL at 80 % yield, 99 % coverage: percent, ppm, one in" \
  "$(calc 'd = 1 - exp(0.01 * log(0.8)); printf "%.2f %.0f %.0f", 100 * d, 1e6 * d, 1 / d')" "0.22 2229 449"
check "coverage for 100 ppm at 80 % yield" \
  "$(calc 'printf "%.3f", 100 * (1 - log(1 - 1e-4) / log(0.8))')" "99.955"
check "barrel shifter of chapter 4: input bits" "$(calc 'printf "%d", 32 + 5 + 2')" "39"
check "exhaustive: vectors, hours at 100 MHz" \
  "$(calc 'n = 2 ^ 39; printf "%.1e %.1f", n, n / 1e8 / 3600')" "5.5e+11 1.5"
check "16-bit comparator: detection by 1000 vectors, vectors for 99 %" \
  "$(calc 'p = 2 ^ -16; printf "%.1f %.1e", 100 * (1 - exp(1000 * log(1 - p))), log(0.01) / log(1 - p)')" \
  "1.5 3.0e+05"

echo "== Cells of SG13CMOS5L"
check "scan flip-flops (test_cell groups)" \
  "$(awk '/^ *cell \(/ {c = $2} /test_cell \(\)/ {print c}' "$LIB" | tr -d '()' | tr '\n' ' ')" \
  "sg13cmos5l_sdfbbp_1 sg13cmos5l_sdfrbp_1 sg13cmos5l_sdfrbp_2 sg13cmos5l_sdfrbpq_1 sg13cmos5l_sdfrbpq_2 "
check "areas of sdfrbpq_1, dfrbpq_1, mux2_1" \
  "$(libarea sdfrbpq_1) $(libarea dfrbpq_1) $(libarea mux2_1)" "63.504 48.9888 18.144"
check "scan flip-flop: percent more, flip-flop plus mux" \
  "$(calc 'printf "%.0f %.1f", (63.504 / 48.9888 - 1) * 100, 48.9888 + 18.144')" "30 67.1"
check "areas of slgcp_1, lgcp_1" "$(libarea slgcp_1) $(libarea lgcp_1)" "30.8448 27.216"
check "pins of sdfrbpq_1: no separate scan output" \
  "$(awk '/cell \(sg13cmos5l_sdfrbpq_1\)/ {on = 1} on && /^ *pin *\(/ {gsub(/[()"{ ]/, ""); sub(/pin/, ""); print} on && /cell \(sg13cmos5l_sdfrbpq_2\)/ {exit}' "$LIB" | sort -u | tr '\n' ' ')" \
  "CLK D Q RESET_B SCD SCE "
check "slgcp_1: integrated cell type, test pin" \
  "$(awk '/cell \(sg13cmos5l_slgcp_1\)/ {on = 1} on && /clock_gating_integrated_cell/ {print $3} on && /clock_gate_test_pin/ {print p} {p = $0} on && /^  cell \(sg13cmos5l_[^s]/ {exit}' "$LIB" | tr -d '";' | sed 's/.*pin (\(.*\)) {/\1/' | tr '\n' ' ')" \
  "latch_posedge_precontrol SCE "

echo "== Exercise: Transistor Faults"
cd "$X"
check "nor2_1: transistors, gates, widths" \
  "$(awk '/^\.subckt sg13cmos5l_nor2_1 /, /^\.ends/' "$D/spice/sg13cmos5l_stdcell.spice" | awk '/^X/ {print $1, $3, $7}' | tr '\n' ' ')" \
  "XN0 A w=740.00n XN1 B w=740.00n XP0 A w=1.12u XP1 B w=1.12u "
check "nor2_1: drain of XP0, source of XP1, both at Y: XN0 and XN1 drains, XP1 drain" \
  "$(awk '/^\.subckt sg13cmos5l_nor2_1 /, /^\.ends/' "$D/spice/sg13cmos5l_stdcell.spice" | awk '$1 == "XP0" {a = $2} $1 == "XP1" {b = $4; c = $2} $1 == "XN0" {d = $2} $1 == "XN1" {e = $2} END {print a, b, d, e, c}')" \
  "net1 net1 Y Y Y"
for f in good n_open n_on p_on; do
  python3 nor2_faults.py $f > nor2_$f.txt 2>&1
done
yz() {  # yz <fault>: Y/Z at the end of each vector
  awk 'NR > 2 {y = $2 + 0; z = $3 + 0; printf "%.3f/%.3f ", y == 0 ? 0 : y, z == 0 ? 0 : z}' "nor2_$1.txt"
}
iddq() { awk 'NR > 2 {printf "%s %s, ", $4, $5}' "nor2_$1.txt"; }
check "vectors" "$(awk 'NR > 2 {print $1}' nor2_good.txt | tr '\n' ' ')" "00 10 11 10 00 01 "
check "good: Y/Z" "$(yz good)" \
  "1.200/0.000 0.000/1.200 0.000/1.200 0.000/1.200 1.200/0.000 0.000/1.200 "
check "XN0 stuck-open: Y/Z" "$(yz n_open)" \
  "1.200/0.000 1.279/0.000 0.000/1.200 0.080/1.200 1.200/0.000 0.000/1.200 "
check "XN0 stuck-on: Y/Z" "$(yz n_on)" \
  "0.121/1.200 0.000/1.200 0.000/1.200 0.000/1.200 0.121/1.200 0.000/1.200 "
check "XP0 stuck-on: Y/Z" "$(yz p_on)" \
  "1.200/0.000 0.121/1.200 0.000/1.200 0.121/1.200 1.200/0.000 0.000/1.200 "
check "IDDQ good" "$(iddq good)" "138 pA, 76 pA, 48 pA, 76 pA, 138 pA, 99 pA, "
check "IDDQ XN0 stuck-open" "$(iddq n_open)" "120 pA, 328 nA, 48 pA, 328 nA, 120 pA, 99 pA, "
check "IDDQ XN0 stuck-on" "$(iddq n_on)" "108 uA, 96.2 pA, 68.2 pA, 96.2 pA, 108 uA, 119 pA, "
check "IDDQ XP0 stuck-on" "$(iddq p_on)" "138 pA, 108 uA, 99 pA, 108 uA, 138 pA, 99 pA, "
check "delay A to Z at 00 -> 10, good and XP0 stuck-on (ps)" \
  "$(python3 -I -c "
import sys; sys.path.insert(0, '.')
import nor2_faults as n
for f in ('good', 'p_on'):
    out = n.ngspice(f, n.pwl('01'), n.pwl('00'), '.tran 1e-13 4e-9\n.meas tran d trig v(a) val=0.6 rise=1 targ v(z) val=0.6 rise=1')
    print(f\"{[float(l.split()[2]) for l in out.splitlines() if l.split()[:1] == ['d']][0] * 1e12:.1f}\", end=' ')")" \
  "79.7 92.1 "
check "overshoot above VDD (mV), 108 uA / 76 pA" \
  "$(calc 'printf "%.0f %.1e", (1.279 - 1.2) * 1000, 108e-6 / 76e-12')" "79 1.4e+06"
HOLD=1 SEQ="00 10" python3 nor2_faults.py n_open > nor2_hold.txt 2>&1
check "stuck-open, 10 after 00: Y after 1 ns, 1 us, 1 ms, 1 s" \
  "$(awk 'NR > 2 {print $2}' nor2_hold.txt | tr '\n' ' ')" "1.279 1.254 0.857 0.857 "
check "stuck-open, 10 after 00: samples of Z, those above 0.01 V" \
  "$(awk 'NR > 2 {n++; if ($3 > 0.01) bad++} END {print n + 0, bad + 0}' nor2_hold.txt)" "4 0"
HOLD=1 SEQ="11 10" python3 nor2_faults.py n_open > nor2_hold2.txt 2>&1
check "stuck-open, 10 after 11: Y after 1 ns, 1 us, 1 ms, 1 s" \
  "$(awk 'NR > 2 {print $2}' nor2_hold2.txt | tr '\n' ' ')" "0.071 0.160 0.857 0.857 "
check "stuck-open, 10 after 11: Z after 1 us, 1 ms" \
  "$(awk 'NR == 4 || NR == 5 {printf "%.3f ", $3}' nor2_hold2.txt)" "1.200 0.001 "
check "HOLD without SEQ stops" "$(HOLD=1 python3 nor2_faults.py n_open > /dev/null 2>&1; echo $?)" "1"
check "stuck-open at 10: operating point Y (V), IDDQ" \
  "$(python3 -I -c "
import sys; sys.path.insert(0, '.')
import nor2_faults as n
out = n.ngspice('n_open', 1.2, 0.0, '.op').splitlines()
v = {l.split()[0]: float(l.split()[1]) for l in out if len(l.split()) == 2 and l.split()[0] in ('y', 'vdd#branch')}
print(f\"{v['y']:.3f} {n.amps(-v['vdd#branch'])}\")")" "0.857 328 nA"
check "stuck-open: Y after 00 -> 10 with 0, 20 fF more at Y" \
  "$(python3 -I -c "
import sys; sys.path.insert(0, '.')
import nor2_faults as n
base = n.DECK
for c in ('1e-24', '20f'):
    n.DECK = base.replace('CL z 0 5f', 'CL z 0 5f\nCY y 0 ' + c)
    print(f\"{n.tran('n_open', ['00', '10'], 4e-9, 1e-12, [3.95e-9])[0][0]:.3f}\", end=' ')")" \
  "1.279 1.225 "

echo "== The D-algorithm"
check "table of the chapter equals the gates on good/faulty pairs" \
  "$(python3 - "$W/content/dft/_sec_dft.qmd" << 'EOF'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
rows = re.search(r'\| \$a\$ \| \$b\$ \| \$a\$ AND.*?\n\n', text, re.S).group(0)
val = {'0': [(0, 0)], '1': [(1, 1)], '$D$': [(1, 0)], r'$\bar{D}$': [(0, 1)],
       '$X$': [(0, 0), (1, 1)]}
name = {v[0]: k for k, v in val.items() if len(v) == 1}
ops = [lambda p, q: p & q, lambda p, q: p | q, lambda p, q: p ^ q]
bad = 0
lines = [l for l in rows.splitlines() if l.strip()][2:]
for line in lines:
    c = [s.strip() for s in line.strip('|').split('|')]
    for op, want in zip(ops, c[2:]):
        res = {(op(a[0], b[0]), op(a[1], b[1])) for a in val[c[0]] for b in val[c[1]]}
        got = name[res.pop()] if len(res) == 1 else '$X$'
        bad += got != want
print(len(lines), 'rows,', bad, 'wrong')
EOF
)" "5 rows, 0 wrong"
check "fig-dft-sensitize: all tests for the inverter output s-a-0 (a, b, c, d)" \
  "$(python3 -c "
import itertools
def y(a, b, c, d, f):
    n1 = 0 if f else 1 - c
    return 1 - ((1 - (d & n1)) | (a | b))
print([v for v in itertools.product((0, 1), repeat=4) if y(*v, 0) != y(*v, 1)])")" "[(0, 0, 0, 1)]"

echo "== Exercise: Find the Test"
cd "$A"
check "SAT: ab s-a-0, a_n s-a-1, bc s-a-1, bc s-a-0" \
  "$(satest cons.v cons u_or/A 0) $(satest cons.v cons u_anc/A 1) $(satest cons.v cons u_or/C 1) $(satest cons.v cons u_or/C 0)" \
  "(1, 1, 0) (1, 0, 1) (0, 0, 0) none"
check "SAT: b_i s-a-0, b_i s-a-1, u_bc.A s-a-0" \
  "$(satest cons.v cons 'u_ab/B u_bc/A' 0) $(satest cons.v cons 'u_ab/B u_bc/A' 1) $(satest cons.v cons u_bc/A 0)" \
  "(1, 1, 1) (1, 0, 0) none"
cat > force.sv << 'EOF'
module force_tb;
  logic a = 1'b0, b = 1'b0, c = 1'b1, y;
  cons dut (.clk_i(1'b0), .rst_ni(1'b1), .a_i(a), .b_i(b), .c_i(c),
            .y_o(y));
  initial begin
    force dut.u_bc.B = 1'b0;
    #1 $display("%b %b %b", dut.c_i, dut.u_anc.B, y);
  end
endmodule
EOF
iverilog -g2012 -gno-specify -o force.vvp "$CELLS/sg13cmos5l_udp.v" \
  "$CELLS/sg13cmos5l_stdcell.v" cons.v force.sv > /dev/null 2>&1
check "force on u_bc.B reaches c_i, u_anc.B, and y" "$(vvp -n force.vvp)" "0 0 0"
fault atpg cons.v -c "$CELLS/sg13cmos5l_stdcell.v" \
  -I "$CELLS/sg13cmos5l_udp.v" --clock clk_i --reset rst_ni \
  --activeLow -v 8 -m 100 --ceiling 32 -o cons.tv.json \
  --output-coverage-metadata cons.cov.yml > cons.log 2>&1
check "Fault on cons: sites, coverage, compacted vectors" \
  "$(grep -o 'Found [0-9]* fault sites' cons.log | awk '{print $2}') $(grep -o 'Coverage [0-9.]*' cons.log | awk '{printf "%.2f", $2}') $(grep -o 'Compacted TV Count: [0-9]*' cons.log | awk '{print $4}')" \
  "19 94.74 4"
check "Fault on cons: undetected s-a-0, s-a-1" \
  "$(uncovered cons.cov.yml sa0) / $(uncovered cons.cov.yml sa1)" "u_bc.X u_or.C / "
check "Fault on cons: sa0Uncovered, sa1Uncovered as written" \
  "$(python3 -c "import yaml; y = yaml.safe_load(open('cons.cov.yml')); print(sorted(y['sa0Uncovered']), sorted(y['sa1Uncovered']))")" \
  "['u_bc.X', 'u_or.C'] ['u_bc.X', 'u_or.C']"
check "Fault on cons: the compacted vectors (a, b, c)" \
  "$(python3 -c "import json; d = json.load(open('cons.tv.json')); print(' '.join('(%d, %d, %d)' % tuple(v[1] for v in e['vector']) for e in d['coverageList']))")" \
  "(0, 0, 1) (1, 0, 1) (0, 1, 0) (1, 1, 0)"
fault atpg cons.v -c "$CELLS/sg13cmos5l_stdcell.v" \
  -I "$CELLS/sg13cmos5l_udp.v" --clock clk_i --reset rst_ni \
  --activeLow -v 8 -m 100 --ceiling 32 -o cons2.tv.json > cons2.log 2>&1
check "Fault on cons: the same vectors in a second run" \
  "$(python3 -c "import json; a, b = (json.load(open(f))['coverageList'] for f in ('cons.tv.json', 'cons2.tv.json')); print([e['vector'] for e in a] == [e['vector'] for e in b])")" "True"
check "collapsing rule on cons: P_O F_O G_I N_I, faults left" \
  "$(python3 - << 'EOF'
import re
s = open('cons.v').read()
cells = re.findall(r'sg13cmos5l_(\w+)\s+\w+\s*\((.*?)\);', s, re.S)
ins = [n for t, b in cells for p, n in re.findall(r'\.(\w+)\((\w+)\)', b)
       if p not in ('X', 'Y')]
po = len(re.findall(r'output\s+wire', s))
fo = sum(ins.count(n) > 1 for n in set(ins))
gi = len(ins)
ni = sum(t.startswith('inv') for t, b in cells)
print(po, fo, gi, ni, 2 * (po + fo) + gi - ni)
EOF
)" "1 3 10 1 17"
python3 collapse.py cons.v > collapse.log 2>&1
check "collapse.py: faults, sites, groups" \
  "$(head -2 collapse.log | tr '\n' ' ')" \
  "28 faults at 14 sites (8 nets, 6 branches) 13 classes with the same outputs for all 8 input vectors: "
check "collapse.py: the groups of more than one fault" \
  "$(tail -n +3 collapse.log | grep ',' | sed 's/^ *//' | tr '\n' ';')" \
  "b_i s-a-1, u_ab.B s-a-1;c_i s-a-1, u_anc.B s-a-1;a_n s-a-0, anc s-a-0, u_inv.A s-a-1, u_anc.B s-a-0;a_n s-a-1, u_inv.A s-a-0, u_bc.A s-a-1;ab s-a-0, u_ab.A s-a-0, u_ab.B s-a-0;ab s-a-1, anc s-a-1, bc s-a-1, y_o s-a-1;untestable: bc s-a-0, u_bc.A s-a-0, u_bc.B s-a-0;u_ab.A s-a-1, u_bc.B s-a-1;"

echo "== bs_reg with 8 bits: synthesis and ATPG"
cd "$S"
yosys -p "read_verilog -sv \
  ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
  ../../../sequential/code/bs_reg/rtl/bs_reg.sv; \
  chparam -set WIDTH 8 bs_reg; synth -top bs_reg; flatten; \
  dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; \
  opt_clean; stat -liberty $LIB; write_verilog -noattr bs_reg.nl.v" > syn.log 2>&1
check "bs_reg: flip-flops, area" "$(ctype syn.log sg13cmos5l_dfrbpq_1) $(area syn.log)" "21 2543.448600"
fault cut bs_reg.nl.v --sclConfig scl.yml --clock clk_i \
  --reset rst_ni --activeLow -o bs_reg.cut.v > cut.log 2>&1
fault atpg bs_reg.cut.v -c "$CELLS/sg13cmos5l_stdcell.v" \
  -I "$CELLS/sg13cmos5l_udp.v" --clock clk_i --reset rst_ni \
  --activeLow -v 100 -r 100 -m 100 --ceiling 1000 \
  -o bs_reg.tv.json --output-coverage-metadata bs_reg.cov.yml > atpg.log 2>&1
cov() { grep -oE '\(([0-9.]+)%' "$1" | tr -d '(%' | awk '{printf "%.2f ", $1}'; }
check "fault sites, faults" "$(grep -o 'Found [0-9]* fault sites' atpg.log | awk '{print $2, 2 * $2}')" "580 1160"
check "coverage after 100, 200, ..., 900 vectors" "$(cov atpg.log)" \
  "97.84 99.40 99.40 99.66 99.66 99.66 99.66 99.66 99.66 "
check "final coverage, detected faults, compacted vectors" \
  "$(grep -o 'Coverage [0-9.]*' atpg.log | awk '{printf "%.2f %.0f", $2, $2 / 100 * 1160}') $(grep -o 'Compacted TV Count: [0-9]*' atpg.log | awk '{print $4}')" \
  "99.66 1156 32"
check "undetected faults: s-a-0 / s-a-1" \
  "$(uncovered bs_reg.cov.yml sa0) / $(uncovered bs_reg.cov.yml sa1)" "_253_.B / _253_.B _253_.Y _254_.A2"
check "_253_ drives only _254_.A2" "$(grep -c '(_008_)' bs_reg.nl.v) $(grep -B3 '\.A2(_008_)' bs_reg.nl.v | grep -o 'a21oi_1 _254_')" "2 a21oi_1 _254_"
check "SAT: _253_.B s-a-0, s-a-1, _254_.A2 s-a-1, _254_.A1 s-a-1" \
  "$(satest bs_reg.cut.v bs_reg _253_/B 0) $(satest bs_reg.cut.v bs_reg _253_/B 1) $(satest bs_reg.cut.v bs_reg _254_/A2 1) $(satest bs_reg.cut.v bs_reg _254_/A1 1)" \
  "none none none found"
fault atpg bs_reg.cut.v -c "$CELLS/sg13cmos5l_stdcell.v" \
  -I "$CELLS/sg13cmos5l_udp.v" --clock clk_i --reset rst_ni \
  --activeLow -v 10 -r 10 -m 100 --ceiling 500 -o curve.json > curve.log 2>&1
check "coverage curve in steps of 10 equals the figure" \
  "$(python3 - << 'EOF'
import re
log = open('curve.log').read()
got = [float(x) for x in re.findall(r'\(([0-9.]+)%', log)]
got.append(float(re.search(r'Coverage ([0-9.]+)', log).group(1)))
fig = open('../../_fig_coverage.qmd').read()
m = re.search(r'cov = \[(.*?)\] \+ \[99.397\] \* 16 \+ \[99.655\] \* 16', fig, re.S)
want = [float(x) for x in m.group(1).split(',')] + [99.397] * 16 + [99.655] * 16
print(len(got), all(abs(a - b) < 0.001 for a, b in zip(got, want)))
EOF
)" "50 True"
check "first vector count with 99.66 %" \
  "$(grep -oE '\(([0-9.]+)%' curve.log | tr -d '(%' | awk '$1 > 99.6 {print NR * 10; exit}')" "350"

echo "== Timing of bs_reg before and after scan insertion"
TOP=bs_reg openroad -no_init -exit dft.tcl > dft.log 2>&1
for n in bs_reg bs_reg_scan; do
  cat > sta_$n.tcl << EOF
read_liberty $LIB
read_verilog $n.nl.v
link_design bs_reg
read_sdc $W/content/sequential/code/bs_reg/syn/bs_reg.sdc
report_clock_min_period
report_checks -path_delay max -from [all_registers] -to [all_registers] -fields {cap slew} -digits 3
report_checks -path_delay min -group_path_count 25 -endpoint_path_count 1 -format end -digits 3
EOF
  sta -no_init -exit sta_$n.tcl > sta_$n.log 2>&1
done
tcq() { awk '/\/Q \(sg13cmos5l_/ {print $3; exit}' "$1"; }
tsu() { awk '/library setup time/ {print -$1; exit}' "$1"; }
check "minimum period before, after" \
  "$(grep -o 'period_min = [0-9.]*' sta_bs_reg.log | awk '{print $3}') $(grep -o 'period_min = [0-9.]*' sta_bs_reg_scan.log | awk '{print $3}')" "1.30 1.43"
check "worst path: clock-to-output, setup before / after" \
  "$(tcq sta_bs_reg.log) $(tsu sta_bs_reg.log) / $(tcq sta_bs_reg_scan.log) $(tsu sta_bs_reg_scan.log)" \
  "0.309 0.125 / 0.344 0.204"
check "smallest hold slacks: SCD endpoints before the first D, slack" \
  "$(awk '/group clk/ {on = 1} on && /\/SCD / {n++; if (n == 1) s = $(NF-1)} on && /\/D / {print n, s, $(NF-1); exit}' sta_bs_reg_scan.log)" \
  "20 0.292 0.383"
check "SCE pins on scan_enable_0" "$(grep -c 'SCE(scan_enable_0)' bs_reg_scan.nl.v)" "21"

echo "== Exercise: Insert a Scan Chain"
check "chain: length, first, last" \
  "$(grep -o "has [0-9]* cells" dft.log | awk '{print $2}') $(awk '/\(clk_i, rising\)/ {f = $1} /^  _[0-9]+_$/ {l = $1} END {print f, l}' dft.log)" "21 _288_ _268_"
check "Q of _288_, scan_out_0" \
  "$(grep -A1 'sdfrbpq_1 _288_' bs_reg_scan.nl.v | grep -o 'Q([^)]*)') $(grep -o 'assign scan_out_0 = .*;' bs_reg_scan.nl.v)" \
  "Q(mode_q[1]) assign scan_out_0 = data_q[0];"
check "chain of registers from scan_in_0" \
  "$(python3 scan_patterns.py bs_reg_scan.nl.v bs_reg.tv.json 2>&1 > bs_reg.pat | awk '{print $3}') $(for i in _288_ _284_ _283_ _276_ _275_ _268_; do grep -A1 "sdfrbpq_1 $i " bs_reg_scan.nl.v | grep -o 'Q([^)]*)'; done | tr '\n' ' ')" \
  "21 Q(mode_q[1]) Q(shamt_q[0]) Q(out_q[7]) Q(out_q[0]) Q(data_q[7]) Q(data_q[0]) "
yosys -p "read_liberty -lib $LIB; read_verilog bs_reg_scan.nl.v; stat -liberty $LIB" > scanstat.log 2>&1
check "after insertion: scan flip-flops, area" "$(ctype scanstat.log sg13cmos5l_sdfrbpq_1) $(area scanstat.log)" "21 2848.267800"
check "added area, percent, per flip-flop" \
  "$(calc 'printf "%.1f %.1f %.1f", 2848.2678 - 2543.4486, (2848.2678 / 2543.4486 - 1) * 100, 63.504 - 48.9888')" \
  "304.8 12.0 14.5"
check "only the flip-flops changed" \
  "$(diff <(grep -E '^ +[0-9]+ .*sg13cmos5l_' syn.log | grep -v dfrbpq | awk '{print $1, $NF}') <(grep -E '^ +[0-9]+ .*sg13cmos5l_' scanstat.log | grep -v sdfrbpq | awk '{print $1, $NF}') > /dev/null && echo same)" "same"
check "scan test with the vectors of Fault" "$(tb bs_reg_scan.nl.v -DPATTERNS=\"bs_reg.pat\")" \
  "chain test: 0 of 21 bits wrong;scan test: 32 patterns, 0 bits differ;"
check "end of the testbench: (2 + 2 * 21 + 725) cycles of 100 ns" \
  "$(vvp -n tb.vvp | grep -o 'finish called at [0-9]*' | awk '{print $4 / 1e3 " ns"}') $(calc 'printf "%d ns", (2 + 42 + 33 * 21 + 32) * 100')" \
  "76900 ns 76900 ns"
check "_007_ s-a-0, s-a-1 with the vectors of Fault" \
  "$(tb bs_reg_scan.nl.v -DPATTERNS=\"bs_reg.pat\" -DFAULT=_007_ -DSA=0 | grep -o '[0-9]* bits differ') / $(tb bs_reg_scan.nl.v -DPATTERNS=\"bs_reg.pat\" -DFAULT=_007_ -DSA=1 | grep -o '[0-9]* bits differ')" \
  "1 bits differ / 1 bits differ"
check "_008_ s-a-1 with the vectors of Fault" \
  "$(tb bs_reg_scan.nl.v -DPATTERNS=\"bs_reg.pat\" -DFAULT=_008_ -DSA=1)" \
  "chain test: 0 of 21 bits wrong;scan test: 32 patterns, 0 bits differ;"
check "random patterns: fault-free, _007_ s-a-0" \
  "$(tb bs_reg_scan.nl.v | grep -o '[0-9]* bits differ') / $(tb bs_reg_scan.nl.v -DFAULT=_007_ -DSA=0 | grep -o '[0-9]* bits differ')" \
  "0 bits differ / 0 bits differ"
check "test time with one chain, three chains of 7 (cycles, us at 10 MHz)" \
  "$(calc 'a = 33 * 21 + 32; b = 33 * 7 + 32; printf "%d %.1f %d %.1f", a, a / 10, b, b / 10')" "725 72.5 263 26.3"
python3 - << 'EOF'
import re
s = open('bs_reg_scan.nl.v').read()
cases, n = [], 0
for typ, name, pins in re.findall(r'\n\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S):
    if 'sdf' in typ:
        continue
    for pin in re.findall(r'\.(\w+)\(', pins):
        for v in (0, 1):
            cases.append(f'      {n}: force dut.{name}.{pin} = {v};  // {name}.{pin} sa{v}')
            n += 1
open('faults.svh', 'w').write('initial begin\n  int f;\n  if ($value$plusargs("f=%d", f))\n'
                              '    case (f)\n' + '\n'.join(cases) + '\n    endcase\nend\n')
EOF
sed 's|^`ifdef FAULT$|`include "faults.svh"\n`ifdef FAULT|' "$S/tb/tb_scan.sv" > tb_faults.sv
iverilog -g2012 -gno-specify -DPATTERNS=\"bs_reg.pat\" -o faults.vvp "$CELLS/sg13cmos5l_udp.v" \
  "$CELLS/sg13cmos5l_stdcell.v" bs_reg_scan.nl.v tb_faults.sv > /dev/null 2>&1
nf=$(grep -c 'force dut' faults.svh)
missed=$(for i in $(seq 0 $((nf - 1))); do
  r=$(vvp -n faults.vvp +f=$i | grep -E '^(chain|scan) test' | tr '\n' ' ')
  case "$r" in
    *"0 of 21 bits wrong"*"patterns, 0 bits differ"*) grep " $i: " faults.svh | awk '{print $NF, $(NF-1)}' ;;
  esac
done | awk '{print $2 "_" $1}' | LC_ALL=C sort | tr '\n' ' ')
check "cell-pin faults through the chain: number, undetected" "$nf $missed" \
  "1034 _253_.B_sa0 _253_.B_sa1 _253_.Y_sa1 _254_.A2_sa1 "

echo "== The same faults at the pin level: a wire of its own for every cell input"
check "inputs of logic cells on nets of one bit, on bits of vectors" \
  "$(python3 - << 'EOF'
import re
s = open('bs_reg_scan.nl.v').read()
n = [0, 0]
for typ, name, body in re.findall(r'(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S):
    if 'sdf' not in typ:
        for p, net in re.findall(r'\.(\w+)\(([^()]*)\)', body):
            if p not in ('X', 'Y'):
                n['[' in net] += 1
print(n[0], n[1])
EOF
)" "300 79"
python3 - << 'EOF'
import re
s = open('bs_reg_scan.nl.v').read()
decls, cases = [], []
def cell(m):
    typ, name, body = m.group(1), m.group(2), m.group(3)
    if 'sdf' in typ:
        return m.group(0)
    def pin(pm):
        p, net = pm.group(1), pm.group(2).strip()
        if p not in ('X', 'Y') and '[' not in net:
            w = f'br_{len(decls)}'
            decls.append(f'  wire {w};\n  assign {w} = {net};')
            net = w
        for v in (0, 1):
            cases.append(f'      {len(cases)}: force dut.{name}.{p} = {v};  // {name}.{p} sa{v}')
        return f'.{p}({net})'
    return f'{typ} {name} ({re.sub(r"[.](\w+)[(]([^()]*)[)]", pin, body)});'
s = re.sub(r'(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', cell, s, flags=re.S)
k = s.rindex('\n', 0, s.index('sg13cmos5l_'))  # after the declarations
open('bs_reg_br.nl.v', 'w').write(s[:k + 1] + '\n'.join(decls) + s[k:])
open('faults_br.svh', 'w').write('initial begin\n  int f;\n  if ($value$plusargs("f=%d", f))\n'
                                 '    case (f)\n' + '\n'.join(cases) + '\n    endcase\nend\n')
EOF
sed 's|^`ifdef FAULT$|`include "faults_br.svh"\n`ifdef FAULT|' "$S/tb/tb_scan.sv" > tb_br.sv
iverilog -g2012 -gno-specify -DPATTERNS=\"bs_reg.pat\" -o br.vvp "$CELLS/sg13cmos5l_udp.v" \
  "$CELLS/sg13cmos5l_stdcell.v" bs_reg_br.nl.v tb_br.sv > /dev/null 2>&1
check "pin-level netlist: scan test without a fault" "$(vvp -n br.vvp | grep -E '^(chain|scan) test' | tr '\n' ';')" \
  "chain test: 0 of 21 bits wrong;scan test: 32 patterns, 0 bits differ;"
nb=$(grep -c 'force dut' faults_br.svh)
for i in $(seq 0 $((nb - 1))); do
  r=$(vvp -n br.vvp +f=$i | grep -E '^(chain|scan) test' | tr '\n' ' ')
  case "$r" in
    *"0 of 21 bits wrong"*"patterns, 0 bits differ"*) grep " $i: " faults_br.svh | awk '{print $NF, $(NF-1)}' ;;
  esac
done > missed_br.txt
untestable=""
while read -r sa ref; do
  c=${ref%%.*}; p=${ref#*.}
  if [ "$p" == X ] || [ "$p" == Y ]; then  # an output: all loads of its net
    pins=$(python3 - "$c" "$p" << 'EOF'
import re, sys
s = open('bs_reg.cut.v').read()
cells = re.findall(r'(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
pins = lambda b: re.findall(r'\.(\w+)\(([^()]*)\)', b)
net = [n for t, c, b in cells if c == sys.argv[1] for p, n in pins(b) if p == sys.argv[2]][0].strip()
print(' '.join(f'{c}/{p}' for t, c, b in cells for p, n in pins(b) if n.strip() == net and p not in ('X', 'Y')))
EOF
)
  else
    pins="$c/$p"
  fi
  NETLIST=bs_reg.cut.v TOP=bs_reg PINS="$pins" SA=${sa#sa} yosys -q -c "$A/sat_test.tcl" | grep -q 'NO TEST' \
    && untestable="$untestable ${ref}_$sa"
done < missed_br.txt
nmiss=$(wc -l < missed_br.txt)
nunt=$(echo $untestable | wc -w)
check "pin-level faults: number, missed by the 32 vectors" "$nb $nmiss" "1034 59"
check "missed and untestable (SAT)" "$(echo $untestable | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')" \
  "_157_.B1_sa1 _158_.A_sa1 _209_.C_sa1 _220_.B1_sa1 _223_.B_sa1 _252_.A_sa1 _253_.A_N_sa1 _253_.B_sa0 _253_.B_sa1 _253_.Y_sa1 _254_.A2_sa1 _265_.B1_sa0 "
check "testable but missed, test coverage at the cell pins" \
  "$((nmiss - nunt)) $(calc "printf \"%.1f\", 100 * ($nb - $nmiss) / ($nb - $nunt)")" "47 95.4"

echo "== Equivalence after scan insertion"
check "scan inputs at 0, at 1" \
  "$(TOP=bs_reg yosys -q -c scan_eq.tcl) / $(TIE=1 TOP=bs_reg yosys -q -c scan_eq.tcl)" \
  "163 points proven equal, 0 unproven / 125 points proven equal, 38 unproven"
MAX_LENGTH=7 TOP=bs_reg openroad -no_init -exit dft.tcl > dft7.log 2>&1
check "MAX_LENGTH=7: chains" "$(grep -o 'has [0-9]* cells' dft7.log | awk '{print $2}' | tr '\n' ' ')" "7 7 7 "
check "three chains: scan inputs at 0, at 1" \
  "$(TOP=bs_reg yosys -q -c scan_eq.tcl) / $(TIE=1 TOP=bs_reg yosys -q -c scan_eq.tcl)" \
  "163 points proven equal, 0 unproven / 131 points proven equal, 32 unproven"

echo "== The scan chain after the placement"
cd "$S"
yosys -p "read_verilog -sv \
  ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
  ../../../sequential/code/bs_reg/rtl/bs_reg.sv; \
  synth -top bs_reg; flatten; dfflibmap -liberty $LIB; \
  abc -constr $CONSTR -liberty $LIB; opt_clean; stat -liberty $LIB; \
  write_verilog -noattr bs_reg32.nl.v" > syn32.log 2>&1
check "32-bit bs_reg: flip-flops" "$(ctype syn32.log sg13cmos5l_dfrbpq_1)" "71"
NETLIST=bs_reg32.nl.v TOP=bs_reg openroad -no_init -exit dft_place.tcl > place.log 2>&1
check "core, chain, same cells by name" \
  "$(grep -E '^(core|chain|same)' place.log | tr '\n' ';')" \
  "core: 5.0 7.0 185.0 185.0 um;chain: 71 cells, 910.7 um;same cells by name: 3024.4 um;"
check "rounded lengths, percent less wire" \
  "$(calc 'printf "%.0f %.0f %.0f", 910.7, 3024.4, 100 * (1 - 910.7 / 3024.4)')" "911 3024 70"
check "figure data equals the run, all flip-flops above y = 132 um" \
  "$(python3 - "$W/content/dft/_fig_reorder.qmd" << 'EOF'
import ast, re, sys
fig = open(sys.argv[1], encoding='utf-8').read()
data = ast.literal_eval(re.search(r'chain = (\[.*?\])\n', fig, re.S).group(1))
code = {'data_q': 'd', 'shamt_q': 's', 'mode_q': 'm', 'out_q': 'o'}
run = [(int(f[1].strip('_')), float(f[2]), float(f[3]), code[f[4].split('[')[0]])
       for f in (l.split() for l in open('place.log')) if f and f[0] == 'cell']
print(data == run, all(c[2] > 132 for c in run), end=' ')
hops =[(abs(b[1] - a[1]) + abs(b[2] - a[2]), a[0], b[0]) for a, b in zip(run, run[1:])]
print('%.1f _%d_ _%d_' % max(hops))
EOF
)" "True True 101.8 _1702_ _1693_"
cat > scan_opt.tcl << 'EOF'
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_lef $lib/lef/sg13cmos5l_tech.lef
read_lef $lib/lef/sg13cmos5l_stdcell.lef
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog bs_reg32.nl.v
link_design bs_reg
create_clock -name clk_i -period 100 [get_ports clk_i]
scan_replace
scan_opt
EOF
check "scan_opt" "$(openroad -no_init -exit scan_opt.tcl 2>&1 | grep -o 'DFT-0014.*')" \
  "DFT-0014] Scan Opt is not currently implemented"

echo "== Design rules: clock gates and clock domains"
mkdir -p "$W/cg" && cd "$W/cg"
yosys -p "read_verilog -sv $W/content/synth_opt/code/clock_gate/rtl/cg_reg.sv; \
  chparam -set WIDTH 8 cg_reg; synth -top cg_reg; \
  clockgate -pos sg13cmos5l_slgcp_1 GATE:CLK:GCLK -min_net_size 4; \
  dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; opt_clean; \
  write_verilog -noattr cg_reg.nl.v" > syn.log 2>&1
TOP=cg_reg openroad -no_init -exit "$S/dft.tcl" > dft.log 2>&1
icg() { awk '/sg13cmos5l_slgcp_1/ {on = 1} on {print} on && /\);/ {exit}' "$1" | grep -oE '\.[A-Z]+' | LC_ALL=C sort | tr -d '\n'; }
check "cg_reg: slgcp_1 pins before, after scan insertion" \
  "$(icg cg_reg.nl.v) $(icg cg_reg_scan.nl.v)" ".CLK.GATE.GCLK .CLK.GATE.GCLK"
check "clockgate can tie a test pin to 0" "$(yosys -h clockgate | grep -c 'tie_lo <port_name>')" "1"
check "cg_reg: chain length, warning" \
  "$(grep -o 'has [0-9]* cells' dft.log | awk '{print $2}') $(grep -o 'DFT-0007.*not a scan cell' dft.log | head -1)" \
  "8 DFT-0007] Cell '_1_' is not a scan cell"
mkdir -p "$W/ff" && cd "$W/ff"
yosys -p "read_verilog -sv $W/content/cdc/code/sync/rtl/sync_2ff.sv \
  $W/content/cdc/code/fifo/rtl/async_fifo.sv; synth -top async_fifo; flatten; \
  dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; opt_clean; \
  write_verilog -noattr async_fifo.nl.v" > syn.log 2>&1
TOP=async_fifo CLOCKS="wclk_i rclk_i" openroad -no_init -exit "$S/dft.tcl" > dft.log 2>&1
check "async_fifo: chains and their clocks" \
  "$(grep -oE 'has [0-9]+ cells|\((wclk_i|rclk_i), rising\)' dft.log | awk '/^has/ {print $2} /^\(/ {gsub(/[(,]/, "", $1); print $1}' | tr '\n' ' ')" \
  "43 wclk_i 11 rclk_i "
check "async_fifo: scan ports" "$(grep -oE '^ *(input|output) scan_[a-z_0-9]+' async_fifo_scan.nl.v | awk '{print $2}' | tr '\n' ' ')" \
  "scan_enable_0 scan_in_0 scan_out_0 scan_in_1 scan_out_1 "

echo "== Exercise: Make It Testable"
cd "$R"
check "lint of bs_reg_rs_tm" \
  "$(lint --top-module bs_reg_rs_tm rtl/bs_reg_rs_tm.sv ../../../cdc/code/reset/rtl/rst_sync.sv ../../../sequential/code/bs_reg/rtl/bs_reg.sv ../../../verification/code/barrel_shift/rtl/barrel_shift.sv)" "0"
for top in bs_reg_rs bs_reg_rs_tm; do
  extra=""
  [ $top == bs_reg_rs_tm ] && extra=rtl/bs_reg_rs_tm.sv
  yosys -p "read_verilog -sv \
    ../../../verification/code/barrel_shift/rtl/barrel_shift.sv \
    ../../../sequential/code/bs_reg/rtl/bs_reg.sv \
    ../../../cdc/code/reset/rtl/rst_sync.sv \
    ../../../cdc/code/reset/rtl/bs_reg_rs.sv $extra; \
    chparam -set WIDTH 8 $top; synth -top $top; flatten; \
    dfflibmap -liberty $LIB; abc -constr $CONSTR -liberty $LIB; \
    opt_clean; stat -liberty $LIB; write_verilog -noattr $top.nl.v" > syn_$top.log 2>&1
  TOP=$top openroad -no_init -exit ../scan/dft.tcl > dft_$top.log 2>&1
done
check "bs_reg_rs: flip-flops, chain, area" \
  "$(ctype syn_bs_reg_rs.log sg13cmos5l_dfrbpq_1) $(grep -o 'has [0-9]* cells' dft_bs_reg_rs.log | awk '{print $2}') $(area syn_bs_reg_rs.log)" \
  "23 23 2661.460200"
check "bs_reg_rs: scan test" "$(tb bs_reg_rs_scan.nl.v -DTOP=bs_reg_rs -DLEN=23)" \
  "chain test: 11 of 23 bits wrong;scan test: 32 patterns, 0 bits differ;"
check "bs_reg_rs_tm: chain, area, reset multiplexer" \
  "$(grep -o 'has [0-9]* cells' dft_bs_reg_rs_tm.log | awk '{print $2}') $(area syn_bs_reg_rs_tm.log) $(grep -B4 '\.S(test_mode_i)' bs_reg_rs_tm.nl.v | grep -o 'sg13cmos5l_mux2_1')" \
  "23 2663.274600 sg13cmos5l_mux2_1"
check "bs_reg_rs_tm: multiplexer inputs" \
  "$(grep -A4 "$(grep -B4 '\.S(test_mode_i)' bs_reg_rs_tm.nl.v | grep -o 'sg13cmos5l_mux2_1 _[0-9]*_')" bs_reg_rs_tm.nl.v | grep -oE '\.(A0|A1)\([^)]*\)' | tr -d ' ' | tr '\n' ' ')" \
  ".A0(\\u_rst_sync.rst_no) .A1(rst_ni) "
check "area of the fix" "$(calc 'printf "%.1f", 2663.2746 - 2661.4602')" "1.8"
check "bs_reg_rs_tm: scan test" "$(tb bs_reg_rs_tm_scan.nl.v -DTOP=bs_reg_rs_tm -DLEN=23 -DTEST_MODE)" \
  "chain test: 0 of 23 bits wrong;scan test: 32 patterns, 0 bits differ;"

echo "== Code listings"
check "longest line of the code files" \
  "$(cd "$REPO/content/dft/code" && cat atpg/*.v atpg/*.tcl atpg/*.py scan/*.tcl scan/*.py scan/*.yml scan/tb/*.sv reset/rtl/*.sv transistor/*.py | awk '{ if (length > m) m = length } END { print (m <= 70) ? "<= 70" : m }')" "<= 70"

echo
if [ $fails -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails checks FAILED."
  exit 1
fi
