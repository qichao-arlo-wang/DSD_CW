# Task 7 (DE1-SoC) - Complete RTL + Verification Pack

This folder implements Task 7 in three parts aligned with the coursework and marking scheme:

1. **Task 7a (analysis)**
- `analysis/task7a_cordic_mc.m`
- Monte-Carlo sweep of CORDIC iterations and fixed-point fractional bits.
- Reports analytical `2^{-i}` estimate, MSE, and 95% CI upper bound against single-precision cosine, for `x ~ U[-1,1]`.
- Use this script to justify the selected CORDIC configuration.

2. **Task 7b (CORDIC architecture/implementation)**
- `rtl/core/task7_cordic_cos_multi_iter.sv`
- Fixed-point CORDIC cosine core with **multiple iterations per cycle** (`ITER_PER_CYCLE > 1`), matching the high-mark architecture direction.
- Default configuration:
  - `N_ITER = 18`
  - `ITER_PER_CYCLE = 3`
  - Q format for CORDIC: signed Q6.22 (`W=28, FRAC=22`)

3. **Task 7c (single custom instruction with internal FSM)**
- `rtl/ci_step3/task7_ci_f_single.sv`
- Computes
  - `f(x) = 0.5*x + x^3*cos((x-128)/128)`
- Non-cos arithmetic path uses fp32 units; only `cos()` path uses fixed-point CORDIC.
- Integrates all sub-blocks under one custom instruction style interface:
  - ports: `clk, reset, clk_en, start, dataa, datab, n, done, result`
- Uses one instance each of:
  - CORDIC core
  - fixed-point multiplier unit
  - fixed-point adder unit
- FSM + register file schedule all operations internally (NIOS no longer orchestrates intermediate calls).

## RTL files
- `rtl/core/task7_fp32_to_fx.sv`: IEEE-754 single -> fixed-point converter
- `rtl/core/task7_fx_to_fp32.sv`: fixed-point -> IEEE-754 single converter
- `rtl/core/task7_fp32_mul_unit.sv`: shared fp32 multiply accelerator with start/done
- `rtl/core/task7_fp32_add_unit.sv`: shared fp32 add accelerator with start/done
- `rtl/core/task7_cordic_cos_multi_iter.sv`: multi-iteration CORDIC cosine core
- `rtl/ci_step2/task7_ci_cos_only.sv`: Step-2 standalone CORDIC custom instruction
- `rtl/ci_step2/task7_ci_fp32_mul.sv`: Step-2 standalone fp32 multiplier custom instruction
- `rtl/ci_step2/task7_ci_fp32_addsub.sv`: Step-2 standalone fp32 add/sub custom instruction (`n[0]` selects add/sub)
- `rtl/ci_step3/task7_ci_f_single.sv`: final Step-3 single custom instruction for `f(x)`
- `rtl/optional_fx/task7_fx_add_unit.sv`: optional fixed-point saturating adder (not used in main CI path)
- `rtl/optional_fx/task7_fx_mul_unit.sv`: optional fixed-point saturating multiplier (not used in main CI path)

## Testbenches
- SystemVerilog:
  - `tb/tb_task7_cordic.sv`
  - `tb/tb_task7_ci_f.sv`
  - `tb/tb_task7_step2_accels.sv`
  - `tb/tb_task7_fp32_units.sv`
  - `tb/tb_task7_perf.sv` (cycle-latency measurement support)
- cocotb + Verilator:
  - `cocotb/test_task7_ci.py`
  - `cocotb/Makefile`

## How to run

### 7a Monte-Carlo analysis
```bash
/Applications/MATLAB_R2025b.app/bin/matlab -batch "cd('/Users/arlo/Projects/DSD_CW/task7_code/analysis'); task7a_cordic_mc('samples',50000,'seed',7,'iters',12:24,'fracs',20:34,'export_csv','/Users/arlo/Projects/DSD_CW/report3/Code/task7a_sweep_results.csv','figure_dir','/Users/arlo/Projects/DSD_CW/report3/Images','figure_prefix','t7a');"
```

### cocotb + Verilator regression
```bash
cd task7_code/cocotb
make
```

### Direct Verilator run with SystemVerilog TBs
```bash
# CORDIC core TB
rm -rf obj_dir
/opt/homebrew/bin/verilator -Wall -Wno-fatal -Wno-DECLFILENAME --binary -sv \
  --top-module tb_task7_cordic \
  tb/tb_task7_cordic.sv rtl/core/task7_cordic_cos_multi_iter.sv
./obj_dir/Vtb_task7_cordic

# Final single custom instruction TB
rm -rf obj_dir
/opt/homebrew/bin/verilator -Wall -Wno-fatal -Wno-DECLFILENAME --binary -sv \
  --top-module tb_task7_ci_f \
  tb/tb_task7_ci_f.sv \
  rtl/core/task7_fp32_to_fx.sv rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_fp32_mul_unit.sv rtl/core/task7_fp32_add_unit.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv rtl/ci_step3/task7_ci_f_single.sv
./obj_dir/Vtb_task7_ci_f

# Step-2 three-accelerator TB
rm -rf obj_dir
/opt/homebrew/bin/verilator -Wall -Wno-fatal -Wno-DECLFILENAME --binary -sv \
  --top-module tb_task7_step2_accels \
  tb/tb_task7_step2_accels.sv \
  rtl/core/task7_fp32_to_fx.sv rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv \
  rtl/core/task7_fp32_mul_unit.sv rtl/core/task7_fp32_add_unit.sv \
  rtl/ci_step2/task7_ci_fp32_mul.sv rtl/ci_step2/task7_ci_fp32_addsub.sv rtl/ci_step2/task7_ci_cos_only.sv
./obj_dir/Vtb_task7_step2_accels
```

## Notes for Quartus / Platform Designer integration
- Add `rtl/ci_step3/task7_ci_f_single.sv` as the component top module.
- In the custom instruction template, use variable multicycle mode and map:
  - `dataa` as the float input `x`
  - `result` as float output `f(x)`
  - `start/done/clk/clk_en/reset` as standard multicycle control.
- Keep `datab` and `n` connected for interface compatibility (unused in this implementation).

## Important implementation note
- The CORDIC constants in `rtl/core/task7_cordic_cos_multi_iter.sv` are precomputed for `FRAC = 22`.
- If you change `FRAC`, regenerate the constants (or keep `FRAC=22`).
