# inter_per_cycle = 3, 7b Resource + Timing Snapshot

Generated: 2026-03-12 14:47:09 +00:00
Source fit summary: DE1-SoC/system_template_de1_soc/hello_world.fit.summary
Source sta summary: DE1-SoC/system_template_de1_soc/hello_world.sta.summary
Source sta report: DE1-SoC/system_template_de1_soc/hello_world.sta.rpt

## Build Info
- Revision: `hello_world`
- Device: `5CSEMA5F31C6`
- Quartus: `23.1std.0 Build 991 11/28/2023 SC Lite Edition`
- Fitter Status: `Successful - Thu Mar 12 14:32:15 2026`

## Resource Utilization
| Metric | Value |
|---|---|
| Logic utilization (ALMs) | 3,767 / 32,070 ( 12 % ) |
| Total registers | 4207 |
| Total block memory bits | 3,159,680 / 4,065,280 ( 78 % ) |
| Total RAM Blocks | 397 / 397 ( 100 % ) |
| Total DSP Blocks | 1 / 87 ( 1 % ) |

## Worst-Case Timing (from `hello_world.sta.summary`)
| Check | Type | Slack | TNS |
|---|---|---:|---:|
| Setup | Slow 1100mV 85C Model Setup 'sopc_clk' | 3.106 | 0.000 |
| Hold | Fast 1100mV 0C Model Hold 'sopc_clk' | 0.086 | 0.000 |

## Setup/Hold Per Corner
| Type | Slack | TNS |
|---|---:|---:|
| Slow 1100mV 85C Model Setup 'sopc_clk' | 3.106 | 0.000 |
| Slow 1100mV 85C Model Setup 'altera_reserved_tck' | 23.300 | 0.000 |
| Slow 1100mV 85C Model Hold 'sopc_clk' | 0.269 | 0.000 |
| Slow 1100mV 85C Model Hold 'altera_reserved_tck' | 0.432 | 0.000 |
| Slow 1100mV 0C Model Setup 'sopc_clk' | 3.106 | 0.000 |
| Slow 1100mV 0C Model Setup 'altera_reserved_tck' | 23.440 | 0.000 |
| Slow 1100mV 0C Model Hold 'sopc_clk' | 0.158 | 0.000 |
| Slow 1100mV 0C Model Hold 'altera_reserved_tck' | 0.405 | 0.000 |
| Fast 1100mV 85C Model Setup 'sopc_clk' | 9.697 | 0.000 |
| Fast 1100mV 85C Model Setup 'altera_reserved_tck' | 25.357 | 0.000 |
| Fast 1100mV 85C Model Hold 'sopc_clk' | 0.154 | 0.000 |
| Fast 1100mV 85C Model Hold 'altera_reserved_tck' | 0.206 | 0.000 |
| Fast 1100mV 0C Model Setup 'sopc_clk' | 10.678 | 0.000 |
| Fast 1100mV 0C Model Setup 'altera_reserved_tck' | 25.535 | 0.000 |
| Fast 1100mV 0C Model Hold 'sopc_clk' | 0.086 | 0.000 |
| Fast 1100mV 0C Model Hold 'altera_reserved_tck' | 0.168 | 0.000 |

## Fmax Summary (first occurrence per clock from `hello_world.sta.rpt`)
| Clock | Fmax | Restricted Fmax |
|---|---:|---:|
| altera_reserved_tck | 18.73 MHz | 18.73 MHz |
| sopc_clk | 59.19 MHz | 59.19 MHz |
