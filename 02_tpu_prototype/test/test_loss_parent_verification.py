"""
loss_parent 验证测试
验证方法学: Reference Model + Scoreboard + Coverage
MSE 梯度: gradient = (2/N) * (H - Y)
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

FRAC_BITS = 8
TOLERANCE = 0.08  # loss 有两级运算，容差稍大


def to_fixed(val, frac_bits=FRAC_BITS):
    scaled = int(round(val * (1 << frac_bits)))
    return scaled & 0xFFFF

def from_fixed(val, frac_bits=FRAC_BITS):
    if val >= 1 << 15:
        val -= 1 << 16
    return float(val) / (1 << frac_bits)


class LossRefModel:
    """MSE 梯度参考模型: (2/N) * (H - Y)，模拟定点精度"""
    def __init__(self, inv_batch_size_times_two):
        self.inv_n2 = inv_batch_size_times_two

    def compute(self, h_val, y_val):
        h_fxp = from_fixed(to_fixed(h_val))
        y_fxp = from_fixed(to_fixed(y_val))
        diff = from_fixed(to_fixed(h_fxp - y_fxp))
        inv_fxp = from_fixed(to_fixed(self.inv_n2))
        return from_fixed(to_fixed(diff * inv_fxp))


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
    dut.H_1_in.value = 0
    dut.Y_1_in.value = 0
    dut.H_2_in.value = 0
    dut.Y_2_in.value = 0
    dut.valid_1_in.value = 0
    dut.valid_2_in.value = 0
    dut.inv_batch_size_times_two_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, col1_h, col1_y, col2_h, col2_y, inv_n2, max_collect=15):
    dut.inv_batch_size_times_two_in.value = to_fixed(inv_n2)
    col1_res, col2_res = [], []
    n1, n2 = len(col1_h), len(col2_h)
    total_cycles = max(n1, n2) + max_collect

    for cyc in range(total_cycles):
        if cyc < max(n1, n2):
            if cyc < n1:
                dut.H_1_in.value = to_fixed(col1_h[cyc])
                dut.Y_1_in.value = to_fixed(col1_y[cyc])
                dut.valid_1_in.value = 1
            else:
                dut.H_1_in.value = 0
                dut.Y_1_in.value = 0
                dut.valid_1_in.value = 0
            if cyc < n2:
                dut.H_2_in.value = to_fixed(col2_h[cyc])
                dut.Y_2_in.value = to_fixed(col2_y[cyc])
                dut.valid_2_in.value = 1
            else:
                dut.H_2_in.value = 0
                dut.Y_2_in.value = 0
                dut.valid_2_in.value = 0
        else:
            dut.valid_1_in.value = 0
            dut.valid_2_in.value = 0

        await RisingEdge(dut.clk)

        if dut.valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.gradient_1_out.value.integer))
        if dut.valid_2_out.value.integer:
            col2_res.append(from_fixed(dut.gradient_2_out.value.integer))

        if cyc >= max(n1, n2) and len(col1_res) >= n1 and len(col2_res) >= n2:
            break

    return col1_res, col2_res


@cocotb.test()
async def test_basic_gradient(dut):
    """TC1: 基本梯度计算 — H > Y 和 H < Y"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    inv_n2 = 0.5  # 2/N, N=4
    ref = LossRefModel(inv_n2)
    sb = Scoreboard("basic_gradient")
    cov = FunctionalCoverage()

    col1_h = [0.7, 0.5, 0.3, 0.9]
    col1_y = [1.0, 0.0, 0.5, 1.0]
    col2_h = [0.8, 0.6, 0.2, 0.4]
    col2_y = [0.0, 1.0, 0.3, 0.7]

    col1_res, col2_res = await drive_and_collect(dut, col1_h, col1_y, col2_h, col2_y, inv_n2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        exp = ref.compute(col1_h[i], col1_y[i])
        sb.check(i, exp, col1_res[i], "col1")
        cov.sample("H>Y" if col1_h[i] > col1_y[i] else "H<Y")

    for i in range(4):
        exp = ref.compute(col2_h[i], col2_y[i])
        sb.check(i, exp, col2_res[i], "col2")
        cov.sample("H>Y" if col2_h[i] > col2_y[i] else "H<Y")

    cov.report()
    sb.report()


@cocotb.test()
async def test_zero_gradient(dut):
    """TC2: H == Y 时梯度应为零"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    inv_n2 = 0.5
    ref = LossRefModel(inv_n2)
    sb = Scoreboard("zero_gradient")

    col1_h = [1.0, 0.5, -0.5, 2.0]
    col1_y = [1.0, 0.5, -0.5, 2.0]
    col2_h = [0.0, -1.0, 3.0, 0.25]
    col2_y = [0.0, -1.0, 3.0, 0.25]

    col1_res, col2_res = await drive_and_collect(dut, col1_h, col1_y, col2_h, col2_y, inv_n2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"

    for i in range(4):
        sb.check(i, 0.0, col1_res[i], "col1")
    for i in range(min(4, len(col2_res))):
        sb.check(i, 0.0, col2_res[i], "col2")

    sb.report()


@cocotb.test()
async def test_single_column(dut):
    """TC3: 单列驱动"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    inv_n2 = 1.0  # 2/N, N=2
    ref = LossRefModel(inv_n2)
    sb = Scoreboard("single_col")

    dut.inv_batch_size_times_two_in.value = to_fixed(inv_n2)
    h_vals = [0.8, 0.3, 0.6, 0.1]
    y_vals = [1.0, 0.0, 0.5, 0.5]

    col1_res = []
    col2_count = 0

    for i in range(4):
        dut.H_1_in.value = to_fixed(h_vals[i])
        dut.Y_1_in.value = to_fixed(y_vals[i])
        dut.valid_1_in.value = 1
        dut.valid_2_in.value = 0
        await RisingEdge(dut.clk)
        if dut.valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.gradient_1_out.value.integer))
        if dut.valid_2_out.value.integer:
            col2_count += 1

    dut.valid_1_in.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.gradient_1_out.value.integer))
        if dut.valid_2_out.value.integer:
            col2_count += 1

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert col2_count == 0, f"col2 should have 0 outputs, got {col2_count}"

    for i in range(4):
        sb.check(i, ref.compute(h_vals[i], y_vals[i]), col1_res[i], "col1")
    sb.report()


@cocotb.test()
async def test_valid_handshake(dut):
    """TC4: valid 信号握手"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.inv_batch_size_times_two_in.value = to_fixed(0.5)
    dut.H_1_in.value = to_fixed(0.8)
    dut.Y_1_in.value = to_fixed(0.2)
    dut.valid_1_in.value = 1
    dut.valid_2_in.value = 0
    await RisingEdge(dut.clk)

    dut.valid_1_in.value = 0
    await RisingEdge(dut.clk)
    assert dut.valid_1_out.value.integer == 1, "valid output expected 1 cycle after input"

    await RisingEdge(dut.clk)
    assert dut.valid_1_out.value.integer == 0, "valid should deassert"
    cocotb.log.info("[valid_handshake] PASS")


@cocotb.test()
async def test_large_difference(dut):
    """TC5: 大差值梯度"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    inv_n2 = 0.5
    ref = LossRefModel(inv_n2)
    sb = Scoreboard("large_diff")

    col1_h = [5.0, -5.0, 3.0, -3.0]
    col1_y = [-5.0, 5.0, -3.0, 3.0]
    col2_h = [4.0, -4.0, 2.0, -2.0]
    col2_y = [-4.0, 4.0, -2.0, 2.0]

    col1_res, col2_res = await drive_and_collect(dut, col1_h, col1_y, col2_h, col2_y, inv_n2)

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"

    for i in range(4):
        sb.check(i, ref.compute(col1_h[i], col1_y[i]), col1_res[i], "col1")
    for i in range(min(4, len(col2_res))):
        sb.check(i, ref.compute(col2_h[i], col2_y[i]), col2_res[i], "col2")

    sb.report()
