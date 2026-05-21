import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    dut.rst.value = 1
    dut.ready_in.value = 0
    for i in range(2):
        dut.data_in[i].value = 0
        dut.valid_in[i].value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_single_stall_holds_payload(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.ready_in.value = 0
    dut.data_in[0].value = 0x0011
    dut.data_in[1].value = 0x0022
    dut.valid_in[0].value = 1
    dut.valid_in[1].value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert dut.holding_out.value.integer == 1
    assert dut.valid_out[0].value.integer == 1
    assert dut.valid_out[1].value.integer == 1
    assert dut.data_out[0].value.integer == 0x0011
    assert dut.data_out[1].value.integer == 0x0022
    assert dut.overflow_out.value.integer == 0

    dut.data_in[0].value = 0x00AA
    dut.data_in[1].value = 0x00BB
    dut.valid_in[0].value = 0
    dut.valid_in[1].value = 0
    await Timer(1, units="ns")

    assert dut.data_out[0].value.integer == 0x0011
    assert dut.data_out[1].value.integer == 0x0022

    dut.ready_in.value = 1
    await Timer(1, units="ns")
    assert dut.fire_out.value.integer == 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert dut.holding_out.value.integer == 0


@cocotb.test()
async def test_second_stalled_beat_raises_overflow(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.ready_in.value = 0
    dut.data_in[0].value = 0x0101
    dut.data_in[1].value = 0x0202
    dut.valid_in[0].value = 1
    dut.valid_in[1].value = 1
    await RisingEdge(dut.clk)

    dut.data_in[0].value = 0x0303
    dut.data_in[1].value = 0x0404
    dut.valid_in[0].value = 1
    dut.valid_in[1].value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert dut.holding_out.value.integer == 1
    assert dut.overflow_out.value.integer == 1
    assert dut.data_out[0].value.integer == 0x0101
    assert dut.data_out[1].value.integer == 0x0202
