# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for led_blink and, with
# TOPLEVEL=led_blink_fpga, for the FPGA version of the exercise.

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb_tools.runner import get_results, get_runner

DIV = 4  # passed to the DUT as parameter in the runner below


@cocotb.test()
async def test_led_toggles_every_2div_cycles(dut):
    """led_o toggles exactly every 2*DIV clock cycles."""
    cocotb.start_soon(Clock(dut.clk_i, 20, "ns").start())
    if hasattr(dut, "rst_ni"):  # the FPGA version has no reset
        dut.rst_ni.value = 0
        await ClockCycles(dut.clk_i, 2)
        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 1

    toggles = []
    last = None
    for cycle in range(10 * DIV):
        await FallingEdge(dut.clk_i)
        assert dut.led_o.value.is_resolvable, f"cycle {cycle}: led_o is x"
        led = int(dut.led_o.value)
        if last is not None and led != last:
            toggles.append(cycle)
        last = led

    assert toggles, "led_o never toggles"
    assert toggles[0] < 2 * DIV, f"first toggle too late: {toggles[0]}"
    gaps = [b - a for a, b in zip(toggles, toggles[1:])]
    assert all(g == 2 * DIV for g in gaps), f"toggle gaps {gaps}"


def led_blink_runner():
    sim = os.getenv("SIM", "icarus")
    top = os.getenv("TOPLEVEL", "led_blink")
    proj_path = Path(__file__).resolve().parent
    folder = "exercise" if top == "led_blink_fpga" else "rtl"

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / f"../../{folder}/{top}.sv"],
        hdl_toplevel=top,
        parameters={"DIV": DIV},
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel=top,
        test_module="led_blink_tb",
        waves=True,
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    led_blink_runner()
