# Verilator Quick Start

工作目录：

```bash
cd /Users/arlo/Projects/DSD_CW/DE1-SoC/task7_code
```

## 1. 直接运行一个 testbench

示例：运行 `tb/tb_task8_ci_fsum_pipe_protocol.sv`。

```bash
verilator --binary -Wall -Irtl/sim_models \
  --top-module tb_task8_ci_fsum_pipe_protocol \
  tb/tb_task8_ci_fsum_pipe_protocol.sv \
  rtl/task8_pipe/task8_ci_fsum_pipe.sv \
  rtl/task8_pipe/task8_pipe_fsum_core.sv \
  rtl/task8_pipe/task8_fp_accum_interleaved.sv \
  rtl/task8_pipe/task8_fp_add_rr_stage.sv \
  rtl/task8_pipe/task8_fp_mul_rr_stage.sv \
  rtl/task8_pipe/task8_cordic_cos_pipe.sv \
  rtl/task8/task8_ci_f2_accum.sv \
  rtl/ci_step3/task7_ci_f_single.sv \
  rtl/core/task7_fp_add_ip_unit.sv \
  rtl/core/task7_fp_mul_ip_unit.sv \
  rtl/core/task7_fp_sub_ip_unit.sv \
  rtl/core/task7_fp32_to_fx.sv \
  rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv \
  rtl/sim_models/custom_fp_add.sv \
  rtl/sim_models/custom_fp_mul.sv \
  rtl/sim_models/custom_fp_sub.sv

./obj_dir/Vtb_task8_ci_fsum_pipe_protocol
```

如果只是先看 lint：

```bash
verilator --lint-only -Wall -Irtl/sim_models \
  --top-module task8_ci_fsum_pipe \
  rtl/task8_pipe/task8_ci_fsum_pipe.sv \
  rtl/task8_pipe/task8_pipe_fsum_core.sv \
  rtl/task8_pipe/task8_fp_accum_interleaved.sv \
  rtl/task8_pipe/task8_fp_add_rr_stage.sv \
  rtl/task8_pipe/task8_fp_mul_rr_stage.sv \
  rtl/task8_pipe/task8_cordic_cos_pipe.sv \
  rtl/task8/task8_ci_f2_accum.sv \
  rtl/ci_step3/task7_ci_f_single.sv \
  rtl/core/task7_fp_add_ip_unit.sv \
  rtl/core/task7_fp_mul_ip_unit.sv \
  rtl/core/task7_fp_sub_ip_unit.sv \
  rtl/core/task7_fp32_to_fx.sv \
  rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv \
  rtl/sim_models/custom_fp_add.sv \
  rtl/sim_models/custom_fp_mul.sv \
  rtl/sim_models/custom_fp_sub.sv
```

## 2. 看波形

当前这些 testbench 默认**不导出波形**。要看波形，先在对应 testbench 里加：

```systemverilog
initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_task8_ci_fsum_pipe_protocol);
end
```

然后用 `--trace` 重新编译运行：

```bash
verilator --binary --trace -Wall -Irtl/sim_models \
  --top-module tb_task8_ci_fsum_pipe_protocol \
  tb/tb_task8_ci_fsum_pipe_protocol.sv \
  rtl/task8_pipe/task8_ci_fsum_pipe.sv \
  rtl/task8_pipe/task8_pipe_fsum_core.sv \
  rtl/task8_pipe/task8_fp_accum_interleaved.sv \
  rtl/task8_pipe/task8_fp_add_rr_stage.sv \
  rtl/task8_pipe/task8_fp_mul_rr_stage.sv \
  rtl/task8_pipe/task8_cordic_cos_pipe.sv \
  rtl/task8/task8_ci_f2_accum.sv \
  rtl/ci_step3/task7_ci_f_single.sv \
  rtl/core/task7_fp_add_ip_unit.sv \
  rtl/core/task7_fp_mul_ip_unit.sv \
  rtl/core/task7_fp_sub_ip_unit.sv \
  rtl/core/task7_fp32_to_fx.sv \
  rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv \
  rtl/sim_models/custom_fp_add.sv \
  rtl/sim_models/custom_fp_mul.sv \
  rtl/sim_models/custom_fp_sub.sv

./obj_dir/Vtb_task8_ci_fsum_pipe_protocol
```

运行后会生成 `waves.vcd`，打开：

```bash
gtkwave waves.vcd
```
