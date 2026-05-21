## Phase 1 - Direct-Core Interface Sketch

### 目标

定义一个最小 direct-core wrapper 接口，使其在不依赖 `tpu_soc / tpu_frontend_axil / IMEM` 的前提下，仍能完成当前 SoC 前向子集。

### 设计原则

1. 保留 `tpu.v` 原始计算核心及其依赖。
2. 不把 `sys_psum_out_*` 重新拿出来做外部后处理。
3. 最终结果仍从 `UB Y` 或等价核心存储语义读回。
4. 只为当前前向子集暴露最小控制面。

### 候选分层

- `stage2_soc_shell`
  - descriptor / shared SRAM / AXI
- `stage2_direct_core_bridge`
  - tile 调度 / 参数装填 / 累积 / readback
- `tpu_core_island`
  - `tpu.v` 或拆开的 `unified_buffer + systolic + vpu`

### 最小控制接口草图

```systemverilog
module tpu_stage2_direct_core_wrapper (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        launch_pulse,
    input  logic        soft_reset_pulse,
    input  logic [31:0] desc_base_addr,

    output logic        status_busy,
    output logic        status_done,
    output logic        status_error,

    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready
);
```

上面只是 SoC 外层端口。真正关键的是 bridge 到 core island 的本地接口。

### bridge 到 core island 的本地接口

#### Host-write into UB

```systemverilog
output logic [15:0] ub_wr_host_data_in [0:1];
output logic        ub_wr_host_valid_in[0:1];
output logic        ub_wr_ptr_restore_in;
```

用途：装填 `X/W/B`。

#### UB read control

```systemverilog
output logic        ub_rd_start_in;
output logic        ub_rd_transpose;
output logic [8:0]  ub_ptr_select;
output logic [15:0] ub_rd_addr_in;
output logic [15:0] ub_rd_row_size;
output logic [15:0] ub_rd_col_size;
```

用途：替代当前 `UB_RD` 指令语义。

#### Core control scalars

```systemverilog
output logic        sys_switch_in;
output logic [3:0]  vpu_data_pathway;
output logic [15:0] vpu_leak_factor_in;
output logic [15:0] inv_batch_size_times_two_in;
output logic [15:0] learning_rate_in;
```

用途：替代 `LEAK / INV_BATCH / LR / SWITCH / pathway` 这些 frontend 控制项。

#### Core observation ports

```systemverilog
input  logic [15:0] vpu_data_out_1, vpu_data_out_2;
input  logic        vpu_valid_out_1, vpu_valid_out_2;
input  logic [15:0] ub_rd_Y_data_out_0, ub_rd_Y_data_out_1;
input  logic        ub_rd_Y_valid_out_0, ub_rd_Y_valid_out_1;
```

用途：

- `vpu_data_out_*`：中间 tile 累积捕获
- `ub_rd_Y_*`：最终结果 readback

### 第一版 direct-core 状态机建议

最小状态机可以仍按当前 IMEM 顺序拆成显式状态：

1. `LOAD_DESC`
2. `FETCH_INPUTS`
3. `FETCH_PARAMS`
4. `RESTORE_UB_PTR`
5. `PUSH_X`
6. `PUSH_W`
7. `PUSH_B`
8. `ISSUE_RD_WEIGHT`
9. `WAIT_WEIGHT_PIPE`
10. `ISSUE_SWITCH`
11. `WAIT_SWITCH_PIPE`
12. `ISSUE_RD_BIAS`
13. `ISSUE_RD_INPUT`
14. `WAIT_TILE_DONE`
15. `CAPTURE_TILE_OUT`
16. `ISSUE_RD_Y`
17. `WAIT_RD_Y`
18. `AXI_WRITEBACK`

### 当前不建议直接做的事

当前不建议在 direct-core 第一步就做：

- 同时改 forward 和 training 路径
- 同时改 scratch 协议
- 同时去掉 `vpu_data_out -> next bias` 的外部暂存
- 同时扩大到更多矩阵形状

### 验收约束

当 direct-core wrapper 第一版完成时，至少要满足：

- `real_params` 输出不变
- `fixture cpu_frontend` 输出不变
- `UB readback -> AXI writeback` 路径不变
- 中间 tile 累积语义不变
