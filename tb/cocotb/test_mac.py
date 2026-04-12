"""cocotb testbench for the Q8.8 mac_unit.

DUT behavior (registered, 1-cycle latency):
    if !rst_n: acc_out <= 0
    else if en: acc_out <= acc_in + a*b  (signed, wrapping 32-bit)
    else:       hold
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

MASK32 = (1 << 32) - 1


def to_signed32(x):
    """Wrap an arbitrary Python int into a signed 32-bit 2's complement int."""
    return ((x & MASK32) ^ (1 << 31)) - (1 << 31)


def mac_ref(a, b, acc_in):
    """Golden reference: signed 32-bit wrapping MAC."""
    return to_signed32(acc_in + a * b)


async def reset(dut):
    """Synchronous active-low reset sequence.
    Writes are scheduled before the first sync edge, then two clocks of
    rst_n=0 are observed before release."""
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.a.value = 0
    dut.b.value = 0
    dut.acc_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_and_check(dut, a, b, acc_in):
    """Drive one MAC vector with en=1 and check the registered output.

    Canonical cocotb pattern for posedge-triggered DUTs: sync to a clock
    edge first, THEN drive inputs (so they propagate in time for the next
    edge), THEN wait the next edge (DUT samples new inputs), THEN read."""
    await RisingEdge(dut.clk)
    dut.a.value = a & 0xFFFF
    dut.b.value = b & 0xFFFF
    dut.acc_in.value = acc_in & MASK32
    dut.en.value = 1
    await RisingEdge(dut.clk)
    # iverilog fires the posedge VPI callback in the active region, before NBAs
    # have applied. Step 1 ps past the edge so we see the post-NBA value and
    # can still write signals afterwards (unlike ReadOnly, which is read-only).
    await Timer(1, unit="ps")

    expected = mac_ref(a, b, acc_in)
    actual = dut.acc_out.value.signed_integer
    assert actual == expected, (
        f"MAC mismatch: a={a}, b={b}, acc_in={acc_in} -> "
        f"expected {expected}, got {actual}"
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_zero(dut):
    """0 * 0 + 0 == 0."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await drive_and_check(dut, 0, 0, 0)


@cocotb.test()
async def test_one_times_one(dut):
    """1 * 1 + 0 == 1."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await drive_and_check(dut, 1, 1, 0)


@cocotb.test()
async def test_directed_extremes(dut):
    """Directed corner cases covering Q1.15 extremes and mixed signs."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    vectors = [
        (0, 0, 0),
        (1, 1, 0),
        (32767, 32767, 0),
        (-32768, -32768, 0),
        (-32768, 32767, 0),
        (32767, 32767, 100),
        (-1, -1, -1),
        (100, -200, 50000),
    ]
    for a, b, acc_in in vectors:
        await drive_and_check(dut, a, b, acc_in)


@cocotb.test()
async def test_hold(dut):
    """When en=0 the accumulator output must hold its value."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Drive one valid MAC so acc_out becomes a known non-zero value.
    a, b, acc_in = 123, -45, 6789
    await drive_and_check(dut, a, b, acc_in)

    held = dut.acc_out.value.signed_integer

    # Now deassert en and scribble on the inputs for a few cycles.
    dut.en.value = 0
    dut.a.value = 0x1234
    dut.b.value = 0x5678
    dut.acc_in.value = 0xDEADBEEF & MASK32

    for _ in range(5):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ps")
        current = dut.acc_out.value.signed_integer
        assert current == held, (
            f"acc_out changed while en=0: expected {held}, got {current}"
        )


@cocotb.test()
async def test_reset(dut):
    """Synchronous reset clears acc_out even when en=1."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Make acc_out non-zero.
    await drive_and_check(dut, 1000, 1000, 12345)
    assert dut.acc_out.value.signed_integer != 0, "precondition: acc_out should be nonzero"

    # Pulse reset for one cycle while en stays high.
    dut.rst_n.value = 0
    dut.en.value = 1
    dut.a.value = 0x0FFF
    dut.b.value = 0x0FFF
    dut.acc_in.value = 0x0000_0001
    await RisingEdge(dut.clk)
    await Timer(1, unit="ps")

    # Release reset on the following edge and verify acc_out is 0.
    assert dut.acc_out.value.signed_integer == 0, (
        f"acc_out should be 0 after reset, got {dut.acc_out.value.signed_integer}"
    )
    dut.rst_n.value = 1


@cocotb.test()
async def test_random(dut):
    """1000 pseudo-random vectors against the golden model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    random.seed(0xC0C07B)
    for _ in range(1000):
        a = random.randint(-32768, 32767)
        b = random.randint(-32768, 32767)
        acc_in = random.randint(-(1 << 31), (1 << 31) - 1)
        await drive_and_check(dut, a, b, acc_in)
