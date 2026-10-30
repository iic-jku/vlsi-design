# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for the exclusive counter.
# TOPLEVEL selects the architecture: excl_cnt_bin (default),
# excl_cnt_ring, excl_cnt_ring_for, or excl_cnt_johnson.

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb_tools.runner import get_results, get_runner


async def start_up(dut):
    """Start a 50 MHz clock and reset the DUT for two cycles."""
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    dut.rst_ni.value = 0
    dut.clr_i.value = 0
    dut.en_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1


@cocotb.test()
async def test_reset_value(dut):
    """After the reset, q_o[0] is the only high bit."""
    await start_up(dut)
    assert dut.q_o.value == 0b0000_0001, f"q_o = {dut.q_o.value}"


@cocotb.test()
async def test_count_and_wrap(dut):
    """en_i moves the high bit up by one and wraps from 7 to 0."""
    await start_up(dut)
    dut.en_i.value = 1
    for step in range(1, 20):
        await FallingEdge(dut.clk_i)
        expected = 1 << (step % 8)
        assert dut.q_o.value == expected, \
            f"step {step}: expected {expected:08b}, got {dut.q_o.value}"


@cocotb.test()
async def test_random_against_model(dut):
    """Random clr_i and en_i, compared with a model in every cycle."""
    await start_up(dut)
    rng = random.Random(1)
    index = 0  # position of the high bit in the model
    for cycle in range(500):
        clr, en = rng.random() < 0.1, rng.random() < 0.6
        dut.clr_i.value = int(clr)
        dut.en_i.value = int(en)
        await FallingEdge(dut.clk_i)
        if clr:
            index = 0
        elif en:
            index = (index + 1) % 8
        assert dut.q_o.value == 1 << index, \
            f"cycle {cycle}: expected {1 << index:08b}, got {dut.q_o.value}"


def excl_cnt_runner():
    sim = os.getenv("SIM", "icarus")
    top = os.getenv("TOPLEVEL", "excl_cnt_bin")
    proj_path = Path(__file__).resolve().parent

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / f"../../rtl/{top}.sv"],
        hdl_toplevel=top,
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel=top,
        test_module="excl_cnt_tb",
        waves=True,
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    excl_cnt_runner()
