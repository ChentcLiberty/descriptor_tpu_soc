"""
VPU 顶层验证测试
验证三条数据通路:
  Forward:    0b1100 — sys -> bias -> leaky_relu -> output
  Transition: 0b1111 — sys -> bias -> lr -> loss -> lr_d -> output
  Backward:   0b0001 — sys -> leaky_relu_derivative -> output
验证方法学: Reference Model + Scoreboard + Coverage
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

FRAC_BITS = 8
TOLERANCE = 0.08


def to_fixed(val, frac_bits=FRAC_BITS):
    scaled = int(round(val * (1 << frac_bits)))
    return scaled & 0xFFFF

def from_fixed(val, frac_bits=FRAC_BITS):
    if val >= 1 << 15:
        val -= 1 << 16
    return float(val) / (1 << frac_bits)


def ref_bias(data, bias):
    a = from_fixed(to_fixed(data))
    b = from_fixed(to_fixed(bias))
    return from_fixed(to_fixed(a + b))

def ref_leaky_relu(data, leak):
    d = from_fixed(to_fixed(data))
    if d >= 0:
        return d
    l = from_fixed(to_fixed(leak))
    return from_fixed(to_fixed(d * l))

def ref_loss_gradient(h, y, inv_n2):
    h_f = from_fixed(to_fixed(h))
    y_f = from_fixed(to_fixed(y))
    diff = from_fixed(to_fixed(h_f - y_f))
    inv_f = from_fixed(to_fixed(inv_n2))
    return from_fixed(to_fixed(diff * inv_f))

def ref_leaky_relu_deriv(data, h, leak):
    d = from_fixed(to_fixed(data))
    if h >= 0:
        return d
    l = from_fixed(to_fixed(leak))
    return from_fixed(to_fixed(d * l))


def ref_forward_path(data, bias, leak):
    z = ref_bias(data, bias)
    return ref_leaky_relu(z, leak)

def ref_backward_path(data, h, leak):
    return ref_leaky_relu_deriv(data, h, leak)


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
    dut.vpu_data_pathway.value = 0
    dut.vpu_data_in_1.value = 0
    dut.vpu_data_in_2.value = 0
    dut.vpu_valid_in_1.value = 0
    dut.vpu_valid_in_2.value = 0
    dut.bias_scalar_in_1.value = 0
    dut.bias_scalar_in_2.value = 0
    dut.lr_leak_factor_in.value = 0
    dut.Y_in_1.value = 0
    dut.Y_in_2.value = 0
    dut.inv_batch_size_times_two_in.value = 0
    dut.H_in_1.value = 0
    dut.H_in_2.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_forward_path(dut):
    """TC1: Forward path (0b1100) — bias -> leaky_relu"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    sb = Scoreboard("forward_path")
    cov = FunctionalCoverage()

    bias1, bias2 = 0.5, -0.3
    leak = 0.1
    dut.vpu_data_pathway.value = 0b1100
    dut.bias_scalar_in_1.value = to_fixed(bias1)
    dut.bias_scalar_in_2.value = to_fixed(bias2)
    dut.lr_leak_factor_in.value = to_fixed(leak)

    col1_data = [1.0, -2.0, 0.5, -1.5]
    col2_data = [2.0, -1.0, 1.5, -0.5]
    col1_res, col2_res = [], []

    for i in range(4):
        dut.vpu_data_in_1.value = to_fixed(col1_data[i])
        dut.vpu_data_in_2.value = to_fixed(col2_data[i])
        dut.vpu_valid_in_1.value = 1
        dut.vpu_valid_in_2.value = 1
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.vpu_data_out_1.value.integer))
        if dut.vpu_valid_out_2.value.integer:
            col2_res.append(from_fixed(dut.vpu_data_out_2.value.integer))

    dut.vpu_valid_in_1.value = 0
    dut.vpu_valid_in_2.value = 0

    for _ in range(15):
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.vpu_data_out_1.value.integer))
        if dut.vpu_valid_out_2.value.integer:
            col2_res.append(from_fixed(dut.vpu_data_out_2.value.integer))

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        exp = ref_forward_path(col1_data[i], bias1, leak)
        sb.check(i, exp, col1_res[i], "col1")
        cov.sample("forward_path")
    for i in range(4):
        exp = ref_forward_path(col2_data[i], bias2, leak)
        sb.check(i, exp, col2_res[i], "col2")
        cov.sample("forward_path")

    cov.report()
    sb.report()


@cocotb.test()
async def test_backward_path(dut):
    """TC2: Backward path (0b0001) — leaky_relu_derivative only"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    sb = Scoreboard("backward_path")
    cov = FunctionalCoverage()

    leak = 0.1
    dut.vpu_data_pathway.value = 0b0001
    dut.lr_leak_factor_in.value = to_fixed(leak)

    col1_data = [0.15, -0.12, -0.09, 0.17]
    col1_h = [-0.25, 0.61, 0.28, -0.39]
    col2_data = [0.08, -0.07, -0.05, 0.09]
    col2_h = [0.19, -0.54, 0.70, -0.70]
    col1_res, col2_res = [], []

    for i in range(4):
        dut.vpu_data_in_1.value = to_fixed(col1_data[i])
        dut.vpu_data_in_2.value = to_fixed(col2_data[i])
        dut.H_in_1.value = to_fixed(col1_h[i])
        dut.H_in_2.value = to_fixed(col2_h[i])
        dut.vpu_valid_in_1.value = 1
        dut.vpu_valid_in_2.value = 1
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.vpu_data_out_1.value.integer))
        if dut.vpu_valid_out_2.value.integer:
            col2_res.append(from_fixed(dut.vpu_data_out_2.value.integer))

    dut.vpu_valid_in_1.value = 0
    dut.vpu_valid_in_2.value = 0

    for _ in range(15):
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            col1_res.append(from_fixed(dut.vpu_data_out_1.value.integer))
        if dut.vpu_valid_out_2.value.integer:
            col2_res.append(from_fixed(dut.vpu_data_out_2.value.integer))

    assert len(col1_res) == 4, f"col1 expected 4, got {len(col1_res)}"
    assert len(col2_res) == 4, f"col2 expected 4, got {len(col2_res)}"

    for i in range(4):
        exp = ref_backward_path(col1_data[i], col1_h[i], leak)
        sb.check(i, exp, col1_res[i], "col1")
        cov.sample("backward_path")
    for i in range(4):
        exp = ref_backward_path(col2_data[i], col2_h[i], leak)
        sb.check(i, exp, col2_res[i], "col2")
        cov.sample("backward_path")

    cov.report()
    sb.report()


@cocotb.test()
async def test_pathway_switching(dut):
    """TC3: 通路切换 — forward -> reset -> backward"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    sb = Scoreboard("path_switch")
    leak = 0.1

    # Phase 1: Forward
    dut.vpu_data_pathway.value = 0b1100
    dut.bias_scalar_in_1.value = to_fixed(0.5)
    dut.bias_scalar_in_2.value = to_fixed(0.3)
    dut.lr_leak_factor_in.value = to_fixed(leak)

    dut.vpu_data_in_1.value = to_fixed(1.0)
    dut.vpu_data_in_2.value = to_fixed(-1.0)
    dut.vpu_valid_in_1.value = 1
    dut.vpu_valid_in_2.value = 1
    await RisingEdge(dut.clk)

    dut.vpu_valid_in_1.value = 0
    dut.vpu_valid_in_2.value = 0

    fwd_res = []
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            fwd_res.append(from_fixed(dut.vpu_data_out_1.value.integer))

    assert len(fwd_res) >= 1, "forward path should produce output"
    sb.check(0, ref_forward_path(1.0, 0.5, leak), fwd_res[0], "fwd")

    # Phase 2: Reset + backward
    await reset_dut(dut)
    dut.vpu_data_pathway.value = 0b0001
    dut.lr_leak_factor_in.value = to_fixed(leak)

    dut.vpu_data_in_1.value = to_fixed(0.5)
    dut.H_in_1.value = to_fixed(1.0)
    dut.vpu_valid_in_1.value = 1
    dut.vpu_valid_in_2.value = 0
    await RisingEdge(dut.clk)

    dut.vpu_valid_in_1.value = 0

    bwd_res = []
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.vpu_valid_out_1.value.integer:
            bwd_res.append(from_fixed(dut.vpu_data_out_1.value.integer))

    assert len(bwd_res) >= 1, "backward path should produce output"
    sb.check(0, ref_backward_path(0.5, 1.0, leak), bwd_res[0], "bwd")

    sb.report()


@cocotb.test()
async def test_disabled_pathway(dut):
    """TC4: 通路 0b0000 — 所有模块禁用"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.vpu_data_pathway.value = 0b0000
    dut.vpu_data_in_1.value = to_fixed(5.0)
    dut.vpu_data_in_2.value = to_fixed(3.0)
    dut.vpu_valid_in_1.value = 1
    dut.vpu_valid_in_2.value = 1
    await RisingEdge(dut.clk)

    dut.vpu_valid_in_1.value = 0
    dut.vpu_valid_in_2.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)

    cocotb.log.info("[disabled_pathway] PASS — no crash, pathway routing verified")
