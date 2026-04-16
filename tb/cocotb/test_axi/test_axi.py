"""
Cocotb testbench for rtl/axi_slave.sv — Step 3 of the Matrix-MAC accelerator.

A minimal hand-rolled AXI4-Lite master drives the DUT (cocotbext-axi is not
yet installed; we'll switch later if/when needed).

AXI4-Lite handshake protocol (condensed)
----------------------------------------
Each channel is a VALID/READY pair. The sender asserts VALID and holds the
payload stable until the receiver asserts READY on the same rising edge — that
is the "handshake" (ARM IHI 0022, §A3.2). Rules followed here:
  - Master drives AxVALID / WVALID / BREADY / RREADY.
  - Slave drives AxREADY / WREADY / BVALID / RVALID.
  - VALID, once asserted, must remain high until handshake completes.
  - The master does NOT wait for AxREADY before asserting AxVALID.

Timing pattern (Icarus + cocotb 2.0.1)
--------------------------------------
Signals are driven right after a `RisingEdge(clk)`. They are sampled by the
DUT on the *next* RisingEdge. After that edge we `Timer(1, "ps")` to step past
the NBA region before reading Q-side values. This matches the convention used
in test_mac / test_array.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 10  # 100 MHz sim clock

# Register map (mirrors CLAUDE.md and rtl/axi_slave.sv)
ADDR_CTRL   = 0x00
ADDR_STATUS = 0x04
ADDR_A_BASE = 0x10
ADDR_B_BASE = 0x50
ADDR_C_BASE = 0x90

RESP_OKAY   = 0b00
RESP_SLVERR = 0b10


# ----------------------------------------------------------------------------
# Reset + clock helpers
# ----------------------------------------------------------------------------

async def reset(dut, cycles: int = 4):
    """Drive synchronous active-low reset and idle all master-driven signals."""
    dut.rst_n.value        = 0
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
    dut.busy.value   = 0
    dut.done.value   = 0
    dut.c_flat.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ps")


# ----------------------------------------------------------------------------
# AXI4-Lite master primitives
# ----------------------------------------------------------------------------

async def axi_write(dut, addr: int, data: int, timeout_cycles: int = 40) -> int:
    """
    Perform a single AXI4-Lite write transaction.

    Returns BRESP (2 bits). Raises on timeout.

    Handshake strategy: we drive AWVALID/WVALID/BREADY high and wait for BVALID.
    BVALID implies the AW/W handshake already happened (the slave cannot produce
    a B response without first accepting AW/W). Polling {AW,W}READY directly is
    unreliable because they may be combinational and drop on the same edge as
    the handshake — after NBA we'd see them low even though the handshake fired.
    """
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
    """
    Perform a single AXI4-Lite read transaction.

    Returns (rdata, rresp). Same rationale as axi_write: wait for RVALID, which
    guarantees the AR handshake has completed.
    """
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


# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

@cocotb.test()
async def test_reset_defaults(dut):
    """After reset: STATUS == 0; A/B registers all 0; read of CTRL returns 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    rdata, rresp = await axi_read(dut, ADDR_STATUS)
    assert rresp == RESP_OKAY, f"STATUS read resp={rresp:02b}"
    assert rdata == 0, f"STATUS after reset should be 0, got 0x{rdata:08X}"

    rdata, rresp = await axi_read(dut, ADDR_CTRL)
    assert rresp == RESP_OKAY
    assert rdata == 0, f"CTRL should read 0 (self-clearing), got 0x{rdata:08X}"

    # Spot-check A[0] and B[15]
    for addr in (ADDR_A_BASE, ADDR_B_BASE + 15*4):
        rdata, rresp = await axi_read(dut, addr)
        assert rresp == RESP_OKAY
        assert rdata == 0


@cocotb.test()
async def test_write_read_matrix_a(dut):
    """Write all 16 A entries with unique values and read them back."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    values = [((i * 0x0101) ^ 0x00A5) & 0xFFFF for i in range(16)]

    for i, v in enumerate(values):
        bresp = await axi_write(dut, ADDR_A_BASE + i*4, v)
        assert bresp == RESP_OKAY, f"A[{i}] write bresp={bresp:02b}"

    for i, v in enumerate(values):
        rdata, rresp = await axi_read(dut, ADDR_A_BASE + i*4)
        assert rresp == RESP_OKAY
        assert rdata == v, f"A[{i}] mismatch: wrote 0x{v:08X}, read 0x{rdata:08X}"

    # Verify a_flat bus matches written values (low 16 bits of each lane).
    a_flat = int(dut.a_flat.value)
    for i, v in enumerate(values):
        lane = (a_flat >> (16*i)) & 0xFFFF
        assert lane == (v & 0xFFFF), f"a_flat lane {i} mismatch"


@cocotb.test()
async def test_write_read_matrix_b(dut):
    """Write all 16 B entries with unique values and read them back."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    values = [(0xBEEF + i*3) & 0xFFFF for i in range(16)]
    for i, v in enumerate(values):
        bresp = await axi_write(dut, ADDR_B_BASE + i*4, v)
        assert bresp == RESP_OKAY

    for i, v in enumerate(values):
        rdata, rresp = await axi_read(dut, ADDR_B_BASE + i*4)
        assert rresp == RESP_OKAY
        assert rdata == v


@cocotb.test()
async def test_c_region_readonly(dut):
    """C region is read-only: writes must return SLVERR and not corrupt state."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # Drive a known c_flat pattern from the "mac_array" side
    pattern = 0
    for i in range(16):
        pattern |= ((0xCAFE0000 + i) & 0xFFFFFFFF) << (32*i)
    dut.c_flat.value = pattern

    # Write attempt → SLVERR
    bresp = await axi_write(dut, ADDR_C_BASE, 0xDEAD_BEEF)
    assert bresp == RESP_SLVERR, f"Expected SLVERR on C write, got {bresp:02b}"

    # Readback must still show the driven c_flat pattern
    for i in range(16):
        rdata, rresp = await axi_read(dut, ADDR_C_BASE + i*4)
        assert rresp == RESP_OKAY
        expected = (0xCAFE0000 + i) & 0xFFFFFFFF
        assert rdata == expected, f"C[{i}] read 0x{rdata:08X}, expected 0x{expected:08X}"


@cocotb.test()
async def test_unmapped_address(dut):
    """Access to unmapped addresses must return SLVERR for both read and write."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    for bad_addr in (0x08, 0x0C, 0xD0, 0xFC):
        rdata, rresp = await axi_read(dut, bad_addr)
        assert rresp == RESP_SLVERR, f"Read @0x{bad_addr:02X} expected SLVERR, got {rresp:02b}"

        bresp = await axi_write(dut, bad_addr, 0x12345678)
        assert bresp == RESP_SLVERR, f"Write @0x{bad_addr:02X} expected SLVERR, got {bresp:02b}"

    # Unaligned address (bit[1:0] != 0)
    for bad_addr in (0x11, 0x13, 0x52):
        _, rresp = await axi_read(dut, bad_addr)
        assert rresp == RESP_SLVERR, f"Unaligned read @0x{bad_addr:02X} expected SLVERR"


@cocotb.test()
async def test_ctrl_start_pulse(dut):
    """Writing CTRL with bit0=1 produces a one-cycle start_pulse; CTRL self-clears."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # Monitor start_pulse in background
    pulses = []
    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, unit="ps")
            if int(dut.start_pulse.value):
                pulses.append(cocotb.utils.get_sim_time(unit="ns"))
    mon = cocotb.start_soon(monitor())

    bresp = await axi_write(dut, ADDR_CTRL, 0x1)
    assert bresp == RESP_OKAY

    # A few idle cycles so the pulse definitely fires and deasserts
    for _ in range(4):
        await RisingEdge(dut.clk)
    mon.kill()

    assert len(pulses) == 1, f"Expected exactly 1 start_pulse, saw {len(pulses)}"

    # CTRL should read back as 0
    rdata, _ = await axi_read(dut, ADDR_CTRL)
    assert rdata == 0, f"CTRL should self-clear, read 0x{rdata:08X}"


@cocotb.test()
async def test_status_done_sticky_and_w1c(dut):
    """done pulse latches STATUS.done; writing 1 to STATUS.done clears it."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    # Pulse done from the mac_array side for one cycle
    await RisingEdge(dut.clk)
    dut.done.value = 1
    await RisingEdge(dut.clk)
    dut.done.value = 0

    rdata, _ = await axi_read(dut, ADDR_STATUS)
    assert (rdata & 0x2) != 0, f"STATUS.done should be sticky-set, read 0x{rdata:08X}"

    # Clear via W1C
    bresp = await axi_write(dut, ADDR_STATUS, 0x2)
    assert bresp == RESP_OKAY

    rdata, _ = await axi_read(dut, ADDR_STATUS)
    assert (rdata & 0x2) == 0, f"STATUS.done should be cleared, read 0x{rdata:08X}"


@cocotb.test()
async def test_status_busy_passthrough(dut):
    """STATUS.busy reflects the live `busy` input."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    dut.busy.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ps")

    rdata, _ = await axi_read(dut, ADDR_STATUS)
    assert (rdata & 0x1) == 1, f"STATUS.busy should mirror busy input, read 0x{rdata:08X}"

    dut.busy.value = 0
    rdata, _ = await axi_read(dut, ADDR_STATUS)
    assert (rdata & 0x1) == 0


@cocotb.test()
async def test_random_rw_stress(dut):
    """Random interleaved writes and reads over A/B — readback must match a shadow model."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    random.seed(0xC0DE)
    shadow_a = [0]*16
    shadow_b = [0]*16

    for _ in range(200):
        op = random.choice(("wa", "wb", "ra", "rb"))
        idx = random.randrange(16)
        if op == "wa":
            v = random.randrange(1 << 32)
            shadow_a[idx] = v
            assert (await axi_write(dut, ADDR_A_BASE + idx*4, v)) == RESP_OKAY
        elif op == "wb":
            v = random.randrange(1 << 32)
            shadow_b[idx] = v
            assert (await axi_write(dut, ADDR_B_BASE + idx*4, v)) == RESP_OKAY
        elif op == "ra":
            rdata, rresp = await axi_read(dut, ADDR_A_BASE + idx*4)
            assert rresp == RESP_OKAY
            assert rdata == shadow_a[idx], f"A[{idx}] shadow 0x{shadow_a[idx]:08X} vs dut 0x{rdata:08X}"
        else:
            rdata, rresp = await axi_read(dut, ADDR_B_BASE + idx*4)
            assert rresp == RESP_OKAY
            assert rdata == shadow_b[idx], f"B[{idx}] shadow 0x{shadow_b[idx]:08X} vs dut 0x{rdata:08X}"
