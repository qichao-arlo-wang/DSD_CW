# Report 3 Review Notes
Generated: 2026-03-15

## Estimated Score
| Task | Criterion | Tier | Est. Score |
|------|-----------|------|-----------|
| 7a (10%) | MC + both iterations AND wordlength | 100% ✓ | 9-10/10 |
| 7b (10%) | Multiple CORDIC iterations per cycle | 100% ✓ | 9-10/10 |
| 7c (15%) | FSM integrating all subblocks under single CI | Full credit design | 11-14/15 |
| 8 (10%) | Pipelined design (85% tier) + CORDIC redesign (20%) | 85% tier at risk | 7-8/10 |

**Overall (4 tasks, 45% total):** ~36-42/45

---

## Action Items (Priority Order)

### P1 — Task 8: Add simulation correctness evidence ⬜ (deferred — tb exists but not run)
- `tb_task8_pipe_fsum_core.sv` already exists (untracked)
- Run Verilator simulation, capture F(X) output for at least one test vector
- Add a table or waveform figure to Section 5.5 proving RTL-correct output
- **This directly defends the 85% pipelined-design tier from challenge on zero on-board output**

### P2 — Add block diagram(s) ⬜
- Spec explicitly requires: "High level view diagram (block diagram) of your design and clear indication on how you call your IP from NIOS"
- Need at minimum:
  - T7-S3: FSM states + FP-MUL/FP-ADD/CORDIC subblock connections
  - T8: pipeline chain (x² → x³ → FIFO → term → f(x) → accum)
- Also include Nios main loop pseudo-code/C showing CI calling convention

### P3 — Task 7c: Add ideal-latency lower bound ⬜
- Spec marks with "@" (required deliverable)
- Either: measure with combinatorial dummy CI
- Or: compute analytically: C3 ideal = 65281 / 50MHz = 1.306 ms vs measured 220 ms
- Add as a sentence/row comparing ideal vs actual to quantify SW overhead floor

### P4 — Task 7c: Derive 21-cycle FSM latency explicitly ✅
- Spec requires "elaboration on the predicted latency of the block used in isolation"
- Report states "21 cycles" without derivation
- Need 3-line breakdown showing FSM critical path:
  IDLE → x² (3) → x³ (3, CORDIC parallel at 6) → cos done (0 extra) → term (3) → add (3) → OUT (1) → some overlap = 21 cycles
- Confirm CORDIC runs in parallel with x² and x³ multiplications

### P5 — Task 8: CORDIC parameter trade-off discussion ⬜
- Spec says: "the design decision on the CORDIC architecture for Task 7 may not be the best one for Task 8"
- Report does not address why N_iter=18, W=24 were retained
- Add 1-2 sentences: "In a throughput-oriented pipeline, CORDIC depth adds fill latency (18 cycles) but not steady-state throughput limitation — one cos/cycle regardless of depth. Therefore T7 parameters are reused without penalty."

### P6 — Task 8: Pipeline utilisation analysis ✅
- Spec: "Comment on its pipeline's utilisation"
- Add calculation for at least two cases:
  - C3 (N=65281): fill = 18/65281 < 0.03% → ~100% utilisation
  - C2 (N=2041): fill = 18/2041 ≈ 0.9% → ~99% utilisation
  - Note: actual fill is more like ~26 cycles (whole pipeline), not just CORDIC

### P7 — Add "What Would You Do Differently" paragraph ⬜
- Required for Report 3 under general report requirements (point e)
- Add short paragraph in Conclusions section
- Candidates: FIFO depth sizing, accumulator lane count, Nios driver design as MM interface vs CI

### P8 — Add footnote to T8 results table ⬜
- rel.err = 1.0 column has no annotation
- Add dagger footnote: "†F(X)=0 (integration issue, see text)"
- Protects against marker scanning table without reading body text

### P9 — Task 7a: Clarify threshold and "odd values" ⬜
- Add 1 sentence justifying 2.4×10⁻¹¹ threshold derivation
- Clarify "After including odd values" phrasing (sweep says "all integer" but implies odd FRAC excluded initially)

---

## Already Fixed / Strengths
- ✅ T7a: 2D sweep (iterations AND wordlength) present — reaches 100% tier
- ✅ T7b: IPC=3 implemented and measured — reaches 100% tier
- ✅ T7c: FSM single-CI confirmed, 19.91× on C3 with error verified
- ✅ T8 correctness honestly disclosed with root cause identified
- ✅ T8 pipeline architecture clearly described (CORDIC pipeline, round-robin stages, FIFO, interleaved accumulator)
- ✅ T8 CI PUSH protocol matches 85% marking tier criterion explicitly stated
- ✅ Cross-task comparison table with full progression (V1 + V2 rows populated)
- ✅ HW/SW boundary insight in correct location (Section 4.3)
- ✅ Conclusions compressed to 4 sentences, no duplication
- ✅ V1 on-board data: C2/C3/C4 populated from 8_data.md
- ✅ V2 on-board data: C2/C3/C4 from CORRECTED VERSION in 8_data.md
- ✅ V2 resources: ALMs=13,955 / DSP=18 from task8_pipeline.md
- ✅ Two figures added (r3_latency_alms.png, r3_speedup_alms.png) with ALMs + DSP encoding
- ✅ CORDIC redesign discussion added (P5 complete)
