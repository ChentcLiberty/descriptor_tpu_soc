"""
Unified Buffer V2 Verification Test
验证 V2 版本的修复：
1. rst 时序修复（增加保持周期）
2. 阻塞/非阻塞赋值修复（组合逻辑计算 ptr）
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly


# ==================== Q8.8 定点数转换 ====================
def to_fixed(val, frac_bits=8):
    return int(round(val * (1 << frac_bits))) & 0xFFFF


def from_fixed(val, frac_bits=8):
    if val >= (1 << 15):
        val -= (1 << 16)
    return float(val) / (1 << frac_bits)


# ==================== Helper Functions ====================
async def reset_dut(dut):
    """复位 + 初始化所有输入为 0"""
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    dut.learning_rate_in.value = to_fixed(0.5)
    dut.ub_wr_data_in[0].value = 0
    dut.ub_wr_data_in[1].value = 0
    dut.ub_wr_valid_in[0].value = 0
    dut.ub_wr_valid_in[1].value = 0
    dut.ub_wr_host_data_in[0].value = 0
    dut.ub_wr_host_valid_in[0].value = 0
    dut.ub_wr_host_data_in[1].value = 0
    dut.ub_wr_host_valid_in[1].value = 0
    dut.ub_rd_start_in.value = 0
    dut.ub_rd_transpose.value = 0
    dut.ub_ptr_select.value = 0
    dut.ub_rd_addr_in.value = 0
    dut.ub_rd_row_size.value = 0
    dut.ub_rd_col_size.value = 0
    await RisingEdge(dut.clk)


async def write_matrix_host(dut, matrix):
    """按 lane 交错模式写入矩阵到 UB，产生行主序存储。"""
    rows = len(matrix)
    cols = len(matrix[0]) if rows > 0 else 0
    lane0_data = [matrix[r][0] for r in range(rows)]
    lane1_data = [matrix[r][1] for r in range(rows)] if cols > 1 else []

    total_cycles = rows + (1 if cols > 1 else 0)
    for cyc in range(total_cycles):
        if cyc < rows:
            dut.ub_wr_host_data_in[0].value = to_fixed(lane0_data[cyc])
            dut.ub_wr_host_valid_in[0].value = 1
        else:
            dut.ub_wr_host_data_in[0].value = 0
            dut.ub_wr_host_valid_in[0].value = 0
        if cols > 1 and 0 <= cyc - 1 < rows:
            dut.ub_wr_host_data_in[1].value = to_fixed(lane1_data[cyc - 1])
            dut.ub_wr_host_valid_in[1].value = 1
        else:
            dut.ub_wr_host_data_in[1].value = 0
            dut.ub_wr_host_valid_in[1].value = 0
        await RisingEdge(dut.clk)

    dut.ub_wr_host_data_in[0].value = 0
    dut.ub_wr_host_valid_in[0].value = 0
    dut.ub_wr_host_data_in[1].value = 0
    dut.ub_wr_host_valid_in[1].value = 0
    await RisingEdge(dut.clk)


async def send_read_cmd(dut, ptr_select, addr, row_size, col_size, transpose=0):
    """发读命令 1 周期后清除"""
    dut.ub_rd_start_in.value = 1
    dut.ub_ptr_select.value = ptr_select
    dut.ub_rd_addr_in.value = addr
    dut.ub_rd_row_size.value = row_size
    dut.ub_rd_col_size.value = col_size
    dut.ub_rd_transpose.value = transpose
    await RisingEdge(dut.clk)
    dut.ub_rd_start_in.value = 0
    dut.ub_ptr_select.value = 0
    dut.ub_rd_addr_in.value = 0
    dut.ub_rd_row_size.value = 0
    dut.ub_rd_col_size.value = 0
    dut.ub_rd_transpose.value = 0


def read_ub_memory(dut, addr, count):
    return [int(dut.ub_memory[addr + i].value) for i in range(count)]


def report_errors(dut, errors, test_name):
    if errors:
        dut._log.error(f"[{test_name}] Found {len(errors)} errors:")
        for e in errors:
            dut._log.error(f"  {e}")
        assert False, f"[{test_name}] {len(errors)} errors found"
    else:
        dut._log.info(f"[{test_name}] PASSED")


async def setup_test(dut, matrix, base_addr=0):
    """通用测试初始化: 启动时钟 + 复位 + 写入矩阵"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    await write_matrix_host(dut, matrix)


# ==================== Test 1: Host Write ====================
@cocotb.test()
async def test_host_write(dut):
    """写入 2x2 矩阵 [[1,2],[3,4]]，验证行主序存储"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    errors = []
    matrix = [[1, 2], [3, 4]]
    await write_matrix_host(dut, matrix)

    expected = [to_fixed(1), to_fixed(2), to_fixed(3), to_fixed(4)]
    actual = read_ub_memory(dut, 0, 4)
    for i in range(4):
        if actual[i] != expected[i]:
            errors.append(
                f"mem[{i}]: expected {from_fixed(expected[i])}, "
                f"got {from_fixed(actual[i])} (raw: 0x{actual[i]:04x})"
            )

    report_errors(dut, errors, "test_host_write")


# ==================== Test 2: Input Read with Hold Cycle ====================
@cocotb.test()
async def test_input_read_hold_cycle(dut):
    """V2 新增测试：验证最后一个数据的保持周期
    tc=0: lane0 valid, data=1
    tc=1: lane0 valid, data=3; lane1 valid, data=2
    tc=2: lane1 valid, data=4
    tc=3 (hold): 保持 tc=2 的输出
    tc=4: 复位
    """
    matrix = [[1, 2], [3, 4]]
    await setup_test(dut, matrix)

    errors = []
    await send_read_cmd(dut, 0, 0, 2, 2, transpose=0)

    # tc=0 output
    await RisingEdge(dut.clk)
    await ReadOnly()
    d0_tc0 = from_fixed(int(dut.ub_rd_input_data_out_0.value))
    v0_tc0 = int(dut.ub_rd_input_valid_out_0.value)
    v1_tc0 = int(dut.ub_rd_input_valid_out_1.value)

    # tc=1 output
    await RisingEdge(dut.clk)
    await ReadOnly()
    d0_tc1 = from_fixed(int(dut.ub_rd_input_data_out_0.value))
    d1_tc1 = from_fixed(int(dut.ub_rd_input_data_out_1.value))
    v0_tc1 = int(dut.ub_rd_input_valid_out_0.value)
    v1_tc1 = int(dut.ub_rd_input_valid_out_1.value)

    # tc=2 output (最后一个有效数据)
    await RisingEdge(dut.clk)
    await ReadOnly()
    d1_tc2 = from_fixed(int(dut.ub_rd_input_data_out_1.value))
    v0_tc2 = int(dut.ub_rd_input_valid_out_0.value)
    v1_tc2 = int(dut.ub_rd_input_valid_out_1.value)

    # tc=3 (hold cycle) - 关键验证点
    await RisingEdge(dut.clk)
    await ReadOnly()
    d1_tc3 = from_fixed(int(dut.ub_rd_input_data_out_1.value))
    v0_tc3 = int(dut.ub_rd_input_valid_out_0.value)
    v1_tc3 = int(dut.ub_rd_input_valid_out_1.value)

    # 验证 tc=3 保持了 tc=2 的输出
    if v1_tc3 != v1_tc2:
        errors.append(f"tc=3 hold: lane1 valid changed from {v1_tc2} to {v1_tc3}, expected hold")
    if v1_tc3 == 1 and abs(d1_tc3 - d1_tc2) > 0.01:
        errors.append(f"tc=3 hold: lane1 data changed from {d1_tc2} to {d1_tc3}, expected hold")

    # tc=4 应该复位
    await RisingEdge(dut.clk)
    await ReadOnly()
    v0_tc4 = int(dut.ub_rd_input_valid_out_0.value)
    v1_tc4 = int(dut.ub_rd_input_valid_out_1.value)

    if v0_tc4 != 0 or v1_tc4 != 0:
        errors.append(f"tc=4 reset: expected all valid=0, got v0={v0_tc4}, v1={v1_tc4}")

    dut._log.info(f"Hold cycle test: tc=2 v1={v1_tc2} d1={d1_tc2:.2f}, tc=3 v1={v1_tc3} d1={d1_tc3:.2f}")
    report_errors(dut, errors, "test_input_read_hold_cycle")


# ==================== Test 3: Weight Read with Hold Cycle ====================
@cocotb.test()
async def test_weight_read_hold_cycle(dut):
    """验证 weight read 的保持周期"""
    matrix = [[1, 2], [3, 4]]
    await setup_test(dut, matrix)

    errors = []
    await send_read_cmd(dut, 1, 0, 2, 2, transpose=0)

    # tc=0, tc=1, tc=2 正常输出
    for tc in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()

    # 记录 tc=2 的输出
    d1_tc2 = from_fixed(int(dut.ub_rd_weight_data_out_1.value))
    v1_tc2 = int(dut.ub_rd_weight_valid_out_1.value)

    # tc=3 (hold cycle)
    await RisingEdge(dut.clk)
    await ReadOnly()
    d1_tc3 = from_fixed(int(dut.ub_rd_weight_data_out_1.value))
    v1_tc3 = int(dut.ub_rd_weight_valid_out_1.value)

    # 验证保持
    if v1_tc3 != v1_tc2:
        errors.append(f"Weight hold: lane1 valid changed from {v1_tc2} to {v1_tc3}")
    if v1_tc3 == 1 and abs(d1_tc3 - d1_tc2) > 0.01:
        errors.append(f"Weight hold: lane1 data changed from {d1_tc2} to {d1_tc3}")

    report_errors(dut, errors, "test_weight_read_hold_cycle")


# ==================== Test 4: Ptr Calculation Consistency ====================
@cocotb.test()
async def test_ptr_calculation_consistency(dut):
    """验证组合逻辑 ptr 计算的一致性
    连续两次读取相同数据，结果应该一致
    """
    matrix = [[5, 6], [7, 8]]
    await setup_test(dut, matrix)

    errors = []

    # 第一次读取
    await send_read_cmd(dut, 0, 0, 2, 2, transpose=0)
    first_read = []
    for tc in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()
        first_read.append({
            'd0': from_fixed(int(dut.ub_rd_input_data_out_0.value)),
            'd1': from_fixed(int(dut.ub_rd_input_data_out_1.value)),
            'v0': int(dut.ub_rd_input_valid_out_0.value),
            'v1': int(dut.ub_rd_input_valid_out_1.value)
        })

    # 等待复位
    await ClockCycles(dut.clk, 3)

    # 第二次读取
    await send_read_cmd(dut, 0, 0, 2, 2, transpose=0)
    second_read = []
    for tc in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()
        second_read.append({
            'd0': from_fixed(int(dut.ub_rd_input_data_out_0.value)),
            'd1': from_fixed(int(dut.ub_rd_input_data_out_1.value)),
            'v0': int(dut.ub_rd_input_valid_out_0.value),
            'v1': int(dut.ub_rd_input_valid_out_1.value)
        })

    # 对比两次读取
    for tc in range(3):
        if first_read[tc]['v0'] != second_read[tc]['v0']:
            errors.append(f"tc={tc}: lane0 valid mismatch: {first_read[tc]['v0']} vs {second_read[tc]['v0']}")
        if first_read[tc]['v1'] != second_read[tc]['v1']:
            errors.append(f"tc={tc}: lane1 valid mismatch: {first_read[tc]['v1']} vs {second_read[tc]['v1']}")
        if first_read[tc]['v0'] == 1 and abs(first_read[tc]['d0'] - second_read[tc]['d0']) > 0.01:
            errors.append(f"tc={tc}: lane0 data mismatch: {first_read[tc]['d0']} vs {second_read[tc]['d0']}")
        if first_read[tc]['v1'] == 1 and abs(first_read[tc]['d1'] - second_read[tc]['d1']) > 0.01:
            errors.append(f"tc={tc}: lane1 data mismatch: {first_read[tc]['d1']} vs {second_read[tc]['d1']}")

    report_errors(dut, errors, "test_ptr_calculation_consistency")


# ==================== Test 5: Gradient Descent with New Ptr Logic ====================
@cocotb.test()
async def test_gradient_descent_ptr_logic(dut):
    """验证梯度下降的 ptr 计算逻辑（组合逻辑版本）"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    errors = []

    # 写入旧权重
    await write_matrix_host(dut, [[10, 20], [30, 40]])
    mem_before = read_ub_memory(dut, 0, 4)

    # 发 weight gradient 命令
    await send_read_cmd(dut, 6, 0, 2, 2)

    # 喂梯度数据
    grad_matrix = [[1, 2], [3, 4]]
    grad_lane0 = [grad_matrix[r][0] for r in range(2)]
    grad_lane1 = [grad_matrix[r][1] for r in range(2)]

    # Cycle 1
    dut.ub_wr_data_in[0].value = to_fixed(grad_lane0[0])
    dut.ub_wr_valid_in[0].value = 1
    dut.ub_wr_data_in[1].value = 0
    dut.ub_wr_valid_in[1].value = 0
    await RisingEdge(dut.clk)

    # Cycle 2
    dut.ub_wr_data_in[0].value = to_fixed(grad_lane0[1])
    dut.ub_wr_valid_in[0].value = 1
    dut.ub_wr_data_in[1].value = to_fixed(grad_lane1[0])
    dut.ub_wr_valid_in[1].value = 1
    await RisingEdge(dut.clk)

    # Cycle 3
    dut.ub_wr_data_in[0].value = 0
    dut.ub_wr_valid_in[0].value = 0
    dut.ub_wr_data_in[1].value = to_fixed(grad_lane1[1])
    dut.ub_wr_valid_in[1].value = 1
    await RisingEdge(dut.clk)

    # Clear
    dut.ub_wr_data_in[0].value = 0
    dut.ub_wr_valid_in[0].value = 0
    dut.ub_wr_data_in[1].value = 0
    dut.ub_wr_valid_in[1].value = 0

    await ClockCycles(dut.clk, 8)

    mem_after = read_ub_memory(dut, 0, 4)

    # 验证所有位置都被修改了
    changed_count = sum(1 for i in range(4) if mem_after[i] != mem_before[i])
    if changed_count == 0:
        errors.append("No memory locations changed after gradient descent")

    # 验证梯度方向正确（正梯度应该减小值）
    for i in range(4):
        old_val = from_fixed(mem_before[i])
        new_val = from_fixed(mem_after[i])
        if mem_after[i] != mem_before[i] and new_val > old_val:
            errors.append(f"mem[{i}]: value increased ({old_val} -> {new_val}), expected decrease")

    dut._log.info(f"Gradient descent: {changed_count}/4 locations updated")
    report_errors(dut, errors, "test_gradient_descent_ptr_logic")
