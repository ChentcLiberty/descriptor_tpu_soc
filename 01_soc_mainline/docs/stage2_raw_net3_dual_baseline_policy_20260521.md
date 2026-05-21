# raw `NET_ID=3` 双基线策略决定（2026-05-21）

## 1. 当前决定

当前决定是：

```text
继续保留 raw 路双基线
但不把双基线视为永久状态
```

也就是说，现阶段采用的是：

- `algorithmic expected` 保留
- `rtl expected` 保留
- `rtl expected` 作为 raw SoC 回归的签收真值
- `algorithmic expected` 作为模型审计和语义对照

当前策略名固定为：

- `staged_dual_baseline_rtl_signoff`

这个策略名已经写入：

- `work/600_competition_5stage/scripts/check_breath_cpu_frontend_q8_8_rtl_diff.py`
- `work/600_competition_5stage/scripts/run_breath_cpu_frontend_q8_8_rtl_precheck.sh`

## 2. 为什么现在不能直接删掉双基线

原因不是“习惯保留”，而是当前证据已经表明 raw 路在中间层就和算法导出分叉：

- `mlp_key`
- `mlp_other`
- `classifier_l2`
- `classifier_final`

因此如果直接删掉 `rtl expected`，会把 raw SoC 回归重新绑回一个已经证明不等价的参考值。

反过来，如果删掉 `algorithmic expected`，又会丢掉模型语义对照，后续很难定位到底是：

- 算法导出不贴 RTL
- fullcore 语义有固定差异
- 还是新的实现回归引入了真实漂移

## 3. 两套基线当前各自的职责

### 3.1 `rtl expected`

文件：

- `software/generated/breath_cpu_frontend_q8_8_rtl_expected.{json,svh}`

职责：

- raw `NET_ID=3` SoC 回归签收基线
- `extended/soak` 结果真值
- precheck allowlist 的严格对象

### 3.2 `algorithmic expected`

文件：

- `software/generated/breath_cpu_frontend_q8_8_expected.{json,svh}`

职责：

- 算法 / software fixed-point 参考
- raw 差异审计源
- 后续模型收敛目标

## 4. 这不意味着长期无限期保留双基线

当前建议不是“永远双基线”，而是“分阶段退出”。

退出双基线、收敛到单一签收模型，需要同时满足下面 4 个条件：

1. 有一份更贴近 fullcore 语义的 Python / reference model。
2. raw 路 UVM audit scoreboard 能解释当前允许差异集合。
3. `check_breath_cpu_frontend_q8_8_rtl_diff.py` 连续多轮没有出现 allowlist 外新漂移。
4. `fixture` 和 `raw` 两条路径在关键中间 watchpoint 上对参考模型收敛，而不是只看最终 classifier 两字输出。

在这些条件达成前，不建议把 `algorithmic expected` 直接升格成 raw SoC signoff 真值。

## 5. 当前验证口径怎么落

短期按下面这套口径执行：

### 5.1 交付 / 回归签收

使用：

- `rtl expected`

覆盖入口：

- `run_breath_cpu_frontend_q8_8_rtl_precheck.sh`
- `run_vcs_stage2_cpu_boot_cpu_frontend_raw_net3.sh`
- `run_vcs_stage2_regression_extended.sh`
- `run_vcs_stage2_net3_delivery.sh`

### 5.2 模型审计

使用：

- `algorithmic expected`
- `breath_cpu_frontend_q8_8_rtl_diff.md`

当前目标不是让它决定回归 pass/fail，而是让它持续暴露模型与 RTL 的差异边界。

## 6. 与 UVM 方法学的关系

UVM 引入后，双基线策略会更清楚地落成两类 scoreboard：

1. `rtl_signoff_scoreboard`
   - 决定 raw SoC 回归能否签收
2. `algorithmic_audit_scoreboard`
   - 决定模型差异是否仍在已知边界内

所以当前的“继续保留双基线”不是方法学混乱，反而是为了后续 UVM 双层校验做铺垫。

## 7. 结论

截至 `2026-05-21`，raw `NET_ID=3` 最合理的策略是：

- 短期保留双基线
- 交付签收以 `rtl expected` 为准
- `algorithmic expected` 继续作为审计参考
- 等 fullcore-faithful 模型和 raw UVM audit 机制成熟后，再讨论是否收敛成单基线
