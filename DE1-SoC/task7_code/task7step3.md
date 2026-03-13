# Resource + Timing Snapshot (Current System)

Generated: 2026-03-12 17:22:44 +00:00
Sources: DE1-SoC\system_template_de1_soc\hello_world.fit.summary, DE1-SoC\system_template_de1_soc\hello_world.sta.summary, DE1-SoC\system_template_de1_soc\hello_world.sta.rpt

## Build Info
- Revision: `hello_world`
- Device: `5CSEMA5F31C6`
- Quartus: `23.1std.0 Build 991 11/28/2023 SC Lite Edition`
- Fitter Status: `Successful - Thu Mar 12 17:06:41 2026`

## Resource Utilization
| Metric | Value |
|---|---|
| Logic utilization (ALMs) | 3,795 / 32,070 ( 12 % ) |
| Total registers | 4203 |
| Total block memory bits | 3,159,680 / 4,065,280 ( 78 % ) |
| Total RAM Blocks | 397 / 397 ( 100 % ) |
| Total DSP Blocks | 1 / 87 ( 1 % ) |

## Worst-Case Timing
| Check | Type | Slack | TNS |
|---|---|---:|---:|
| Setup | Slow 1100mV 85C Model Setup 'sopc_clk' | 2.907 | 0.000 |
| Hold | Fast 1100mV 0C Model Hold 'sopc_clk' | 0.085 | 0.000 |

## Fmax Summary (per clock)
| Clock | Fmax | Restricted Fmax |
|---|---:|---:|
| altera_reserved_tck | 18.73 MHz | 18.73 MHz |
| sopc_clk | 58.5 MHz | 58.5 MHz |
