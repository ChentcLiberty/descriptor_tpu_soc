"""
leaky_relu_derivative_parent 验证测试
验证方法学: Reference Model + Scoreboard + Coverage
leaky_relu_derivative: if H >= 0 then passthrough, else data * leak_factor
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


class LeakyReluDerivRefModel:
    """参考模型: 基于 H 值判断分支，而非 data 本身"""
    def __init__(self, leak_factor):
        self.leak_factor = leak_factor

    def compute(self, data, h_val):
        if h_val >= 0:
            return from_fixed(to_fixed(data))
        else:
            d_fxp = from_fixed(to_fixed(data))
            l_fxp = from_fixed(to_fixed(self.leak_factor))
            return from_fixed(to_fixed(d_fxp * l_fxp))


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
    dut.lr_d_valid_1_in.value = 0
    dut.lr_d_data_1_in.value = 0
    dut.lr_d_valid_2_in.value = 0
    dut.lr_d_data_2_in.value = 0
    dut.lr_d_H_1_in.value = 0
    dut.lr_d_H_2_in.value = 0
    dut.lr_leak_factor_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, col1_data, col1_h, col2_data, col2_h, leak, max_collect=15):
    dut.lr_leak_factor_in.value = to_fixed(leak)
    col1_res, col2_res = [], []
    n1, n2 = len(col1_data), len(col2_data)
    total_cycles = max(n1, n2) + max_collect

    for cyc in range(total_cycles):
        if cyc < max(n1, n2):
            if cyc < n1:
                dut.lr_d_data_1_in.value = to_fixed(col1_data[cyc])
                dut.lr_d_H_1_in.value = to_fixed(col1_h[cyc])
                dut.lr_d_valid_1_in.value = 1
            else:
                dut.lr_d_data_1_in.value = 0
                dut.lr_d_H_1_in.value = 0
                dut.lr_d_valid_1_in.value = 0
            if cyc < n2:
                dut.lr_d_data_2_in.value = to_fixed(col2_data[cyc])
                dut.lr_d_H_2_in.value = to_fixed(col2_h[cyc])
                dut.lr_d_valid_2_in.value = 1
            else:
                dut.lr_d_data_2_in.value = 0
                dut.lr_d_H_2_in.value = 0
                dut.lr_d_valid_2_in.value = 0
        else:
            dut.lr_d_valid_1_in.value = 0
            dut.lr_d_valid_2_in.value = 0

        await RisingEdge(dut.clk)

        if dut.lr_d_valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.lr_d_data_1_out.value.integer))
        if dut.lr_d_valid_2_out.value.integer:
            col2_res.append(from_fixed(dut.lr_d_data_2_out.value.integer))

        if cyc >= max(n1, n2) and len(col1_res) >= n1 and len(col2_res) >= n2:
            break

    return col1_res, col2_res


@cocotb.test()
async def test_h_positive_passthrough(dut):
    """TC1: H >= 0 时 data 直通"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluDerivRefModel(leak)
    sb = Scoreboard("h_positive")
    cov = FunctionalCoverage()

    col1_data = [1.5, -2.0, 0.5, -3.0]
    col1_h = [1.0, 0.5, 2.0, 0.1]  # 全正 H -> 全直通
    col2_data = [0.8, -1.5, 2.0, -0.5]
    col2_h = [0.3, 1.0, 0.0, 0.5]  # 全 >= 0

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col1_h, col2_data, col2_h, leak)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        sb.check(i, ref.compute(col1_data[i], col1_h[i]), col1_res[i], "col1")
        cov.sample("H>=0_passthrough")
    for i in range(4):
        sb.check(i, ref.compute(col2_data[i], col2_h[i]), col2_res[i], "col2")
        cov.sample("H>=0_passthrough")

    cov.report()
    sb.report()


@cocotb.test()
async def test_h_negative_scaled(dut):
    """TC2: H < 0 时 data 乘以 leak_factor"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluDerivRefModel(leak)
    sb = Scoreboard("h_negative")
    cov = FunctionalCoverage()

    col1_data = [1.5, -2.0, 0.5, -3.0]
    col1_h = [-1.0, -0.5, -2.0, -0.1]  # 全负 H -> 全缩放
    col2_data = [0.8, -1.5, 2.0, -0.5]
    col2_h = [-0.3, -1.0, -0.01, -0.5]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col1_h, col2_data, col2_h, leak)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        sb.check(i, ref.compute(col1_data[i], col1_h[i]), col1_res[i], "col1")
        cov.sample("H<0_scaled")
    for i in range(4):
        sb.check(i, ref.compute(col2_data[i], col2_h[i]), col2_res[i], "col2")
        cov.sample("H<0_scaled")

    cov.report()
    sb.report()


@cocotb.test()
async def test_mixed_h_values(dut):
    """TC3: H 正负混合"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluDerivRefModel(leak)
    sb = Scoreboard("mixed_h")
    cov = FunctionalCoverage()

    col1_data = [2.5, -1.2, 0.8, -3.1]
    col1_h = [0.5, -0.3, -0.1, 1.0]
    col2_data = [1.8, -0.9, 1.5, -2.2]
    col2_h = [-0.2, 0.7, 0.3, -0.8]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col1_h, col2_data, col2_h, leak)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        exp = ref.compute(col1_data[i], col1_h[i])
        sb.check(i, exp, col1_res[i], "col1")
        cov.sample("H>=0_passthrough" if col1_h[i] >= 0 else "H<0_scaled")
    for i in range(4):
        exp = ref.compute(col2_data[i], col2_h[i])
        sb.check(i, exp, col2_res[i], "col2")
        cov.sample("H>=0_passthrough" if col2_h[i] >= 0 else "H<0_scaled")

    cov.report()
    sb.report()


@cocotb.test()
async def test_single_column(dut):
    """TC4: 单列驱动"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluDerivRefModel(leak)
    sb = Scoreboard("single_col")

    dut.lr_leak_factor_in.value = to_fixed(leak)
    data_vals = [1.0, -2.0, 3.0, -4.0]
    h_vals = [0.5, -0.5, 0.5, -0.5]

    col1_res = []
    col2_count = 0

    for i in range(4):
        dut.lr_d_data_1_in.value = to_fixed(data_vals[i])
        dut.lr_d_H_1_in.value = to_fixed(h_vals[i])
        dut.lr_d_valid_1_in.value = 1
        dut.lr_d_valid_2_in.value = 0
        await RisingEdge(dut.clk)
        if dut.lr_d_valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.lr_d_data_1_out.value.integer))
        if dut.lr_d_valid_2_out.value.integer:
            col2_count += 1

    dut.lr_d_valid_1_in.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.lr_d_valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.lr_d_data_1_out.value.integer))
        if dut.lr_d_valid_2_out.value.integer:
            col2_count += 1

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert col2_count == 0, f"col2 should have 0 outputs, got {col2_count}"

    for i in range(4):
        sb.check(i, ref.compute(data_vals[i], h_vals[i]), col1_res[i], "col1")
    sb.report()


@cocotb.test()
async def test_valid_handshake(dut):
    """TC5: valid 信号握手"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.lr_leak_factor_in.value = to_fixed(0.1)
    dut.lr_d_data_1_in.value = to_fixed(5.0)
    dut.lr_d_H_1_in.value = to_fixed(1.0)
    dut.lr_d_valid_1_in.value = 1
    dut.lr_d_valid_2_in.value = 0
    await RisingEdge(dut.clk)

    dut.lr_d_valid_1_in.value = 0
    await RisingEdge(dut.clk)
    assert dut.lr_d_valid_1_out.value.integer == 1, "valid output expected 1 cycle after input"

    await RisingEdge(dut.clk)
    assert dut.lr_d_valid_1_out.value.integer == 0, "valid should deassert"
    cocotb.log.info("[valid_handshake] PASS")
