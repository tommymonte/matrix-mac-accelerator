"""
Cocotb testbench for rtl/top.sv — Step 4 end-to-end integration.

Flow per test vector:
  1. Write 16 A elements via AXI (ADDR_A_BASE)
  2. Write 16 B elements via AXI (ADDR_B_BASE)
  3. Write CTRL.start (0x1)
  4. Poll STATUS until done bit (bit 1) is set
  5. Read 16 C elements via AXI (ADDR_C_BASE)
  6. Compare against integer matmul gold (int64 → wrap to int32)

Gold model: raw Q8.8 integer matmul.  C_raw[i][j] = sum_k(A_raw[i,k] * B_raw[k,j]).
For full-range int16 operands the 4-term sum can overflow int32, so gold is
computed in int64 and then wrapped with .astype(np.int32) — matching the RTL's
2's-complement wrapping accumulator.
"""

import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 10

ADDR_CTRL   = 0x00
ADDR_STATUS = 0x04
ADDR_A_BASE = 0x10
ADDR_B_BASE = 0x50
ADDR_C_BASE = 0x90

RESP_OKAY   = 0b00
STATUS_BUSY = 0x1
STATUS_DONE = 0x2


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset(dut, cycles=4):
    dut.rst_n.value         = 0
    dut.s_axi_awaddr.value  = 0
    dut.s_axi_awprot.value  = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value   = 0
    dut.s_axi_wstrb.value   = 0b1111
    dut.s_axi_wvalid.value  = 0
    dut.s_axi_bready.value  = 0
    dut.s_axi_araddr.value  = 0
    dut.s_axi_arprot.value  = 0
    dut.s_axi_arvalid.value = 0
    dut.s_axi_rready.value  = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ps")


async def axi_write(dut, addr: int, data: int, timeout_cycles: int = 40) -> int:
    dut.s_axi_awaddr.value  = addr & 0xFF
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value   = data & 0xFFFFFFFF
    dut.s_axi_wvalid.value  = 1
    dut.s_axi_bready.value  = 1
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ps")
        if int(dut.s_axi_bvalid.value):
            bresp = int(dut.s_axi_bresp.value)
            dut.s_axi_awvalid.value = 0
            dut.s_axi_wvalid.value  = 0
            dut.s_axi_bready.value  = 0
            return bresp
    raise TimeoutError(f"axi_write @0x{addr:02X}: no BVALID in {timeout_cycles} cycles")


async def axi_read(dut, addr: int, timeout_cycles: int = 40):
    dut.s_axi_araddr.value  = addr & 0xFF
    dut.s_axi_arvalid.value = 1
    dut.s_axi_rready.value  = 1
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ps")
        if int(dut.s_axi_rvalid.value):
            rdata = int(dut.s_axi_rdata.value)
            rresp = int(dut.s_axi_rresp.value)
            dut.s_axi_arvalid.value = 0
            dut.s_axi_rready.value  = 0
            return rdata, rresp
    raise TimeoutError(f"axi_read @0x{addr:02X}: no RVALID in {timeout_cycles} cycles")


def to_signed16(v: int) -> int:
    return v if v < (1 << 15) else v - (1 << 16)


def to_signed32(v: int) -> int:
    return v if v < (1 << 31) else v - (1 << 32)


def matmul_gold(a_flat, b_flat):
    """4×4 integer matmul in int64, wrapped to int32 (mirrors RTL 2's-complement)."""
    A = np.array(a_flat, dtype=np.int64).reshape(4, 4)
    B = np.array(b_flat, dtype=np.int64).reshape(4, 4)
    return (A @ B).astype(np.int32).flatten().tolist()


async def write_matrix(dut, base: int, vals):
    for i, v in enumerate(vals):
        bresp = await axi_write(dut, base + i * 4, int(v) & 0xFFFF)
        assert bresp == RESP_OKAY, f"write_matrix @0x{base:02X}[{i}] got bresp={bresp}"


async def read_matrix_c(dut):
    result = []
    for i in range(16):
        rdata, rresp = await axi_read(dut, ADDR_C_BASE + i * 4)
        assert rresp == RESP_OKAY, f"read C[{i}] rresp={rresp}"
        result.append(to_signed32(rdata))
    return result


async def poll_done(dut, timeout_reads: int = 200):
    for _ in range(timeout_reads):
        rdata, _ = await axi_read(dut, ADDR_STATUS)
        if rdata & STATUS_DONE:
            return
    raise TimeoutError("poll_done: STATUS.done never set")


async def run_matmul(dut, a_flat, b_flat):
    """Full end-to-end: write A/B, fire start, poll done, return C (list of 16 int32)."""
    await write_matrix(dut, ADDR_A_BASE, a_flat)
    await write_matrix(dut, ADDR_B_BASE, b_flat)
    await axi_write(dut, ADDR_CTRL, 0x1)
    await poll_done(dut)
    return await read_matrix_c(dut)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_defaults(dut):
    """STATUS==0 and C reads all 0 after reset."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    rdata, rresp = await axi_read(dut, ADDR_STATUS)
    assert rresp == RESP_OKAY
    assert rdata == 0, f"STATUS after reset = 0x{rdata:08X}"

    for i in range(16):
        rdata, rresp = await axi_read(dut, ADDR_C_BASE + i * 4)
        assert rresp == RESP_OKAY
        assert rdata == 0, f"C[{i}] after reset = 0x{rdata:08X}"


@cocotb.test()
async def test_zero_matmul(dut):
    """A=0, B=0 → C must be all zeros."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    a = [0] * 16
    b = [0] * 16
    c = await run_matmul(dut, a, b)
    assert all(v == 0 for v in c), f"Zero matmul produced non-zero C: {c}"


@cocotb.test()
async def test_identity_matmul(dut):
    """A=I, B=I (raw value 1 on diagonal) → C[i][i]=1, off-diagonal=0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # Raw value 1 (not 1.0 in Q8.8 — purely integer identity for structural check)
    a = [1 if (i // 4 == i % 4) else 0 for i in range(16)]
    b = [1 if (i // 4 == i % 4) else 0 for i in range(16)]
    c = await run_matmul(dut, a, b)
    gold = matmul_gold(a, b)
    assert c == gold, f"Identity matmul mismatch:\n  got  {c}\n  gold {gold}"


@cocotb.test()
async def test_known_matmul(dut):
    """Fixed small-value matmul with easily verifiable result."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # A = all 2s, B = all 3s → C[i][j] = 4 * (2*3) = 24
    a = [2] * 16
    b = [3] * 16
    c = await run_matmul(dut, a, b)
    gold = matmul_gold(a, b)
    assert c == gold, f"Known matmul mismatch:\n  got  {c}\n  gold {gold}"
    assert all(v == 24 for v in c), f"Expected all 24, got {c}"


@cocotb.test()
async def test_random_50(dut):
    """50 random 4×4 Q8.8 matrix pairs, verified against int64 gold model."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    rng = random.Random(0xDEAD_BEEF)
    for trial in range(50):
        a = [rng.randint(-32768, 32767) for _ in range(16)]
        b = [rng.randint(-32768, 32767) for _ in range(16)]
        c = await run_matmul(dut, a, b)
        gold = matmul_gold(a, b)
        assert c == gold, (
            f"Trial {trial}: mismatch\n"
            f"  A={a}\n  B={b}\n  got={c}\n  gold={gold}"
        )


@cocotb.test()
async def test_back_to_back(dut):
    """10 consecutive runs without any idle gap between done and next start."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    rng = random.Random(0xC0C0_C0C0)
    for trial in range(10):
        a = [rng.randint(-128, 127) for _ in range(16)]
        b = [rng.randint(-128, 127) for _ in range(16)]
        # Write A/B and fire immediately (no extra idle cycles inserted)
        c = await run_matmul(dut, a, b)
        gold = matmul_gold(a, b)
        assert c == gold, (
            f"Back-to-back trial {trial}: mismatch\n"
            f"  got={c}\n  gold={gold}"
        )


@cocotb.test()
async def test_soft_reset_clears_array(dut):
    """CTRL.soft_reset (bit1) resets mac_array; STATUS.busy goes 0 and re-run works."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # Load A=I, B=I and fire once to get a valid result baseline
    a = [1 if (i // 4 == i % 4) else 0 for i in range(16)]
    b = [1 if (i // 4 == i % 4) else 0 for i in range(16)]
    await write_matrix(dut, ADDR_A_BASE, a)
    await write_matrix(dut, ADDR_B_BASE, b)
    await axi_write(dut, ADDR_CTRL, 0x1)
    await poll_done(dut)

    # Issue soft_reset
    await axi_write(dut, ADDR_CTRL, 0x2)

    # After soft reset, STATUS.busy should be 0 (mac_array back in IDLE)
    for _ in range(5):
        await RisingEdge(dut.clk)
    rdata, _ = await axi_read(dut, ADDR_STATUS)
    assert (rdata & STATUS_BUSY) == 0, f"busy still set after soft_reset: STATUS=0x{rdata:08X}"

    # A new computation must still work correctly
    c = await run_matmul(dut, a, b)
    gold = matmul_gold(a, b)
    assert c == gold, f"Post-soft-reset matmul mismatch: {c} != {gold}"
