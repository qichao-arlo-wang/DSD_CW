# Task 7b Step-2 Data

## Low-perturbation software timing

The following numbers are the reduced-perturbation Step-2 runs used to compare
different `ITER_PER_CYCLE` settings. `ITER_PER_CYCLE=1` and
`ITER_PER_CYCLE=2` were transcribed from `iter=1.png` and `iter=2.png`.
`ITER_PER_CYCLE=3` is the existing low-perturbation run.

### ITER_PER_CYCLE = 1

```
[Step-2][C2] len=2041 step=0.125 runs=10
[Step-2][C2] F_hw=6.6274329600e+09 F_ref=6.6274362744e+09 abs_err=3.314e+03 rel_err=5.001e-07
[Step-2][C2] total=263 ticks avg=26 ticks/run

[Step-2][C3] len=65281 step=0.00390625 runs=10
[Step-2][C3] F_hw=2.1193241395e+11 F_ref=2.1193741026e+11 abs_err=4.996e+06 rel_err=2.357e-05
[Step-2][C3] total=8401 ticks avg=840 ticks/run

[Step-2][C4] len=2323 step=-1 runs=10
[Step-2][C4] F_hw=7.6686100480e+09 F_ref=7.6686084108e+09 abs_err=1.637e+03 rel_err=2.135e-07
[Step-2][C4] total=299 ticks avg=29 ticks/run
```

### ITER_PER_CYCLE = 2

```
[Step-2][C2] len=2041 step=0.125 runs=10
[Step-2][C2] F_hw=6.6274329600e+09 F_ref=6.6274362744e+09 abs_err=3.314e+03 rel_err=5.001e-07
[Step-2][C2] total=259 ticks avg=25 ticks/run

[Step-2][C3] len=65281 step=0.00390625 runs=10
[Step-2][C3] F_hw=2.1193241395e+11 F_ref=2.1193741026e+11 abs_err=4.996e+06 rel_err=2.357e-05
[Step-2][C3] total=8282 ticks avg=828 ticks/run

[Step-2][C4] len=2323 step=-1 runs=10
[Step-2][C4] F_hw=7.6686100480e+09 F_ref=7.6686084108e+09 abs_err=1.637e+03 rel_err=2.135e-07
[Step-2][C4] total=295 ticks avg=29 ticks/run
```

### ITER_PER_CYCLE = 3

```
[Step-2][C2] len=2041 step=0.125 runs=10
[Step-2][C2] F_hw=6.6274329600e+09 F_ref=6.6274362744e+09 abs_err=3.314e+03 rel_err=5.001e-07
[Step-2][C2] total=258 ticks avg=25 ticks/run

[Step-2][C3] len=65281 step=0.00390625 runs=10
[Step-2][C3] F_hw=2.1193241395e+11 F_ref=2.1193741026e+11 abs_err=4.996e+06 rel_err=2.357e-05
[Step-2][C3] total=8243 ticks avg=824 ticks/run

[Step-2][C4] len=2323 step=-1 runs=10
[Step-2][C4] F_hw=7.6686100480e+09 F_ref=7.6686084108e+09 abs_err=1.637e+03 rel_err=2.135e-07
[Step-2][C4] total=293 ticks avg=29 ticks/run
```

## Resource + timing snapshot for ITER_PER_CYCLE = 3

Generated: 2026-03-12 14:47:09 +00:00
Source fit summary: `DE1-SoC/system_template_de1_soc/hello_world.fit.summary`
Source sta summary: `DE1-SoC/system_template_de1_soc/hello_world.sta.summary`
Source sta report: `DE1-SoC/system_template_de1_soc/hello_world.sta.rpt`

### Build info

- Revision: `hello_world`
- Device: `5CSEMA5F31C6`
- Quartus: `23.1std.0 Build 991 11/28/2023 SC Lite Edition`
- Fitter status: `Successful - Thu Mar 12 14:32:15 2026`

### Resource utilization

| Metric | Value |
|---|---|
| Logic utilization (ALMs) | 3,767 / 32,070 ( 12 % ) |
| Total registers | 4207 |
| Total block memory bits | 3,159,680 / 4,065,280 ( 78 % ) |
| Total RAM Blocks | 397 / 397 ( 100 % ) |
| Total DSP Blocks | 1 / 87 ( 1 % ) |

### Worst-case timing

| Check | Type | Slack | TNS |
|---|---|---:|---:|
| Setup | Slow 1100mV 85C Model Setup `sopc_clk` | 3.106 | 0.000 |
| Hold | Fast 1100mV 0C Model Hold `sopc_clk` | 0.086 | 0.000 |

### Setup/hold per corner

| Type | Slack | TNS |
|---|---:|---:|
| Slow 1100mV 85C Model Setup `sopc_clk` | 3.106 | 0.000 |
| Slow 1100mV 85C Model Setup `altera_reserved_tck` | 23.300 | 0.000 |
| Slow 1100mV 85C Model Hold `sopc_clk` | 0.269 | 0.000 |
| Slow 1100mV 85C Model Hold `altera_reserved_tck` | 0.432 | 0.000 |
| Slow 1100mV 0C Model Setup `sopc_clk` | 3.106 | 0.000 |
| Slow 1100mV 0C Model Setup `altera_reserved_tck` | 23.440 | 0.000 |
| Slow 1100mV 0C Model Hold `sopc_clk` | 0.158 | 0.000 |
| Slow 1100mV 0C Model Hold `altera_reserved_tck` | 0.405 | 0.000 |
| Fast 1100mV 85C Model Setup `sopc_clk` | 9.697 | 0.000 |
| Fast 1100mV 85C Model Setup `altera_reserved_tck` | 25.357 | 0.000 |
| Fast 1100mV 85C Model Hold `sopc_clk` | 0.154 | 0.000 |
| Fast 1100mV 85C Model Hold `altera_reserved_tck` | 0.206 | 0.000 |
| Fast 1100mV 0C Model Setup `sopc_clk` | 10.678 | 0.000 |
| Fast 1100mV 0C Model Setup `altera_reserved_tck` | 25.535 | 0.000 |
| Fast 1100mV 0C Model Hold `sopc_clk` | 0.086 | 0.000 |
| Fast 1100mV 0C Model Hold `altera_reserved_tck` | 0.168 | 0.000 |

### Fmax summary

| Clock | Fmax | Restricted Fmax |
|---|---:|---:|
| altera_reserved_tck | 18.73 MHz | 18.73 MHz |
| sopc_clk | 59.19 MHz | 59.19 MHz |
