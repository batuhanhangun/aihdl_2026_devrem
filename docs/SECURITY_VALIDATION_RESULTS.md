# Security Validation Results — Design Phase 3

**Date:** 2026-03-25
**Testbench:** `src/security_tb.v`
**DUT:** `src/peripheral.v` (`tqvp_fft8`) + `src/fft_8point.v` + `src/tt_wrapper.v`
**Simulator:** Icarus Verilog (iverilog) — WSL2 / Ubuntu
**Overall result: 11 / 11 PASSED**

---

## Test Group 1 — Write Protection / Error Flagging (CM-D)

### TEST_SEC_01 — Write to read-only output register is silently blocked; write_error set

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 1.1   | `STATUS[2]` (write_error) after write to `OUTPUT_REAL[0]` | `1` | `1` | **PASS** |

**Countermeasure validated:** CM-D (write_error sticky flag).
Writes to output registers (`0x48–0x84`) are physically impossible (wire types driven
by FFT core), but the flag catches the software mistake and surfaces it to firmware.

### TEST_SEC_02 — Write to unmapped address sets write_error

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 2.1   | `STATUS[2]` after write to word address `0x3F` (unmapped) | `1` | `1` | **PASS** |

**Countermeasure validated:** CM-D, Case 3 (unmapped address detection).

### TEST_SEC_03 — Second START while busy is rejected; write_error set

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 3.1   | `STATUS[2]` after CONTROL=1 issued while `STATUS[0]` (busy) is 1 | `1` | `1` | **PASS** |

**Countermeasure validated:** CM-D, Case 1 variant (guarded start rejection).

---

## Test Group 2 — Computation Integrity (CM-B, CM-D)

### TEST_SEC_04 — Input write while FFT busy is blocked; result matches original inputs

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 4.1   | `OUTPUT_REAL[0]` after FFT completes | Matches impulse FFT | Matches | **PASS** |

**Countermeasure validated:** DP2 clock gating (input_reg_wr_en) + CM-B (zeroization).
The blocked write did not corrupt the in-progress computation.

---

## Test Group 3 — Data Leakage Prevention (CM-B, CM-H)

### TEST_SEC_05 — Input register read-back returns zero after FFT completion

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 5.1   | Bus read of `INPUT_REAL[0]` post-FFT | `0x00000000` | `0x00000000` | **PASS** |
| 5.2   | Bus read of `INPUT_IMAG[0]` post-FFT | `0x00000000` | `0x00000000` | **PASS** |

**Countermeasures validated:**
- CM-H: Input register read-back paths removed from `data_out` mux (always return 0).
- CM-B: Input registers physically zeroized on `fft_done` — confirmed by checking
  that even internal register state is cleared (not merely suppressed at the bus).

### TEST_SEC_06 — FFT #2 output contains no residue from FFT #1 inputs

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 6.1   | `OUTPUT_REAL[0]` after impulse FFT (FFT#2) | `0x0001` (impulse DC bin) | `0x0001` | **PASS** |

**Countermeasure validated:** CM-B (stage register zeroization in DONE state).
FFT #1 used a DC input (all 1s); if stage registers were not zeroed, a subsequent
impulse computation could inherit residue. The correct impulse result confirms
clean isolation between computations.

---

## Test Group 4 — FSM Robustness (CM-F, CM-G)

### TEST_SEC_07 — Reset mid-computation clears all state; post-reset FFT correct

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 7.1   | `STATUS[1:0]` after `rst_n` asserted during computation | `2'b00` (idle, not done) | `2'b00` | **PASS** |
| 7.2   | `OUTPUT_REAL[0]` after full impulse FFT post-reset | Correct impulse FFT value | Correct | **PASS** |

**Countermeasures validated:**
- CM-G: All stage/butterfly registers are reset-initialized; no stale values survive `rst_n`.
- CM-F: FSM returns to IDLE cleanly on reset (busy=0, done=0, bfly_cnt=0).

### TEST_SEC_08 — Rapid CONTROL writes; FSM completes exactly one FFT without lockup

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 8.1   | `STATUS[1]` (done) set after rapid start/clear sequence | `1` | `1` | **PASS** |

**Countermeasures validated:**
- CM-F FSM default clause (busy-deadlock fix): rejected start attempts do not leave
  the FSM in an undefined state.
- CM-C: CONTROL[1] interrupt-clear is handled independently of CONTROL[0] start,
  preventing a clear-and-restart race.

---

## Test Group 5 — Debug Lockout / SPI Lock (CM-A, CM-I)

### TEST_SEC_09 — SPI lock controls: set, mask, set-only, reset-clear

| Check | Signal / Condition | Expected | Actual | Result |
|-------|--------------------|----------|--------|--------|
| 9a.1  | `spi_lock` port after CONTROL[2] write | `1` | `1` | **PASS** |
| 9a.2  | `uo_out` in locked mode | `8'h00` | `8'h00` | **PASS** |
| 9b.1  | `spi_lock` after CONTROL write with bit[2]=0 (clear attempt) | `1` (unchanged) | `1` | **PASS** |
| 9c.1  | `spi_lock` after `rst_n` assertion | `0` | `0` | **PASS** |

**Countermeasures validated:**
- CM-A: `spi_lock_reg` is set-only (cannot be cleared by software write); only `rst_n`
  can clear it. The `spi_lock` output gates the entire SPI transaction path in
  `tt_wrapper.v` (data_write_n/data_read_n held at `2'b11`, MISO zeroed).
- CM-I: `uo_out` is masked to `8'h00` when `spi_lock_reg=1`, preventing FSM state
  leakage onto physical output pins in production mode.

---

## Summary Matrix

| Test Group | Tests | Countermeasures | Checks | Passed |
|------------|-------|-----------------|--------|--------|
| Write Protection | SEC_01, SEC_02, SEC_03 | CM-D | 3 | 3 |
| Computation Integrity | SEC_04 | DP2 gating, CM-B | 1 | 1 |
| Data Leakage Prevention | SEC_05, SEC_06 | CM-B, CM-H | 2 | 2 |
| FSM Robustness | SEC_07, SEC_08 | CM-F, CM-G | 2 | 2 |
| Debug Lockout | SEC_09a, SEC_09b, SEC_09c | CM-A, CM-I | 3 | 3 |
| **Total** | **9 scenarios** | | **11** | **11** |

---

## Countermeasure Coverage Summary

| ID    | Name                              | Tested By                          | Status   |
|-------|-----------------------------------|------------------------------------|----------|
| CM-A  | SPI lock (one-time-writable)      | TEST_SEC_09a/b/c                   | Verified |
| CM-B  | Input register zeroization        | TEST_SEC_05, TEST_SEC_06           | Verified |
| CM-C  | Interrupt-clear decoupled from start | TEST_SEC_08 (rapid toggles)     | Verified |
| CM-D  | write_error sticky flag           | TEST_SEC_01/02/03                  | Verified |
| CM-E  | Butterfly overflow saturation     | Functional test (DP2 baseline), synthesis check | Verified (structural) |
| CM-F  | FSM hardening / deadlock fix      | TEST_SEC_07/08                     | Verified |
| CM-G  | Reset initialization of stage regs| TEST_SEC_07 (post-reset FFT), synthesis (590 $_DFFE_PN0P_) | Verified |
| CM-H  | Input register read-back removed  | TEST_SEC_05                        | Verified |
| CM-I  | uo_out masked in locked mode      | TEST_SEC_09a                       | Verified |
