#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Reproduces every number that the chapter "The RTL-to-GDSII
# Flow with LibreLane" quotes, inside the IIC-OSIC-TOOLS container
# (image 2026.10). Run from the repository root:
#   bash scripts/check_digital_flow.sh
# Works on a copy in /tmp, so the repository stays clean. Exits with 1
# if any result differs from the value in the chapter. It runs LibreLane
# seven times, at most two at a time, about 25 minutes in total.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
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

echo "== Code listings"
check "longest line of the code files" \
  "$(cd "$REPO/content/digital_flow/code" && cat bs_reg/config.yaml bs_reg/lec.eqy cg_mix/config.yaml cg_mix/rtl/cg_mix.sv div_mix/config.yaml div_mix/div_mix.sdc div_mix/rtl/div_mix.sv | awk '{ if (length > m) m = length } END { print (m <= 70) ? "<= 70" : m }')" "<= 70"

echo
if [ $fails -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails checks FAILED."
  exit 1
fi
