# DP3 Security Report — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 Competition | Team Devrem | Design Phase 3**
*Submitted: 2026-03-25*

---

## Executive Summary

Design Phase 3 (DP3) hardened the 8-point FFT accelerator peripheral against nine classes
of hardware security vulnerability identified through a structured threat-modelling process.
The analysis covered the complete attack surface across three source files
(`src/fft_8point.v`, `src/peripheral.v`, `src/tt_wrapper.v`), produced six threat-analysis
documents, and implemented nine countermeasures (CM-A through CM-I).

All 11 security regression checks pass. All 3 functional regression tests pass.
Synthesis completes with 0 errors. The DP3 design is 6.4% smaller than the DP1 baseline
while providing substantially stronger security guarantees.

---

## 1. Threat Modelling Process

### 1.1 Attack Surface

The attack surface was mapped across four trust-boundary crossings (see `docs/ATTACK_SURFACE_MAP.md`):

| Boundary | Description | Key Risks |
|----------|-------------|-----------|
| **CPU bus** | TinyQV RISC-V core → peripheral register interface | Arbitrary read/write with no MMU protection |
| **SPI test harness** | External SPI master → `spi_reg` → same register bus | Unauthenticated production-silicon access |
| **Physical IO pins** | `ui_in`, `uo_out`, `uio_*` | State observation, reset injection |
| **Clock / Reset** | `clk`, `rst_n` | Computation abort, FSM glitch |

### 1.2 CIA Analysis

Confidentiality, Integrity, and Availability were assessed for input samples, FFT output
results, control registers, and FSM state (see `docs/CIA_ANALYSIS.md`). Key findings:

- **Confidentiality:** Input registers and output registers were freely readable at any time,
  exposing computation data to any bus master. FSM state was continuously visible on
  `uo_out` pins.
- **Integrity:** No mechanism prevented SPI-originated unauthorized writes to CONTROL;
  butterfly addition could silently wrap on large inputs; FSM illegal-state default left
  `busy=1` deadlocked.
- **Availability:** Silent write failures (busy write, unmapped address) provided no error
  feedback; `done_flag` had no standalone clear path.

### 1.3 STRIDE Analysis

18 threats were identified across all six STRIDE categories
(see `docs/STRIDE_ANALYSIS.md`). Highest-severity findings:

| STRIDE | Threat | Summary |
|--------|--------|---------|
| Spoofing | S-02/E-01 | SPI test harness synthesised unconditionally — unauthenticated CONTROL writes |
| Tampering | T-02 | SPI path triggers FFT computation without CPU authorization |
| Information Disclosure | I-01, I-02, I-04 | Stale outputs, readable inputs, MISO serializes all register data |
| Denial of Service | D-01, D-02, D-04 | FSM deadlock, no interrupt-clear, silent write drops |
| Elevation of Privilege | E-01 | SPI bypasses any CPU-level access control |

### 1.4 DREAD Scoring

All 18 threats were scored on Damage, Reproducibility, Exploitability, Affected users,
and Discoverability (1–10 each). Results (see `docs/DREAD_SCORES.md`):

- 8 threats scored **CRITICAL** (avg ≥ 7.0) — all addressed in DP3
- 9 threats scored **HIGH** (avg 5.0–6.9) — all addressed in DP3
- 1 threat scored **MEDIUM** (documented, partially mitigated by platform)

### 1.5 CWE Mapping

Nine hardware-relevant CWEs were evaluated against the pre-DP3 RTL
(see `docs/CWE_FINDINGS.md`):

| CWE | Title | Pre-DP3 | Post-DP3 |
|-----|-------|---------|----------|
| CWE-1234 | Debug modes override locks | **YES** | Mitigated (CM-A) |
| CWE-1262 | Registers writable in wrong operational mode | **YES** | Mitigated (CM-A) |
| CWE-1271 | Uninitialized value on reset | **YES** | Mitigated (CM-G) |
| CWE-1272 | Sensitive data uncleared before State Transition | **YES** | Mitigated (CM-B) |
| CWE-1351 | Improper handling of hardware behavior in exceptional conditions | **YES** | Mitigated (CM-E, CM-F) |
| CWE-1231 | Improper prevention of lock bit modification | **YES** | Mitigated (CM-A) |
| CWE-276 | Incorrect default permissions | **PARTIAL** | Mitigated (CM-H, CM-I) |
| CWE-390 | Detection of error condition without action | **YES** | Mitigated (CM-D) |
| CWE-682 | Incorrect calculation | **PARTIAL** | Mitigated (CM-E) |

---

## 2. Countermeasures Implemented

Nine countermeasures address all CRITICAL and HIGH threats. Implementation spans
three source files.

### CM-A — SPI Lock (One-Time-Writable LOCK Bit)

**File:** `src/peripheral.v`, `src/tt_wrapper.v`
**Threats:** S-02/E-01 (8.6 CRITICAL), T-02 (8.2 CRITICAL), I-04 (7.0 CRITICAL), R-03 (6.4 HIGH)
**CWEs:** CWE-1234, CWE-1262, CWE-1231

`CONTROL[2]` is a set-only bit that engages `spi_lock_reg`. Once set, `spi_lock_reg`
can only be cleared by asserting `rst_n`. The `spi_lock` signal is exported to
`tt_wrapper.v`, where it gates `data_write_n`, `data_read_n`, and `data_out_masked`
to suppress all SPI transactions and zero the MISO output. The CPU bus path is unaffected.

**Location in RTL:** `peripheral.v:87–88, 145, 191` and `tt_wrapper.v:56–123`

### CM-B — Input Register Zeroization on Completion

**File:** `src/peripheral.v`, `src/fft_8point.v`
**Threats:** I-02 (8.0 CRITICAL), I-01 (8.6 CRITICAL — stage residue)
**CWEs:** CWE-1272

On `fft_done`, all 16 input registers (`in_real[0:7]`, `in_imag[0:7]`) are zeroed in
`peripheral.v`. Independently, all 16 stage registers and 6 butterfly pipeline registers
in `fft_8point.v` are zeroed in the DONE state. Non-blocking assignments ensure output
registers receive correct FFT results before stage registers are cleared.

**Location in RTL:** `peripheral.v:157–163`, `fft_8point.v` (DONE state, stage zeroization)

### CM-C — Interrupt-Clear Decoupled from Start

**File:** `src/peripheral.v`
**Threats:** D-02 (8.4 CRITICAL)
**CWEs:** CWE-390

`CONTROL[1]` clears `done_flag` without triggering a new FFT computation. Firmware
can now acknowledge an interrupt without immediately starting the next computation,
eliminating the forced restart race.

**Location in RTL:** `peripheral.v:193–194`

### CM-D — Write-Error Sticky Flag

**File:** `src/peripheral.v`
**Threats:** D-04 (7.6 CRITICAL), E-02 (6.8 HIGH)
**CWEs:** CWE-390

`STATUS[2]` (`write_error`) is set on three conditions: (1) input write while FFT busy,
(2) write to any read-only register (STATUS, OUTPUT_REAL, OUTPUT_IMAG), (3) write to
an unmapped address. `CONTROL[3]` provides a clear path. Simultaneous error detection
overrides the clear (last NBA wins), ensuring errors are never silently dropped.

**Location in RTL:** `peripheral.v:186–233`

### CM-E — Butterfly Overflow Saturation

**File:** `src/fft_8point.v`
**Threats:** CIA-I-04 (6.6 HIGH)
**CWEs:** CWE-1351, CWE-682

All four butterfly add/subtract outputs are computed in 17-bit sign-extended arithmetic.
Overflow is detected by `wide[16] ^ wide[15]`. Saturating clamps apply `16'sh7FFF`
(positive overflow) or `16'sh8000` (negative overflow) rather than silently wrapping.

**Location in RTL:** `fft_8point.v` (butterfly_pipelined Stage 2, `wide_*` wires and `ovf_*` signals)

### CM-F — FSM Hardening / Deadlock Fix

**File:** `src/fft_8point.v`
**Threats:** D-01 (5.8 HIGH)
**CWEs:** CWE-1272, CWE-1351

The main FSM `default` clause now clears `busy`, `done`, and `bfly_cnt` in addition to
returning to IDLE, eliminating the `busy=1`-in-IDLE deadlock. A new `fsm_error` output
port is asserted on any illegal state transition. All three stage-FSM `default` clauses
also set `fsm_error`.

**Location in RTL:** `fft_8point.v` (main FSM default and stage FSM defaults)

### CM-G — Reset Initialization of Stage Registers

**File:** `src/fft_8point.v`
**Threats:** I-01 (stale values from power-on), D-01 (FSM error on reset)
**CWEs:** CWE-1271

All 16 stage registers (`stage_real[0:7]`, `stage_imag[0:7]`) and all 6 butterfly
pipeline registers (`bfly_a_re/im`, `bfly_b_re/im`, `bfly_w_re/im`) are explicitly
initialized to `16'sd0` in the `if (!rst_n)` block. The synthesis effect is visible:
all 328 `$_DFFE_PP_` (no-reset) DFFs from DP1/DP2 became `$_DFFE_PN0P_`
(async-reset-capable) DFFs in DP3.

**Location in RTL:** `fft_8point.v` (async reset block, stage_real/imag and bfly_* initializations)

### CM-H — Input Register Read-Back Removed

**File:** `src/peripheral.v`
**Threats:** I-02 (8.0 CRITICAL)
**CWEs:** CWE-276

The `data_out` mux no longer includes branches for `ADDR_IN_REAL_BASE` or
`ADDR_IN_IMAG_BASE`. Bus reads of input register addresses return `32'h0`. Firmware
must maintain software shadow copies for verification; the peripheral enforces write-only
semantics at the hardware level.

**Location in RTL:** `peripheral.v:243–271` (read logic, input ranges absent from mux)

### CM-I — Output Pins Masked in Production Mode

**File:** `src/peripheral.v`
**Threats:** I-05 (6.8 HIGH)
**CWEs:** CWE-276

`uo_out` is assigned `8'd0` when `spi_lock_reg=1`, preventing continuous FSM state
(`{done_flag, fft_busy}`) observation on physical output pins in production mode.

**Location in RTL:** `peripheral.v:289`

---

## 3. Security Validation Results

Full results: `docs/SECURITY_VALIDATION_RESULTS.md`

| Test Group | Scenarios | Checks | Result |
|------------|-----------|--------|--------|
| Write Protection (CM-D) | SEC_01, 02, 03 | 3 | **3/3 PASS** |
| Computation Integrity (CM-B) | SEC_04 | 1 | **1/1 PASS** |
| Data Leakage Prevention (CM-B, CM-H) | SEC_05, 06 | 2 | **2/2 PASS** |
| FSM Robustness (CM-F, CM-G) | SEC_07, 08 | 2 | **2/2 PASS** |
| Debug Lockout (CM-A, CM-I) | SEC_09a/b/c | 3 | **3/3 PASS** |
| **Overall** | **9 scenarios** | **11** | **11/11 PASS** |

Functional regression (DP1/DP2 testbench, unchanged): **3/3 PASS**.

---

## 4. PPA Impact

Full analysis: `docs/PPA_IMPACT_ANALYSIS.md`

| Metric | DP1 Baseline | DP2 Optimized | DP3 Hardened | DP3 Δ vs DP2 | DP3 Δ vs DP1 |
|--------|-------------|---------------|--------------|-------------|-------------|
| Total cells | 12,172 | 10,731 | **11,396** | +665 (+6.2%) | **−776 (−6.4%)** |
| Flip-flops | 854 | 923 | **925** | +2 (+0.2%) | +71 (+8.3%) |
| Logic gates | 11,318 | 9,808 | **10,471** | +663 (+6.8%) | −847 (−7.5%) |
| Critical path | Long (comb. butterfly) | Improved (pipelined) | Same as DP2 + CM-E clamp (~1–2 gate delay) | Negligible | **Improved** |
| Synthesis errors | 0 | 0 | **0** | — | — |

**Dominant overhead sources (DP2 → DP3):**
1. CM-G: ~200–250 cells — async-reset mux added to all stage-register DFFs
2. CM-E: ~200–250 cells — 17-bit saturation arithmetic in butterfly critical path
3. CM-D: ~30–50 cells — address-range comparators for error detection
4. CM-F: ~20–40 cells — FSM recovery logic + `fsm_error` register
5. CM-H: ~−20–−30 cells — input read-back mux paths removed (negative overhead)

The net 6.4% area reduction vs DP1 demonstrates that DP2 pipeline optimizations
more than offset the DP3 security additions.

---

## 5. Residual Risks

| Threat | Status | Residual Risk | Rationale |
|--------|--------|---------------|-----------|
| S-01 (No MMU) | Platform limitation | MEDIUM | tinyQV has no MMU; all processes share address space. Out of scope for peripheral RTL. |
| R-01 (No audit trail) | Accepted | LOW | Distinguishing CPU vs SPI origin requires system-level logging outside peripheral scope. CM-A disables SPI path in production, eliminating the primary risk. |
| S-03 (Physical rst_n) | Accepted | LOW | Physical pad access requires physical chip access; threat model does not include silicon probing. |
| T-01 (Write race window) | Accepted | LOW | Multi-process scenario requires OS-level mutual exclusion; peripheral cannot enforce this. |
| T-06 (done_flag clear race) | Accepted | LOW | Same reasoning as T-01; requires OS scheduling guarantees. |

---

## 6. Source File Summary

| File | Changes | Countermeasures |
|------|---------|-----------------|
| `src/peripheral.v` | Register map extended (CONTROL[1:3], STATUS[2]); read mux simplified; uo_out gated | CM-A, CM-B, CM-C, CM-D, CM-H, CM-I |
| `src/fft_8point.v` | Reset block extended; DONE state zeroization; saturation logic; FSM default hardening; `fsm_error` port | CM-B, CM-E, CM-F, CM-G |
| `src/tt_wrapper.v` | `spi_lock` wire added; `tqvp_fft8` port connection extended; `always @(*)` block gated; `ui_in_sync` type corrected | CM-A |
| `src/security_tb.v` | New file — 9 test scenarios, 11 checks | Validation |

---

## 7. Document Index

| Document | Purpose |
|----------|---------|
| `docs/ATTACK_SURFACE_MAP.md` | Trust boundaries, entry points, data flows |
| `docs/CIA_ANALYSIS.md` | Confidentiality / Integrity / Availability assessment |
| `docs/STRIDE_ANALYSIS.md` | 18 threats across 6 STRIDE categories |
| `docs/DREAD_SCORES.md` | Quantitative risk ranking of all 18 threats |
| `docs/CWE_FINDINGS.md` | 9 hardware CWE evaluations with RTL evidence |
| `docs/MITIGATION_PLAN.md` | Countermeasure design specifications (CM-A…CM-I) |
| `docs/REGRESSION_RESULTS.md` | Simulation and synthesis results summary |
| `docs/SECURITY_VALIDATION_RESULTS.md` | Per-check security test results |
| `docs/PPA_IMPACT_ANALYSIS.md` | DP1/DP2/DP3 cell count and FF comparison |
| `docs/DP3_SECURITY_REPORT.md` | This document — final DP3 submission |
