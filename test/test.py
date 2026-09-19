"""Pin-only regression: identical assertions on RTL and GDS gate netlist."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

@cocotb.test()
async def test_vga_and_reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    await ClockCycles(dut.clk, 10)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    colors = {}
    hlow = vlow = visible = 0
    for tick in range(1, 800 * 525 + 1):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = int(dut.uo_out.value)
        x, y = tick % 800, (tick // 800) % 525
        assert bool(value & 0x80) == (not (656 <= x < 752)), (tick, "HSYNC")
        assert bool(value & 0x08) == (not (490 <= y < 492)), (tick, "VSYNC")
        hlow += not bool(value & 0x80)
        vlow += not bool(value & 0x08)
        rgb = value & 0x77
        if x >= 640 or y >= 480:
            assert rgb == 0, (x, y, "blanking")
        else:
            visible += 1
            colors[rgb] = colors.get(rgb, 0) + 1
        assert int(dut.uio_out.value) == 0
        assert int(dut.uio_oe.value) == 0
    assert visible == 640 * 480
    assert hlow == 96 * 525
    assert vlow == 2 * 800
    assert colors.get(0x33, 0) > 200, "missing yellow player"
    assert colors.get(0x11, 0) > 200, "missing red ghost"
    assert colors.get(0x64, 0) > 2000, "missing blue maze"
    assert colors.get(0x77, 0) > 500, "missing pellets/eyes"
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0x10
    await ClockCycles(dut.clk, 8)
    await Timer(1, unit="ns")
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uo_out.value) == 0x88
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    await Timer(1, unit="ns")
    assert int(dut.uo_out.value) == 0x88
