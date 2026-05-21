"""
tpu_soc AXI-Lite 端到端验证
DUT: tpu_soc_top
验证: forward + backward 完整流程，VPU 输出 vs numpy 参考模型
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from pathlib import Path
import numpy as np

FRAC_BITS = 8
TOLERANCE = 0.20

# ---- Q8.8 helpers ----
def to_fxp(v):
    return int(round(v * (1 << FRAC_BITS))) & 0xFFFF

def from_fxp(v):
    if v >= (1 << 15): v -= (1 << 16)
    return float(v) / (1 << FRAC_BITS)

def fxp(v):   return from_fxp(to_fxp(v))
def fxpa(a):  return np.vectorize(fxp)(a)

# ---- 训练数据 & 权重 ----
X  = fxpa(np.array([[0.,0.],[0.,1.],[1.,0.],[1.,1.]]))
Y  = fxpa(np.array([0, 1, 1, 0], dtype=float))
W1 = fxpa(np.array([[0.2985,-0.5792],[0.0913,0.4234]]))
W2 = fxpa(np.array([0.5266, 0.2958]))
B1 = fxpa(np.array([-0.4939, 0.189]))
B2 = fxpa(np.array([0.6358]))
LEAK   = fxp(0.5)
INV_N2 = fxp(2.0 / 4)
LR     = fxp(0.125)
TILE_WIDTH = 2
PARAM_TOLERANCE = 0.01

# ---- 参考模型 ----
def leaky_relu(x):      return np.where(x >= 0, x, fxpa(x * LEAK))
def leaky_relu_d(g, h): return np.where(h >= 0, g, fxpa(g * LEAK))

def reference_forward():
    Z1 = fxpa(X @ W1.T + B1)
    H1 = leaky_relu(Z1)
    Z2 = fxpa(H1 @ W2.reshape(-1,1) + B2)
    H2 = leaky_relu(Z2).flatten()
    return H1, H2

def reference_backward(H1, H2):
    dZ2 = fxpa((H2 - Y) * INV_N2)
    dH1 = fxpa(dZ2.reshape(-1,1) @ W2.reshape(1,-1))
    dZ1 = leaky_relu_d(dH1, H1)
    return dZ2, dZ1


def flatten_words(arr):
    return [to_fxp(float(v)) for v in np.asarray(arr).reshape(-1)]


def fxp_mul_scalar(a, b):
    return fxp(float(a) * float(b))


def apply_update_scalar(param, grad, lr=LR):
    return fxp(float(param) - fxp_mul_scalar(grad, lr))


def reference_params_after_update(H1, dZ2, dZ1):
    w1 = np.array(W1, dtype=float, copy=True)
    b1 = np.array(B1, dtype=float, copy=True)
    w2 = np.array(W2, dtype=float, copy=True)
    b2 = np.array(B2, dtype=float, copy=True)

    # Bias updates are accumulated sample by sample in the in-UB gradient_descent path.
    for g in np.asarray(dZ2).reshape(-1):
        b2[0] = apply_update_scalar(b2[0], g)

    for row in np.asarray(dZ1):
        for j in range(b1.shape[0]):
            b1[j] = apply_update_scalar(b1[j], row[j])

    # Weight updates happen tile by tile; each tile produces one outer-product partial sum.
    for tile_start in range(0, len(dZ2), TILE_WIDTH):
        dz2_tile = np.asarray(dZ2[tile_start:tile_start + TILE_WIDTH], dtype=float)
        h1_tile = np.asarray(H1[tile_start:tile_start + TILE_WIDTH], dtype=float)
        tile_grad_w2 = fxpa(dz2_tile.reshape(1, -1) @ h1_tile).reshape(-1)
        for j, grad in enumerate(tile_grad_w2):
            w2[j] = apply_update_scalar(w2[j], grad)

    for tile_start in range(0, dZ1.shape[0], TILE_WIDTH):
        dz1_tile = np.asarray(dZ1[tile_start:tile_start + TILE_WIDTH], dtype=float)
        x_tile = np.asarray(X[tile_start:tile_start + TILE_WIDTH], dtype=float)
        tile_grad_w1 = fxpa(dz1_tile.T @ x_tile)
        for r in range(w1.shape[0]):
            for c in range(w1.shape[1]):
                w1[r, c] = apply_update_scalar(w1[r, c], tile_grad_w1[r, c])

    return {
        "W1": flatten_words(w1),
        "B1": flatten_words(b1),
        "W2": flatten_words(w2),
        "B2": flatten_words(b2),
    }

# ---- AXI-Lite 驱动 ----
async def axil_write(dut, addr, data):
    await RisingEdge(dut.s_axil_aclk)
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data & 0xFFFFFFFF
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_wvalid.value  = 1
    dut.s_axil_bready.value  = 1
    await RisingEdge(dut.s_axil_aclk)
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    while not dut.s_axil_bvalid.value:
        await RisingEdge(dut.s_axil_aclk)
    await RisingEdge(dut.s_axil_aclk)
    dut.s_axil_bready.value  = 0

async def axil_read(dut, addr):
    await RisingEdge(dut.s_axil_aclk)
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    dut.s_axil_rready.value  = 1
    while not dut.s_axil_rvalid.value:
        await RisingEdge(dut.s_axil_aclk)
    val = int(dut.s_axil_rdata.value)
    await RisingEdge(dut.s_axil_aclk)
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value  = 0
    return val

# ---- UB 双 lane 写入 ----
# push_mask: 0=no push, 1=lane0 only, 2=lane1 only, 3=both lanes
async def ub_write_cycle(dut, d0, d1, push_mask):
    """写 data0/data1 寄存器，然后按 push_mask 触发 push"""
    if push_mask & 1:
        await axil_write(dut, 0x020, d0 & 0xFFFF)
    if push_mask & 2:
        await axil_write(dut, 0x028, d1 & 0xFFFF)
    if push_mask:
        await axil_write(dut, 0x024, push_mask)

async def load_all_data_axil(dut):
    """
    精确复刻 load_all_data 的双 lane 写入时序：
    每个原始 clock 翻译为：写 data0/data1 寄存器 + push

    原始序列（lane0, lane1, push_mask）：
    clk0: X[0][0],  -,        1  (lane0 only)
    clk1: X[1][0],  X[0][1],  3
    clk2: X[2][0],  X[1][1],  3
    clk3: X[3][0],  X[2][1],  3
    clk4: Y[0],     X[3][1],  3
    clk5: Y[1],     -,        1
    clk6: Y[2],     -,        1
    clk7: Y[3],     -,        1
    clk8: W1[0][0], -,        1
    clk9: W1[1][0], W1[0][1], 3
    clk10:B1[0],    W1[1][1], 3
    clk11:W2[0],    B1[1],    3
    clk12:B2[0],    W2[1],    3
    """
    seq = [
        (to_fxp(X[0][0]),  0,                  1),
        (to_fxp(X[1][0]),  to_fxp(X[0][1]),    3),
        (to_fxp(X[2][0]),  to_fxp(X[1][1]),    3),
        (to_fxp(X[3][0]),  to_fxp(X[2][1]),    3),
        (to_fxp(Y[0]),     to_fxp(X[3][1]),    3),
        (to_fxp(Y[1]),     0,                  1),
        (to_fxp(Y[2]),     0,                  1),
        (to_fxp(Y[3]),     0,                  1),
        (to_fxp(W1[0][0]), 0,                  1),
        (to_fxp(W1[1][0]), to_fxp(W1[0][1]),   3),
        (to_fxp(B1[0]),    to_fxp(W1[1][1]),   3),
        (to_fxp(W2[0]),    to_fxp(B1[1]),      3),
        (to_fxp(B2[0]),    to_fxp(W2[1]),      3),
    ]
    for d0, d1, mask in seq:
        await ub_write_cycle(dut, d0, d1, mask)

# ---- IMEM 加载 ----
async def imem_load(dut, hex_path):
    lines = Path(hex_path).read_text().strip().splitlines()
    instrs = [int(l.strip(), 16) for l in lines if l.strip()]
    for i, instr in enumerate(instrs):
        await axil_write(dut, 0x030, i)
        await axil_write(dut, 0x034, instr)
        await axil_write(dut, 0x040, 1)
    await axil_write(dut, 0x044, len(instrs))
    return len(instrs)

# ---- 输出采集（等 busy=0 结束，按 valid 收集） ----
async def collect_until_done(dut, timeout_cycles=500000):
    col1, col2 = [], []
    for _ in range(timeout_cycles):
        await RisingEdge(dut.s_axil_aclk)
        v1 = int(dut.vpu_valid_out_1.value)
        v2 = int(dut.vpu_valid_out_2.value)
        if v1:
            col1.append(from_fxp(int(dut.vpu_data_out_1.value)))
        if v2:
            col2.append(from_fxp(int(dut.vpu_data_out_2.value)))
        # 检查 busy
        # busy 清零后再等几拍确认
        status = int(dut.vpu_valid_out_1.value) | int(dut.vpu_valid_out_2.value)
    return col1, col2

async def wait_busy_clear(dut, timeout_cycles=500000):
    for _ in range(timeout_cycles):
        await RisingEdge(dut.s_axil_aclk)
        # 轮询 STATUS 寄存器 busy bit
        # 避免每 cycle 都做 AXI read（太慢），改用直接观察 vpu_valid
        pass

# ---- Scoreboard ----
class Scoreboard:
    def __init__(self):
        self.passed = 0; self.failed = 0

    def check(self, tag, exp, got):
        err = abs(got - exp)
        if err <= TOLERANCE:
            self.passed += 1
            cocotb.log.info(f"PASS {tag}: exp={exp:.4f} got={got:.4f}")
        else:
            self.failed += 1
            cocotb.log.error(f"FAIL {tag}: exp={exp:.4f} got={got:.4f} err={err:.4f}")

    def check_word(self, tag, exp, got):
        exp &= 0xFFFF
        got &= 0xFFFF
        if got == exp:
            self.passed += 1
            cocotb.log.info(f"PASS {tag}: exp=0x{exp:04x} got=0x{got:04x}")
        else:
            self.failed += 1
            cocotb.log.error(f"FAIL {tag}: exp=0x{exp:04x} got=0x{got:04x}")

    def check_param(self, tag, exp, got):
        err = abs(got - exp)
        if err <= PARAM_TOLERANCE:
            self.passed += 1
            cocotb.log.info(f"PASS {tag}: exp={exp:.4f} got={got:.4f}")
        else:
            self.failed += 1
            cocotb.log.error(f"FAIL {tag}: exp={exp:.4f} got={got:.4f} err={err:.4f}")

    def report(self):
        cocotb.log.info(f"=== Scoreboard: {self.passed}/{self.passed+self.failed} PASS ===")
        assert self.failed == 0, f"{self.failed} checks failed"

# ============================================================
# Main test
# ============================================================
@cocotb.test()
async def test_tpu_soc_e2e(dut):
    cocotb.start_soon(Clock(dut.s_axil_aclk, 10, units="ns").start())

    # Reset
    dut.s_axil_aresetn.value = 0
    for sig in [dut.s_axil_awvalid, dut.s_axil_wvalid, dut.s_axil_bready,
                dut.s_axil_arvalid, dut.s_axil_rready]:
        sig.value = 0
    dut.s_axil_awaddr.value = 0; dut.s_axil_wdata.value = 0
    dut.s_axil_wstrb.value = 0; dut.s_axil_araddr.value = 0
    await ClockCycles(dut.s_axil_aclk, 4)
    dut.s_axil_aresetn.value = 1
    await ClockCycles(dut.s_axil_aclk, 2)

    # 配置全局参数
    await axil_write(dut, 0x050, to_fxp(LEAK))    # LEAK_FACTOR
    await axil_write(dut, 0x054, to_fxp(INV_N2))  # INV_BATCH_N2
    await axil_write(dut, 0x058, to_fxp(LR))      # LEARNING_RATE

    # 加载 UB 数据（精确双 lane 交错）
    await load_all_data_axil(dut)
    cocotb.log.info("UB data loaded")

    # 加载 IMEM
    imem_hex = Path(__file__).parent.parent / "compiler/out/imem.hex"
    n = await imem_load(dut, str(imem_hex))
    cocotb.log.info(f"Loaded {n} instructions into IMEM")

    # 启动 sequencer，同时开始采集输出
    # 确认 UB 关键地址
    await ClockCycles(dut.s_axil_aclk, 2)
    try:
        def safe_ub(addr):
            v = dut.dut.tpu_inst.ub_inst.ub_memory[addr].value
            try: return int(v)
            except: return -1
        cocotb.log.info(f"UB check: [3]={safe_ub(3):#06x}(exp X[1][1]=0x0100) [12]={safe_ub(12):#06x}(exp W1[0][0]={to_fxp(W1[0][0]):#06x}) [16]={safe_ub(16):#06x}(exp B1[0]={to_fxp(B1[0]):#06x})")
    except Exception as e:
        cocotb.log.warning(f"UB check: {e}")
    col1, col2 = [], []

    async def collect():
        while True:
            await RisingEdge(dut.s_axil_aclk)
            try: v1 = int(dut.vpu_valid_out_1.value)
            except: v1 = -1
            try: v2 = int(dut.vpu_valid_out_2.value)
            except: v2 = -1
            if v1 > 0:
                try:
                    val = from_fxp(int(dut.vpu_data_out_1.value))
                    col1.append(val)
                    cocotb.log.info(f"col1[{len(col1)-1}]={val:.4f}")
                except: col1.append(float('nan'))
            if v2 > 0:
                try:
                    val = from_fxp(int(dut.vpu_data_out_2.value))
                    col2.append(val)
                    cocotb.log.info(f"col2[{len(col2)-1}]={val:.4f}")
                except: col2.append(float('nan'))
            if v1 < 0 or v2 < 0:
                pass  # X value, ignore

    collector = cocotb.start_soon(collect())

    await axil_write(dut, 0x000, 0x2)  # CTRL.start=1
    cocotb.log.info("Sequencer started")

    # 等待 busy=0（轮询 STATUS 寄存器，每 500 cycle 查一次，最多 200 次 = 100K cycles）
    for attempt in range(200):
        await ClockCycles(dut.s_axil_aclk, 500)
        status = await axil_read(dut, 0x004)
        try:
            state = int(dut.dut.frontend.seq_state.value)
            pc    = int(dut.dut.frontend.pc.value)
            vd    = int(dut.dut.frontend.vpu_drain.value)
            vp    = int(dut.dut.frontend.tpu_vpu_valid_in.value)
        except: state=pc=vd=vp=-1
        if attempt < 5 or attempt % 20 == 0:
            cocotb.log.info(f"[poll {attempt}] STATUS=0x{status:x} state={state} pc={pc} vpu_valid={vp} drain={vd} col1={len(col1)} col2={len(col2)}")
        if not (status & 0x1):
            cocotb.log.info(f"Sequencer done after ~{attempt*500} cycles")
            break
    else:
        cocotb.log.error(f"Timeout! col1={col1[:8]} col2={col2[:8]}")
        raise TimeoutError("Sequencer did not complete")

    await ClockCycles(dut.s_axil_aclk, 10)
    collector.kill()

    cocotb.log.info(f"col1 ({len(col1)}): {col1}")
    cocotb.log.info(f"col2 ({len(col2)}): {col2}")

    # 参考模型
    H1_ref, H2_ref = reference_forward()
    dZ2_ref, dZ1_ref = reference_backward(H1_ref, H2_ref)
    params_after_update = reference_params_after_update(H1_ref, dZ2_ref, dZ1_ref)
    cocotb.log.info(f"REF H1[:,0]={H1_ref[:,0].tolist()}")
    cocotb.log.info(f"REF H1[:,1]={H1_ref[:,1].tolist()}")
    cocotb.log.info(f"REF dZ2={dZ2_ref.tolist()}")
    cocotb.log.info(f"REF dZ1[:,0]={dZ1_ref[:,0].tolist()}")
    cocotb.log.info(f"REF dZ1[:,1]={dZ1_ref[:,1].tolist()}")
    cocotb.log.info(f"REF LR={LR:.4f}")
    cocotb.log.info(f"REF updated W1={list(map(from_fxp, params_after_update['W1']))}")
    cocotb.log.info(f"REF updated B1={list(map(from_fxp, params_after_update['B1']))}")
    cocotb.log.info(f"REF updated W2={list(map(from_fxp, params_after_update['W2']))}")
    cocotb.log.info(f"REF updated B2={list(map(from_fxp, params_after_update['B2']))}")

    if len(col1) < 12 or len(col2) < 8:
        raise AssertionError(
            f"Unexpected output counts: need col1>=12 col2>=8, got col1={len(col1)} col2={len(col2)}"
        )

    h1_col1 = col1[0:4]
    h1_col2 = col2[0:4]
    dz2_col1 = col1[4:8]
    dz1_col1 = col1[8:12]
    dz1_col2 = col2[4:8]

    sb = Scoreboard()

    for i in range(4):
        sb.check(f"H1[{i},0]", H1_ref[i, 0], h1_col1[i])
    for i in range(4):
        sb.check(f"H1[{i},1]", H1_ref[i, 1], h1_col2[i])

    for i in range(4):
        sb.check(f"dZ2[{i}]", dZ2_ref[i], dz2_col1[i])

    for i in range(4):
        sb.check(f"dZ1[{i},0]", dZ1_ref[i, 0], dz1_col1[i])
    for i in range(4):
        sb.check(f"dZ1[{i},1]", dZ1_ref[i, 1], dz1_col2[i])

    def ub_word(addr):
        return int(dut.dut.tpu_inst.ub_inst.ub_memory[addr].value) & 0xFFFF

    dz2_words = flatten_words(dZ2_ref)
    dz1_words = flatten_words(dZ1_ref)
    for i, exp in enumerate(dz2_words):
        sb.check(f"UB dZ2[{i}]", from_fxp(exp), from_fxp(ub_word(29 + i)))
    for i, exp in enumerate(dz1_words):
        sb.check(f"UB dZ1[{i}]", from_fxp(exp), from_fxp(ub_word(33 + i)))

    for i, exp in enumerate(params_after_update["W1"]):
        sb.check_param(f"UB W1[{i}]", from_fxp(exp), from_fxp(ub_word(12 + i)))
    for i, exp in enumerate(params_after_update["B1"]):
        sb.check_param(f"UB B1[{i}]", from_fxp(exp), from_fxp(ub_word(16 + i)))
    for i, exp in enumerate(params_after_update["W2"]):
        sb.check_param(f"UB W2[{i}]", from_fxp(exp), from_fxp(ub_word(18 + i)))
    for i, exp in enumerate(params_after_update["B2"]):
        sb.check_param(f"UB B2[{i}]", from_fxp(exp), from_fxp(ub_word(20 + i)))

    sb.report()
