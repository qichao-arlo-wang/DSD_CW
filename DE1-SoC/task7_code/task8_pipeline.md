# Resource Utilization Summary

Source reports:
- `hello_world.fit.summary`
- `hello_world.fit.rpt`
- `hello_world.flow.rpt`

Build info:
- Status: Successful
- Build time: 2026-03-16 00:02:44
- Quartus: 23.1std.0 Build 991 SC Lite Edition
- Family: Cyclone V
- Device: 5CSEMA5F31C6
- Revision: `hello_world`

## Top-level Usage

| Resource | Usage | Device Total | Utilization |
| --- | ---: | ---: | ---: |
| Logic utilization (ALMs) | 13,955 | 32,070 | 44% |
| Total registers | 29,723 | 64,140 | 46.3% |
| Total pins | 47 | 457 | 10% |
| Block memory bits | 3,159,680 | 4,065,280 | 78% |
| RAM blocks (M10K) | 397 | 397 | 100% |
| DSP blocks | 18 | 87 | 21% |
| PLLs | 0 | 6 | 0% |
| DLLs | 0 | 4 | 0% |

## Fitter Detail

| Metric | Value |
| --- | ---: |
| ALMs used in final placement | 18,830 |
| ALMs used for LUT logic and registers | 6,001 |
| ALMs used for LUT logic | 5,109 |
| ALMs used for registers | 7,570 |
| ALMs used for memory | 150 |
| Recoverable by dense packing | 5,039 |
| Unavailable ALMs | 164 |
| Total LABs used | 2,510 / 3,207 (78%) |
| Combinational ALUT usage | 18,162 |
| Dedicated logic registers | 29,723 |
| Block memory implementation bits | 4,065,280 / 4,065,280 (100%) |

## Hierarchy Snapshot

| Hierarchy | ALMs needed | Combinational ALUTs | Registers | Block Memory Bits | M10Ks | DSPs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `hello_world` | 13,954.3 | 18,162 | 29,723 | 3,159,680 | 397 | 18 |
| `first_nios2_system:inst` | 13,813.0 | 17,939 | 29,556 | 3,159,680 | 397 | 18 |

## Notes

- The design is memory-limited in this build: `RAM blocks = 397 / 397 (100%)`.
- Logic usage is moderate at `44% ALMs`.
- DSP usage is relatively low at `21%`.
