# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Turns the test vectors that Fault generated for the cut
# netlist (JSON) into scan patterns for tb_scan.sv. Follows the scan
# chain of the scan netlist from scan_in_0 to scan_out_0 and writes
# one line per vector: the chain bits in the order they are shifted
# in, then data_i, shamt_i, and mode_i. Usage:
#   python3 scan_patterns.py <scan netlist> <vectors> > <patterns>

import json
import re
import sys

netlist, vectors = sys.argv[1], sys.argv[2]

# Each scan flip-flop with the nets at its pins SCD and Q
by_scd, q_net = {}, {}
cells = re.findall(r'sg13cmos5l_sdf\w+\s+(\S+)\s*\((.*?)\);',
                   open(netlist).read(), re.S)
for name, pins in cells:
    pin = dict(re.findall(r'\.(\w+)\(([^()]*)\)', pins))
    by_scd[pin['SCD'].strip()] = name
    q_net[name] = pin['Q'].strip()

# The chain, from the flip-flop at scan_in_0 to the one at scan_out_0
chain, net = [], 'scan_in_0'
while net in by_scd:
    chain.append(by_scd[net])
    net = q_net[chain[-1]]
print(f'chain of {len(chain)} flip-flops: {" ".join(chain)}',
      file=sys.stderr)

# The first bit shifted in ends up in the last flip-flop of the chain
tv = json.load(open(vectors))
names = [port['name'] for port in tv['inputs']]
width = {p['name']: p['from'] - p['to'] + 1 for p in tv['inputs']}
for entry in tv['coverageList']:
    value = {n: v[1] for n, v in zip(names, entry['vector'])}
    bits = ''.join(str(value[ff]) for ff in reversed(chain))
    for port in ('data_i', 'shamt_i', 'mode_i'):
        bits += format(value[port], f'0{width[port]}b')
    print(bits)
