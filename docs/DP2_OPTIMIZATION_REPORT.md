# AI-HDL 2026 - Design Phase 2 Optimization Report

**Team:** Devrem  
**Project:** 8-Point FFT Accelerator Peripheral  
**Competition Phase:** DP2 (Design Phase 2 — PPA Optimization)  
**Submission Date:** February 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Baseline PPA Analysis (DP1)](#baseline-ppa-analysis-dp1)
3. [Optimization Plan](#optimization-plan)
4. [Changes Made](#changes-made)
5. [Final PPA Results (DP2)](#final-ppa-results-dp2)
6. [Before-and-After Comparison](#before-and-after-comparison)
7. [Trade-off Analysis](#trade-off-analysis)
8. [Regression Test Results](#regression-test-results)

---

## Executive Summary

Design Phase 2 optimizes the functional DP1 FFT accelerator for **Power, Performance, and Area (PPA)**. Five categories of optimization were applied:

| Optimization | Target | Technique |
|-------------|--------|-----------|
| **Butterfly Pipelining** | Performance (Fmax) | 2-stage pipeline registers in multiply path |
| **Clock Gating** | Power | Gate stage/output/input registers when idle |
| **Operand Isolation** | Power | Zero butterfly inputs when not computing |
| **Trivial Twiddle Bypass** | Area + Power | Skip multiplier for W₈⁰ = 1+j0 |
| **Synthesis Enhancement** | Area | Flatten + resource sharing passes |

---

## Baseline PPA Analysis (DP1)

Baseline numbers from DP1 Yosys synthesis (`synth.ys` with `abc -g AND,OR,XOR,NAND,NOR`):

### Cell Count

| Module | Cells | Percentage |
|--------|-------|------------|
| tqvp_fft8 (top) | 12,172 | 100% |
| └─ fft_8point | 2,946 | 24% |
| └── butterfly | 7,782 | 64% |
| └─ peripheral logic | 1,444 | 12% |

### Cell Type Distribution

| Cell Type | Count |
|-----------|-------|
| $_AND_ | 2,431 |
| $_DFFE_PN0P_ | 513 |
| $_DFFE_PP_ | 328 |
| $_DFF_PN0_ | 11 |
| $_DFF_PN1_ | 2 |
| $_NAND_ | 5,709 |
| $_NOR_ | 37 |
| $_NOT_ | 112 |
| $_OR_ | 468 |
| $_XOR_ | 2,561 |
| **Total** | **12,172** |

### Performance

| Metric | Value |
|--------|-------|
| Target Clock | 64 MHz (TinyQV default) |
| FFT Latency | ~15 cycles |
| Time per FFT | ~234 ns |
| Critical Path | Through butterfly multiply (combinational) |

### Key Observations

1. **Butterfly dominates**: 64% of total area is in the single combinational butterfly unit
2. **Critical path**: 16×16 multiply → subtract → add chain is the longest path
3. **No power features**: All registers clock every cycle regardless of activity
4. **Wasted computation**: W₈⁰ butterflies (8 out of 12) still go through full multiply

---

## Optimization Plan

### Performance: Butterfly Pipelining

**Problem:** The combinational butterfly has a long critical path through:

```
b_re × w_re → subtract (b_im × w_im) → add with a_re
```

This 4-multiplier + 2-adder chain limits Fmax.

**Solution:** Split butterfly into 2 pipeline stages:

- **Stage 1** (registered): Compute all 4 partial products, mux with trivial bypass, register results
- **Stage 2** (combinational): Final add/subtract with delayed `a` operand

**Expected impact:** ~30-40% improvement in maximum achievable Fmax.

### Power: Clock Gating

**Problem:** All 16 stage registers (256 bits) and 16 output registers (256 bits) toggle on every clock edge, even in IDLE state.

**Solution:**

- Gate `stage_real/imag` registers with `state != IDLE` enable
- Gate output registers with `state == DONE` enable  
- Gate peripheral input registers with `~fft_busy` enable

### Power: Operand Isolation

**Problem:** When the FFT is idle, the butterfly inputs float with previous values. The 4 multipliers (7,782 cells) continue switching on glitches.

**Solution:** Mux butterfly inputs to zero when `state` is not in STAGE1/STAGE2/STAGE3. This eliminates switching activity in the entire multiply tree when idle.

### Area + Power: Trivial Twiddle Bypass

**Problem:** 8 out of 12 butterflies use W₈⁰ = 1+j0, meaning `b × W₈⁰ = b`. The full 4-multiplier complex multiply is wasted.

**Solution:** Add a `trivial_w` flag. When asserted, the butterfly pipeline bypasses multiplication and passes `b` through directly. Saves power by eliminating unnecessary switching in ~67% of butterfly operations.

### Area: Enhanced Synthesis

**Solution:** Added `-flatten` to `synth` command for cross-module optimization, plus `share` pass for arithmetic resource sharing.

---

## Changes Made

### Modified Files

| File | Changes |
|------|---------|
| `src/fft_8point.v` | Pipelined butterfly, clock gating enables, operand isolation, W0 bypass, FSM with pipeline wait states |
| `src/peripheral.v` | Clock gating on input registers during FFT computation |
| `src/synth.ys` | Flatten + share + opt-full passes |
| `src/tt_wrapper.v` | Bug fix: `tqvp_example` → `tqvp_fft8` |
| `src/fft_8point_tb.v` | Updated timeout for pipeline latency |

### Architectural Changes

**Before (DP1):**

```
IDLE → STAGE1 (5 cycles) → STAGE2 (5 cycles) → STAGE3 (5 cycles) → DONE → IDLE
= ~15 cycles, combinational butterfly
```

**After (DP2):**

```
IDLE → STAGE1 (9 cycles) → STAGE2 (9 cycles) → STAGE3 (9 cycles) → DONE → IDLE
= ~28 cycles, pipelined butterfly (higher Fmax)
```

Each butterfly now takes 3 sub-cycles: SETUP → WAIT (pipeline) → STORE.

---

## Final PPA Results (DP2)

> **Note:** Run `yosys synth.ys` on the synthesis machine to populate these numbers.

| Metric | DP1 Baseline | DP2 Optimized | Change |
|--------|-------------|---------------|--------|
| Total Cells | 12,172 | _(run synthesis)_ | |
| Flip-Flops | 854 | _(run synthesis)_ | |
| FFT Latency | ~15 cycles | ~28 cycles | +87% |
| Max Fmax | Limited by multiply chain | Pipeline-registered | ↑ improved |
| Idle Power | Unoptimized | Clock gated + isolated | ↓ reduced |

---

## Before-and-After Comparison

### Performance

| Aspect | DP1 | DP2 | Rationale |
|--------|-----|-----|-----------|
| Critical path | 4×mult + 2×add/sub (combinational) | 2×mult + mux (registered) | Pipeline cuts path in half |
| Latency (cycles) | ~15 | ~28 | Extra cycles for pipeline waits |
| Throughput at Fmax | Lower Fmax × 1/15 | Higher Fmax × 1/28 | Net positive if Fmax gain > 1.87× |

### Power

| Aspect | DP1 | DP2 | Rationale |
|--------|-----|-----|-----------|
| Idle switching | Full butterfly toggles | Zero (operand isolation) | Eliminates ~7,782 cells of switching |
| Stage register clocking | Every cycle | Gated when IDLE | Saves 256 bits of clock power |
| Output register clocking | Every cycle | Only in DONE state | Saves 256 bits of clock power |
| W₈⁰ butterflies | Full multiply | Bypass (identity) | Saves ~67% of multiply switching |

### Area

| Aspect | DP1 | DP2 | Rationale |
|--------|-----|-----|-----------|
| Butterfly | Combinational only | + pipeline FFs (64 bits) | Small area increase for timing |
| Synthesis | Basic synth | Flatten + share | Cross-module + resource sharing |
| bfly_cnt width | 3-bit | 4-bit | Accommodates pipeline states |

---

## Trade-off Analysis

### Latency vs. Frequency (Primary Trade-off)

We chose to **increase latency from ~15 to ~28 cycles** in exchange for improved Fmax:

- The butterfly critical path is cut roughly in half
- At the same 64 MHz target clock, latency goes from 234ns to 437ns
- However, if the design can now run at a higher frequency (e.g., 100+ MHz), actual wall-clock time decreases
- For applications requiring low-latency single FFTs, this is a trade-off; for throughput-oriented applications, higher Fmax wins

**Justification:** In real-world embedded systems, the FFT peripheral is typically I/O-bound (CPU writes 16 registers, reads 16 registers), so the extra cycles in computation are dominated by bus transfer time.

### Area Increase from Pipeline Registers

Adding pipeline registers in the butterfly unit adds ~64 bits of flip-flops (4 pipeline registers × 16 bits). This is a modest ~7.5% increase in FF count, well justified by the timing improvement.

### Power Savings vs. Mux Overhead

Operand isolation and clock gating add multiplexer logic, slightly increasing area. However:

- The 7,782-cell butterfly operates for only ~28 out of N total cycles
- During all idle time, switching activity drops to zero
- Net power savings are significant for duty cycles typical in embedded workloads

---

## Regression Test Results

> **Run on synthesis machine and paste results here:**

```
Test 1: DC Signal (all ones)         → [PASS/FAIL]
Test 2: Impulse Signal               → [PASS/FAIL]
Test 3: Alternating Signal (Nyquist) → [PASS/FAIL]
Test 4: Single Cycle Sine Wave       → [PASS/FAIL]
Test 5: Two-Cycle Cosine Wave        → [PASS/FAIL]
```

**Commands to run:**

```bash
cd src/
iverilog -o fft_test fft_8point.v fft_8point_tb.v
vvp fft_test
```

---

**Prepared by:** Team Devrem  
**AI-HDL 2026 Competition**  
**Design Phase 2 Submission**
