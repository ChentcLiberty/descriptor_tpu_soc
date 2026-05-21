import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

def to_fixed(val, frac_bits=8):
    return int(round(val * (1 << frac_bits))) & 0xFFFF

def from_fixed(val, frac_bits=8):
    if val >= (1 << 15):
        val -= (1 << 16)
    return float(val) / (1 << frac_bits)

# ==================== 参考模型 ====================
class PE_Model:
    """PE 参考模型"""
    def __init__(self):
        self.weight = 0.0

    def compute(self, input_val, psum_in):
        """MAC: output = input * weight + psum"""
        return input_val * self.weight + psum_in

# ==================== 测试向量 ====================
test_cases = [
    # (input, weight, psum_in, expected)
    (2.0,   10.0,  50.0,  70.0),
    (1.5,   2.0,   0.0,   3.0),
    (-1.0,  3.0,   5.0,   2.0),
    (4.0,   -2.0,  10.0,  2.0),
]

@cocotb.test()
async def test_pe(dut):
    """PE 验证：参考模型 + 多组测试"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    model = PE_Model()

    print("\n" + "="*60)
    print("PE Verification with Reference Model")
    print("="*60)

    # 复位
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

    # 遍历测试用例
    for i, (inp, weight, psum, expected) in enumerate(test_cases, 1):
        print(f"\n--- Test {i}: inp={inp}, w={weight}, psum={psum} ---")

        # 加载权重
        dut.pe_accept_w_in.value = 1
        dut.pe_weight_in.value = to_fixed(weight)
        await RisingEdge(dut.clk)
        dut.pe_accept_w_in.value = 0

        # 切换权重
        dut.pe_switch_in.value = 1
        await RisingEdge(dut.clk)
        dut.pe_switch_in.value = 0

        # 更新参考模型
        model.weight = weight

        # 计算
        dut.pe_valid_in.value = 1
        dut.pe_input_in.value = to_fixed(inp)
        dut.pe_psum_in.value = to_fixed(psum)
        await RisingEdge(dut.clk)

        # 读取结果
        dut_out = from_fixed(int(dut.pe_psum_out.value))
        ref_out = model.compute(inp, psum)
        error = abs(dut_out - ref_out)

        # 比对
        status = "✓" if error < 0.01 else "✗"
        print(f"{status} DUT={dut_out:.2f}, REF={ref_out:.2f}, Error={error:.4f}")

        assert error < 0.01, f"Mismatch! DUT={dut_out}, REF={ref_out}"

        dut.pe_valid_in.value = 0
        await RisingEdge(dut.clk)

    print("\n" + "="*60)
    print(f"✓ All {len(test_cases)} tests PASSED!")
    print("="*60 + "\n")
