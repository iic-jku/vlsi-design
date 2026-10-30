# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: cocotb testbench for the FIFO with a driver, a monitor,
# a reference model, a scoreboard, and functional coverage.
# Environment variables: SIM=verilator builds with code coverage, and
# SVA=1 adds the assertions of testbenches/sva. GL=1 (Icarus only)
# simulates the netlist fifo.nl.v of the macro folder, SDF=1 adds the
# delays of fifo.sdf. CLK_PERIOD_NS sets the clock (default 20), and
# CHECK=0 switches the scoreboard checks off.

import os
import random
from collections import Counter, deque
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly
from cocotb_tools.runner import get_results, get_runner

DEPTH = 4
WIDTH = 8
CLK_PERIOD_NS = float(os.getenv("CLK_PERIOD_NS", "20"))
CHECK = os.getenv("CHECK", "1") == "1"


class Scoreboard:
    """Reference model of the specification, checks, and coverage."""

    def __init__(self):
        self.model = deque()  # oldest entry first
        self.coverage = Counter()

    def check(self, full, empty, data):
        """Compare the outputs of the DUT with the model."""
        n = len(self.model)
        assert full == (n == DEPTH), f"full_o = {full}, {n} entries"
        assert empty == (n == 0), f"empty_o = {empty}, {n} entries"
        if n > 0:
            assert data == self.model[0], \
                f"data_o = {data}, expected {self.model[0]:0{WIDTH}b}"

    def update(self, push, data, pop):
        """Count coverage, then apply one clock edge to the model."""
        full, empty = len(self.model) == DEPTH, len(self.model) == 0
        state = "full" if full else "empty" if empty else "partial"
        op = ["idle", "pop", "push", "push+pop"][2 * push + pop]
        self.coverage[f"{op} when {state}"] += 1
        if pop and not empty:
            self.model.popleft()
        if push and not full:  # a full FIFO refuses a push
            self.model.append(data)


async def monitor(dut, sb):
    """Sample the DUT at every falling edge, after the driver."""
    while True:
        await ReadOnly()
        if CHECK:
            sb.check(dut.full_o.value, dut.empty_o.value,
                     dut.data_o.value)
        sb.update(int(dut.push_i.value), int(dut.data_i.value),
                  int(dut.pop_i.value))
        await FallingEdge(dut.clk_i)


async def driver(dut, transactions):
    """Apply one (push, data, pop) transaction per clock cycle."""
    for push, data, pop in transactions:
        dut.push_i.value = push
        dut.data_i.value = data
        dut.pop_i.value = pop
        await FallingEdge(dut.clk_i)
    dut.push_i.value = 0
    dut.pop_i.value = 0
    await ClockCycles(dut.clk_i, 2)


async def start_up(dut):
    """Start the clock, reset the DUT, and start the monitor."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, "ns").start())
    dut.rst_ni.value = 0
    dut.push_i.value = 0
    dut.data_i.value = 0
    dut.pop_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    sb = Scoreboard()
    cocotb.start_soon(monitor(dut, sb))
    return sb


def report(sb):
    """Log the coverage bins, return the bins that were never hit."""
    bins = [f"{op} when {state}"
            for op in ("idle", "push", "pop", "push+pop")
            for state in ("empty", "partial", "full")]
    for name in bins:
        cocotb.log.info(f"{name:24s} {sb.coverage[name]:5d}")
    return [name for name in bins if sb.coverage[name] == 0]


@cocotb.test()
async def test_fill_and_drain(dut):
    """Directed: push DEPTH values, then pop all of them."""
    sb = await start_up(dut)
    values = [0x11 * (i + 1) for i in range(DEPTH)]
    await driver(dut, [(1, v, 0) for v in values]
                 + [(0, 0, 1)] * DEPTH)
    report(sb)


@cocotb.test()
async def test_random(dut):
    """Random: phases of 50 cycles that tend to fill or to drain."""
    sb = await start_up(dut)
    transactions = []
    for _ in range(20):
        p_push = random.choice([0.2, 0.5, 0.8])
        for _ in range(50):
            push = int(random.random() < p_push)
            pop = int(random.random() < 1 - p_push)
            data = random.getrandbits(WIDTH)
            transactions.append((push, data, pop))
    await driver(dut, transactions)
    holes = report(sb)
    assert not holes, f"coverage holes: {holes}"


def fifo_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    macro_path = proj_path / "../.."

    top = "fifo"
    sources = [macro_path / "rtl/fifo.sv"]
    sva = macro_path / "testbenches/sva/fifo_sva.sv"
    build_args, plusargs = [], []
    if sim == "verilator":
        build_args = ["--coverage"]
        if os.getenv("SVA", "0") == "1":
            sources.append(sva)
    if os.getenv("GL", "0") == "1":
        cells = Path(os.environ["PDK_ROOT"]) \
            / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
        sources = [cells / "sg13cmos5l_udp.v",
                   cells / "sg13cmos5l_stdcell.v",
                   macro_path / "fifo.nl.v"]
        build_args = ["-gno-specify"]
        if os.getenv("SDF", "0") == "1":
            top = "fifo_sdf"
            sources.append(proj_path / "fifo_sdf.sv")
            build_args = ["-gspecify"]
            sdf_file = (macro_path / "fifo.sdf").resolve()
            plusargs = [f"+SDF={sdf_file}"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=top,
        build_args=build_args,
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel=top,
        test_module="fifo_tb",
        plusargs=plusargs,
        waves=True,
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    fifo_runner()
