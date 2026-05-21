"""
leaky_relu_parent 验证测试
验证方法学: Reference Model + Scoreboard + Coverage
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

FRAC_BITS = 8
TOLERANCE = 0.05  # Q8.8 定点精度容差


# ============ 定点工具 ============
def to_fixed(val, frac_bits=FRAC_BITS):
    scaled = int(round(val * (1 << frac_bits)))
    return scaled & 0xFFFF

def from_fixed(val, frac_bits=FRAC_BITS):
    if val >= 1 << 15:
        val -= 1 << 16
    return float(val) / (1 << frac_bits)


# ============ Reference Model ============
class LeakyReluRefModel:
    def __init__(self, leak_factor):
        self.leak_factor = leak_factor

    def compute(self, data):
        if data >= 0:
            return data
        else:
            # 模拟定点乘法精度
            data_fxp = from_fixed(to_fixed(data))
            leak_fxp = from_fixed(to_fixed(self.leak_factor))
            return from_fixed(to_fixed(data_fxp * leak_fxp))


# ============ Scoreboard ============
class Scoreboard:
    def __init__(self, name, tolerance=TOLERANCE):
        self.name = name
        self.tolerance = tolerance
        self.pass_count = 0
        self.fail_count = 0
        self.errors = []

    def check(self, idx, expected, actual, tag=""):
        abs_err = abs(actual - expected)
        prefix = f"[{self.name}] {tag}[{idx}]" if tag else f"[{self.name}][{idx}]"
        if abs_err <= self.tolerance:
            self.pass_count += 1
            cocotb.log.info(f"{prefix} PASS: exp={expected:.5f} got={actual:.5f} err={abs_err:.5f}")
        else:
            self.fail_count += 1
            msg = f"{prefix} FAIL: exp={expected:.5f} got={actual:.5f} err={abs_err:.5f}"
            self.errors.append(msg)
            cocotb.log.error(msg)

    def report(self):
        total = self.pass_count + self.fail_count
        cocotb.log.info(f"[{self.name}] Scoreboard: {self.pass_count}/{total} passed")
        if self.errors:
            for e in self.errors:
                cocotb.log.error(f"  {e}")
        assert self.fail_count == 0, f"[{self.name}] {self.fail_count} checks failed"


# ============ Coverage ============
class FunctionalCoverage:
    def __init__(self):
        self.bins = {}

    def sample(self, point):
        self.bins[point] = self.bins.get(point, 0) + 1

    def report(self):
        cocotb.log.info("=== Functional Coverage ===")
        for k, v in sorted(self.bins.items()):
            cocotb.log.info(f"  {k}: hit {v}x")
        return self.bins


# ============ 驱动/采集辅助 ============
async def reset_dut(dut):
    dut.rst.value = 1
    dut.lr_valid_1_in.value = 0
    dut.lr_data_1_in.value = 0
    dut.lr_valid_2_in.value = 0
    dut.lr_data_2_in.value = 0
    dut.lr_leak_factor_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, col1_data, col2_data, leak_factor, max_collect_cycles=15):
    """驱动双列数据并采集输出，驱动和采集同时进行"""
    dut.lr_leak_factor_in.value = to_fixed(leak_factor)

    col1_results = []
    col2_results = []
    n1 = len(col1_data)
    n2 = len(col2_data)
    max_input = max(n1, n2)
    total_cycles = max_input + max_collect_cycles

    for cyc in range(total_cycles):
        # 驱动阶段
        if cyc < max_input:
            if cyc < n1:
                dut.lr_data_1_in.value = to_fixed(col1_data[cyc])
                dut.lr_valid_1_in.value = 1
            else:
                dut.lr_data_1_in.value = 0
                dut.lr_valid_1_in.value = 0
            if cyc < n2:
                dut.lr_data_2_in.value = to_fixed(col2_data[cyc])
                dut.lr_valid_2_in.value = 1
            else:
                dut.lr_data_2_in.value = 0
                dut.lr_valid_2_in.value = 0
        else:
            dut.lr_valid_1_in.value = 0
            dut.lr_valid_2_in.value = 0

        await RisingEdge(dut.clk)

        # 采集阶段（每拍都检查）
        if dut.lr_valid_1_out.value.integer:
            col1_results.append(from_fixed(dut.lr_data_1_out.value.integer))
        if dut.lr_valid_2_out.value.integer:
            col2_results.append(from_fixed(dut.lr_data_2_out.value.integer))

        # 提前退出
        if cyc >= max_input and len(col1_results) >= n1 and len(col2_results) >= n2:
            break

    return col1_results, col2_results


# ============ 测试用例 ============

@cocotb.test()
async def test_forward_positive_values(dut):
    """TC1: 正值直通 — leaky relu 对正值应原样输出"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ref = LeakyReluRefModel(0.1)
    sb = Scoreboard("positive_values")
    cov = FunctionalCoverage()

    col1_data = [1.0, 2.5, 0.5, 3.75]
    col2_data = [0.25, 1.5, 4.0, 0.125]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, 0.1)

    assert len(col1_res) == 4, f"col1 expected 4 results, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4 results, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref.compute(inp), got, "col1")
        cov.sample("positive_passthrough")

    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        sb.check(i, ref.compute(inp), got, "col2")
        cov.sample("positive_passthrough")

    cov.report()
    sb.report()


@cocotb.test()
async def test_forward_negative_values(dut):
    """TC2: 负值缩放 — leaky relu 对负值应乘以 leak_factor"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluRefModel(leak)
    sb = Scoreboard("negative_values")
    cov = FunctionalCoverage()

    col1_data = [-1.0, -2.5, -0.5, -3.75]
    col2_data = [-0.25, -1.5, -4.0, -0.125]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, leak)

    assert len(col1_res) == 4, f"col1 expected 4 results, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4 results, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref.compute(inp), got, "col1")
        cov.sample("negative_scaled")

    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        sb.check(i, ref.compute(inp), got, "col2")
        cov.sample("negative_scaled")

    cov.report()
    sb.report()


@cocotb.test()
async def test_mixed_values(dut):
    """TC3: 混合正负值 — 验证正负交替场景"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluRefModel(leak)
    sb = Scoreboard("mixed_values")
    cov = FunctionalCoverage()

    col1_data = [2.5, -1.2, 0.8, -3.1]
    col2_data = [-0.9, 1.5, -2.2, 1.8]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, leak)

    assert len(col1_res) == 4, f"col1 expected 4 results, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4 results, got {len(col2_res)}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        exp = ref.compute(inp)
        sb.check(i, exp, got, "col1")
        cov.sample("positive_passthrough" if inp >= 0 else "negative_scaled")

    for i, (got, inp) in enumerate(zip(col2_res, col2_data)):
        exp = ref.compute(inp)
        sb.check(i, exp, got, "col2")
        cov.sample("positive_passthrough" if inp >= 0 else "negative_scaled")

    cov.report()
    sb.report()


@cocotb.test()
async def test_single_column_only(dut):
    """TC4: 单列驱动 — 仅 col1 有效，col2 应无输出"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    leak = 0.1
    ref = LeakyReluRefModel(leak)
    sb = Scoreboard("single_col")

    dut.lr_leak_factor_in.value = to_fixed(leak)
    col1_data = [1.0, -2.0, 3.0, -4.0]

    col1_res = []
    col2_count = 0

    for val in col1_data:
        dut.lr_data_1_in.value = to_fixed(val)
        dut.lr_valid_1_in.value = 1
        dut.lr_valid_2_in.value = 0
        dut.lr_data_2_in.value = 0
        await RisingEdge(dut.clk)
        if dut.lr_valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.lr_data_1_out.value.integer))
        if dut.lr_valid_2_out.value.integer:
            col2_count += 1

    dut.lr_valid_1_in.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.lr_valid_1_out.value.integer:
            col1_res.append(from_fixed(dut.lr_data_1_out.value.integer))
        if dut.lr_valid_2_out.value.integer:
            col2_count += 1

    assert len(col1_res) == 4, f"col1 expected 4 results, got {len(col1_res)}"
    assert col2_count == 0, f"col2 should have 0 valid outputs, got {col2_count}"

    for i, (got, inp) in enumerate(zip(col1_res, col1_data)):
        sb.check(i, ref.compute(inp), got, "col1")

    sb.report()


@cocotb.test()
async def test_valid_handshake(dut):
    """TC5: valid 信号握手 — valid 拉低时输出应无效"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.lr_leak_factor_in.value = to_fixed(0.1)

    # 驱动一拍有效数据
    dut.lr_data_1_in.value = to_fixed(5.0)
    dut.lr_valid_1_in.value = 1
    dut.lr_valid_2_in.value = 0
    await RisingEdge(dut.clk)

    # 拉低 valid
    dut.lr_valid_1_in.value = 0
    await RisingEdge(dut.clk)

    # 第一拍应有输出
    assert dut.lr_valid_1_out.value.integer == 1, "should see valid output 1 cycle after input"

    await RisingEdge(dut.clk)
    # 第二拍应无输出
    assert dut.lr_valid_1_out.value.integer == 0, "valid should deassert after input stops"

    cocotb.log.info("[valid_handshake] PASS")


@cocotb.test()
async def test_zero_input(dut):
    """TC6: 零值输入 — 零应原样输出（>= 0 分支）"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    ref = LeakyReluRefModel(0.1)
    sb = Scoreboard("zero_input")

    col1_data = [0.0, 0.0]
    col2_data = [0.0, 0.0]

    col1_res, col2_res = await drive_and_collect(dut, col1_data, col2_data, 0.1)

    assert len(col1_res) == 2, f"col1 expected 2 results, got {len(col1_res)}"

    for i, got in enumerate(col1_res):
        sb.check(i, 0.0, got, "col1")

    sb.report()
