# Resource + Timing Snapshot (Current Version)

Generated: 2026-03-13 03:32:35 +00:00
Sources: DE1-SoC\system_template_de1_soc\hello_world.fit.summary, DE1-SoC\system_template_de1_soc\hello_world.sta.summary, DE1-SoC\system_template_de1_soc\hello_world.sta.rpt, DE1-SoC\system_template_de1_soc\software\hello_world_custom_instr_bsp\system.h

## CI Macro (Current BSP)
- #define ALT_CI_CUSTOM_F_ACCUM_0(A,B) __builtin_custom_inii(ALT_CI_CUSTOM_F_ACCUM_0_N,(A),(B))
- #define ALT_CI_CUSTOM_F_ACCUM_0_N 0x0

## Build Info
- Revision: `hello_world`
- Device: `5CSEMA5F31C6`
- Quartus: `23.1std.0 Build 991 11/28/2023 SC Lite Edition`
- Fitter Status: `Successful - Fri Mar 13 03:07:45 2026`

## Resource Utilization
| Metric | Value |
|---|---|
| Logic utilization (ALMs) | 3,793 / 32,070 ( 12 % ) |
| Total registers | 4214 |
| Total block memory bits | 3,159,680 / 4,065,280 ( 78 % ) |
| Total RAM Blocks | 397 / 397 ( 100 % ) |
| Total DSP Blocks | 1 / 87 ( 1 % ) |

## Worst-Case Timing
| Check | Type | Slack | TNS |
|---|---|---:|---:|
| Setup | Slow 1100mV 85C Model Setup 'sopc_clk' | 3.205 | 0.000 |
| Hold | Fast 1100mV 0C Model Hold 'sopc_clk' | 0.114 | 0.000 |

## Fmax Summary (per clock)
| Clock | Fmax | Restricted Fmax |
|---|---:|---:|
| altera_reserved_tck | 18.73 MHz | 18.73 MHz |
| sopc_clk | 59.54 MHz | 59.54 MHz |
