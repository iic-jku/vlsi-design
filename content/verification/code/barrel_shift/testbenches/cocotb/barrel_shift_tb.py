# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Self-checking cocotb testbench for barrel_shift with a
# Python reference model, an exhaustive test (WIDTH <= 8 only), and a
# random test with corner values. WIDTH (default 8) sets the DUT
# parameter, TOPLEVEL=barrel_shift_bug selects the exercise version.

import os
import random
import time
from pathlib import Path

import cocotb
from cocotb.triggers import Timer
from cocotb_tools.runner import get_results, get_runner

WIDTH = int(os.getenv("WIDTH", "8"))
MASK = (1 << WIDTH) - 1
NUM_RANDOM = 10_000


def model(data, shamt, mode):
    """Reference model: what barrel_shift must compute."""
    if mode == 0:
        return (data << shamt) & MASK
    if mode == 1:
        return data >> shamt
    if mode == 2:
        return ((data << shamt) | (data >> (WIDTH - shamt))) & MASK
    return ((data >> shamt) | (data << (WIDTH - shamt))) & MASK


async def check(dut, data, shamt, mode):
    """Apply one input vector and compare data_o with the model."""
    dut.data_i.value = data
    dut.shamt_i.value = shamt
    dut.mode_i.value = mode
    await Timer(1, "ns")
    expected = model(data, shamt, mode)
    assert dut.data_o.value == expected, (
        f"data {data:#x}, shamt {shamt}, mode {mode}: "
        f"expected {expected:0{WIDTH}b}, got {dut.data_o.value}")


@cocotb.test(skip=WIDTH > 8)
async def test_exhaustive(dut):
    """All 2**WIDTH * WIDTH * 4 input vectors."""
    start = time.perf_counter()
    for data in range(1 << WIDTH):
        for shamt in range(WIDTH):
            for mode in range(4):
                await check(dut, data, shamt, mode)
    num = (1 << WIDTH) * WIDTH * 4
    rate = num / (time.perf_counter() - start)
    cocotb.log.info(f"{num} vectors, {rate:.0f} vectors/s")


@cocotb.test()
async def test_random(dut):
    """Corner values first, then NUM_RANDOM random vectors."""
    corners = [0, MASK, 1, 1 << (WIDTH - 1), 0x5555_5555 & MASK]
    for data in corners:
        for shamt in (0, 1, WIDTH - 1):
            for mode in range(4):
                await check(dut, data, shamt, mode)
    for _ in range(NUM_RANDOM):
        await check(dut, random.getrandbits(WIDTH),
                    random.randrange(WIDTH), random.randrange(4))


def barrel_shift_runner():
    sim = os.getenv("SIM", "icarus")
    top = os.getenv("TOPLEVEL", "barrel_shift")
    proj_path = Path(__file__).resolve().parent
    folder = "exercise" if top == "barrel_shift_bug" else "rtl"

    runner = get_runner(sim)
    runner.build(
        sources=[proj_path / f"../../{folder}/{top}.sv"],
        hdl_toplevel=top,
        parameters={"WIDTH": WIDTH},
        always=True,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        hdl_toplevel=top,
        test_module="barrel_shift_tb",
    )

    # A failing test leaves the exit status at 0, so check the results
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        raise SystemExit(
            f"FAIL: {num_failed} of {num_tests} tests failed")


if __name__ == "__main__":
    barrel_shift_runner()
