# Regression Test Results — Design Phase 3

**Date:** 2026-03-25
**Branch:** main
**Commit:** post DP3 security hardening
**Simulator:** Icarus Verilog (iverilog) — run on WSL2 / Ubuntu

---

## 1. Functional Regression (fft_8point_tb.v)

The original DP1/DP2 functional testbench was run unmodified against the DP3 source
files to confirm that security hardening introduced no functional regressions.

### Compile command
```
iverilog -o fft_test fft_8point.v peripheral.v fft_8point_tb.v
vvp fft_test
```

### Results

| Test | Input Pattern       | Checked? | Result        |
|------|---------------------|----------|---------------|
| 1    | DC (all ones)       | Yes      | **PASS**      |
| 2    | Impulse (x[0]=1)    | Yes      | **PASS**      |
| 3    | Nyquist (alternating ±1) | Yes | **PASS**   |
| 4    | Sine wave (8 samples) | Display-only | N/A (no check_results call in testbench) |
| 5    | Cosine wave (8 samples) | Display-only | N/A (no check_results call in testbench) |

**Functional regression status: 3/3 checked tests PASS — no regressions introduced.**

Tests 4 and 5 produce plausible output (single-bin concentration for sine/cosine inputs)
as confirmed by visual inspection of the terminal printout. The absence of
`check_results` calls for these tests is a pre-existing limitation of the DP1 testbench,
not a DP3 issue.

---

## 2. DP3 Security Testbench (security_tb.v)

A purpose-built security regression testbench was created in Prompt 10 and executed
on the same WSL2 environment.

### Compile command
```
iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v
vvp sec_test
```

### Results summary

```
=== SECURITY REGRESSION RESULTS ===
Passed: 11 / 11
```

All 11 checks across 9 test scenarios passed. See `docs/SECURITY_VALIDATION_RESULTS.md`
for per-check detail.

---

## 3. Synthesis Check (Yosys)

```
yosys synth.ys
```

- **Warnings:** 4 (all pre-existing memory-to-register expansion notices)
- **Errors:** 0
- **Final cell count:** 11,396
- **Flip-flops:** 925 (590 `$_DFFE_PN0P_` + 333 `$_DFF_PN0_` + 2 `$_DFF_PN1_`)
- Both FSMs (`fft_core.state`, `fft_core.bfly_cnt`) extracted and one-hot recoded
- 4 multiplier cells absorbed into 2 MACC cells by ALUMACC pass (correct optimization)

See `docs/PPA_IMPACT_ANALYSIS.md` for full DP1/DP2/DP3 comparison.

---

## 4. Known Limitations

- Tests 4 and 5 (sine, cosine) in `fft_8point_tb.v` lack automated pass/fail checks.
  These are inherited from the DP1 testbench and are out of scope for DP3 changes.
- The security testbench does not test via the full `tt_wrapper.v` SPI path end-to-end
  in hardware; it drives the bus directly. SPI lock behaviour is validated separately via
  the `spi_lock` port signal and the CM-A logic in `tt_wrapper.v`.
- Timing analysis (hold/setup slack) was not available from the Yosys CMOS-gate
  synthesis; a full STA run would require mapping to a real standard-cell library.
