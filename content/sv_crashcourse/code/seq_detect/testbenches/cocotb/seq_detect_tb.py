# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for seq_detect with a
# Python reference model.

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb_tools.runner import get_results, get_runner

PATTERN = [1, 0, 1, 1]


async def start_up(dut):
    """Start a 50 MHz clock and reset the DUT for two cycles."""
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    dut.rst_ni.value = 0
    dut.bit_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1


async def send_and_check(dut, bits):
    """Send one bit per cycle, compare detect_o with the model."""
    history = []
    detections = 0
    for bit in bits:
        dut.bit_i.value = bit
        # The DUT samples the bit at the rising edge in between
        await FallingEdge(dut.clk_i)
        history.append(bit)
        expected = 1 if history[-len(PATTERN):] == PATTERN else 0
        assert dut.detect_o.value == expected, \
            f"after bits ...{history[-8:]}: " \
            f"expected {expected}, got {dut.detect_o.value}"
        detections += expected
    return detections


@cocotb.test()
async def test_overlapping(dut):
    """1011011 contains the pattern twice, the second overlapping."""
    await start_up(dut)
    detections = await send_and_check(dut, [1, 0, 1, 1, 0, 1, 1, 0, 0])
    assert detections == 2, f"expected 2 detections, got {detections}"


@cocotb.test()
async def test_random_bits(dut):
    """A long random bit stream against the reference model."""
    await start_up(dut)
    rng = random.Random(1234)  # fixed seed: every run is reproducible
    bits = [rng.randint(0, 1) for _ in range(500)]
    detections = await send_and_check(dut, bits)
    # Guard against a test that passes without ever seeing the pattern
    assert detections > 0, "no pattern in the random stream"
    dut._log.info(f"{detections} detections in {len(bits)} bits")


def seq_detect_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / "../../rtl/seq_detect.sv"],
        hdl_toplevel="seq_detect",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel="seq_detect",
        test_module="seq_detect_tb",
        waves=True,
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    seq_detect_runner()
