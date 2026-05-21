"""
PE Module Verification with Reference Model
使用验证方法学：参考模型 + 自动比对
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly, FallingEdge
import random

# ==================== 定点数转换 ====================
def to_fixed(val, frac_bits=8):
    """浮点数转定点数 (Q8.8 格式)"""
    return int(round(val * (1 << frac_bits))) & 0xFFFF

def from_fixed(val, frac_bits=8):
    """定点数转浮点数"""
    if val >= (1 << 15):
        val -= (1 << 16)
    return float(val) / (1 << frac_bits)

# ==================== 参考模型 (Golden Model) ====================
class PE_ReferenceModel:
    """PE 的 Python 参考模型"""

    def __init__(self):
        self.weight_active = 0.0
        self.weight_inactive = 0.0

    def load_weight(self, weight):
        """加载权重到后台寄存器"""
        self.weight_inactive = weight

    def switch_weight(self):
        """切换权重：后台 -> 前台"""
        self.weight_active = self.weight_inactive

    def compute(self, input_val, psum_in):
        """计算 MAC: output = input * weight + psum"""
        result = input_val * self.weight_active + psum_in
        return result

    def reset(self):
        """复位"""
        self.weight_active = 0.0
        self.weight_inactive = 0.0

# ==================== 测试用例数据 ====================
test_vectors = [
    # (input, weight, psum_in, expected_output)
    (2.0,   10.0,  50.0,  70.0),    # 基本测试
    (1.5,   2.0,   0.0,   3.0),     # 简单乘法
    (-1.0,  3.0,   5.0,   2.0),     # 负数输入
    (4.0,   -2.0,  10.0,  2.0),     # 负数权重
    (0.0,   5.0,   8.0,   8.0),     # 零输入
    (3.5,   0.0,   12.0,  12.0),    # 零权重
    (-2.5,  -4.0,  -5.0,  5.0),     # 全负数
]

# ==================== 辅助函数 ====================
async def reset_dut(dut):
    """复位 DUT"""
    dut.rst.value = 1
    dut.pe_enabled.value = 1
    dut.pe_valid_in.value = 0
    dut.pe_accept_w_in.value = 0
    dut.pe_switch_in.value = 0
    dut.pe_input_in.value = 0
    dut.pe_weight_in.value = 0
    dut.pe_psum_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

async def load_weight_to_pe(dut, weight):
    """加载权重到 PE 的后台寄存器"""
    dut.pe_accept_w_in.value = 1
    dut.pe_weight_in.value = to_fixed(weight)
    await RisingEdge(dut.clk)
    dut.pe_accept_w_in.value = 0

async def switch_weight_in_pe(dut):
    """切换 PE 的权重：后台 -> 前台"""
    dut.pe_switch_in.value = 1
    await RisingEdge(dut.clk)
    dut.pe_switch_in.value = 0

async def compute_and_check(dut, ref_model, input_val, psum_in, expected):
    """执行计算并比对结果，返回错误列表"""
    errors = []

    # 设置输入
    dut.pe_valid_in.value = 1
    dut.pe_input_in.value = to_fixed(input_val)
    dut.pe_psum_in.value = to_fixed(psum_in)
    await RisingEdge(dut.clk)
    await ReadOnly()  # 等待非阻塞赋值完成

    # 读取 DUT 输出
    dut_output_fixed = int(dut.pe_psum_out.value)
    dut_output = from_fixed(dut_output_fixed)

    # 参考模型计算
    ref_output = ref_model.compute(input_val, psum_in)

    # 比对结果（允许定点误差）
    tolerance = 0.02
    error = abs(dut_output - ref_output)

    # 打印比对信息
    status = "✓ PASS" if error < tolerance else "✗ FAIL"
    print(f"{status} | Input={input_val:6.2f}, Weight={ref_model.weight_active:6.2f}, "
          f"PSum={psum_in:6.2f} | DUT={dut_output:7.2f}, REF={ref_output:7.2f}, "
          f"Error={error:.4f}")

    # 收集错误
    if error >= tolerance:
        errors.append(f"Output mismatch! DUT={dut_output:.2f}, REF={ref_output:.2f}, Error={error:.4f}")

    # 检查输入传递
    dut_input_out = from_fixed(int(dut.pe_input_out.value))
    if abs(dut_input_out - input_val) >= tolerance:
        errors.append(f"Input passthrough failed! Expected={input_val}, Got={dut_input_out}")

    # 在下降沿清零，valid只保持1个时钟周期
    await FallingEdge(dut.clk)
    dut.pe_valid_in.value = 0

    return errors

# ==================== 主测试 ====================
@cocotb.test()
async def test_pe_with_reference_model(dut):
    """使用参考模型验证 PE 模块"""

    # 启动时钟
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # 创建参考模型
    ref_model = PE_ReferenceModel()

    print("\n" + "="*80)
    print("PE Verification with Reference Model")
    print("="*80)

    # 复位
    await reset_dut(dut)
    ref_model.reset()
    print("✓ Reset completed")

    # 遍历所有测试向量
    test_count = 0
    all_errors = []
    for input_val, weight, psum_in, expected in test_vectors:
        test_count += 1
        print(f"\n--- Test Case {test_count} ---")

        # 加载权重
        await load_weight_to_pe(dut, weight)
        ref_model.load_weight(weight)

        # 切换权重
        await switch_weight_in_pe(dut)
        ref_model.switch_weight()

        # 计算并收集错误
        test_errors = await compute_and_check(dut, ref_model, input_val, psum_in, expected)
        if test_errors:
            all_errors.extend([f"Test {test_count}: {e}" for e in test_errors])

    print("\n" + "="*80)
    if all_errors:
        print(f"✗ {len(all_errors)} errors in {test_count} test cases")
        print("="*80 + "\n")
        assert False, "\n".join(all_errors)
    else:
        print(f"✓ All {test_count} test cases PASSED!")
        print("="*80 + "\n")

@cocotb.test()
async def test_pe_random_vectors(dut):
    """随机测试向量"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    ref_model = PE_ReferenceModel()

    print("\n" + "="*80)
    print("PE Random Vector Testing")
    print("="*80)

    await reset_dut(dut)
    ref_model.reset()

    num_random_tests = 10
    random.seed(42)
    all_errors = []

    for i in range(num_random_tests):
        input_val = random.uniform(-10, 10)
        weight = random.uniform(-10, 10)
        psum_in = random.uniform(-10, 10)

        print(f"\n--- Random Test {i+1}/{num_random_tests} ---")

        await load_weight_to_pe(dut, weight)
        ref_model.load_weight(weight)

        await switch_weight_in_pe(dut)
        ref_model.switch_weight()

        expected = input_val * weight + psum_in
        test_errors = await compute_and_check(dut, ref_model, input_val, psum_in, expected)
        if test_errors:
            all_errors.extend([f"Random {i+1}: {e}" for e in test_errors])

    print("\n" + "="*80)
    if all_errors:
        print(f"✗ {len(all_errors)} errors in {num_random_tests} random tests")
        print("="*80 + "\n")
        assert False, "\n".join(all_errors)
    else:
        print(f"✓ All {num_random_tests} random tests PASSED!")
        print("="*80 + "\n")
