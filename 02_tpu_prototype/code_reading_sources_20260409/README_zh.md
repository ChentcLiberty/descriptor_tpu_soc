# 本地源码阅读镜像目录

这个目录是为了让你只在 `tpu-soc` 下面看代码，不用再跳去 `_vendor/tiny-tpu`。

建议直接按编号顺序看：
1. `01_scheduler.py`
2. `02_ub_allocator.py`
3. `03_encode_instrs.py`
4. `04_control_unit.sv`
5. `05_tpu_frontend_axil.sv`
6. `06_tpu_soc.sv`
7. `07_tpu.sv`
8. `08_unified_buffer_v3.sv`
9. `09_pe.sv`
10. `10_systolic.sv`
11. `11_vpu.sv`
12. `12_test_tpu_soc_axil_train_convergence.py`

配套说明文档看：
- `/home/jjt/tpu-soc/docs/code_reading_pack_20260408`

附加产物：
- `13_mlp_2_2_1_q8_8.schedule.json`
- `14_mlp_2_2_1_q8_8.ub_map.json`
- `15_imem.hex`
- `16_imem.txt`

一句话：
先看软件链，再看控制链，最后看数据链和验证。
