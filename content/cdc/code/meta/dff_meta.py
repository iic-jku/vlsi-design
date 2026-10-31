# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Metastability of sg13cmos5l_dfrbpq_1 in ngspice. Finds
# the data arrival at which the flip-flop just fails to capture a
# rising D, then moves the data edge earlier in decades and measures
# the clock-to-output delay. A fit gives the time constant tau and
# the window T0 of t_cq = t_cq0 + tau * ln(T0 / (2 * delta)), from
# 1e-17 to 1e-14 s: farther away, the start difference of the latch
# is no longer small. The PDK netlist is the schematic of the cell,
# so CPAR adds a wiring capacitance to every internal node (default
# 1.5 fF, CPAR=0 for the bare schematic).
# Usage: [CPAR=<fF>] python3 dff_meta.py [typ|slow|fast]

import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PDK = os.environ['PDK_ROOT'] + '/ihp-sg13cmos5l'
CELLS = (PDK + '/libs.ref/sg13cmos5l_stdcell/spice/'
         'sg13cmos5l_stdcell.spice')
PORTS = {'q', 'clk', 'd', 'reset_b', 'vdd', 'vss'}
CORNERS = {  # model section, supply, temperature
    'typ': ('mos_tt', 1.2, 25),
    'slow': ('mos_ss', 1.08, 125),
    'fast': ('mos_ff', 1.32, -40),
}
T_CLK = 2.0e-9   # the clock edge starts here, 0.15 ns ramps
DECK = """* dfrbpq_1: clock-to-output delay against the data arrival
.lib {pdk}/libs.tech/ngspice/models/cornerMOSlv.lib {mos}
{cell}
.temp {temp}
VDD vdd 0 {vdd}
VRST rst 0 PWL(0 0 0.5n 0 0.65n {vdd})
VCLK clk 0 PWL(0 0 {tc} 0 {tc2} {vdd})
VD d 0 PWL(0 0 {td} 0 {td2} {vdd})
X1 q clk d rst vdd 0 dff
CL q 0 5f
.option reltol=1e-7 abstol=1e-15 vntol=1e-9
.tran 0.2p 6n 0 0.2p
.meas tran tclk when v(clk)={half} rise=1
.meas tran tq when v(q)={half} rise=1
.end
"""


def cell(cpar):
    """The subcircuit of dfrbpq_1, cpar fF at each internal node."""
    text = Path(CELLS).read_text()
    sub = re.search(r'^\.subckt sg13cmos5l_dfrbpq_1 .*?^\.ends',
                    text, re.M | re.S | re.I).group(0)
    nets = set()
    for line in sub.splitlines()[1:]:
        f = line.split()
        if f and f[0][0] in 'Xx':
            nets.update(n.lower() for n in f[1:5])
    caps = [f'Cp{i} {n} VSS {cpar}f'
            for i, n in enumerate(sorted(nets - PORTS)) if cpar > 0]
    lines = sub.splitlines()
    lines[0] = lines[0].replace('sg13cmos5l_dfrbpq_1', 'dff')
    return '\n'.join(lines[:-1] + caps + [lines[-1]])


def tcq(td, setup, work):
    """Clock-to-output delay for a data edge at td, or None."""
    mos, vdd, temp, sub = setup
    deck = work / 'meta.cir'
    deck.write_text(DECK.format(
        pdk=PDK, cell=sub, mos=mos, vdd=vdd, temp=temp,
        half=vdd / 2, tc=repr(T_CLK), tc2=repr(T_CLK + 0.15e-9),
        td=repr(td), td2=repr(td + 0.15e-9)))
    out = subprocess.run(['ngspice', '-b', str(deck)], cwd=work,
                         capture_output=True, text=True).stdout
    meas = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 3 and f[0] in ('tclk', 'tq') and f[1] == '=':
            meas[f[0]] = float(f[2])
    if 'tclk' not in meas:
        sys.exit('ngspice failed:\n' + out[-2000:])
    return meas['tq'] - meas['tclk'] if 'tq' in meas else None


def main():
    corner = sys.argv[1] if len(sys.argv) > 1 else 'typ'
    cpar = float(os.environ.get('CPAR', '1.5'))
    mos, vdd, temp = CORNERS[corner]
    setup = (mos, vdd, temp, cell(cpar))
    work = Path(tempfile.mkdtemp(prefix='dff_meta_'))
    # Bisection: lo captures the rising D, hi does not
    lo, hi = T_CLK - 0.5e-9, T_CLK + 0.3e-9
    while hi - lo > 1e-19:
        mid = (lo + hi) / 2
        if tcq(mid, setup, work) is None:
            hi = mid
        else:
            lo = mid
    t0 = tcq(lo - 1e-9, setup, work)  # data 1 ns early
    print(f'corner {corner}: {mos}, {vdd} V, {temp} C, '
          f'{cpar:g} fF per internal node')
    print(f'normal clock-to-output delay t_cq0 = {t0 * 1e12:.1f} ps')
    print('  delta (s)   t_cq (ps)')
    pts = []
    for e in range(18, 10, -1):
        delta = 10.0 ** (-e)
        t = tcq(lo - delta, setup, work)
        print(f'  1e-{e:<7d} {t * 1e12:9.1f}')
        if 14 <= e <= 17:
            pts.append((math.log(delta), t))
    shutil.rmtree(work)
    # Least-squares fit of t_cq = a - tau * ln(delta)
    n = len(pts)
    mx = sum(x for x, _ in pts) / n
    my = sum(y for _, y in pts) / n
    slope = (sum((x - mx) * (y - my) for x, y in pts)
             / sum((x - mx) ** 2 for x, _ in pts))
    tau = -slope
    a = my - slope * mx
    t_w = 2 * math.exp((a - t0) / tau)  # both sides of the point
    print(f'tau = {tau * 1e12:.1f} ps, T0 = {t_w * 1e12:.1f} ps')


if __name__ == '__main__':
    main()
