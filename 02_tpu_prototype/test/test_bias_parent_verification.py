"""
bias_parent 验证测试
验证方法学: Reference Model + Scoreboard + Coverage
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

FRAC_BITS = 8
TOLERANCE = 0.05


def to_fixed(val, frac_bits=FRAC_BITS):
    scaled = int(round(val * (1 << frac_bits)))
    return scaled & 0xFFFF

def from_fixed(val, frac_bits=FRAC_BITS):
    if val >= 1 << 15:
        val -= 1 << 16
    return float(val) / (1 << frac_bits)


class BiasRefModel:
    def __init__(self, bias_scalar):
        self.bias_scalar = bias_scalar

    def compute(self, sys_data):
        a = from_fixed(to_fixed(sys_data))
        b = from_fixed(to_fixed(self.bias_scalar))
        return from_fixed(to_fixed(a + b))


class Scoreboard:
    def __init__(self, name, tolerance=TOLERANCE):
        self.name = name
        self.tolerance = tolerance
        self.pass_count = 0
        self.fail_count = 0
        self.errors = []

    def check(self, idx, expected, actual, tag=""):
        abs_err = abs(actual - expected)
        prefix = f"[{self.name}] {tag}[{idx}]"
        if abs_err <= self.tolerance:
            self.pass_count += 1
            cocotb.log.info(f"{prefix} PASS: exp={expected:.5f} got={actual:.5f}")
        else:
            self.fail_count += 1
            msg = f"{prefix} FAIL: exp={expected:.5f} got={actual:.5f} err={abs_err:.5f}"
            self.errors.append(msg)
            cocotb.log.error(msg)

    def report(self):
        total = self.pass_count + self.fail_count
        cocotb.log.info(f"[{self.name}] Scoreboard: {self.pass_count}/{total} passed")
        assert self.fail_count == 0, f"[{self.name}] {self.fail_count} checks failed"


class FunctionalCoverage:
    def __init__(self):
        self.bins = {}

    def sample(self, point):
        self.bins[point] = self.bins.get(point, 0) + 1

    def report(self):
        cocotb.log.info("=== Functional Coverage ===")
        for k, v in sorted(self.bins.items()):
            cocotb.log.info(f"  {k}: hit {v}x")


async def reset_dut(dut):
    dut.rst.value = 1
    dut.bias_scalar_in_1.value = 0
    dut.bias_sys_data_in_1.value = 0
    dut.bias_sys_valid_in_1.value = 0
    dut.bias_scalar_in_2.value = 0
    dut.bias_sys_data_in_2.value = 0
    dut.bias_sys_valid_in_2.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, col1_data, col2_data, bias1, bias2, max_collect=15):
    dut.bias_scalar_in_1.value = to_fixed(bias1)
    dut.bias_scalar_in_2.value = to_fixed(bias2)
    col1_res, col2_res = [], []
    n1, n2 = len(col1_data), len(col2_data)
    total_cycles = max(n1, n2) + max_collect

    for cyc in range(total_cycles):
        if cyc < max(n1, n2):
            if cyc < n1:
                dut.bias_sys_data_in_1.value = to_fixed(col1_data[cyc])
                dut.bias_sys_valid_in_1.value = 1
            else:
                dut.bias_sys_data_in_1.value = 0
                dut.bias_sys_valid_in_1.value = 0
            if cyc < n2:
                dut.bias_sys_data_in_2.value = to_fixed(col2_data[cyc])
                dut.bias_sys_valid_in_2.value = 1
            else:
                dut.bias_sys_data_in_2.value = 0
                dut.bias_sys_valid_in_2.value = 0
        else:
            dut.bias_sys_valid_in_1.value = 0
            dut.bias_sys_valid_in_2.value = 0

        await RisingEdge(dut.clk)

        if dut.bias_Z_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.bias_z_data_out_1.value.integer))
        if dut.bias_Z_valid_out_2.value.integer:
            col2_res.append(from_fixed(dut.bias_z_data_out_2.value.integer))

        if cyc >= max(n1, n2) and len(col1_res) >= n1 and len(col2_res) >= n2:
            break

    return col1_res, col2_res


@cocotb.test()
async def test_positive_bias_add(dut):
    """TC1: 正值偏置加法"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    bias1, bias2 = 0.5, 0.3
    ref1, ref2 = BiasRefModel(bias1), BiasRefModel(bias2)
    sb = Scoreboard("positive_bias")
    cov = FunctionalCoverage()

    col1_data = [1.0, 2.5, 0.5, 3.75]
    col2_data = [0.25, 1.5, 4.0, 0.125]
    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, bias1, bias2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref1.compute(inp), got, "col1")
        cov.sample("pos+pos_bias")
    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        sb.check(i, ref2.compute(inp), got, "col2")
        cov.sample("pos+pos_bias")

    cov.report()
    sb.report()


@cocotb.test()
async def test_negative_data_bias(dut):
    """TC2: 负值数据 + 正偏置"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    bias1, bias2 = 0.5, 0.3
    ref1, ref2 = BiasRefModel(bias1), BiasRefModel(bias2)
    sb = Scoreboard("neg_data")

    col1_data = [-1.0, -2.5, -0.5, -3.75]
    col2_data = [-0.25, -1.5, -4.0, -0.125]
    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, bias1, bias2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref1.compute(inp), got, "col1")
    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        sb.check(i, ref2.compute(inp), got, "col2")

    sb.report()


@cocotb.test()
async def test_mixed_values(dut):
    """TC3: 混合正负值 + 负偏置"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    bias1, bias2 = -0.5, 0.3
    ref1, ref2 = BiasRefModel(bias1), BiasRefModel(bias2)
    sb = Scoreboard("mixed")

    col1_data = [2.5, -1.2, 0.8, -3.1]
    col2_data = [1.8, -0.9, 1.5, -2.2]
    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, bias1, bias2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref1.compute(inp), got, "col1")
    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        sb.check(i, ref2.compute(inp), got, "col2")

    sb.report()


@cocotb.test()
async def test_single_column(dut):
    """TC4: 单列驱动"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    bias1 = 0.5
    ref1 = BiasRefModel(bias1)
    sb = Scoreboard("single_col")

    dut.bias_scalar_in_1.value = to_fixed(bias1)
    col1_data = [1.0, -2.0, 3.0, -4.0]

    col1_res = []
    col2_count = 0

    for val in col1_data:
        dut.bias_sys_data_in_1.value = to_fixed(val)
        dut.bias_sys_valid_in_1.value = 1
        dut.bias_sys_valid_in_2.value = 0
        await RisingEdge(dut.clk)
        if dut.bias_Z_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.bias_z_data_out_1.value.integer))
        if dut.bias_Z_valid_out_2.value.integer:
            col2_count += 1

    dut.bias_sys_valid_in_1.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.bias_Z_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.bias_z_data_out_1.value.integer))
        if dut.bias_Z_valid_out_2.value.integer:
            col2_count += 1

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert col2_count == 0, f"col2 should have 0 outputs, got {col2_count}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref1.compute(inp), got, "col1")
    sb.report()


@cocotb.test()
async def test_valid_handshake(dut):
    """TC5: valid 信号握手"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.bias_scalar_in_1.value = to_fixed(0.5)
    dut.bias_sys_data_in_1.value = to_fixed(1.0)
    dut.bias_sys_valid_in_1.value = 1
    dut.bias_sys_valid_in_2.value = 0
    await RisingEdge(dut.clk)

    dut.bias_sys_valid_in_1.value = 0
    await RisingEdge(dut.clk)
    assert dut.bias_Z_valid_out_1.value.integer == 1, "valid output expected 1 cycle after input"

    await RisingEdge(dut.clk)
    assert dut.bias_Z_valid_out_1.value.integer == 0, "valid should deassert"
    cocotb.log.info("[valid_handshake] PASS")


@cocotb.test()
async def test_zero_bias(dut):
    """TC6: 零偏置 — 输出应等于输入"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ref = BiasRefModel(0.0)
    sb = Scoreboard("zero_bias")

    col1_data = [1.5, -2.5, 0.0, 3.0]
    col2_data = [-1.0, 2.0, -3.0, 4.0]
    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, 0.0, 0.0)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref.compute(inp), got, "col1")
    sb.report()
