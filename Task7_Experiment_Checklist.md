# Task 7 Experiment Checklist (Spec + Marking Aligned)

This checklist is a direct execution plan for Task 7a/7b/7c and the three implementation steps in the coursework.
It focuses on:
- required files,
- purpose of each file,
- experiments to run,
- data that must be collected for report/marking.

## 1) Hard Requirements From Spec and Marking

## 1.1 Spec requirements that must be satisfied
- Implement `f(x) = 0.5x + x^3 cos((x-128)/128)` as hardware custom instruction flow for Task 7.
- `cos(.)` must be a fixed-point CORDIC implementation.
- LUT cosine and existing cosine IP are not allowed.
- CORDIC must be optimized by selecting:
  - number of iterations / stages,
  - fixed-point wordlength.
- Accuracy target for CORDIC (`x ~ U[-1,1]`, single-precision input):
  - MSE < `2.4e-11` with `95%` confidence.
- Verify by simulation (function + cycles), and check timing after place and route at `50 MHz`.
- Task 7 objective: minimize latency for single `f(x)` evaluation; for equal latency, choose smaller resource footprint.
- Use the three coursework cases for full-function reporting:
  - C1: `X = 0:5:255`
  - C2: `X = 0:1/8:255`
  - C3: `X = 0:1/256:255`

## 1.2 Marking requirements that must be evidenced
- Task 7a full-mark direction:
  - use `2^-i` error trend estimate,
  - Monte Carlo simulation,
  - investigate both iterations and wordlength.
- Task 7b full-mark direction:
  - multiple CORDIC iterations per cycle (not only 1 iteration/cycle).
- Task 7c core requirement:
  - single custom instruction block with internal FSM,
  - integrate all sub-blocks under that single CI.

---

## 2) Step-by-Step Plan

## Step 1: CORDIC design/analysis and isolated validation (Task 7a + Task 7b base)

### Files to use
- MATLAB analysis:
  - [/Users/arlo/Projects/DSD_CW/task7_code/analysis/task7a_cordic_mc.m](/Users/arlo/Projects/DSD_CW/task7_code/analysis/task7a_cordic_mc.m)
- CORDIC RTL:
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_cordic_cos_multi_iter.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_cordic_cos_multi_iter.sv)
- CORDIC isolated TB:
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_cordic.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_cordic.sv)
- Quick latency TB (for relative checks):
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv)

### Experiments to run
1. Monte Carlo sweep on both dimensions:
   - `N_ITER` sweep and `FRAC` sweep (not only one dimension).
2. Compute and report:
   - analytical `2^-i` trend,
   - Monte Carlo MSE,
   - 95% CI bounds.
3. Isolated CORDIC functional simulation:
   - check representative points in `[-1,1]`,
   - verify handshake (`start/busy/done`) and output correctness.
4. Compare architecture choices:
   - at least one single-iteration/cycle candidate and one multi-iteration/cycle candidate.

### Data that must be collected
- Sweep table (`N_ITER`, `FRAC`, MSE, CI low/high, pass/fail).
- Selected CORDIC parameter point(s) and justification.
- CORDIC isolated latency in cycles.
- Accuracy examples/summary from simulation.
- Timing pass/fail at 50 MHz for selected CORDIC architecture candidate.

### Recommended outputs
- CSV:
  - [/Users/arlo/Projects/DSD_CW/report3/Code/task7a_sweep_results.csv](/Users/arlo/Projects/DSD_CW/report3/Code/task7a_sweep_results.csv)
- Figures in `report3/Images` for sweep and error trends.

---

## Step 2: Three-accelerator integration (intermediate architecture)

### Files to use
- Step-2 CI RTL:
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_fp32_mul.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_fp32_mul.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_fp32_addsub.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_fp32_addsub.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_cos_only.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step2/task7_ci_cos_only.sv)
- Shared core RTL:
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_mul_unit.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_mul_unit.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_add_unit.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_add_unit.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_to_fx.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fp32_to_fx.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fx_to_fp32.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_fx_to_fp32.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_cordic_cos_multi_iter.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/core/task7_cordic_cos_multi_iter.sv)
- Step-2 TB:
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_step2_accels.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_step2_accels.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv)
- Nios software runner (already prepared for Step-2 and Step-3):
  - [/Users/arlo/Projects/DSD_CW/DE1-SoC/system_template_de1_soc/software/hello_world_custom_instr/hello_world.c](/Users/arlo/Projects/DSD_CW/DE1-SoC/system_template_de1_soc/software/hello_world_custom_instr/hello_world.c)

### Experiments to run
1. Integrate 3 separate custom instructions in Platform Designer (mul/addsub/cos).
2. Verify each accelerator call correctness.
3. Measure per-accelerator latency (cycles) in simulation.
4. Run C1/C2/C3 in Nios scheduling mode and record:
   - whole-function time,
   - sum of accelerator times,
   - software/control overhead.
5. Compare measured time split with expected split from block latency.

### Data that must be collected
- Per-accelerator predicted vs measured cycles (mul/addsub/cos).
- Step-2 full-case timing table for C1/C2/C3:
  - total time,
  - accelerator-time sum,
  - overhead.
- Error vs double-precision software reference for C1/C2/C3.
- Step-2 integrated resource and timing report at 50 MHz.

---

## Step 3: Final single custom instruction integration (Task 7c final)

### Files to use
- Final Step-3 CI RTL:
  - [/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step3/task7_ci_f_single.sv](/Users/arlo/Projects/DSD_CW/task7_code/rtl/ci_step3/task7_ci_f_single.sv)
- Supporting RTL (same core files as Step 2).
- Step-3 TB:
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_ci_f.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_ci_f.sv)
  - [/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv](/Users/arlo/Projects/DSD_CW/task7_code/tb/tb_task7_perf.sv)
- Nios software runner:
  - [/Users/arlo/Projects/DSD_CW/DE1-SoC/system_template_de1_soc/software/hello_world_custom_instr/hello_world.c](/Users/arlo/Projects/DSD_CW/DE1-SoC/system_template_de1_soc/software/hello_world_custom_instr/hello_world.c)

### Experiments to run
1. Integrate one single CI for `f(x)` in Platform Designer.
2. Verify FSM-based single-CI behavior in simulation.
3. Measure isolated Step-3 latency (cycles) and compare with Step-2 schedule expectation.
4. Run C1/C2/C3 in Nios and collect full-function timing and error.
5. Compare Step-3 vs Step-2:
   - latency gain,
   - overhead reduction,
   - resource/timing impact.

### Data that must be collected
- Step-3 predicted vs measured cycles.
- C1/C2/C3 total latency and error vs double reference.
- Resource usage and 50 MHz timing for final design.
- Evidence that architecture is a single CI with internal FSM and reused sub-blocks.

---

## 3) Evidence Package You Should Keep

For report writing and marking defense, keep all of these raw artifacts:
- Task7a sweep CSV and generated plots.
- Verilator/ModelSim logs for:
  - CORDIC isolated TB,
  - Step-2 TB,
  - Step-3 TB.
- Nios console logs for C1/C2/C3 (Step-2 and Step-3 timing + error).
- Quartus reports for selected architecture:
  - resource utilization,
  - timing summary at 50 MHz.
- A short parameter-decision note:
  - why chosen `N_ITER`, `FRAC`, `ITER_PER_CYCLE`,
  - why this choice best fits latency/resource/accuracy constraints.

---

## 4) Completion Gate (must all be true)

- 7a:
  - `2^-i` trend + Monte Carlo + investigation on both iterations and wordlength are reported.
- 7b:
  - CORDIC architecture uses multiple iterations per cycle and is verified.
  - timing at 50 MHz is checked and reported.
- 7c:
  - single custom instruction with internal FSM integrates all sub-blocks.
  - C1/C2/C3 latency + error + resource data are reported.
- Final selection:
  - justified by quantitative data, not only qualitative wording.

