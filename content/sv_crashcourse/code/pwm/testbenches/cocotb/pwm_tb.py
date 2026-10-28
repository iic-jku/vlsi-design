# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for pwm (4-bit PWM).

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb_tools.runner import get_results, get_runner

WIDTH = 4
PERIOD = 2**WIDTH


async def start_up(dut):
    """Start a 50 MHz clock and reset the DUT for two cycles."""
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    dut.rst_ni.value = 0
    dut.duty_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1


@cocotb.test()
async def test_all_duty_values(dut):
    """For every duty d, pwm_o is high for d cycles per period."""
    await start_up(dut)
    for duty in range(PERIOD):
        dut.duty_i.value = duty
        for _ in range(2):  # the new duty reaches pwm_o
            await FallingEdge(dut.clk_i)
        high_cycles = 0
        for _ in range(PERIOD):
            await FallingEdge(dut.clk_i)
            assert dut.pwm_o.value.is_resolvable, "pwm_o is X or Z"
            high_cycles += int(dut.pwm_o.value)
        assert high_cycles == duty, \
            f"duty {duty} gives {high_cycles} high cycles"


@cocotb.test()
async def test_against_model(dut):
    """Random duty changes, checked cycle by cycle against a model."""
    await start_up(dut)
    rng = random.Random(42)  # fixed seed: every run is reproducible
    count, pwm, duty = 0, 0, 0  # model state after reset
    for _ in range(20 * PERIOD):
        if rng.random() < 0.05:
            # Keep the value in Python: a write becomes visible in
            # the DUT only at the end of the current time step
            duty = rng.randrange(PERIOD)
            dut.duty_i.value = duty
        await FallingEdge(dut.clk_i)
        # Model of the rising edge: both registers update at once
        pwm = 1 if count < duty else 0
        count = (count + 1) % PERIOD
        assert dut.pwm_o.value == pwm, \
            f"expected {pwm}, got {dut.pwm_o.value}"


def pwm_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / "../../rtl/pwm.sv"],
        hdl_toplevel="pwm",
        parameters={"WIDTH": WIDTH},
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel="pwm",
        test_module="pwm_tb",
        waves=True,
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    pwm_runner()
