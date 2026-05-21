"""
Systolic Array Boundary and Multi-Case Testing
2x2 脉动阵列边界测试：多组权重 + 边界值 + 随机测试
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge
import random

# ==================== 定点数转换 ====================
def to_fixed(val, frac_bits=8):
    return int(round(val * (1 << frac_bits))) & 0xFFFF

def from_fixed(val, frac_bits=8):
    if val >= (1 << 15):
        val -= (1 << 16)
    return float(val) / (1 << frac_bits)

# ==================== 测试数据集 ====================
# Test Case 1: 原始测试数据
X1 = [[2., 2.], [0., 1.], [1., 0.], [1., 1.]]
W1 = [[0.2985, -0.5792], [0.0913, 0.4234]]

# Test Case 2: 全零测试
X2 = [[0., 0.], [0., 0.]]
W2 = [[0., 0.], [0., 0.]]

# Test Case 3: 单位矩阵
X3 = [[1., 0.], [0., 1.]]
W3 = [[1., 0.], [0., 1.]]

# Test Case 4: 边界值（接近 Q8.8 最大值 ±127.996）
X4 = [[100., -100.], [50., -50.]]
W4 = [[0.5, -0.5], [0.25, 0.25]]

# Test Case 5: 极小值（接近量化精度 1/256 ≈ 0.0039）
X5 = [[0.01, 0.02], [0.03, 0.04]]
W5 = [[0.05, 0.06], [0.07, 0.08]]

# ==================== 参考模型 ====================
class SystolicRefModel:
    def __init__(self):
        self.weights = [[0.0]*2 for _ in range(2)]

    def load_weights(self, W):
        self.weights = [row[:] for row in W]

    def compute(self, X):
        result = []
        for i in range(len(X)):
            row = []
            for j in range(2):
                val = sum(X[i][k] * self.weights[j][k] for k in range(2))
                row.append(val)
            result.append(row)
        return result

# ==================== 辅助函数 ====================
async def reset_dut(dut):
    dut.rst.value = 1
    dut.sys_start.value = 0
    dut.sys_accept_w_1.value = 0
    dut.sys_accept_w_2.value = 0
    dut.sys_switch_in.value = 0
    dut.sys_data_in_11.value = 0
    dut.sys_data_in_21.value = 0
    dut.sys_weight_in_11.value = 0
    dut.sys_weight_in_12.value = 0
    dut.ub_rd_col_size_in.value = 0
    dut.ub_rd_col_size_valid_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    dut.ub_rd_col_size_in.value = 2
    dut.ub_rd_col_size_valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.ub_rd_col_size_valid_in.value = 0
    await RisingEdge(dut.clk)

async def load_weights(dut, W):
    dut.sys_weight_in_11.value = to_fixed(W[0][1])
    dut.sys_accept_w_1.value = 1
    await RisingEdge(dut.clk)

    dut.sys_weight_in_11.value = to_fixed(W[0][0])
    dut.sys_accept_w_1.value = 1
    dut.sys_weight_in_12.value = to_fixed(W[1][1])
    dut.sys_accept_w_2.value = 1
    await RisingEdge(dut.clk)

    dut.sys_accept_w_1.value = 0
    dut.sys_weight_in_12.value = to_fixed(W[1][0])
    dut.sys_accept_w_2.value = 1
    dut.sys_switch_in.value = 1
    await RisingEdge(dut.clk)

    dut.sys_accept_w_2.value = 0
    dut.sys_switch_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

async def feed_data_and_collect(dut, X):
    num_rows = len(X)
    results_col1 = []
    results_col2 = []

    for i in range(num_rows + 2):
        if i < num_rows:
            dut.sys_data_in_11.value = to_fixed(X[i][0])
            dut.sys_start.value = 1
        else:
            dut.sys_start.value = 0

        if 0 < i <= num_rows:
            dut.sys_data_in_21.value = to_fixed(X[i-1][1])

        await RisingEdge(dut.clk)
        await ReadOnly()

        if int(dut.sys_valid_out_21.value):
            results_col1.append(from_fixed(int(dut.sys_data_out_21.value)))
        if int(dut.sys_valid_out_22.value):
            results_col2.append(from_fixed(int(dut.sys_data_out_22.value)))

        await FallingEdge(dut.clk)

    for _ in range(4):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.sys_valid_out_21.value):
            results_col1.append(from_fixed(int(dut.sys_data_out_21.value)))
        if int(dut.sys_valid_out_22.value):
            results_col2.append(from_fixed(int(dut.sys_data_out_22.value)))
        await FallingEdge(dut.clk)

    return results_col1, results_col2

def verify_results(col1, col2, ref_result, tolerance, test_name):
    errors = []
    num_rows = len(ref_result)

    for i in range(min(num_rows, len(col1))):
        err = abs(col1[i] - ref_result[i][0])
        if err >= tolerance:
            errors.append(f"{test_name} Row{i} Col1: DUT={col1[i]:.4f}, REF={ref_result[i][0]:.4f}, Err={err:.4f}")

    for i in range(min(num_rows, len(col2))):
        err = abs(col2[i] - ref_result[i][1])
        if err >= tolerance:
            errors.append(f"{test_name} Row{i} Col2: DUT={col2[i]:.4f}, REF={ref_result[i][1]:.4f}, Err={err:.4f}")

    if len(col1) < num_rows:
        errors.append(f"{test_name} Col1 count: expected {num_rows}, got {len(col1)}")
    if len(col2) < num_rows:
        errors.append(f"{test_name} Col2 count: expected {num_rows}, got {len(col2)}")

    return errors

# ==================== 测试用例 ====================
@cocotb.test()
async def test_multiple_weights(dut):
    """多组权重测试"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    ref_model = SystolicRefModel()

    print("\n" + "="*80)
    print("Test 1: Multiple Weight Matrices")
    print("="*80)

    await reset_dut(dut)
    all_errors = []

    test_cases = [
        ("Original", X1, W1),
        ("Identity", X3, W3),
        ("Small Values", X5, W5),
    ]

    for name, X, W in test_cases:
        print(f"\n--- {name} ---")
        await load_weights(dut, W)
        ref_model.load_weights(W)

        ref_result = ref_model.compute(X)
        col1, col2 = await feed_data_and_collect(dut, X)

        errors = verify_results(col1, col2, ref_result, 0.05, name)
        all_errors.extend(errors)

        if not errors:
            print(f"✓ {name} PASSED")
        else:
            print(f"✗ {name} FAILED")

    print("\n" + "="*80)
    if all_errors:
        print(f"✗ {len(all_errors)} errors found")
        print("="*80 + "\n")
        assert False, "\n".join(all_errors)
    else:
        print("✓ All multi-weight tests PASSED!")
        print("="*80 + "\n")
