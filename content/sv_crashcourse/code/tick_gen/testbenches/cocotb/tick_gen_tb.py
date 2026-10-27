# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for tick_gen.

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb_tools.runner import get_results, get_runner

DIV = 5  # passed to the DUT as parameter in the runner below


async def start_up(dut):
    """Start a 50 MHz clock and apply the active-low reset for two cycles."""
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    dut.rst_ni.value = 0
    dut.en_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1


@cocotb.test()
async def test_no_tick_when_disabled(dut):
    """tick_o stays low while en_i is low."""
    await start_up(dut)
    for _ in range(3 * DIV):
        await FallingEdge(dut.clk_i)
        assert dut.tick_o.value == 0, "tick while disabled"


@cocotb.test()
async def test_tick_every_div_cycles(dut):
    """tick_o is high for one cycle every DIV cycles."""
    await start_up(dut)
    dut.en_i.value = 1
    for cycle in range(1, 4 * DIV + 1):
        await FallingEdge(dut.clk_i)
        expected = 1 if cycle % DIV == 0 else 0
        assert dut.tick_o.value == expected, \
            f"cycle {cycle}: expected {expected}, got {dut.tick_o.value}"


def tick_gen_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / "../../rtl/tick_gen.sv"],
        hdl_toplevel="tick_gen",
        parameters={"DIV": DIV},
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel="tick_gen",
        test_module="tick_gen_tb",
        waves=True,
    )

    # A failing test does not change the exit status, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    tick_gen_runner()
