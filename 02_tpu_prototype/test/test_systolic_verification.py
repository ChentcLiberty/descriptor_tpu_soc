"""
Systolic Array Verification with Reference Model
2x2 脉动阵列验证：参考模型 + 自动比对
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge

# ==================== 定点数转换 ====================
def to_fixed(val, frac_bits=8):
    return int(round(val * (1 << frac_bits))) & 0xFFFF

def from_fixed(val, frac_bits=8):
    if val >= (1 << 15):
        val -= (1 << 16)
    return float(val) / (1 << frac_bits)

# ==================== 测试数据 ====================
X = [
    [2., 2.],
    [0., 1.],
    [1., 0.],
    [1., 1.]
]

W1 = [
    [0.2985, -0.5792],
    [0.0913, 0.4234]
]

# Expected: X @ W1^T
# [[-0.5614,  1.0294],
#  [-0.5792,  0.4234],
#  [ 0.2985,  0.0913],
#  [-0.2807,  0.5147]]

# ==================== 参考模型 ====================
class SystolicRefModel:
    """2x2 脉动阵列参考模型"""

    def __init__(self):
        self.weights = [[0.0]*2 for _ in range(2)]

    def load_weights(self, W):
        self.weights = [row[:] for row in W]

    def compute(self, X):
        """计算 C = X @ W^T"""
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
    # 复位释放后再使能 PE 列
    dut.ub_rd_col_size_in.value = 2
    dut.ub_rd_col_size_valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.ub_rd_col_size_valid_in.value = 0
    await RisingEdge(dut.clk)

async def load_weights(dut, W):
    """加载权重（按列从上到下传播）"""
    # Cycle 1: 列1第一个权重
    dut.sys_weight_in_11.value = to_fixed(W[0][1])
    dut.sys_accept_w_1.value = 1
    await RisingEdge(dut.clk)

    # Cycle 2: 列1第二个 + 列2第一个
    dut.sys_weight_in_11.value = to_fixed(W[0][0])
    dut.sys_accept_w_1.value = 1
    dut.sys_weight_in_12.value = to_fixed(W[1][1])
    dut.sys_accept_w_2.value = 1
    await RisingEdge(dut.clk)

    # Cycle 3: 列2第二个 + switch
    dut.sys_accept_w_1.value = 0
    dut.sys_weight_in_12.value = to_fixed(W[1][0])
    dut.sys_accept_w_2.value = 1
    dut.sys_switch_in.value = 1
    await RisingEdge(dut.clk)

    dut.sys_accept_w_2.value = 0
    dut.sys_switch_in.value = 0
    # 等待 switch 信号传播到所有 PE
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

async def feed_data_and_collect(dut, X):
    """喂入数据并收集输出，使用单个 sys_start"""
    num_rows = len(X)
    results_col1 = []
    results_col2 = []

    # 对角线喂数：row1 先进，row2 延迟1拍
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

    # 多等几拍收集剩余输出
    for _ in range(4):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.sys_valid_out_21.value):
            results_col1.append(from_fixed(int(dut.sys_data_out_21.value)))
        if int(dut.sys_valid_out_22.value):
            results_col2.append(from_fixed(int(dut.sys_data_out_22.value)))
        await FallingEdge(dut.clk)

    return results_col1, results_col2

# ==================== 主测试 ====================
@cocotb.test()
async def test_systolic_array(dut):
    """使用参考模型验证 2x2 脉动阵列"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    ref_model = SystolicRefModel()

    print("\n" + "="*80)
    print("Systolic Array Verification with Reference Model")
    print("="*80)

    await reset_dut(dut)
    print("✓ Reset completed")

    await load_weights(dut, W1)
    ref_model.load_weights(W1)
    print("✓ Weights loaded")

    ref_result = ref_model.compute(X)
    print(f"\nReference (X @ W1^T):")
    for i, row in enumerate(ref_result):
        print(f"  Row {i}: [{row[0]:8.4f}, {row[1]:8.4f}]")

    col1, col2 = await feed_data_and_collect(dut, X)

    print(f"\nDUT Output:")
    print(f"  Col1 ({len(col1)}): {[f'{v:.4f}' for v in col1]}")
    print(f"  Col2 ({len(col2)}): {[f'{v:.4f}' for v in col2]}")

    # 比对结果
    tolerance = 0.05
    errors = []
    num_rows = len(X)

    print(f"\nComparison:")
    for i in range(min(num_rows, len(col1))):
        err = abs(col1[i] - ref_result[i][0])
        s = "✓" if err < tolerance else "✗"
        print(f"  {s} Row{i} Col1: DUT={col1[i]:8.4f}, REF={ref_result[i][0]:8.4f}, Err={err:.4f}")
        if err >= tolerance:
            errors.append(f"Row{i} Col1: DUT={col1[i]:.4f}, REF={ref_result[i][0]:.4f}")

    for i in range(min(num_rows, len(col2))):
        err = abs(col2[i] - ref_result[i][1])
        s = "✓" if err < tolerance else "✗"
        print(f"  {s} Row{i} Col2: DUT={col2[i]:8.4f}, REF={ref_result[i][1]:8.4f}, Err={err:.4f}")
        if err >= tolerance:
            errors.append(f"Row{i} Col2: DUT={col2[i]:.4f}, REF={ref_result[i][1]:.4f}")

    if len(col1) < num_rows:
        errors.append(f"Col1 count: expected {num_rows}, got {len(col1)}")
    if len(col2) < num_rows:
        errors.append(f"Col2 count: expected {num_rows}, got {len(col2)}")

    print("\n" + "="*80)
    if errors:
        print(f"✗ {len(errors)} errors found")
        print("="*80 + "\n")
        assert False, "\n".join(errors)
    else:
        print("✓ All checks PASSED!")
        print("="*80 + "\n")
