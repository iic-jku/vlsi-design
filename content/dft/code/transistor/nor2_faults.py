# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Transistor faults in sg13cmos5l_nor2_1, simulated
# with ngspice in the typical corner. The NOR gate drives an inv_1.
# The inputs (A, B) step through a sequence of vectors, 2 ns each,
# and the script prints the output Y of the NOR gate and the output
# Z of the inverter at the end of every vector, and the quiescent
# supply current IDDQ of each vector from an operating point, for
# the fault-free cell and for one transistor fault:
#   n_open  XN0, the NMOS at input A, removed (stuck-open)
#   n_on    gate of XN0 at VDD, it always conducts (stuck-on)
#   p_on    gate of XP0, the PMOS at input A, at VSS (stuck-on)
# With HOLD=<s> and SEQ="<v1> <v2>", it applies v1, then holds v2
# for that time, and prints how Y and Z develop.
# Usage: python3 nor2_faults.py [good|n_open|n_on|p_on]
#        HOLD=1 SEQ="00 01" python3 nor2_faults.py n_open

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PDK = os.environ['PDK_ROOT'] + '/ihp-sg13cmos5l'
CELLS = (PDK + '/libs.ref/sg13cmos5l_stdcell/spice/'
         'sg13cmos5l_stdcell.spice')
VDD = 1.2
T = 2e-9       # time per vector
EDGE = 0.1e-9  # rise and fall time of the inputs
VECTORS = ['00', '10', '11', '10', '00', '01']
DECK = """* nor2_1 with a fault, driving an inv_1
.lib {pdk}/libs.tech/ngspice/models/cornerMOSlv.lib mos_tt
{cells}
.temp 25
VDD vdd 0 {vdd}
VA a 0 {va}
VB b 0 {vb}
X1 y a b vdd 0 nor2
X2 z y vdd 0 sg13cmos5l_inv_1
CL z 0 5f
.option reltol=1e-6 abstol=1e-15
{analysis}
.end
"""


def subckt(name, text):
    """The subcircuit of a cell from the PDK netlist."""
    return re.search(rf'^\.subckt {name} .*?^\.ends', text,
                     re.M | re.S | re.I).group(0)


def nor2(fault):
    """nor2_1 renamed to nor2, with the fault built in."""
    text = Path(CELLS).read_text()
    lines = subckt('sg13cmos5l_nor2_1', text).splitlines()
    lines[0] = lines[0].replace('sg13cmos5l_nor2_1', 'nor2')
    out = []
    for line in lines:
        f = line.split()
        if f and f[0] in ('XN0', 'XP0'):
            assert f[2] == 'A', line  # both have their gate at A
            if fault == 'n_open' and f[0] == 'XN0':
                continue
            if fault == 'n_on' and f[0] == 'XN0':
                line = ' '.join(f[:2] + ['VDD'] + f[3:])
            if fault == 'p_on' and f[0] == 'XP0':
                line = ' '.join(f[:2] + ['VSS'] + f[3:])
        out.append(line)
    return '\n'.join(out) + '\n' + subckt('sg13cmos5l_inv_1', text)


def pwl(bits):
    """PWL source of an input that takes the values in bits."""
    pts, v = [0.0, 0.0], 0.0
    for i, b in enumerate(bits):
        t = i * T
        new = VDD * int(b)
        if new != v:
            pts += [t, v, t + EDGE, new]
            v = new
    return 'PWL(' + ' '.join(f'{p:.4g}' for p in pts) + ')'


def ngspice(fault, va, vb, analysis):
    """Runs the deck and returns the output of ngspice."""
    deck = DECK.format(pdk=PDK, cells=nor2(fault), vdd=VDD, va=va,
                       vb=vb, analysis=analysis)
    # One thread: the deck is small, extra threads cost time
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    with tempfile.TemporaryDirectory() as work:
        path = Path(work) / 'nor2.cir'
        path.write_text(deck)
        return subprocess.run(['ngspice', '-b', str(path)],
                              cwd=work, env=env, capture_output=True,
                              text=True).stdout


def tran(fault, vectors, stop, step, times):
    """Transient: Y and Z at the given times."""
    meas = [f'.meas tran {q}{i} find v({q}) at={t:.6g}'
            for i, t in enumerate(times) for q in 'yz']
    out = ngspice(fault, pwl(v[0] for v in vectors),
                  pwl(v[1] for v in vectors),
                  f'.tran {step:.3g} {stop:.6g}\n' + '\n'.join(meas))
    got = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 3 and f[1] == '=' and f[0][0] in 'yz':
            got[f[0]] = float(f[2])
    if len(got) != 2 * len(times):
        sys.exit('ngspice failed:\n' + out[-2000:])
    return [(got[f'y{i}'], got[f'z{i}']) for i in range(len(times))]


def iddq(fault, ab):
    """Operating point: the supply current with the inputs ab."""
    out = ngspice(fault, VDD * int(ab[0]), VDD * int(ab[1]), '.op')
    for line in out.splitlines():
        f = line.split()
        if len(f) == 2 and f[0] == 'vdd#branch':
            return -float(f[1])
    sys.exit('ngspice failed:\n' + out[-2000:])


def amps(i):
    """A current with a unit, e.g., 12.3 nA."""
    for unit, s in (('mA', 1e-3), ('uA', 1e-6), ('nA', 1e-9)):
        if abs(i) >= s:
            return f'{i / s:.3g} {unit}'
    return f'{i / 1e-12:.3g} pA'


def main():
    fault = sys.argv[1] if len(sys.argv) > 1 else 'good'
    if 'HOLD' in os.environ:
        hold = float(os.environ['HOLD'])
        seq = os.environ.get('SEQ', '').split()
        if len(seq) != 2:
            sys.exit('HOLD needs two vectors, e.g., SEQ="00 01"')
        after = [d for d in (1e-9, 1e-6, 1e-3, 1.0) if d <= hold]
        res = tran(fault, seq, T + hold, hold / 1e4,
                   [T + d for d in after])
        print(f'{fault}: {seq[0]}, then {seq[1]} for {hold:g} s')
        print(f'  after {seq[1]}    Y (V)   Z (V)')
        for d, (y, z) in zip(after, res):
            print(f'  {d:<8.0e} {y:7.3f} {z:7.3f}')
        return
    times = [(i + 1) * T - 0.05e-9 for i in range(len(VECTORS))]
    res = tran(fault, VECTORS, len(VECTORS) * T, 1e-12, times)
    print(f'{fault}: nor2_1 driving inv_1, typical corner')
    print('  AB    Y (V)   Z (V)   IDDQ')
    for v, (y, z) in zip(VECTORS, res):
        print(f'  {v}  {y:6.3f}  {z:6.3f}   {amps(iddq(fault, v))}')


if __name__ == '__main__':
    main()
