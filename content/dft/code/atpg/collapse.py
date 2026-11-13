# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Simulates every single stuck-at fault of a small
# netlist of inv, and, or cells for all input vectors and groups the
# faults whose outputs are equal for every vector. The fault sites
# are the nets and, for a net with several loads, each branch to a
# cell input. Unused ports (clk_i, rst_ni) have no fault sites. The
# netlist must list its cells in the order of the signal flow.
# Usage: python3 collapse.py cons.v

import itertools
import re
import sys

FUNCS = {'inv': lambda v: 1 - v[0], 'and': lambda v: int(all(v)),
         'or': lambda v: int(any(v))}


def parse(path):
    """Ports and cells (type, name, input pins, output net)."""
    text = open(path, encoding='utf-8').read()
    ins = re.findall(r'input\s+wire\s+(\w+)', text)
    outs = re.findall(r'output\s+wire\s+(\w+)', text)
    cells = []
    for typ, name, body in re.findall(
            r'sg13cmos5l_(\w+?)\d*_\d+\s+(\w+)\s*\((.*?)\);', text,
            re.S):
        pins = re.findall(r'\.(\w+)\((\w+)\)', body)
        out = [n for p, n in pins if p in ('X', 'Y')][0]
        cells.append((typ, name, [(p, n) for p, n in pins
                                  if p not in ('X', 'Y')], out))
    return ins, outs, cells


def main():
    ins, outs, cells = parse(sys.argv[1])
    loads = {}
    for _, name, pins, _ in cells:
        for p, n in pins:
            loads.setdefault(n, []).append(f'{name}.{p}')
    nets = [n for n in ins if n in loads] + [c[3] for c in cells]
    branches = [b for n in nets if len(loads.get(n, [])) > 1
                for b in loads[n]]
    ins = [n for n in ins if n in loads]
    sites = nets + branches
    faults = [(s, v) for s in sites for v in (0, 1)]

    def simulate(vec, fault):
        val = dict(zip(ins, vec))
        site = lambda s, v: fault[1] if fault[0] == s else v
        for n in ins:
            val[n] = site(n, val[n])
        for typ, name, pins, out in cells:  # in topological order
            v = [site(f'{name}.{p}', val[n]) for p, n in pins]
            val[out] = site(out, FUNCS[typ](v))
        return tuple(val[o] for o in outs)

    vecs = list(itertools.product((0, 1), repeat=len(ins)))
    good = [simulate(v, (None, None)) for v in vecs]
    groups = {}
    for f in faults:
        resp = tuple(simulate(v, f) for v in vecs)
        groups.setdefault(resp, []).append(f)
    print(f'{len(faults)} faults at {len(sites)} sites '
          f'({len(nets)} nets, {len(branches)} branches)')
    print(f'{len(groups)} classes with the same outputs for all '
          f'{len(vecs)} input vectors:')
    for resp, fs in groups.items():
        tag = 'untestable: ' if list(resp) == good else ''
        print('  ' + tag + ', '.join(f'{s} s-a-{v}' for s, v in fs))


if __name__ == '__main__':
    main()
