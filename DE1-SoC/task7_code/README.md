# Task 7 (DE1-SoC) - RTL + Verification Pack

This folder contains a Task 7 implementation aligned with the coursework split:
- Task 7a: CORDIC analysis (`analysis/task7a_cordic_mc.m`)
- Task 7b: step-2 accelerator setup (mul/add/sub/cos exposed separately)
- Task 7c: step-3 single custom instruction `f(x)` with internal FSM

## Current architecture

### CORDIC path
- `rtl/core/task7_cordic_cos_multi_iter.sv`
- Fixed-point CORDIC cosine (multi-iteration-per-cycle capable).

### Floating-point arithmetic path (IP-backed)
- `rtl/core/task7_fp_mul_ip_unit.sv`
- `rtl/core/task7_fp_add_ip_unit.sv`
- `rtl/core/task7_fp_sub_ip_unit.sv`

These files are execution-unit wrappers used by the FSM/control logic.
- Simulation: lightweight shortreal model
- Synthesis: uses your Intel FP IP modules `custom_fp_mul`, `custom_fp_add`, `custom_fp_sub`

### Conversion blocks
- `rtl/core/task7_fp32_to_fx.sv`
- `rtl/core/task7_fx_to_fp32.sv`

### Step-2 CIs
- `rtl/ci_step2/task7_ci_fp32_mul.sv`
- `rtl/ci_step2/task7_ci_fp32_add.sv`
- `rtl/ci_step2/task7_ci_fp32_sub.sv`
- `rtl/ci_step2/task7_ci_cos_only.sv`

### Step-3 final CI
- `rtl/ci_step3/task7_ci_f_single.sv`

`task7_ci_f_single` computes
`f(x) = 0.5*x + x^3*cos((x-128)/128)`
through one internal FSM and reuses a single instance of each accelerator path.

## Testbenches
- `tb/tb_task7_cordic.sv`
- `tb/tb_task7_step2_accels.sv`
- `tb/tb_task7_ci_f.sv`
- `tb/tb_task7_perf.sv`
- `cocotb/test_task7_ci.py`

## Notes for Quartus integration
- Keep `task7_ci_f_single.sv` as step-3 custom-instruction top.
- Ensure these generated IP modules are available in your project:
  - `custom_fp_mul` (mul)
  - `custom_fp_add` (add)
  - `custom_fp_sub` (sub)
- This code assumes latency `2` cycles for FP add/sub/mul by default. If your IP latency is changed, update `MUL_LATENCY` / `ADD_LATENCY` accordingly.