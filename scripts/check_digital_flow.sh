#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "The RTL-to-GDSII
# Flow with LibreLane" quotes, inside the IIC-OSIC-TOOLS container
# (image 2026.10). Run from the repository root:
#   bash scripts/check_digital_flow.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter. It runs LibreLane
# seven times, at most two at a time, and opens the run base twice in
# its GUI flow without a screen, about 35 minutes in total. The AMS
# chip template is checked only if a clone of the template lies next to
# the repository (or in TEMPLATE_DIR).

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
TPL=${TEMPLATE_DIR:-$REPO/../ihp-sg13cmos5l-ams-chip-template}
W=${CHECK_DIR:-/tmp/vlsi_check_flow}
D=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
LIB=$D/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
PDKLL=$PDK_ROOT/ihp-sg13cmos5l/libs.tech/librelane
fails=0

rm -rf "$W" && mkdir -p "$W/content"
for ch in digital_flow sequential verification; do
  cp -r "$REPO/content/$ch" "$W/content/"
done
B=$W/content/digital_flow/code/bs_reg
G=$W/content/digital_flow/code/cg_mix
V=$W/content/digital_flow/code/div_mix

check() {  # check <what> <got> <expected>
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

calc() { awk "BEGIN { $1 }"; }

metric() {  # metric <run> <key> [format]: a value of final/metrics.json
  python3 -c "import json; v = json.load(open('$B/runs/$1/final/metrics.json'))['$2']; print(format(v, '${3:-}'))"
}

stage() {  # stage <run> <step folder> <key>: a metric after one step
  python3 -c "import json; print('%.4f' % json.load(open('$B/runs/$1/$2/state_out.json'))['metrics']['$3'])"
}

lint() {  # lint <files>: number of Verilator warnings and errors
  verilator --lint-only -Wall "$@" 2>&1 | grep -c -E '%Warning|%Error'
}

echo "== Versions"
check "LibreLane" "$(python3 -c 'import librelane; print(librelane.__version__)')" "3.1.0.dev3"
check "OpenROAD of LibreLane" "$($TOOLS/openroad-librelane/bin/openroad -version 2>/dev/null | awk '{print $1}')" "26Q1-1024-gdcf36133a"
check "Yosys" "$(yosys -V | awk '{print $2}')" "0.70"
check "Magic" "$(magic --version)" "8.3.685"
check "KLayout" "$(klayout -v | awk '{print $2}')" "0.30.12"
check "Netgen" "$(netgen -batch quit 2>&1 | head -1 | awk '{print $2}')" "1.5.324"
check "Icarus Verilog" "$(iverilog -V 2>&1 | head -1 | awk '{print $4}')" "14.0"

echo "== PDK defaults for LibreLane"
pdk() { grep -h "set ::env($1)" "$PDKLL/config.tcl" "$PDKLL/sg13cmos5l_stdcell/config.tcl" | head -1 | sed 's/.*) *//' | tr -d '"'; }
check "site width, height" "$(pdk PLACE_SITE_WIDTH) $(pdk PLACE_SITE_HEIGHT)" "0.48 3.78"
check "tap cell distance" "$(pdk FP_TAPCELL_DIST)" "0"
check "straps: Metal4 width, pitch, TopMetal1 width, pitch" \
  "$(pdk FP_PDN_VERTICAL_LAYER) $(pdk FP_PDN_VWIDTH) $(pdk FP_PDN_VPITCH) $(pdk FP_PDN_HORIZONTAL_LAYER) $(pdk FP_PDN_HWIDTH) $(pdk FP_PDN_HPITCH)" \
  "Metal4 1.0 50.0 TopMetal1 2.0 50.0"
check "pin layers left/right, top/bottom" "$(pdk FP_IO_HLAYER) $(pdk FP_IO_VLAYER)" "Metal3 Metal2"
check "maximum fanout" "$(pdk MAX_FANOUT_CONSTRAINT)" "10"
check "fanout limit of the library, set_max_fanout in the SDC of bs_reg" \
  "$(grep -o 'default_max_fanout : [0-9]*' $LIB | awk '{print $3}') $(grep -c set_max_fanout $W/content/sequential/code/bs_reg/syn/bs_reg.sdc)" "8 0"
check "CTS root and clock buffers" "$(pdk CTS_ROOT_BUFFER) / $(pdk CTS_CLK_BUFFERS)" \
  "sg13cmos5l_buf_8 / sg13cmos5l_buf_8 sg13cmos5l_buf_4 sg13cmos5l_buf_2 sg13cmos5l_buf_1"
check "diode, decap, and fill cells" "$(pdk DIODE_CELL) / $(pdk DECAP_CELLS) / $(pdk FILL_CELLS)" \
  "sg13cmos5l_antennanp / sg13cmos5l_decap_* / sg13cmos5l_fill_1 sg13cmos5l_fill_2"

echo "== LibreLane runs (two at a time, to stay within the memory)"
cd "$B" || exit 1
LL="librelane config.yaml --pdk ihp-sg13cmos5l --pdk-root $PDK_ROOT --manual-pdk"
$LL --run-tag base > base.log 2>&1 &
$LL --run-tag util75 -c FP_CORE_UTIL=75 -c PL_TARGET_DENSITY_PCT=85 > util75.log 2>&1 &
wait
$LL --run-tag hold05 -c PL_RESIZER_HOLD_SLACK_MARGIN=0.5 > hold05.log 2>&1 &
$LL --run-tag delay4 -c SYNTH_STRATEGY="DELAY 4" > delay4.log 2>&1 &
wait
$LL --run-tag margin -c PL_RESIZER_SETUP_SLACK_MARGIN=0.6 > margin.log 2>&1 &
(cd "$G" && $LL --run-tag base > run.log 2>&1
 cd "$V" && $LL --run-tag base > run.log 2>&1) &
wait
for t in base util75 hold05 delay4 margin; do
  check "run $t complete" "$(grep -c 'Flow complete' runs/$t/flow.log)" "1"
done
R=$B/runs/base

echo "== The run folder"
check "steps" "$(ls -d $R/[0-9]*-* | wc -l)" "76"
check "final views" "$(ls $R/final | tr '\n' ' ')" \
  "def gds json_h klayout_gds lef lib mag mag_gds metrics.csv metrics.json nl odb pnl render sdc sdf spef spice vh "

echo "== Synthesis and floorplan"
check "synthesized area, buffers" \
  "$(grep -oE 'Chip area for module .*: [0-9.]+' $R/06-yosys-synthesis/reports/stat.rpt | awk '{print $NF}') $(grep -c 'buf_' $R/06-yosys-synthesis/reports/stat.rpt)" \
  "13008.114000 0"
check "core for 50 %: area, edge, rows, sites" \
  "$(calc 'a = 13008.114 / 0.5; e = sqrt(a); printf "%.0f %.1f %d %d", a, e, int(e / 3.78), int(e / 0.48)')" "26016 161.3 42 336"
DEF=$R/final/def/bs_reg.def
check "die (nm)" "$(grep -o 'DIEAREA.*' $DEF)" "DIEAREA ( 0 0 ) ( 172820 191540 ) ;"
check "rows, sites per row, first row origin" \
  "$(grep -c '^ROW' $DEF) $(grep '^ROW' $DEF | head -1 | awk '{print $8, $4, $5}')" "42 336 5760 15120"
check "computed edge, die minus the margins in x and y" \
  "$(calc 'printf "%.2f %.2f %.2f", sqrt(13008.114 / 0.5), 172.82 - 2 * 5.76, 191.54 - 2 * 15.12')" "161.30 161.30 161.30"
check "straps: Metal4 VDD, VSS, TopMetal1 VDD, VSS" \
  "$(awk '/^SPECIALNETS/,/^END SPECIALNETS/' $DEF | awk '/^ *- / {n = $2} /Metal4 [1-9][0-9]* \+ SHAPE STRIPE/ {m[n]++} /TopMetal1 [1-9][0-9]* \+ SHAPE STRIPE/ {t[n]++} END {print m["VDD"], m["VSS"], t["VDD"], t["VSS"]}')" \
  "4 3 3 3"
check "core area, utilization of the layout, added area" \
  "$(metric base design__core__area .1f) $(metric base design__instance__utilization .3f) $(calc 'printf "%.1f", 15023.2 - 13008.114')" \
  "25604.8 0.587 2015.1"
check "cells in the layout, their area" "$(metric base design__instance__count__stdcell) $(metric base design__instance__area__stdcell .1f)" "1062 15023.2"
check "supply pins of the macro (LEF layers of VDD)" \
  "$(awk '/PIN VDD/,/END VDD/' $R/final/lef/bs_reg.lef | grep -oE 'LAYER [A-Za-z0-9]+' | sort -u | awk '{print $2}' | tr '\n' ' ')" "Metal4 TopMetal1 "
check "no tap cells in the layout" "$(grep -ci 'tap' $R/53-odb-cellfrequencytables/cell.rpt)" "0"

echo "== Placement and repair of the design"
L32=$(ls $R/32-openroad-repairdesignpostgpl/*.log)
check "port buffers in, out" "$(grep -o 'Inserted [0-9]* sg13cmos5l_buf_1 input' $L32 | awk '{print $2}') $(grep -o 'Inserted [0-9]* sg13cmos5l_buf_1 output' $L32 | awk '{print $2}')" "40 32"
check "slew, fanout violations, buffers, nets" \
  "$(grep -o 'Found [0-9]* slew' $L32 | awk '{print $2}') $(grep -o 'Found [0-9]* fanout' $L32 | awk '{print $2}') $(grep -o 'Inserted [0-9]* buffers in [0-9]* nets' $L32 | awk '{print $2, $5}')" \
  "5 30 142 30"
FO=$(sed -n '/^max fanout$/,/^max capacitance/p' $R/31-openroad-stamidpnr/*.log)
check "before the repair: limit, fanout of shamt_q[1], violations, fanout of the XNOR" \
  "$(echo "$FO" | awk '/^_1537_\/Q/ {print $2, $3}') $(echo "$FO" | grep -c VIOLATED) $(echo "$FO" | awk '/^_0755_\/Y/ {print $3}')" "8 36 30 53"
check "synthesis strategy, repair after global routing" \
  "$(python3 -c "import json; c = json.load(open('$R/resolved.json')); print(c['SYNTH_STRATEGY'], c['RUN_POST_GRT_RESIZER_TIMING'], c['SYNTH_ABC_BUFFERING'])")" "AREA 0 False False"
check "Metal2: resistance (kOhm/um), capacitance (pF/um)" \
  "$(awk '$1 == "Metal2" {print $3, $4}' $R/14-openroad-dumprcvalues/layer_values_after.rpt | head -1)" "5.150000e-04 9.302000e-05"
check "wire estimate: resistance, capacitance per um (average of the layers)" \
  "$(awk '$1 == "Signal" {print $3, $4; exit}' $R/14-openroad-dumprcvalues/resizer_values_after.rpt)" "3.894512e-04 9.691440e-05"

echo "== Clock tree"
L35=$(ls $R/35-openroad-cts/*.log)
check "sinks, buffers, buffers per path, levels, dummy loads, all sinks" \
  "$(grep -o 'has [0-9]* sinks' $L35 | head -1 | awk '{print $2}') $(grep -o 'Created [0-9]* clock buffers' $L35 | awk '{print $2}') $(grep -oE 'clock path: [0-9]+' $L35 | awk '{print $3}' | tr '\n' ' ')$(grep -o 'Max level of the clock tree: [0-9]*' $L35 | awk '{print $NF}') $(grep -o 'Dummy loads inserted [0-9]*' $L35 | awk '{print $NF}') $(grep -oE 'Sinks [0-9]+' $L35 | awk '{print $2}')" \
  "71 17 2 2 4 9 80"
check "fanout distribution" "$(grep -o 'Fanout distribution for the current clock = .*' $L35 | sed 's/.*= //')" "4:9, 5:7.."
python3 - "$R/final/nl/bs_reg.nl.v" > nl.txt << 'EOF'
import re, sys
s = open(sys.argv[1]).read()
cells = re.findall(r'\n\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
pins = {n: dict((p, v.strip()) for p, v in re.findall(r'\.(\w+)\(([^()]*)\)', b)) for t, n, b in cells}
typ = {n: t for t, n, b in cells}
loads, drv = {}, {}
for n, p in pins.items():
    for k, v in p.items():
        if k in ('X', 'Y', 'Q'):
            drv[v] = n
        else:
            loads.setdefault(v, []).append(n)
leaves = [n for n in pins if n.startswith('clkbuf_4')]
lf = sorted((sum(typ[c].endswith('dfrbpq_1') for c in loads[pins[l]['X']]),
             sum(c.startswith('clkload') for c in loads[pins[l]['X']])) for l in leaves)
print('leaves', len(leaves), ' '.join('%d+%d' % x for x in lf))
rst = set(p['RESET_B'] for p in pins.values() if 'RESET_B' in p)
bufs, depth = set(), 0
for r in rst:
    d, net = 0, r
    while net in drv and typ[drv[net]].startswith('sg13cmos5l_buf'):
        bufs.add(drv[net]); d += 1; net = pins[drv[net]]['A']
    depth = max(depth, d)
per = sorted(sum('RESET_B' in pins[c] and pins[c]['RESET_B'] == r for c in loads[r]) for r in rst)
print('reset', len(bufs), len(rst), per[0], per[-1], depth)
print('start', pins['_1537_']['Q'])
EOF
check "leaf buffers: flip-flops + dummy loads" "$(grep leaves nl.txt)" \
  "leaves 16 4+1 4+1 4+1 4+1 4+1 4+1 4+1 4+1 4+1 5+0 5+0 5+0 5+0 5+0 5+0 5+0"
check "worst setup skew typ, slow, fast" \
  "$(metric base clock__skew__worst_setup__corner:nom_typ_1p20V_25C .3f) $(metric base clock__skew__worst_setup__corner:nom_slow_1p08V_125C .3f) $(metric base clock__skew__worst_setup__corner:nom_fast_1p32V_m40C .3f)" \
  "0.118 0.124 0.116"
check "the fanout violation" \
  "$(grep -A4 '^max fanout' $R/55-openroad-stapostpnr/nom_typ_1p20V_25C/checks.rpt | grep VIOLATED | awk '{print $1, $2, $3}') $(metric base design__max_fanout_violation__count)" \
  "clkbuf_0_clk_i/X 8 16 1"
check "reset tree: buffers, nets, pins per net min max, depth" "$(grep reset nl.txt)" "reset 13 12 2 8 5"
rec() { sed -n '/Startpoint: rst_ni/,/slack/p' $R/55-openroad-stapostpnr/nom_$1/max.rpt | grep -m1 'slack' | awk '{printf "%.3f", $1}'; }
check "recovery slack typ, slow" "$(rec typ_1p20V_25C) $(rec slow_1p08V_125C)" "1.912 1.356"
L37=$(ls $R/37-openroad-resizertimingpostcts/*.log)
check "post-CTS repair: endpoints, start, reached, resized, warning" \
  "$(grep -o 'Found [0-9]* endpoints with setup' $L37 | awk '{print $2}') $(awk '/Iter   \| Removed/ {on = 1} on && $1 ~ /^[0-9]+$/ {print $15; n++} n == 2 {exit}' $L37 | tr '\n' ' ')$(grep -o 'Resized [0-9]* instances' $L37 | awk '{print $2}') $(grep -o 'Removed [0-9]* buffers' $L37 | awk '{print $2}') $(grep -c 'RSZ-0062' $L37)" \
  "29 -0.725 0.031 8 1 1"
check "slack lost after the repair: slow, typical, global routes, extraction" \
  "$(calc 'printf "%.2f %.2f %.2f %.2f", 0.031 + 0.586, 1.4516 - 1.0751, 1.4516 - 1.3394, 1.3394 - 1.0751')" "0.62 0.38 0.11 0.26"
check "no hold repair in base" "$(grep -c 'No hold violations found' $L37) $(grep -c dlygate $R/53-odb-cellfrequencytables/cell.rpt)" "1 0"

echo "== Exercise: Follow the Clock and the Reset (hold margin 0.5 ns)"
H=$B/runs/hold05
check "delay cells, their type" "$(grep -o 'sg13cmos5l_dlygate[a-z0-9_]* *│ *[0-9]*' $H/53-odb-cellfrequencytables/cell.rpt | tr -d '│' | awk '{print $1, $2}')" "sg13cmos5l_dlygate4sd3_1 131"
check "area, growth, repair reached, hold slack fast, warning" \
  "$(metric hold05 design__instance__area__stdcell .1f) $(calc 'printf "%.0f", (17162.4 / 15023.2 - 1) * 100') $(awk '/endpoints with hold/ {h = 1} h && $1 == "final" {print $11; exit}' $H/37-openroad-resizertimingpostcts/*.log) $(metric hold05 timing__hold__ws__corner:nom_fast_1p32V_m40C .3f) $(grep -c 'RSZ-0064' $H/37-openroad-resizertimingpostcts/*.log)" \
  "17162.4 14 0.221 0.268 1"

echo "== Routing"
check "global routing: Metal2, Metal3, total usage, overflow" \
  "$(awk '/GRT-0096/ {on = 1} on && ($1 == "Metal2" || $1 == "Metal3" || $1 == "Total") {printf "%s ", $4} on && $1 == "Total" {print $NF; exit}' $R/39-openroad-globalrouting/*.log)" \
  "43.96% 38.85% 28.20% 0"
check "antenna: violations, diodes" "$(metric base route__antenna_violation__count) $(metric base antenna_diodes_count)" "0 0"
check "detailed routing: iterations, wire length, longest net" \
  "$(for i in 0 1 2 3; do metric base route__drc_errors__iter:$i; done | tr '\n' ' ')$(metric base route__wirelength) $(metric base route__wirelength__max)" \
  "683 355 296 0 40693 436.335"
check "fill: decap_8, decap_4, fill_2, fill_1" \
  "$(for c in decap_8 decap_4 fill_2 fill_1; do grep -o "sg13cmos5l_$c *│ *[0-9]*" $R/53-odb-cellfrequencytables/cell.rpt | tr -d '│' | awk '{print $2}'; done | tr '\n' ' ')" \
  "634 151 255 280 "

echo "== Exercise: Plan the Floorplan (utilization 75 %)"
check "core, utilization" "$(metric util75 design__core__area .0f) $(metric util75 design__instance__utilization .3f)" "16903 0.892"
check "router: first violations, iterations, wire length" \
  "$(metric util75 route__drc_errors__iter:0) $(python3 -c "import json; m = json.load(open('$B/runs/util75/final/metrics.json')); print(len([k for k in m if k.startswith('route__drc_errors__iter:')]))") $(metric util75 route__wirelength)" \
  "1139 6 45974"
check "setup slack typ, slow; core smaller by (%)" \
  "$(metric util75 timing__setup__ws__corner:nom_typ_1p20V_25C .3f) $(metric util75 timing__setup__ws__corner:nom_slow_1p08V_125C .3f) $(calc 'printf "%.0f", (1 - 16903.0 / 25604.8) * 100')" \
  "0.997 -0.745 34"

echo "== Signoff"
check "setup slack after each stage (typical)" \
  "$(for s in 12-openroad-staprepnr 31-openroad-stamidpnr 36-openroad-stamidpnr-1 38-openroad-stamidpnr-2 43-openroad-stamidpnr-3 55-openroad-stapostpnr; do stage base $s timing__setup__ws__corner:nom_typ_1p20V_25C; done | tr '\n' ' ')" \
  "-1.6849 -2.3268 0.9725 1.4516 1.3394 1.0751 "
check "the stages equal the figure" \
  "$(grep -o '^slack = \[.*\]' $W/content/digital_flow/_fig_slack.qmd)" "slack = [-1.6849, -2.3268, 0.9725, 1.4516, 1.3394, 1.0751]"
check "setup slack typ, slow, fast" \
  "$(for c in typ_1p20V_25C slow_1p08V_125C fast_1p32V_m40C; do metric base timing__setup__ws__corner:nom_$c .3f; done | tr '\n' ' ')" "1.075 -0.586 2.072 "
check "slow corner: failing endpoints, TNS; worst hold (fast)" \
  "$(awk '$2 == "nom_slow_1p08V_125C" {print $20, $18}' $R/55-openroad-stapostpnr/summary.rpt) $(metric base timing__setup__tns .2f) $(metric base timing__hold__ws__corner:nom_fast_1p32V_m40C .3f)" \
  "31 -6.9772 -6.98 0.204"
SL=$R/55-openroad-stapostpnr/nom_slow_1p08V_125C/max.rpt
check "worst slow path: start, its net, end" \
  "$(grep -m1 Startpoint $SL | awk '{print $2}') $(grep start nl.txt | awk '{print $2}') $(grep -m1 Endpoint $SL | awk '{print $2}')" '_1537_ \shamt_q[1] _1516_'
check "worst slow path: data delay, six buffers" \
  "$(awk '/Startpoint/ {n++} n == 1 && /_1537_\/Q/ {q = $5} n == 1 && /_1516_\/D/ {d = $3} n == 1 && /fanout[0-9]+\/X/ {b += $4; k++} n == 2 {exit} END {printf "%.2f %.2f %d", d - q, b, k}' $SL)" \
  "3.59 1.83 6"
check "worst slow path: buffers behind the flip-flop, behind the XNOR" \
  "$(awk '/Startpoint/ {n++} n == 1 && /fanout[0-9]+\/X/ {if (x) a++; else b++} n == 1 && /_0755_\/Y/ {x = 1} n == 2 {exit} END {print b, a}' $SL)" "2 4"
check "IR drop worst (mV), share of 1.2 V, VSS rise" \
  "$(metric base ir__drop__worst) $(calc 'printf "%.2f", 0.00133 / 1.2 * 100') $(grep 'Worstcase voltage' $R/56-openroad-irdropreport/*.log | tail -1 | awk '{print $3}')" "0.00133 0.11 1.99e-03"
check "DRC Magic, KLayout, XOR, routing" \
  "$(metric base magic__drc_error__count) $(metric base klayout__drc_error__count) $(metric base design__xor_difference__count) $(metric base route__drc_errors)" "0 0 0 0"
check "LVS" "$(grep -c 'Circuits match uniquely' $R/70-netgen-lvs/netgen-lvs.log) $(metric base design__lvs_error__count)" "1 0"
check "LVS on abstracts, DRC on GDS" \
  "$(python3 -c "import json; c = json.load(open('$R/resolved.json')); print(c['MAGIC_EXT_USE_GDS'], c['MAGIC_DRC_USE_GDS'])")" "False True"

echo "== Exercise: Close the Timing"
check "DELAY 4: slow slack, area, growth" \
  "$(metric delay4 timing__setup__ws__corner:nom_slow_1p08V_125C .3f) $(metric delay4 design__instance__area__stdcell .1f) $(calc 'printf "%.0f", (16852.1 / 15023.2 - 1) * 100')" \
  "-0.542 16852.1 12"
check "DELAY 4: buffers after synthesis, repair reached, warning, loss" \
  "$(grep -c 'sg13cmos5l_buf' $B/runs/delay4/06-yosys-synthesis/bs_reg.nl.v) $(awk '$1 == "final" {print $15}' $B/runs/delay4/37-openroad-resizertimingpostcts/*.log) $(grep -c 'RSZ-0062' $B/runs/delay4/37-openroad-resizertimingpostcts/*.log) $(calc 'printf "%.2f", 0.088 + 0.542')" \
  "32 0.088 0 0.63"
check "margin 0.6: slow, typ, fast slack, area, growth" \
  "$(for c in slow_1p08V_125C typ_1p20V_25C fast_1p32V_m40C; do metric margin timing__setup__ws__corner:nom_$c .3f; done | tr '\n' ' ')$(metric margin design__instance__area__stdcell .1f) $(calc 'printf "%.0f", (15170.2 / 15023.2 - 1) * 100')" \
  "0.048 1.512 2.271 15170.2 1"
check "margin 0.6: hold, DRC, LVS" \
  "$(metric margin timing__hold__ws .3f) $(metric margin route__drc_errors) $(metric margin design__lvs_error__count)" "0.195 0 0"
ln -sf "$LIB" stdcell.lib
eqy -f -d lec_eqy lec.eqy > eqy.log 2>&1
check "EQY: verdict, partitions, of them output bits" \
  "$(grep -o 'DONE (PASS, rc=0)' eqy.log) $(grep -c '' lec_eqy/partition.list) $(grep -c 'bs_reg.data_o.[0-9]* xbits' lec_eqy/partition.list)" "DONE (PASS, rc=0) 32 32"
cp runs/base/final/nl/bs_reg.nl.v good.nl.v
n=$(grep -n 'sg13cmos5l_a21oi_1 ' good.nl.v | head -1 | cut -d: -f1)
sed -i "${n}s/sg13cmos5l_a21oi_1/sg13cmos5l_o21ai_1/" runs/base/final/nl/bs_reg.nl.v
eqy -f -d mut_eqy lec.eqy > mut.log 2>&1
cp good.nl.v runs/base/final/nl/bs_reg.nl.v
check "EQY with one cell replaced: verdict, failed partitions" \
  "$(grep -o 'DONE (FAIL, rc=2)' mut.log) $(grep -o 'Failed to prove equivalence of partition [^ ]*' mut.log | awk '{print $NF}' | sort | tr '\n' ' ')" \
  "DONE (FAIL, rc=2) bs_reg.data_o.1 bs_reg.data_o.17 "

echo "== Post-layout simulation"
CELLS=$D/verilog
SDF_T=runs/base/final/sdf/nom_typ_1p20V_25C/bs_reg__nom_typ_1p20V_25C.sdf
SDF_S=runs/base/final/sdf/nom_slow_1p08V_125C/bs_reg__nom_slow_1p08V_125C.sdf
GLS="$CELLS/sg13cmos5l_udp.v $CELLS/sg13cmos5l_stdcell.v runs/base/final/nl/bs_reg.nl.v tb/tb_bs_reg.sv"
errs() { grep -o '[0-9]* cycles, [0-9]* errors' "$@"; }
check "SDF files, INTERCONNECT entries (typical)" \
  "$(ls runs/base/final/sdf | tr '\n' ' ')$(grep -c INTERCONNECT $SDF_T)" \
  "nom_fast_1p32V_m40C nom_slow_1p08V_125C nom_typ_1p20V_25C 2672"
iverilog -g2012 -o rtl.vvp $W/content/verification/code/barrel_shift/rtl/barrel_shift.sv \
  $W/content/sequential/code/bs_reg/rtl/bs_reg.sv tb/tb_bs_reg.sv > rtl_comp.log 2>&1
check "RTL: warning about \$sdf_annotate, result" \
  "$(grep -c 'Omitting \$sdf_annotate()' rtl_comp.log) $(vvp -n rtl.vvp | errs)" "1 2000 cycles, 0 errors"
iverilog -g2012 -gspecify -ginterconnect -o pl.vvp $GLS > pl_comp.log 2>&1
check "netlist: compile status, sorry messages, timing-check warnings" \
  "$? $(grep -c 'sorry: ifnone' pl_comp.log) $(grep -c 'Timing checks are not supported' pl_comp.log)" "0 68 108"
t0=$(date +%s.%N); vvp -n rtl.vvp > /dev/null; t1=$(date +%s.%N)
vvp -n pl.vvp +SDF=$SDF_T > pl_typ.log 2>&1; t2=$(date +%s.%N)
check "netlist, typical: result, TIMINGCHECK warnings, flip-flops, SDF errors, their lines" \
  "$(errs pl_typ.log) $(grep -c 'TIMINGCHECK not supported' pl_typ.log) $(grep -c 'sg13cmos5l_dfrbpq_1 ' runs/base/final/nl/bs_reg.nl.v) $(grep -c 'SDF ERROR' pl_typ.log) $(grep 'Chosen value not defined' pl_typ.log | sed 's/.*sdf:\([0-9]*\):.*/\1/' | while read n; do sed -n "${n}p" $SDF_T | awk '{print $1}'; done | tr -d '(' | tr '\n' ' ')" \
  "2000 cycles, 0 errors 71 71 2 VOLTAGE TEMPERATURE "
check "run time: netlist at least 100 times the RTL" "$(calc "print (($t2 - $t1) > 100 * ($t1 - $t0)) ? 1 : 0")" "1"
echo "        (RTL $(calc "printf \"%.2f\", $t1 - $t0") s, netlist $(calc "printf \"%.1f\", $t2 - $t1") s)"
iverilog -g2012 -gspecify -o noic.vvp $GLS > /dev/null 2>&1
vvp -n noic.vvp +SDF=$SDF_T > noic.log 2>&1
check "without -ginterconnect: errors, result" \
  "$(grep -c 'Could not find net' noic.log) $(errs noic.log)" "2672 2000 cycles, 0 errors"
python3 - "$R/final/nl/bs_reg.nl.v" "$SDF_T" > clk.txt << 'EOF'
import re
import sys
s = open(sys.argv[1]).read()
cells = re.findall(r'\n\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
pins = {n: dict((p, v.strip()) for p, v in re.findall(r'\.(\w+)\(([^()]*)\)', b)) for t, n, b in cells}
typ = {n: t for t, n, b in cells}
drv = {v: n for n, p in pins.items() for k, v in p.items() if k in ('X', 'Y', 'Q')}
t = open(sys.argv[2]).read()
TRI = r'\(([\d.]+):([\d.]+):([\d.]+)\) \(([\d.]+):([\d.]+):([\d.]+)\)'
def ic(a, b):  # typical rise and fall of a wire
    m = re.search(r'\(INTERCONNECT %s %s %s\)' % (re.escape(a), re.escape(b), TRI), t)
    return (float(m.group(2)), float(m.group(5))) if m else (0.0, 0.0)
def cell(inst):  # typical rise and fall of a buffer, rounded to 10 ps as in Icarus
    i = t.index('(INSTANCE %s)' % inst)
    g = re.search(r'\(IOPATH A X %s\)' % TRI, t[i:i + 600]).groups()
    return float(g[1]), float(g[4])
def path(ff, pin):  # arcs from the start net to ff.pin through buffers
    arcs, net, sink = [], pins[ff][pin], ff + '.' + pin
    while net in drv and typ[drv[net]].startswith('sg13cmos5l_buf'):
        d = drv[net]
        arcs = [(d, cell(d)), ('wire', ic(d + '.X', sink))] + arcs
        sink, net = d + '.A', pins[d]['A']
    return net, [('wire', ic(net, sink))] + arcs
def sim(arcs, k):  # delay in Icarus: cells rounded to 10 ps, half up
    return sum(v[k] if n == 'wire' else (round(v[k] * 1000) + 5) // 10 / 100 for n, v in arcs)
net, arcs = path('_1537_', 'CLK')
print('clk', pins['_1537_']['CLK'], ' '.join('%s:%.3f' % (n, v[0]) for n, v in arcs),
      '%.3f %.3f' % (sum(v[0] for n, v in arcs), sim(arcs, 0)))
rows = []
for ff in pins:
    if typ[ff].endswith('dfrbpq_1'):
        start, d = path(ff, 'D')
        if start.startswith(('data_i', 'shamt_i', 'mode_i')):
            c = path(ff, 'CLK')[1]
            rows.append((sim(c, 0) - min(sim(d, 0), sim(d, 1)), ff, start, sim(c, 0), sim(d, 0),
                         ' '.join('%s:%.3f' % (n, v[0]) for n, v in d)))
rows.sort(reverse=True)
print('inputs', len(rows))
for r in [rows[0]] + [r for r in rows if r[1] == '_1537_']:
    print('in %s %s %.3f %.3f %.3f %s' % (r[1], r[2], r[3], r[4], r[0], r[5]))
EOF
check "clock path of _1537_: net, arcs (typical rise), sum, in Icarus" "$(grep '^clk' clk.txt)" \
  "clk clknet_4_10_0_clk_i wire:0.002 clkbuf_0_clk_i:0.111 wire:0.013 clkbuf_4_10_0_clk_i:0.107 wire:0.002 0.235 0.237"
check "input path of _1537_: flip-flop, input, clock, input path, limit, arcs" "$(grep '^in _1537_' clk.txt)" \
  "in _1537_ shamt_i[1] 0.237 0.055 0.182 wire:0.005 input37:0.052 wire:0.000"
check "flip-flops of the input register, the one that sets the limit" "$(grep '^inputs' clk.txt) $(grep '^in _' clk.txt | grep -v '_1537_' | awk '{print $2, $3, $4, $5, $6}')" \
  "inputs 39 _1542_ mode_i[1] 0.242 0.056 0.186"
for c in typ_1p20V_25C slow_1p08V_125C; do
  cat > hold_$c.tcl << EOF
read_liberty $D/lib/sg13cmos5l_stdcell_$c.lib
read_verilog $R/final/nl/bs_reg.nl.v
link_design bs_reg
read_spef $R/final/spef/nom/bs_reg.nom.spef
read_sdc $R/final/sdc/bs_reg.sdc
set_propagated_clock [all_clocks]
set ins [delete_from_list [all_inputs] [get_ports {clk_i rst_ni}]]
report_checks -path_delay min -from \$ins -format full -digits 3
EOF
  sta -no_init -exit hold_$c.tcl > hold_$c.rpt 2>&1
done
hold() {  # hold <corner>: worst hold path from an input: start, end, clock, uncertainty, hold time, data, slack, limit
  awk '/^Startpoint/ {s = $2} /^Endpoint/ {e = $2} /data arrival time/ && !a {a = $1} /clock uncertainty/ {u = $1; c = $2 - $1}
       /library hold time/ {h = $1} /slack/ {printf "%s %s %.3f %.3f %.3f %.3f %.3f %.3f", s, e, c, u, h, a - 1.0, $1, 1.0 - $1}' hold_$1.rpt
}
check "STA hold from the inputs (typical): start, end, clock, uncertainty, hold time, data, slack, limit" \
  "$(hold typ_1p20V_25C)" "mode_i[1] _1542_ 0.247 0.100 -0.031 0.060 0.745 0.255"
check "STA hold from the inputs (slow): start, end, slack, limit" \
  "$(hold slow_1p08V_125C | awk '{print $1, $2, $7, $8}')" "shamt_i[0] _1536_ 0.666 0.334"
cat > probe.sv << 'EOF'
`timescale 1ns / 1ps
module probe;
  realtime tc, tf;
  initial begin
    @(posedge tb_bs_reg.clk_i) tc = $realtime;
    @(posedge tb_bs_reg.dut._1537_.CLK) tf = $realtime;
    $display("PROBE %0.3f %0.3f", tc, tf - tc);
    @(negedge tb_bs_reg.clk_i) tc = $realtime;
    @(negedge tb_bs_reg.dut._1537_.CLK) tf = $realtime;
    $display("PROBE %0.3f", tf - tc);
  end
endmodule
EOF
iverilog -g2012 -gspecify -ginterconnect -o probe.vvp $GLS probe.sv > /dev/null 2>&1
check "simulated clock edge at _1537_: first edge, rise, fall latency" \
  "$(vvp -n probe.vvp +SDF=$SDF_T +CYCLES=10 | grep PROBE | cut -d' ' -f2- | tr '\n' ' ')" "4.000 0.237 0.236 "
iverilog -g2012 -gspecify -o probe_noic.vvp $GLS probe.sv > /dev/null 2>&1
check "without -ginterconnect, the wire delays are lost: rise latency" \
  "$(vvp -n probe_noic.vvp +SDF=$SDF_T +CYCLES=10 2>/dev/null | grep PROBE | head -1 | awk '{print $3}')" "0.220"
rm -f tb_bs_reg.fst
vvp -n pl.vvp +SDF=$SDF_T +CYCLES=10 +WAVES -fst > /dev/null 2>&1
check "waveform with the pins of _1537_" "$(fst2vcd tb_bs_reg.fst 2>/dev/null | grep -c 'scope module _1537_ ')" "1"
check "drive at 0.1 ns: RTL, netlist, first wrong words" \
  "$(vvp -n rtl.vvp +DRIVE=0.1 | errs) / $(vvp -n pl.vvp +SDF=$SDF_T +DRIVE=0.1 | grep -E 'errors|data_o' | head -2 | tr '\n' ' ' | sed 's/ *$//') / $(vvp -n pl.vvp +SDF=$SDF_T +DRIVE=0.1 | errs)" \
  "2000 cycles, 0 errors / 23.000 ns: data_o = 00018f82, expected 490a9a92 27.000 ns: data_o = 00000cb0, expected 00018f82 / 2000 cycles, 1998 errors"
check "earliest drive time (typical): 0.185 fails, 0.186 passes" \
  "$(vvp -n pl.vvp +SDF=$SDF_T +DRIVE=0.185 | errs | grep -vc ' 0 errors') $(vvp -n pl.vvp +SDF=$SDF_T +DRIVE=0.186 | errs)" "1 2000 cycles, 0 errors"
check "earliest drive time (slow): 0.268 fails, 0.270 passes" \
  "$(vvp -n pl.vvp +SDF=$SDF_S +DRIVE=0.268 | errs | grep -vc ' 0 errors') $(vvp -n pl.vvp +SDF=$SDF_S +DRIVE=0.270 | errs)" "1 2000 cycles, 0 errors"
iverilog -g2012 -gspecify -ginterconnect -Tmax -o pl_max.vvp $GLS > /dev/null 2>&1
check "slow corner at 4 ns: typical, maximum values, first wrong word" \
  "$(vvp -n pl.vvp +SDF=$SDF_S | errs) / $(vvp -n pl_max.vvp +SDF=$SDF_S | errs) / $(vvp -n pl_max.vvp +SDF=$SDF_S | grep -m1 data_o)" \
  "2000 cycles, 0 errors / 2000 cycles, 3 errors / 995.000 ns: data_o = aac56072, expected aac56062"
bits() {  # bits <log>: failing bits of data_o and how often
  python3 -c "
import re, sys
n = {}
for l in open('$1'):
    m = re.match(r'[\d.]+ ns: data_o = (\w+), expected (\w+)', l)
    if m:
        d = int(m.group(1), 16) ^ int(m.group(2), 16)
        for b in range(32):
            n[b] = n.get(b, 0) + (d >> b & 1)
print(' '.join('%d:%d' % (b, k) for b, k in sorted(n.items()) if k))"
}
vvp -n pl_max.vvp +SDF=$SDF_S +SHOW=100 > max2k.log 2>&1
vvp -n pl_max.vvp +SDF=$SDF_S +CYCLES=20000 +SHOW=100 > max20k.log 2>&1
vvp -n pl.vvp +SDF=$SDF_S +CYCLES=20000 > typ20k.log 2>&1
check "slow, maximum values: failing bits in 2000 and 20,000 cycles; typical in 20,000" \
  "$(bits max2k.log) / $(errs max20k.log) $(bits max20k.log) / $(errs typ20k.log)" \
  "4:3 / 20000 cycles, 29 errors 4:24 12:5 / 20000 cycles, 0 errors"
check "slow SDF: triples whose typical value is not the mean of minimum and maximum" \
  "$(python3 -c "
import re
t = open('$SDF_S').read()
v = [tuple(map(float, m)) for m in re.findall(r'\(([\d.]+):([\d.]+):([\d.]+)\)', t)]
print(len(v) > 10000, sum(abs(b - (a + c) / 2) > 0.0011 for a, b, c in v))")" "True 0"
check "slow max.rpt: failing paths, of them data after the capture edge, the latest, the others below 0.1 ns" \
  "$(python3 -c "
import re
t = open('$R/55-openroad-stapostpnr/nom_slow_1p08V_125C/max.rpt').read()
d = []
for b in t.split('Startpoint:')[1:]:
    if 'VIOLATED' in b and 'Path Type: max' in b and 'flip-flop' in b.split(chr(10))[1]:
        e = re.search(r'Endpoint: (\S+)', b).group(1)
        a = float(re.search(r'([-\d.]+)\s+data arrival time', b).group(1))
        c = float(re.findall(r'([-\d.]+) \^ %s/CLK' % re.escape(e), b)[-1])
        d.append((round(a - c, 3), e))
d.sort(reverse=True)
late = [x for x in d if x[0] > 0]
print(len(d), len(late), *['%s:%.3f' % (e, x) for x, e in late[:2]], all(x < 0.1 for x, e in late[2:]))")" \
  "31 6 _1516_:0.208 _1508_:0.191 True"
python3 - "$R/final/nl/bs_reg.nl.v" \
  "$R/55-openroad-stapostpnr/nom_slow_1p08V_125C/violator_list.rpt" > vio.txt << 'EOF'
import re
import sys
s = open(sys.argv[1]).read()
cells = re.findall(r'\n\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
pins = {n: dict((p, v.strip()) for p, v in re.findall(r'\.(\w+)\(([^()]*)\)', b)) for t, n, b in cells}
drv = {v: n for n, p in pins.items() for k, v in p.items() if k in ('X', 'Y', 'Q')}
vio = re.findall(r'\[setup reg-reg\] \S+ -> (_\d+_)/D : (\S+)', open(sys.argv[2]).read())
rank = {ff: (i + 1, sl) for i, (ff, sl) in enumerate(vio)}
for b in (4, 12):
    buf = drv['data_o[%d]' % b]
    ff = drv[pins[buf]['A']]
    print(b, buf, ff, *rank[ff], end=' ')
print(len(vio))
EOF
check "bits 4 and 12: output buffer, flip-flop, rank and slack in the violator list; violators" \
  "$(cat vio.txt)" "4 output67 _1508_ 2 -0.504289 12 output44 _1516_ 1 -0.585889 31"

echo "== A clock gate in the tree (cg_mix)"
printf 'module sg13cmos5l_lgcp_1 (input logic CLK, GATE, output logic GCLK);
  assign GCLK = CLK & GATE;
endmodule
' > "$W/sg13cmos5l_lgcp_1.sv"
check "lint of cg_mix (clock gate as a stub)" "$(lint --top-module cg_mix "$G/rtl/cg_mix.sv" "$W/sg13cmos5l_lgcp_1.sv")" "0"
cd "$G" || exit 1
check "cg_mix run complete" "$(grep -c 'Flow complete' runs/base/flow.log)" "1"
LC=$(ls $G/runs/base/*-openroad-cts/*.log)
check "CTS balances the latency, delay buffers" \
  "$(grep -o 'Balancing latency for clock [a-z_]*' $LC) $(grep -o 'inserted [0-9]* delay buffers' $LC)" \
  "Balancing latency for clock clk_i inserted 3 delay buffers"
check "delay buffers in front of the ungated tree" \
  "$(grep -E 'sg13cmos5l_buf_8 delaybuf_[0-9]_clk_i' $G/runs/base/final/nl/cg_mix.nl.v | wc -l) $(grep -A1 'clkbuf_regs_0_clk_i' $G/runs/base/final/nl/cg_mix.nl.v | grep -o 'A(delaynet_2_clk_i)')" \
  "3 A(delaynet_2_clk_i)"
F=$G/runs/base/final
cat > lat.tcl << EOF
read_liberty $LIB
read_verilog $F/nl/cg_mix.nl.v
link_design cg_mix
read_spef $F/spef/nom/cg_mix.nom.spef
read_sdc $F/sdc/cg_mix.sdc
set_propagated_clock [all_clocks]
report_clock_latency -digits 3
EOF
check "clock latency min, max (typical)" \
  "$(sta -no_init -exit lat.tcl 2>&1 | awk '/rise -> rise/ {on = 1} on && $NF == "latency" && NF == 3 {print $1, $2; exit}')" "0.381 0.440"

echo "== A divided clock in the tree (div_mix)"
check "lint of div_mix" "$(lint --top-module div_mix "$V/rtl/div_mix.sv")" "0"
check "div_mix run complete" "$(grep -c 'Flow complete' $V/runs/base/flow.log)" "1"
LV=$(ls $V/runs/base/*-openroad-cts/*.log)
check "CTS: clock nets, latency balancing" \
  "$(grep -o 'Net "[a-z_]*" found for clock "[a-z_]*"' $LV | tr '\n' ' ')$(grep -c 'Balancing latency' $LV)" \
  'Net "clk_i" found for clock "clk" Net "div_q" found for clock "clk_div" 0'
check "hold after CTS (typical): worst slack, violations" \
  "$(python3 -c "import json; m = json.load(open('$V/runs/base/36-openroad-stamidpnr-1/state_out.json'))['metrics']; print('%.3f' % m['timing__hold__ws__corner:nom_typ_1p20V_25C'], m['timing__hold_vio__count__corner:nom_typ_1p20V_25C'])")" \
  "-0.249 16"
L37V=$(ls $V/runs/base/37-openroad-resizertimingpostcts/*.log)
check "hold repair: endpoints, delay cells" \
  "$(grep -o 'Found [0-9]* endpoints with hold' $L37V | awk '{print $2}') $(grep -o 'Inserted [0-9]* hold buffers' $L37V | awk '{print $2}') $(grep -c 'sg13cmos5l_dlygate4sd3_1 ' $V/runs/base/final/nl/div_mix.nl.v)" \
  "16 32 32"
python3 - "$V/runs/base/final/nl/div_mix.nl.v" > div.txt << 'EOF'
import re
import sys
cells = re.findall(r'(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', open(sys.argv[1]).read(), re.S)
dly, ffs = {}, []
for typ, inst, body in cells:
    pins = {k: v.strip() for k, v in re.findall(r'\.(\w+)\(([^()]*)\)', body)}
    if 'dlygate' in typ:
        dly[pins['X']] = pins['A']
    if 'dfrbp' in typ:
        ffs.append(('div_q' if 'div_q' in pins['CLK'] else 'clk_i', pins['D']))
count = {}
for clk, d in ffs:
    n = 0
    while d in dly:
        d, n = dly[d], n + 1
    count[clk, n] = count.get((clk, n), 0) + 1
print(' '.join('%s:%d:%d' % (c, n, k) for (c, n), k in sorted(count.items())))
EOF
check "flip-flops per tree and delay cells in front of D" "$(cat div.txt)" "clk_i:0:17 div_q:2:16"

echo "== The Chip flow"
check "steps of the Chip flow beyond Classic" \
  "$(python3 -c "from librelane.flows.chip import Chip; print(' '.join(s.id for s in Chip.Steps if s.id in ('OpenROAD.PadRing', 'KLayout.SealRing', 'KLayout.Filler', 'KLayout.Density')))")" \
  "OpenROAD.PadRing KLayout.SealRing KLayout.Filler KLayout.Density"
check "global density window Metal1, Metal2 to Metal4" \
  "$(grep -oE '"(M1|Mn)_[jk]": [0-9.]+' $PDK_ROOT/ihp-sg13cmos5l/libs.tech/klayout/tech/drc/rule_decks/sg13cmos5l_tech_default.json | awk '{print $2}' | tr '\n' ' ')" "0.35 0.6 0.35 0.6 "

echo "== Static cells and PCells"
TECH=$PDK_ROOT/ihp-sg13cmos5l
kl() { KLAYOUT_PATH=$TECH/libs.tech/klayout:$TECH/libs.tech/klayout/tech klayout -n sg13cmos5l -zz -r "$@" 2>&1 | grep -v '^registered'; }
ctx() { grep -a -c CONTEXT_INFO "$1"; }
check "stored PCell parameters: standard cells, IO cells, SRAM, hardened macro" \
  "$(ctx $TECH/libs.ref/sg13cmos5l_stdcell/gds/sg13cmos5l_stdcell.gds) $(ctx $TECH/libs.ref/sg13cmos5l_io/gds/sg13cmos5l_io.gds) $(ctx $TECH/libs.ref/sg13cmos5l_sram/gds/RM_IHPSG13_1P_256x8_c3_bm_bist.gds) $(ctx $R/final/gds/bs_reg.gds)" \
  "0 0 0 0"
mkdir -p "$W/pcell" && cd "$W/pcell" || exit 1
cat > draw.py <<'EOF'
import pya
lib = pya.Library.library_by_name('SG13_dev', 'sg13cmos5l')
print(*[n for n in ('nmos', 'rhigh', 'via_stack', 'bondpad', 'sealring') if n in lib.layout().pcell_names()])
def draw(name, params):
    ly = pya.Layout()
    ly.technology_name = 'sg13cmos5l'
    return ly, ly.cell(ly.add_pcell_variant(lib, lib.layout().pcell_declaration(name).id(), params))
ly, c = draw('nmos', {'w': '10u', 'l': '0.13u', 'ng': 4})
act, gat, con = (pya.Region(c.begin_shapes_rec(ly.layer(n, 0))).merged() for n in (1, 5, 6))
ch = sorted({(p.bbox().width() * ly.dbu, p.bbox().height() * ly.dbu) for p in (gat & act).each()})
print((gat & act).count(), ch, act.count(), (con & act).count() > 0, (con & gat).count())
ly.write('nmos.gds')
_, b = draw('bondpad', {'diameter': '70u', 'shape': 'square', 'bottomMetal': '3'})
print(b.dbbox().width(), b.dbbox().height())
EOF
cat > mark.py <<'EOF'
import pya
ly = pya.Layout()
ly.read('nmos.gds')
ly.cell('nmos').shapes(ly.layer(200, 0)).insert(pya.Box(0, 0, 100, 100))
ly.write('marked.gds')
opt = pya.SaveLayoutOptions()
opt.write_context_info = False
ly.write('static.gds', opt)
EOF
cat > read.py <<'EOF'
import pya
ly = pya.Layout()
ly.technology_name = 'sg13cmos5l'
ly.read(f)
print(ly.cell('nmos').shapes(ly.layer(200, 0)).size())
EOF
cat > bbox.py <<'EOF'
import pya
ly = pya.Layout()
ly.read(f)
print(ly.top_cell().dbbox().width(), ly.top_cell().dbbox().height())
EOF
kl draw.py > draw.txt
check "PCells of the library" "$(sed -n 1p draw.txt)" "nmos rhigh via_stack bondpad sealring"
check "nmos: channels, size, active areas, contacts on source and drain, on the gates" \
  "$(sed -n 2p draw.txt)" "4 [(0.13, 2.5)] 1 True 0"
check "bondpad as the template builds it" "$(sed -n 3p draw.txt)" "70.0 70.0"
klayout -b -r mark.py > /dev/null 2>&1
check "marker in the stored nmos: without the PDK, with it, exported without parameters" \
  "$(klayout -b -rd f=marked.gds -r read.py 2>&1 | tail -1) $(kl read.py -rd f=marked.gds | tail -1) $(kl read.py -rd f=static.gds | tail -1)" "1 0 1"
for d in 500 1600; do
  kl $TECH/libs.tech/klayout/tech/scripts/sealring.py -rd width=$d -rd height=$d -rd output=ring$d.gds > /dev/null
done
check "seal ring of the PDK script for a die of 500 and 1600 um" \
  "$(klayout -b -rd f=ring500.gds -r bbox.py 2>&1 | tail -1) $(klayout -b -rd f=ring1600.gds -r bbox.py 2>&1 | tail -1)" "500.0 500.0 1600.0 1600.0"
check "seal ring: script in the PDK config, its PCell, die size from LibreLane" \
  "$(grep -c 'scripts/sealring.py' $PDKLL/sg13cmos5l_io/config.tcl) $(grep -c "PCELL = 'sealring'" $TECH/libs.tech/klayout/tech/scripts/sealring.py) $(python3 -c "import inspect, librelane.steps.klayout as k; print(inspect.getsource(k.SealRing.run_ihp_sg13g2).count('DIE_AREA'))")" \
  "1 1 2"
PLUGIN=/headless/.klayout/salt/LibraryManagerPlugin/pymacros/library_manager_plugin.py
check "export command, written without parameters" \
  "$(grep -c 'Export Layout For Tapeout' $PLUGIN) $(grep -c 'write_context_info = False' $PLUGIN)" "1 1"
check "PCell code is Python in the PDK" "$(ls $TECH/libs.tech/klayout/python/sg13cmos5l_pycell_lib/ihp/nmos_code.py | wc -l)" "1"
if [ ! -d "$TPL/macros/inverter" ]; then
  echo "  skip  no clone of the template at $TPL"
else
  check "template: bondpad target, its PCell, size, shape" \
    "$(grep -c '^build-bondpad:' $TPL/Makefile) $(grep -oE "^PCELL = '[a-z]+'" $TPL/ip/sg13cmos5l_ip__bondpad_70x70/script/bondpad.py) $(grep -E '^(DIAMETER|SHAPE) ' $TPL/ip/sg13cmos5l_ip__bondpad_70x70/Makefile | tr -d '\r' | awk '{print $3}' | tr '\n' ' ')" \
    "1 PCELL = 'bondpad' 70.0 square "
  check "template: stored PCell parameters in inverter_top.klay.gds, inverter_top.gds" \
    "$(ctx $TPL/macros/inverter/layout/inverter_top.klay.gds) $(ctx $TPL/macros/inverter/layout/inverter_top.gds)" "1 0"
fi

echo "== The reports of a run"
cd "$B" || exit 1
U=$B/runs/util75
check "violation corners of setup and hold, capacity reserve of the global router" \
  "$(python3 -c "import json; c = json.load(open('$R/resolved.json')); print(c['TIMING_VIOLATION_CORNERS'], c['HOLD_VIOLATION_CORNERS'], c['GRT_ADJUSTMENT'])")" \
  "['*typ*'] ['*'] 0.3"
check "setup checker: listed corner, flow complete" \
  "$(grep -A1 'Setup violations found in the following corners:' $R/flow.log | tail -1) $(grep -c 'Flow complete' $R/flow.log)" \
  "* nom_slow_1p08V_125C 1"
check "manufacturability.rpt" \
  "$(python3 -c "print(' '.join(l.replace('✅', '').strip() for l in open('$R/76-misc-reportmanufacturability/manufacturability.rpt', encoding='utf-8') if l.strip()))")" \
  "* Antenna Passed * LVS Passed * DRC Passed"
S=55-openroad-stapostpnr/nom_slow_1p08V_125C
check "reports of the table" \
  "$(cd $R && ls warning.log error.log resolved.json 06-yosys-synthesis/reports/stat.rpt 55-openroad-stapostpnr/summary.rpt \
    $S/max.rpt $S/min.rpt $S/violator_list.rpt $S/checks.rpt $S/clock.rpt $S/skew.max.rpt $S/power.rpt \
    56-openroad-irdropreport/irdrop.rpt 46-openroad-checkantennas-1/reports/antenna_summary.rpt \
    64-magic-drc/reports/drc.magic.rpt 65-klayout-drc/reports/drc.klayout.json \
    70-netgen-lvs/reports/lvs.netgen.rpt 76-misc-reportmanufacturability/manufacturability.rpt 2> /dev/null | wc -l)" "18"
WL=$R/warning.log
check "warning.log: lines, ORD-0032, DRT-0349, the five of the run" \
  "$(wc -l < $WL) $(grep -c ORD-0032 $WL) $(grep -c DRT-0349 $WL) $(grep -c -e 'Setup violations found' -e '^\* nom_slow_1p08V_125C' -e RSZ-0062 -e VSRC_LOC_FILES -e 'long wires is not set' $WL)" \
  "37 25 7 5"
check "power (typical): sequential, combinational, clock, total (mW), sequential and clock" \
  "$(awk '$1 ~ /^(Sequential|Combinational|Clock)$/ {printf "%s ", $NF} $1 == "Total" && NF == 6 {printf "%.2f", $5 * 1000}' $R/55-openroad-stapostpnr/nom_typ_1p20V_25C/power.rpt) $(calc 'printf "%.1f", 45.1 + 22.9')" \
  "45.1% 32.0% 22.9% 2.33 68.0"
check "slow corner: failing setup endpoints, of them below -0.5 ns" \
  "$(grep -c '^\[setup' $R/$S/violator_list.rpt) $(awk '/^\[setup/ && $NF + 0 < -0.5' $R/$S/violator_list.rpt | wc -l)" "31 2"
DEF=$R/final/def/bs_reg.def
pos() { grep -m1 -E "^ *- $1 " $DEF | grep -oE 'PLACED \( [0-9]+ [0-9]+' | awk '{printf "%.1f %.1f", $3 / 1000, $4 / 1000}'; }
pin() { awk -v p="$1" '$1 == "-" && $2 == p && $3 == "+" && $4 == "NET" {f = 1} f && /PLACED/ {print $4 / 1000; exit}' $DEF; }
check "worst slow path: positions of _1537_ and _1516_, x of the pins shamt_i[1] and data_o[12]" \
  "$(pos _1537_) $(pos _1516_) $(pin 'shamt_i[1]') $(pin 'data_o[12]')" "10.1 162.5 153.6 117.2 0.2 172.62"
check "clock tree of the typical corner: earliest and latest flip-flop, tree skew" \
  "$(awk '/rise -> rise/ {on = 1} on && /network latency/ {printf "%s %.3f ", $NF, $1} on && $NF == "skew" {printf "%.3f", $1; exit}' $R/55-openroad-stapostpnr/nom_typ_1p20V_25C/clock.rpt)" \
  "_1508_/CLK 0.225 _1482_/CLK 0.250 0.025"
check "setup skew (typical): source and target latency, uncertainty, CRPR, skew" \
  "$(awk 'NF && $1 ~ /^-?[0-9.]+$/ {printf "%.3f ", $1}' $R/55-openroad-stapostpnr/nom_typ_1p20V_25C/skew.max.rpt)" \
  "0.250 -0.225 0.100 -0.007 0.118 "

echo "== The straps in the GUI"
OR=$TOOLS/openroad-librelane/bin/openroad
cat > straps.tcl << EOF
read_db $R/final/odb/bs_reg.odb
set b [ord::get_db_block]
foreach n {VDD VSS} {
  foreach sw [[\$b findNet \$n] getSWires] {
    foreach w [\$sw getWires] {
      if {[\$w isVia]} continue
      set l [[\$w getTechLayer] getName]
      if {\$l == "Metal4"} { puts "M4 \$n [expr {[\$w xMin] / 1000.0}] [expr {([\$w xMax] - [\$w xMin]) / 1000.0}]" }
      if {\$l == "TopMetal1"} { puts "TM1 \$n [expr {[\$w yMin] / 1000.0}] [expr {([\$w yMax] - [\$w yMin]) / 1000.0}]" }
    }
  }
}
puts "CORE [expr {[[\$b getCoreArea] xMax] / 1000.0}]"
exit
EOF
$OR -no_splash -exit straps.tcl > straps.txt 2>&1
st() { awk -v l=$1 -v n=$2 '$1 == l && $2 == n {print $3, $4}' straps.txt | sort -u -n | tr '\n' ' '; }
check "Metal4 straps of VDD, of VSS (start, width)" "$(st M4 VDD)/ $(st M4 VSS)" \
  "15.26 1.0 65.26 1.0 115.26 1.0 165.26 1.0 / 18.26 1.0 68.26 1.0 118.26 1.0 "
check "TopMetal1 straps of VDD, of VSS (start, width)" "$(st TM1 VDD)/ $(st TM1 VSS)" \
  "24.12 2.0 74.12 2.0 124.12 2.0 / 30.12 2.0 80.12 2.0 130.12 2.0 "
check "right edge of the core, place of a fourth VSS strap" \
  "$(awk '$1 == "CORE" {print $2}' straps.txt) $(calc 'printf "%.2f", 18.26 + 3 * 50')" "167.04 168.26"

echo "== Routing congestion in the GUI"
heat() {  # heat <tag> <odb>: dumps the routing congestion map, all layers and Metal4
  cat > heat_$1.tcl << EOF
read_db $2
set c [[ord::get_db_block] getCoreArea]
puts "CORE [expr {[\$c xMin] / 1000.0}] [expr {[\$c yMin] / 1000.0}] [expr {[\$c xMax] / 1000.0}] [expr {[\$c yMax] / 1000.0}]"
gui::dump_heatmap Routing $PWD/heat_$1.csv
gui::set_heatmap Routing Layer Metal4
gui::set_heatmap Routing rebuild
gui::dump_heatmap Routing $PWD/heat_$1_m4.csv
exit
EOF
  QT_QPA_PLATFORM=offscreen timeout 600 $OR -no_splash -gui heat_$1.tcl 2>&1 | grep '^CORE' > heat_$1.core
}
heat base_grt $R/39-openroad-globalrouting/bs_reg.odb
heat base_final $R/final/odb/bs_reg.odb
heat u75_grt $U/39-openroad-globalrouting/bs_reg.odb
heat u75_final $U/final/odb/bs_reg.odb
cat > heat.py << 'EOF'
import csv
import sys
from collections import defaultdict
tag = sys.argv[1]
d = [list(map(float, r)) for r in list(csv.reader(open('heat_%s.csv' % tag, encoding='utf-8')))[1:]]
x0, y0, x1, y1 = map(float, open('heat_%s.core' % tag, encoding='utf-8').read().split()[1:5])
qx, qy = (x1 - x0) / 4, (y1 - y0) / 4
inner = lambda r: x0 + qx <= r[0] < x1 - qx and y0 + qy <= r[1] < y1 - qy
v = [r[4] for r in d]
mean = lambda a: sum(a) / len(a)
full = [r for r in d if r[4] >= 99.95]
print(len(d), '%.1f' % (d[0][2] - d[0][0]), '%.1f %.1f' % (max(v), mean(v)),
      '%.1f' % mean([r[4] for r in d if inner(r)]),
      '%.1f' % mean([r[4] for r in d if not (x0 <= r[0] < x1 and y0 <= r[1] < y1)]),
      len(full), sum(x >= 90 for x in v), sum(inner(r) for r in full))
m4 = defaultdict(list)
for r in list(csv.reader(open('heat_%s_m4.csv' % tag, encoding='utf-8')))[1:]:
    m4[float(r[0])].append(float(r[4]))
straps = [x for x in m4 if any(x <= s < x + 7.2 for s in (15.26, 65.26, 115.26))]
cols = {x: mean(a) for x, a in m4.items()}
print('m4 straps %.0f-%.0f others %.0f-%.0f' % (min(cols[x] for x in straps), max(cols[x] for x in straps),
      min(c for x, c in cols.items() if x not in straps), max(c for x, c in cols.items() if x not in straps)))
EOF
check "base after global routing: tiles, width, max, mean, central quarter, margins, full, >= 90 %, full in the center" \
  "$(python3 heat.py base_grt | head -1)" "624 7.2 100.0 60.8 82.1 38.1 10 60 8"
check "base: the final database holds the same map" "$(cmp -s heat_base_grt.csv heat_base_final.csv && echo same)" "same"
check "util75 after global routing" "$(python3 heat.py u75_grt | head -1)" "418 7.2 100.0 75.5 89.3 57.3 33 152 12"
check "util75 after global routing, Metal4: columns of the straps, the others" "$(python3 heat.py u75_grt | tail -1)" "m4 straps 57-68 others 31-48"
check "util75, final database: max, mean" "$(python3 heat.py u75_final | head -1 | awk '{print $3, $4}')" "56.7 38.3"
check "util75, detailed routing changed the map" "$(cmp -s heat_u75_grt.csv heat_u75_final.csv || echo changed)" "changed"
check "util75, global routing: usage of all layers, Metal2, Metal3, Metal4" \
  "$(awk '/GRT-0096/ {on = 1} on && ($1 == "Total" || $1 == "Metal2" || $1 == "Metal3" || $1 == "Metal4") {printf "%s ", $4} on && $1 == "Total" {exit}' $U/39-openroad-globalrouting/*.log)" \
  "58.89% 64.18% 13.12% 45.65% "
check "the state after global routing names its database" \
  "$(python3 -c "import json; print(json.load(open('$R/39-openroad-globalrouting/state_out.json'))['odb'])" | grep -c '39-openroad-globalrouting/bs_reg.odb')" "1"

echo "== The GUI flow of LibreLane (run last, it changes the run base)"
mkdir -p "$W/wrap"
cat > "$W/wrap/openroad" << 'EOF'
#!/bin/bash
# The OpenROAD of LibreLane without a screen, with GUI_TCL after gui.tcl.
args=()
for a in "$@"; do
  if [[ "$a" == */gui.tcl ]]; then
    printf 'source %s\nsource %s\nexit\n' "$a" "$GUI_TCL" > "$GUI_TCL.run"
    a=$GUI_TCL.run
  fi
  args+=("$a")
done
QT_QPA_PLATFORM=offscreen exec "$TOOLS/openroad-librelane/bin/openroad" "${args[@]}"
EOF
chmod +x "$W/wrap/openroad"
gui() {  # gui <tcl> [options]: opens the run base in the GUI flow, runs the Tcl, quits
  local t=$1
  shift
  GUI_TCL=$t PATH=$W/wrap:$TOOLS/openroad-librelane/bin:$PATH python3 -m librelane --manual-pdk config.yaml \
    --pdk ihp-sg13cmos5l --pdk-root "$PDK_ROOT" --run-tag base --flow OpenInOpenROAD "$@" > /dev/null 2>&1
  cat "$(ls -d $R/*-openroad-opengui | sort -V | tail -1)/openroad-opengui.log"
}
cat > gui_typ.tcl << EOF
puts "WNS [format %.3f [sta::worst_slack -max]]"
foreach n {VDD VSS} {
  analyze_power_grid -net \$n
  gui::set_heatmap IRDrop Net \$n
  gui::set_heatmap IRDrop rebuild
  gui::dump_heatmap IRDrop $PWD/ir_\$n.csv
}
EOF
n0=$(wc -l < $R/flow.log)
gui gui_typ.tcl > gui_typ.log
check "GUI flow: its step folder, flow.log grew, resolved.json replaced" \
  "$(ls -d $R/*-openroad-opengui | xargs -n1 basename) $(( $(wc -l < $R/flow.log) > n0 )) $(python3 -c "import json; c = json.load(open('$R/resolved.json')); print(c.get('SYNTH_STRATEGY'), len(c) < 200)")" \
  "77-openroad-opengui 1 None True"
check "GUI (typical): propagated clock, parasitics of the corner, worst setup slack" \
  "$(grep -c 'propagating all clocks' gui_typ.log) $(grep -o "parasitics for the '[A-Za-z0-9_]*' corner" gui_typ.log) $(grep -o '^WNS .*' gui_typ.log)" \
  "1 parasitics for the 'nom_typ_1p20V_25C' corner WNS 1.075"
check "GUI: worst IR drop of VDD and VSS, as in irdrop.rpt" \
  "$(grep 'Worstcase IR drop' gui_typ.log | awk '{print $(NF - 1)}' | tr '\n' ' ')$(grep 'Worstcase IR drop' $R/56-openroad-irdropreport/irdrop.rpt | awk '{print $(NF - 1)}' | tr '\n' ' ')" \
  "1.33e-03 1.99e-03 1.33e-03 1.99e-03 "
cat > ir.py << 'EOF'
import csv
import sys
from collections import defaultdict
d = [list(map(float, r)) for r in list(csv.reader(open('ir_%s.csv' % sys.argv[1], encoding='utf-8')))[1:]]
top = max(d, key=lambda r: r[4])
col = defaultdict(float)
for r in d:
    col[r[0]] = max(col[r[0]], r[4])
left = [v for x, v in col.items() if x + 10 <= 118.26]
print('%.0f %.0f %.2f' % (top[0], top[1], top[4]), '%.2f-%.2f' % (min(left), max(left)))
EOF
check "IR drop map of VDD: tile of the peak (x, y), peak (mV)" "$(python3 ir.py VDD | cut -d' ' -f1-3)" "40 150 1.33"
check "IR drop map of VSS: tile of the peak, peak, column maxima left of the last strap" "$(python3 ir.py VSS)" "150 60 1.99 1.72-1.76"
check "warning about the voltage sources" "$(grep -c "'VSRC_LOC_FILES' was not given a value, which may make the results of IR drop analysis inaccurate. If you are not integrating a top-level chip for manufacture, you may ignore this warning" $WL)" "1"
echo 'puts "WNS [format %.3f [sta::worst_slack -max]]"' > gui_slow.tcl
check "GUI in the slow corner: parasitics of the corner, worst setup slack" \
  "$(gui gui_slow.tcl -c DEFAULT_CORNER=nom_slow_1p08V_125C | grep -o -e "parasitics for the '[A-Za-z0-9_]*' corner" -e '^WNS .*' | tr '\n' ' ')" \
  "parasitics for the 'nom_slow_1p08V_125C' corner WNS -0.586 "
check "the selected cell of the figure" "$(grep -c 'sg13cmos5l_buf_1 input1 ' $R/final/nl/bs_reg.nl.v)" "1"

echo "== The Clock Tree Viewer"
python3 - "$G/runs/base/final/nl/cg_mix.nl.v" > cg_tree.txt << 'EOF'
import re
import sys
s = open(sys.argv[1], encoding='utf-8').read()
cells = re.findall(r'\n\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
pins = {n: dict((p, v.strip()) for p, v in re.findall(r'\.(\w+)\(([^()]*)\)', b)) for t, n, b in cells}
typ = {n: t.replace('sg13cmos5l_', '') for t, n, b in cells}
loads = {}
for n, p in pins.items():
    for k, v in p.items():
        if k in ('A', 'CLK'):
            loads.setdefault(v, []).append(n)
out = lambda n: pins[n].get('X', pins[n].get('GCLK'))
for first in sorted(n for n in loads['clk_i'] if typ[n] in ('buf_8', 'lgcp_1')):
    seq, net, names = [typ[first]], out(first), [first]
    while True:
        nxt = [n for n in loads.get(net, []) if typ[n] in ('buf_8', 'lgcp_1')]
        if len(nxt) != 1:
            break
        seq.append(typ[nxt[0]]); names.append(nxt[0]); net = out(nxt[0])
    print(' '.join(seq), '>', len(nxt), sum('delaybuf' in n for n in names), end=' | ')
EOF
check "cg_mix: branches from clk_i (cells > leaves, delay buffers)" "$(cat cg_tree.txt)" \
  "buf_8 buf_8 lgcp_1 buf_8 > 4 0 | buf_8 buf_8 buf_8 buf_8 buf_8 > 4 3 | "
cat > div_arr.tcl << EOF
read_liberty $LIB
read_verilog $V/runs/base/final/nl/div_mix.nl.v
link_design div_mix
read_spef $V/runs/base/final/spef/nom/div_mix.nom.spef
read_sdc $V/runs/base/final/sdc/div_mix.sdc
set_propagated_clock [all_clocks]
foreach c {clk clk_div} {
  report_checks -path_delay min -to [all_registers -clock \$c -data_pins] \
    -group_path_count 100 -endpoint_path_count 1 -format full_clock_expanded -digits 3
}
EOF
sta -no_init -exit div_arr.tcl > div_arr.rpt 2>&1
check "div_mix: flip-flops and their clock arrival of clk and clk_div, output of the divider (typical)" \
  "$(python3 -c "
import re
t = open('div_arr.rpt', encoding='utf-8').read()
res = {}
for b in t.split('Startpoint:')[1:]:
    e = re.search(r'Endpoint: (\S+) \(.*?clocked by (\w+)\)', b)
    if not e:
        continue
    m = re.findall(r'([-\d.]+) \^ %s/CLK' % re.escape(e.group(1)), b.split('data arrival time')[1])
    res.setdefault(e.group(2), {})[e.group(1)] = float(m[-1])
q = [float(x) for x in re.findall(r'([\d.]+) \^ _29_/Q', t)]
print(*['%s %d %.2f %.2f' % (c, len(d), min(d.values()), max(d.values())) for c, d in sorted(res.items())],
      '%.1f %.1f' % (min(q), max(q)))")" \
  "clk 17 0.14 0.14 clk_div 16 0.49 0.49 0.3 0.3"

if [ ! -f "$TPL/netlist/nl/chip_top.nl.v" ]; then
  echo "  skip  no clone of the template at $TPL"
else
  echo "== The template chip in the GUI"
  check "template chip: clock buffers, sinks of the clock tree" \
    "$(grep -cE 'sg13cmos5l_buf_[0-9]+ clkbuf_[0-9_f]*_clk_PAD2CORE ' $TPL/netlist/nl/chip_top.nl.v) $(python3 -c "
import re
s = open('$TPL/netlist/nl/chip_top.nl.v', encoding='utf-8').read()
print(*sorted(n.lstrip('\\\\') for t, n, b in re.findall(r'\n\s*(\w+)\s+(\S+)\s*\((.*?)\);', s, re.S)
      if 'leaf_clk_PAD2CORE' in b and not t.startswith('sg13cmos5l_')))")" \
    "3 i_chip_core.counter1 i_chip_core.counter2 i_chip_core.sram_0"
  CL=$TPL/macros/counter/final/lib/nom_typ_1p50V_25C/counter_top__nom_typ_1p50V_25C.lib
  check "counter timing model: clock tree paths, internal power, latency (ns)" \
    "$(grep -c -e 'min_clock_tree_path' -e 'max_clock_tree_path' $CL) $(grep -c internal_power $CL) $(grep -A12 'clock_tree_path' $CL | grep -oE 'values\("[0-9.]+"\)' | grep -oE '[0-9.]+' | sort -n | sed -n '1p;$p' | awk '{printf "%.1f ", $1}')" \
    "2 0 0.1 0.1 "
  check "template: librelane-openroad of the chip and the counter, report folders" \
    "$(cat $TPL/Makefile $TPL/macros/counter/Makefile | tr -d '\r' | grep -A1 '^librelane-openroad:' | grep -c -- '--last-run --flow OpenInOpenROAD') $(grep -h -E '^REPORT_DIR' $TPL/Makefile $TPL/macros/counter/Makefile | tr -d '\r' | awk '{print $NF}' | tr '\n' ' ')" \
    "2 verification/reports verification "
fi

echo "== Code listings"
check "longest line of the code files" \
  "$(cd "$REPO/content/digital_flow/code" && cat bs_reg/config.yaml bs_reg/lec.eqy bs_reg/tb/tb_bs_reg.sv cg_mix/config.yaml cg_mix/rtl/cg_mix.sv div_mix/config.yaml div_mix/div_mix.sdc div_mix/rtl/div_mix.sv | awk '{ if (length > m) m = length } END { print (m <= 70) ? "<= 70" : m }')" "<= 70"

echo
if [ $fails -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails checks FAILED."
  exit 1
fi
