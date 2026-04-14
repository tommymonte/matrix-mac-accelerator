"""cocotb testbench for the 4×4 Q8.8 mac_array.

DUT behavior:
  - a_flat / b_flat : 256-bit packed buses; element [i][j] at bits 16*(4i+j)+15:16*(4i+j)
  - c_flat          : 512-bit packed bus;  element [i][j] at bits 32*(4i+j)+31:32*(4i+j)
  - start (in), done (out) — one-cycle done pulse
  - FSM latency: 6 cycles from the edge that samples start=1

Flat buses are required because Icarus VPI exposes 2-D unpacked ports as a single
packed handle that cocotb cannot index element-by-element.

Golden model: element-wise signed integer multiply-accumulate with 32-bit wrapping
(the v1 "no saturation" contract). Worst case 4×(−2¹⁵)² = 2³³ overflows; the RTL
wraps and so does our reference.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

N           = 4
ELEM_A_BITS = 16    # q8_8_t
ELEM_C_BITS = 32    # mac_acc_t
MASK16      = (1 << 16) - 1
MASK32      = (1 << 32) - 1


# ---------------------------------------------------------------------------
# Helpers — packing / unpacking
# ---------------------------------------------------------------------------

def to_signed(x: int, bits: int) -> int:
    """Two's-complement signed conversion for an arbitrary width."""
    mask = (1 << bits) - 1
    x &= mask
    if x >= (1 << (bits - 1)):
        x -= (1 << bits)
    return x


def pack_matrix(M, elem_bits: int) -> int:
    """Pack a 4×4 integer matrix to a flat integer, row-major.

    Element [i][j] is placed at bits elem_bits*(4*i+j)+elem_bits-1 : elem_bits*(4*i+j).
    """
    mask = (1 << elem_bits) - 1
    val  = 0
    for i in range(N):
        for j in range(N):
            val |= (M[i][j] & mask) << (elem_bits * (N * i + j))
    return val


def unpack_matrix(val, elem_bits: int):
    """Unpack a flat integer back to a 4×4 signed matrix."""
    mask = (1 << elem_bits) - 1
    M    = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            raw    = (val >> (elem_bits * (N * i + j))) & mask
            M[i][j] = to_signed(raw, elem_bits)
    return M


# ---------------------------------------------------------------------------
# Golden model
# ---------------------------------------------------------------------------

def matmul_ref(A, B):
    """4×4 matrix multiply; accumulator wraps at 32 bits after each k-step.

    Matches the RTL: the mac_unit accumulator is a 32-bit flip-flop, so each
    add wraps before the next k-iteration, not just at the end.
    """
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            acc = 0
            for k in range(N):
                acc = to_signed(acc + A[i][k] * B[k][j], 32)
            C[i][j] = acc
    return C


# ---------------------------------------------------------------------------
# DUT helpers
# ---------------------------------------------------------------------------

async def reset(dut):
    """Two-cycle synchronous active-low reset."""
    dut.rst_n.value  = 0
    dut.start.value  = 0
    dut.a_flat.value = 0
    dut.b_flat.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value  = 1
    await RisingEdge(dut.clk)


async def run_matmul(dut, A, B):
    """Drive A and B via flat buses, assert start, wait for done, return C.

    Canonical timing (identical pattern to test_mac.py):
      1. sync to rising edge
      2. drive flat input buses + assert start
      3. next rising edge  — DUT enters LOAD
      4. de-assert start
      5. poll until done=1 (read 1 ps after rising edge to clear NBA region)
      6. read and unpack c_flat
    """
    dut.a_flat.value = pack_matrix(A, ELEM_A_BITS)
    dut.b_flat.value = pack_matrix(B, ELEM_A_BITS)

    # Pulse start for one cycle
    await RisingEdge(dut.clk)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for done (FSM needs exactly 5 more cycles after start is deasserted)
    for _ in range(20):          # generous timeout
        await RisingEdge(dut.clk)
        await Timer(1, unit="ps")
        if dut.done.value == 1:
            break
    else:
        raise AssertionError("Timeout: done never asserted")

    raw = dut.c_flat.value.to_unsigned()
    return unpack_matrix(raw, ELEM_C_BITS)


def fmt_matrix(M, label=""):
    rows = "\n".join(
        "  [" + ", ".join(f"{M[i][j]:10d}" for j in range(N)) + "]"
        for i in range(N)
    )
    return f"{label}\n{rows}" if label else rows


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_zero_matrices(dut):
    """Zero × anything = zero matrix."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[0] * N for _ in range(N)]
    B = [[random.randint(-100, 100) for _ in range(N)] for _ in range(N)]

    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_identity(dut):
    """I × I = I."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    I = [[int(i == j) for j in range(N)] for i in range(N)]
    C_got = await run_matmul(dut, I, I)
    C_ref = matmul_ref(I, I)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"I×I C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_identity_times_matrix(dut):
    """I × A = A for an arbitrary matrix."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    I = [[int(i == j) for j in range(N)] for i in range(N)]
    A = [[10 * i + j for j in range(N)] for i in range(N)]

    C_got = await run_matmul(dut, I, A)
    C_ref = matmul_ref(I, A)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"I×A C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_ones_matrix(dut):
    """Ones × Ones: each C[i][j] = N = 4."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[1] * N for _ in range(N)]
    B = [[1] * N for _ in range(N)]
    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"Ones C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_negative_inputs(dut):
    """All-negative operands: C[i][j] should be positive (neg × neg = pos)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[-1] * N for _ in range(N)]
    B = [[-1] * N for _ in range(N)]
    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"Neg C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_directed_known_result(dut):
    """A = diag(1,2,3,4), B = ones → C[i][j] = i+1 for all j."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[int(i == j) * (i + 1) for j in range(N)] for i in range(N)]
    B = [[1] * N for _ in range(N)]
    C_expected = [[(i + 1)] * N for i in range(N)]

    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_ref[i][j] == C_expected[i][j], \
                f"Golden model sanity check failed at [{i}][{j}]"
            assert C_got[i][j] == C_ref[i][j], (
                f"Directed C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_consecutive_runs(dut):
    """Two back-to-back computations; accumulators must clear between runs."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A1 = [[1] * N for _ in range(N)]
    B1 = [[2] * N for _ in range(N)]
    A2 = [[3] * N for _ in range(N)]
    B2 = [[-1] * N for _ in range(N)]

    C1_got = await run_matmul(dut, A1, B1)
    C1_ref = matmul_ref(A1, B1)

    C2_got = await run_matmul(dut, A2, B2)
    C2_ref = matmul_ref(A2, B2)

    for i in range(N):
        for j in range(N):
            assert C1_got[i][j] == C1_ref[i][j], \
                f"Run-1 C[{i}][{j}]: expected {C1_ref[i][j]}, got {C1_got[i][j]}"
            assert C2_got[i][j] == C2_ref[i][j], \
                f"Run-2 C[{i}][{j}]: expected {C2_ref[i][j]}, got {C2_got[i][j]}"


@cocotb.test()
async def test_max_positive(dut):
    """All elements = max positive Q8.8 value (32767); verify wrapping model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[32767] * N for _ in range(N)]
    B = [[32767] * N for _ in range(N)]
    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"Max-pos C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_max_negative(dut):
    """All elements = min Q8.8 value (−32768); verify wrapping model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    A = [[-32768] * N for _ in range(N)]
    B = [[-32768] * N for _ in range(N)]
    C_got = await run_matmul(dut, A, B)
    C_ref = matmul_ref(A, B)

    for i in range(N):
        for j in range(N):
            assert C_got[i][j] == C_ref[i][j], (
                f"Max-neg C[{i}][{j}]: expected {C_ref[i][j]}, got {C_got[i][j]}"
            )


@cocotb.test()
async def test_random_100(dut):
    """100 random 4×4 matrices; all results must be bit-exact against the golden model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    random.seed(0xA77A)

    for trial in range(100):
        A = [[random.randint(-32768, 32767) for _ in range(N)] for _ in range(N)]
        B = [[random.randint(-32768, 32767) for _ in range(N)] for _ in range(N)]

        C_got = await run_matmul(dut, A, B)
        C_ref = matmul_ref(A, B)

        for i in range(N):
            for j in range(N):
                assert C_got[i][j] == C_ref[i][j], (
                    f"Random trial {trial} C[{i}][{j}]: "
                    f"expected {C_ref[i][j]}, got {C_got[i][j]}\n"
                    + fmt_matrix(A, "A:") + "\n"
                    + fmt_matrix(B, "B:") + "\n"
                    + fmt_matrix(C_got, "Got:") + "\n"
                    + fmt_matrix(C_ref, "Ref:")
                )
