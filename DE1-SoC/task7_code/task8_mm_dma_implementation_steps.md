# Task 8 MM + DMA Implementation Steps

This guide maps the provided RTL/software files into Quartus + Platform Designer and explains exactly what to run and what data to collect.

## 1. Files Added

- RTL accelerator (MM control + ST stream sink):  
  `DE1-SoC/task7_code/rtl/task8_mm/task8_mm_fsum_accel.sv`
- Task 8 software-only C entry (MM + DMA flow):  
  `DE1-SoC/task7_code/task8_mm_dma_main.c`
- RTL functional testbench (Verilator):  
  `DE1-SoC/task7_code/tb/tb_task8_mm_fsum_accel.sv`

## 2. Accelerator Interface Definition

The accelerator uses:

- Avalon-MM CSR slave registers:
  - `0x00 CTRL`:
    - bit0 `START`
    - bit1 `CLEAR`
    - bit2 `IRQ_EN`
  - `0x04 STATUS`:
    - bit0 `BUSY`
    - bit1 `DONE`
    - bit2 `ERR`
  - `0x08 LEN` (number of fp32 samples)
  - `0x0C RESULT` (fp32 sum)
  - `0x10 CYCLES`
  - `0x14 ACCEPTED`
  - `0x18 PROCESSED`
- Avalon-ST sink:
  - `in_valid`, `in_ready`, `in_data[31:0]`
- Optional IRQ output `irq`.

## 3. Platform Designer Integration

1. Create/import a custom component for `task8_mm_fsum_accel`.
2. In component files, add:
   - `task8_mm_fsum_accel.sv`
   - `task7_ci_f_single.sv`
   - `task7_cordic_cos_multi_iter.sv`
   - `task7_fp32_to_fx.sv`
   - `task7_fx_to_fp32.sv`
   - `task7_fp_add_ip_unit.sv`
   - `task7_fp_mul_ip_unit.sv`
   - `custom_fp_add.qip`
   - `custom_fp_mul.qip`
3. Expose one Avalon-MM slave (`CSR`) and one Avalon-ST sink (`in`).
4. Add `mSGDMA MM-to-ST` in the same system.
5. Connect:
   - `mSGDMA ST source` -> `task8_mm_fsum_accel in`
   - Nios data master -> accelerator CSR slave
   - Nios data master -> mSGDMA CSR + descriptor slave
6. Keep all modules on same clock/reset domain first (50 MHz) for bring-up.
7. Generate HDL and recompile Quartus.

## 4. BSP and Software Setup

1. Regenerate BSP after Qsys changes.
2. Add `task8_mm_dma_main.c` into your Nios application project.
3. Build once, then open generated `system.h`.
4. Check base-address macro names and ensure they match the C file detection logic:
   - accelerator base
   - mSGDMA CSR base
   - mSGDMA descriptor base
5. If your generated names differ, add one more `#elif defined(...)` mapping in the C file.

## 5. Runtime Sequence (Expected)

For each test case:

1. Build vector `X`.
2. Compute software double reference.
3. Program accelerator:
   - write `LEN`
   - write `CTRL=CLEAR`
   - write `CTRL=START`
4. Submit mSGDMA descriptor for `X` (`len * 4` bytes).
5. Wait DMA idle.
6. Poll accelerator `STATUS.DONE`.
7. Read `RESULT` and compare with reference.
8. Record timing ticks for report.

## 6. Experiments to Run

Run at least C1/C2/C3/C4 with `NUM_RUNS=10`:

- C1: `X=0:5:255`
- C2: `X=0:1/8:255`
- C3: `X=0:1/256:255`
- C4: random fixed-seed vector

For each case, collect:

- `F_hw`, `F_ref`, `abs_err`, `rel_err`
- total ticks and average ms/run
- accelerator `CYCLES`, `ACCEPTED`, `PROCESSED`
- Quartus post-fit resources and timing (ALMs, fmax, slack)

## 7. Verification Before Board Run

Use Verilator quick regression:

```bash
cd DE1-SoC/task7_code
verilator -Wall -Wno-fatal --binary --timing \
  --top-module tb_task8_mm_fsum_accel -Mdir obj_dir_task8_mm \
  tb/tb_task8_mm_fsum_accel.sv \
  rtl/task8_mm/task8_mm_fsum_accel.sv \
  rtl/ci_step3/task7_ci_f_single.sv \
  rtl/core/task7_cordic_cos_multi_iter.sv \
  rtl/core/task7_fp32_to_fx.sv \
  rtl/core/task7_fx_to_fp32.sv \
  rtl/core/task7_fp_add_ip_unit.sv \
  rtl/core/task7_fp_mul_ip_unit.sv \
  rtl/sim_models/custom_fp_add.sv \
  rtl/sim_models/custom_fp_mul.sv \
  -Irtl/sim_models
./obj_dir_task8_mm/Vtb_task8_mm_fsum_accel
```

Expected tail line:

`tb_task8_mm_fsum_accel PASSED`

## 8. Common Failure Checks

- `F_hw` always zero:
  - accelerator not started
  - DMA descriptor not launched
  - wrong component connected
- Timeout waiting `DONE`:
  - `LEN` mismatch vs DMA bytes
  - ST handshake not connected
  - clock/reset wiring issue
- Huge error:
  - wrong fp32 payload formatting
  - stale cache lines (flush D-cache before DMA read)
  - wrong base-address macros in software
