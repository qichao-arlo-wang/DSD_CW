import math
import os
import random
import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def f2u(x: float) -> int:
    """Pack Python float to 32-bit unsigned int (IEEE-754 binary32 bit pattern)."""
    return struct.unpack("<I", struct.pack("<f", float(x)))[0]


def u2f(x: int) -> float:
    """Unpack 32-bit unsigned int bit pattern to Python float."""
    return struct.unpack("<f", struct.pack("<I", int(x) & 0xFFFFFFFF))[0]


def ref_f(x: float) -> float:
    """Software golden model for Task 7 function:
    f(x) = 0.5*x + x^3*cos((x-128)/128).
    """
    t = (x - 128.0) / 128.0
    return 0.5 * x + x * x * x * math.cos(t)


async def call_ci(dut, x: float) -> float:
    """Drive one custom-instruction transaction and wait for completion.

    Protocol assumptions:
    - Inputs are sampled on/after a cycle with start=1.
    - start is a one-cycle pulse.
    - done is asserted for at least one observed rising edge.
    """
    # Custom-instruction operand mapping used by this RTL:
    # dataa carries the FP32 x operand; datab and n are unused for this task.
    dut.dataa.value = f2u(x)
    dut.datab.value = 0
    dut.n.value = 0
    dut.start.value = 1

    # Launch request on next clock edge, then deassert start immediately.
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Timeout guard keeps failures actionable (hangs become explicit errors).
    for _ in range(2000):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            return u2f(int(dut.result.value))

    raise TimeoutError("Custom instruction did not assert done")


@cocotb.test()
async def test_task7_ci_f_single(dut):
    # Deterministic random stream for repeatable regressions.
    random.seed(int(os.getenv("SEED", "7")))

    # 50 MHz equivalent simulation clock: 20 ns period.
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # Bring DUT into a known reset state before issuing transactions.
    dut.reset.value = 1
    dut.clk_en.value = 1
    dut.start.value = 0
    dut.dataa.value = 0
    dut.datab.value = 0
    dut.n.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    # Directed vectors cover endpoints and representative interior values.
    vectors = [0.0, 16.0, 32.0, 64.0, 96.0, 128.0, 192.0, 255.0]
    for x in vectors:
        got = await call_ci(dut, x)
        expected = ref_f(x)
        abs_err = abs(got - expected)
        # Error budget:
        # - fixed absolute floor handles small-magnitude outputs
        # - proportional term scales tolerance for large |f(x)| near range edge
        tol = 2e-2 + 2e-5 * abs(expected)
        assert abs_err <= tol, (
            f"Mismatch for x={x}: got={got}, expected={expected}, "
            f"abs_err={abs_err}, tol={tol}"
        )

    # Random sweep checks broad numeric behavior over full required domain.
    for _ in range(200):
        x = random.uniform(0.0, 256.0)
        got = await call_ci(dut, x)
        expected = ref_f(x)
        abs_err = abs(got - expected)
        tol = 2e-2 + 2e-5 * abs(expected)
        assert abs_err <= tol, (
            f"Random mismatch for x={x}: got={got}, expected={expected}, "
            f"abs_err={abs_err}, tol={tol}"
        )

    await Timer(1, unit="us")
