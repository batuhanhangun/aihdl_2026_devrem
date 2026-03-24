# CIA Triad Analysis — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Input: docs/ATTACK_SURFACE_MAP.md | Generated: 2026-03-24*

---

## Overview

This document applies the CIA (Confidentiality, Integrity, Availability) framework to concrete, design-specific vulnerabilities in the `tqvp_fft8` peripheral and `fft_8point` core. Every finding references exact RTL locations and is scoped to what is exploitable by a bus master, SPI controller, or physical attacker — not hypothetical software vulnerabilities.

Severity scale:
- **Critical** — exploitable by any bus transaction, causes silent data corruption or permanent denial of service
- **High** — exploitable with modest effort, significant impact on data confidentiality or system integrity
- **Medium** — requires specific conditions or physical access; impact is bounded
- **Low** — theoretical or mitigated by other factors; noted for completeness

---

## Confidentiality Threats

### CIA-C-01 · Stale FFT Output Data Readable Between Computations

**Description:**
The FFT output registers (`out_real_0`–`out_real_7`, `out_imag_0`–`out_imag_7`) in `fft_8point` are updated only in the DONE state (fft_8point.v:386–393) and cleared only on `rst_n` assertion (fft_8point.v:149–156). Between two computations — after the first completes and before the second starts — the output registers hold the full results of the previous transform. Any bus master (including one that did not initiate the FFT) can read these values at any time via the OUTPUT_REAL/IMAG address range.

In a multi-tenant or multi-process scenario on TinyQV (which has no MMU), a process that did not own the previous FFT computation can read the results of that computation simply by polling the output registers.

**Affected signals/registers:**
- `out_real[0:7]`, `out_imag[0:7]` — peripheral.v:78–79 (wires to FFT core outputs)
- `out_real_0`–`out_real_7`, `out_imag_0`–`out_imag_7` — fft_8point.v:31–34 (registered outputs)
- DONE state write: fft_8point.v:386–393
- Reset clear: fft_8point.v:149–156
- Bus read path: peripheral.v:191–199

**Severity:** High

**Preliminary mitigation:** Zeroize all output registers in the DONE state immediately after copying results, or add a software-triggered clear command to the CONTROL register.

---

### CIA-C-02 · Stage Working Registers Not Cleared After Completion

**Description:**
The 16 internal working registers (`stage_real[0:7]`, `stage_imag[0:7]`) hold all intermediate butterfly results throughout computation. After DONE state executes (fft_8point.v:384–398), these registers are **not cleared** — they retain the Stage 3 butterfly output values (which are the same as the final FFT results). There is no reset clause for these registers in the reset block (fft_8point.v:141–157).

While these registers are not directly bus-accessible, they are present in the synthesized netlist and can be read via:
1. Differential power analysis (DPA) — switching activity correlates with data values
2. Physical probing of the die in a lab environment
3. Any future debug scan-chain infrastructure added by the toolchain

The lack of explicit reset for these registers also means that after power-on (before the first reset), they contain X in simulation or indeterminate values in silicon, which could leak through any scan path.

**Affected signals/registers:**
- `stage_real[0:7]`, `stage_imag[0:7]` — fft_8point.v:70–71
- No reset assignment in fft_8point.v:141–157 (clock-gated by `stage_reg_en`, not reset-initialized)
- DONE state does not clear them: fft_8point.v:384–398

**Severity:** Medium

**Preliminary mitigation:** Add explicit `stage_real[i] <= 0` / `stage_imag[i] <= 0` assignments in the reset block, and zero them out at the end of the DONE state after copying to output registers.

---

### CIA-C-03 · Butterfly Pipeline Registers Retain Partial Intermediate Results

**Description:**
The `butterfly_pipelined` module contains four pipeline registers (`pipe_a_re`, `pipe_a_im`, `pipe_bw_re`, `pipe_bw_im`) that hold mid-butterfly values after each Stage 1 register clock (fft_8point.v:454–455). These are cleared on reset (fft_8point.v:459–462) but are **not zeroed** after the DONE state or when the FSM returns to IDLE. After computation, they hold the inputs and Q1.15-scaled multiplication products from the last butterfly operation of Stage 3.

Like the stage working registers, these are not bus-accessible but are present in the netlist and observable via power side-channels.

**Affected signals/registers:**
- `pipe_a_re`, `pipe_a_im`, `pipe_bw_re`, `pipe_bw_im` — fft_8point.v:454–455
- Reset: fft_8point.v:459–462 (properly reset to zero)
- Not cleared in DONE: no corresponding clear in fft_8point.v:384–398

**Severity:** Low

**Preliminary mitigation:** Assert a clear enable on these pipeline registers when the FSM transitions from DONE to IDLE, driving them to zero for one cycle.

---

### CIA-C-04 · SPI Test Harness Provides Unauthenticated Full-Register Access in Production Silicon

**Description:**
The `tt_um_tqv_peripheral_harness` module (tt_wrapper.v:9) is explicitly labeled "TinyQV peripheral test using SPI" but is **synthesized into production silicon** — it is not gated by an `ifdef SIMULATION` or any compile-time disable. The full SPI decoder (`spi_reg`, tt_wrapper.v:82–98) with its associated synchronizers (tt_wrapper.v:77–79) is live on the chip.

Any entity with physical access to `uio_in[4:6]` (chip-select, clock, MOSI) can:
- Read INPUT_REAL and INPUT_IMAG registers (containing the current FFT input samples)
- Read OUTPUT_REAL and OUTPUT_IMAG registers (containing FFT results)
- Read STATUS (busy/done state)
- Write CONTROL to trigger new FFT computations

There is no credential, authentication token, or session key required. The SPI interface provides an alternative access path to all registers that bypasses any software-level access control the CPU firmware might enforce.

**Affected signals/registers:**
- `spi_cs_n`, `spi_clk`, `spi_mosi` — tt_wrapper.v:73–75 (physical pins `uio_in[4:6]`)
- `spi_reg` instance — tt_wrapper.v:82–98
- Full register file: peripheral.v:64–65 (inputs), 78–79 (outputs), 70–73 (control/status)

**Severity:** High

**Preliminary mitigation:** Add a one-time-writable LOCK register bit that, once set by firmware, disables SPI harness writes (returning zero for reads and ignoring writes) until the next reset.

---

### CIA-C-05 · Input Sample Registers Are Readable After Being Written

**Description:**
The INPUT_REAL and INPUT_IMAG registers (word addresses 0x00–0x0F) are described in the register map as write-only channels for loading FFT input samples. However, the combinational read path in `peripheral.v` explicitly handles reads from these addresses (peripheral.v:174–183), returning sign-extended 16-bit values.

This means that any bus master can read back the exact input samples that were written into the FFT — either before computation starts (to verify writes) or after computation completes (the registers are not cleared on FFT completion). If the input data is sensitive (e.g., sensor readings, cryptographic inputs, private signals), it remains readable indefinitely until overwritten or reset.

**Affected signals/registers:**
- `in_real[0:7]`, `in_imag[0:7]` — peripheral.v:64–65
- Read path: peripheral.v:174–183
- These registers survive FFT completion without modification

**Severity:** Medium

**Preliminary mitigation:** Zero-fill INPUT_REAL and INPUT_IMAG registers at the start of the DONE state (after samples are already latched into the FFT working registers), preventing post-computation read-back.

---

### CIA-C-06 · FSM State Leakage via Dedicated Output Pins

**Description:**
The `uo_out` dedicated output pins continuously expose the FFT FSM state to anyone observing the physical chip outputs:
- `uo_out[0]` = `fft_busy` (driven from peripheral.v:218)
- `uo_out[1]` = `done_flag` (driven from peripheral.v:218)

Additionally, `uio_out[0]` = `user_interrupt` = `done_flag` (tt_wrapper.v:119) and `uio_out[1]` = `data_ready` = `1'b1` (tt_wrapper.v:121).

While computation latency is constant (~28 cycles regardless of input data magnitude), the interrupt assertion timing and the exact cycle count from a bus-observable `start` write to a `done` interrupt could theoretically be correlated with power traces. More directly, exposing `busy`/`done` on physical pins enables precise timing measurement of computation boundaries, which is useful as a trigger signal for side-channel attacks.

**Affected signals/registers:**
- `uo_out[1:0]` = `{done_flag, fft_busy}` — peripheral.v:218
- `uio_out[0]` = `user_interrupt` = `done_flag` — tt_wrapper.v:119

**Severity:** Low

**Preliminary mitigation:** Gate `uo_out` status bits behind the LOCK bit (see CIA-C-04 mitigation) so that in locked/production mode, output pins return zero rather than leaking FSM state.

---

### CIA-C-07 · Timing Side-Channel on STATUS Register Is Negligible (Documented)

**Description:**
The STATUS register (word addr 0x11, peripheral.v:186–188) exposes `fft_busy` and `done_flag`. An attacker could poll STATUS to measure the precise cycle when computation completes. However, since FFT computation time is **data-independent** (the state machine always executes exactly 9 sub-cycles × 3 stages + 1 DONE cycle = 28 cycles regardless of input values), the completion timestamp reveals nothing about the input data content.

**Affected signals/registers:**
- STATUS register: peripheral.v:186–188
- `fft_busy`, `done_flag`

**Severity:** Low (informational — no data-dependent timing path exists in the current RTL)

**Preliminary mitigation:** No mitigation required for timing; however, monitoring STATUS polling frequency could reveal usage patterns (when FFTs are being computed).

---

## Integrity Threats

### CIA-I-01 · Writes to OUTPUT Register Addresses Are Silently Discarded — No Error Signaling

**Description:**
The bus write path in `peripheral.v` (lines 139–160) decodes writes to INPUT_REAL, INPUT_IMAG, and CONTROL. It does **not** decode writes to OUTPUT_REAL (word addr 0x12–0x19) or OUTPUT_IMAG (word addr 0x1A–0x21). A write transaction targeting those addresses falls through all `if`/`else if` conditions without any state change, error flag, or bus fault.

The FFT output registers themselves are driven by `wire` declarations in peripheral.v (lines 78–79) connected directly to the FFT core's registered outputs — they cannot be written by the bus. However, a buggy driver or malicious software that attempts to forge results by writing to output addresses will receive no feedback that the write failed. `data_ready` remains `1'b1` (peripheral.v:207), indicating "success" for every transaction regardless of whether it had any effect.

**Affected signals/registers:**
- Write decode path: peripheral.v:139–160 (no OUTPUT_REAL/IMAG branch)
- `data_ready`: peripheral.v:207 (always 1)
- `out_real[0:7]`, `out_imag[0:7]`: peripheral.v:78–79 (wire, cannot be bus-written)

**Severity:** Low (output registers are physically protected by being wires, but the silent-discard behavior means no error detection)

**Preliminary mitigation:** Assert a `bus_error` or write-fault flag when a write targets a read-only or unmapped address; this requires adding an error output to the peripheral module.

---

### CIA-I-02 · CONTROL Write During Busy Is Silently Discarded — Computation Cannot Be Aborted

**Description:**
The CONTROL register write path (peripheral.v:154–159) checks `data_in[0] && !fft_busy` before asserting `fft_start`. If the FFT is currently busy and firmware writes CONTROL=1, the condition fails silently — no start pulse is generated, `done_flag` is NOT cleared, and no feedback is given to the writer. This has two integrity implications:

1. **No abort mechanism:** Firmware cannot stop a running FFT computation. Once started, the FSM runs to DONE unconditionally. There is no way to cancel a computation with incorrect inputs without asserting `rst_n`.
2. **Silent control failure:** A firmware bug that re-writes CONTROL during a computation (e.g., due to a race condition in an interrupt handler) will appear to succeed (data_ready=1) while having no effect. The firmware has no way to distinguish "FFT was re-started" from "write was ignored."

**Affected signals/registers:**
- CONTROL write condition: peripheral.v:155 (`data_in[0] && !fft_busy`)
- `fft_start` pulse generation: peripheral.v:156
- `data_ready`: peripheral.v:207 (always 1, no fault signaling)

**Severity:** Medium

**Preliminary mitigation:** Add a `ctrl_write_ignored` sticky status bit that is set whenever a CONTROL write is attempted while busy, giving firmware a way to detect and recover from write races.

---

### CIA-I-03 · Input Register Writes During Computation Are Silently Blocked — No Error Flag

**Description:**
The DP2 clock-gating guard `input_reg_wr_en = write_active & ~fft_busy` (peripheral.v:119) prevents writes to INPUT_REAL and INPUT_IMAG while the FFT is computing. This is the correct behavior for computation integrity. However, the write is discarded silently — no error flag is asserted, `data_ready` remains 1, and the bus transaction completes normally from the master's perspective.

A firmware driver that:
1. Starts an FFT
2. Receives the `start` confirmation
3. Writes new samples for the *next* FFT computation immediately (to minimize turnaround)
...will silently lose those writes if the FFT has not yet completed. The driver would need to explicitly poll STATUS.busy before each input write to be safe, but the peripheral provides no other indication that the write was discarded.

**Affected signals/registers:**
- `input_reg_wr_en`: peripheral.v:119
- `in_real[0:7]`, `in_imag[0:7]`: peripheral.v:64–65
- `data_ready`: peripheral.v:207

**Severity:** Medium

**Preliminary mitigation:** Set a sticky `input_write_blocked` status bit (readable in STATUS[2]) whenever an input register write is attempted while busy, so the driver can detect the data loss.

---

### CIA-I-04 · Q1.15 Butterfly Addition Has No Overflow Saturation — Silent Wrap-Around

**Description:**
The final butterfly stage in `butterfly_pipelined` computes addition and subtraction with 16-bit signals and no overflow protection (fft_8point.v:476–479):

```verilog
assign out_a_re = pipe_a_re + pipe_bw_re;   // 16-bit + 16-bit → 16-bit (truncated)
assign out_a_im = pipe_a_im + pipe_bw_im;
assign out_b_re = pipe_a_re - pipe_bw_re;
assign out_b_im = pipe_a_im - pipe_bw_im;
```

In Q1.15 format, each value represents a number in [-1.0, +0.99997]. If two values near +0.5 are added, the result (+1.0) exceeds the representable range and silently wraps to -1.0 (two's complement overflow). This produces a **numerically incorrect FFT output with no error flag**, no saturation, and no indication to the software layer.

The risk is proportional to input signal amplitude. Inputs with amplitudes greater than 0.5 per sample (>16383 in Q1.15) can trigger overflow in stage results, since each butterfly adds two operands that may individually be near the maximum value.

Additionally, the Q1.15 multiplication scaling (fft_8point.v:446–447) adds a rounding bias unconditionally:
```verilog
wire signed [15:0] bw_re_scaled = (bw_re_full + 16384) >>> 15;
```
The 32-bit product is shifted right by 15 and truncated to 16 bits. If the product of two near-maximum Q1.15 values produces a result near ±1.0, the 16-bit truncation silently discards the overflow bits.

**Affected signals/registers:**
- Butterfly outputs: fft_8point.v:476–479 (combinational, no saturation)
- Scaled multiplication: fft_8point.v:446–447 (rounding but no saturation)
- This propagates silently through all three stages

**Severity:** High

**Preliminary mitigation:** Replace the plain addition/subtraction with saturating arithmetic: detect signed overflow by checking sign bit agreement and clamp to `16'h7FFF` or `16'h8000` accordingly.

---

### CIA-I-05 · Bit-Reversed Input Loading Is Not Validated — Incorrect Algorithm Usage Produces Silent Wrong Results

**Description:**
The FFT core uses Decimation-In-Time (DIT) ordering, which requires inputs to be presented in bit-reversed order. The peripheral performs the reordering internally when `start` fires (fft_8point.v:169–176):

```verilog
stage_real[0] <= in_real_0;  stage_imag[0] <= in_imag_0;
stage_real[1] <= in_real_4;  // bit-reverse of index 1 → 4
...
```

The reordering is fixed and correct for the 8-point DIT algorithm. However, **the peripheral provides no documentation or runtime indication of this reordering** to the bus master. A driver that loads samples expecting natural-order input (assuming index 0 → bin 0) will receive a correctly-computed FFT of the bit-reversed input — producing scrambled output with no error or warning. This is a documentation/interface integrity issue rather than an RTL bug, but the consequence (silently wrong results) is an integrity violation.

**Affected signals/registers:**
- Input loading in IDLE→STAGE1 transition: fft_8point.v:169–176
- Input registers: `in_real[0:7]`, `in_imag[0:7]` — peripheral.v:64–65

**Severity:** Low (correct RTL behavior, but an interface contract that is not enforced or signaled)

**Preliminary mitigation:** Document the input ordering requirement explicitly in the register map description; optionally add a mode bit to support natural-order input with software bit-reversal.

---

### CIA-I-06 · No Write Acknowledgment or Error Return Path on the Bus Interface

**Description:**
The `data_ready` signal is hardwired to `1'b1` (peripheral.v:207). Every bus transaction — regardless of whether it wrote to a valid address, was blocked by the busy guard, targeted a read-only register, or fell outside the address map — returns an immediate ready indication with no error. The bus has no `data_error`, `bus_fault`, or `write_ack` signal.

This systemic absence of error signaling means that all integrity-violation scenarios described above (CIA-I-01, CIA-I-02, CIA-I-03) are invisible to the bus master, making silent failures the norm rather than the exception.

**Affected signals/registers:**
- `data_ready`: peripheral.v:207 (always 1'b1)
- No error output port on `tqvp_fft8`

**Severity:** Medium (systemic amplifier for all other integrity threats)

**Preliminary mitigation:** Add a `bus_error` output wire that is asserted for one cycle on any write to a read-only or out-of-range address, or on any blocked write while busy.

---

## Availability Threats

### CIA-A-01 · FSM Deadlock: Illegal State Entry Leaves `busy=1` in IDLE — Permanent Lockout

**Description:**
The main FSM in `fft_8point` uses a 3-bit state register with 5 defined states (0–4) and 3 undefined states (5–7). The default case in the state machine returns to IDLE:
```verilog
default: state <= IDLE;   // fft_8point.v:400
```

However, the `busy` flag is **not cleared** in the default case. If the FSM enters an illegal state (states 5–7) while `busy=1` (which is set when STAGE1 is entered at fft_8point.v:164), the recovery path forces `state=IDLE` but leaves `busy=1`.

Once in IDLE with `busy=1`, the deadlock is complete:
1. The peripheral's `fft_start` generation checks `!fft_busy` (peripheral.v:155) — since busy=1, no new start pulse is ever generated.
2. The IDLE state only transitions on `start` (fft_8point.v:163) — since no start pulse arrives, the FSM stays in IDLE forever.
3. `busy` is only cleared in the DONE state (fft_8point.v:396) — which is never reached.

**Recovery requires an external `rst_n` assertion.** No software-visible error flag exists to diagnose the condition; the STATUS register simply shows `busy=1` indefinitely.

While illegal states are most likely caused by radiation events or power-supply glitches (not software attacks), the systemic absence of busy-cleanup in the default recovery path is a design weakness that could also be triggered by synthesis optimization artifacts in rare timing corners.

**Affected signals/registers:**
- `state` register: fft_8point.v:64
- `busy` output: fft_8point.v:22, cleared only at fft_8point.v:396
- Default case: fft_8point.v:400 (missing `busy <= 1'b0`)
- `fft_start` guard: peripheral.v:155

**Severity:** Critical

**Preliminary mitigation:** Add `busy <= 1'b0; done <= 1'b0;` to the default state recovery clause so the peripheral can be reused without a hard reset after any FSM anomaly.

---

### CIA-A-02 · Stage Working Registers Have No Reset — Indeterminate State After Power-On or Partial Reset

**Description:**
The 16 stage working registers (`stage_real[0:7]`, `stage_imag[0:7]`) are controlled by the clock-enable signal `stage_reg_en = (state != IDLE)` (fft_8point.v:76), but they have **no reset clause** in the `always @(posedge clk or negedge rst_n)` block (fft_8point.v:141–157). Only the output registers and control flags are reset-initialized.

In silicon, these 256 bits of flip-flops will contain indeterminate values at power-on. The first FFT computation overwrites them entirely (IDLE→STAGE1 loads fresh samples), so functional correctness is preserved for normal use. However:

1. **After a partial reset** (rst_n asserted mid-computation): the FSM resets to IDLE, but stage registers retain whatever partial butterfly results were computed before reset. A subsequent FFT computation WILL overwrite them in IDLE (fft_8point.v:169–176), so computation integrity is maintained — but the window between reset deassertion and `start` contains stale partial results in these registers, observable via power analysis.
2. **At power-on**: before any FFT, these registers contain silicon-process-dependent random values that could correlate with previous device usage if the device was powered down mid-computation.

**Affected signals/registers:**
- `stage_real[0:7]`, `stage_imag[0:7]`: fft_8point.v:70–71
- No reset: fft_8point.v:141–157 (absent)
- Clock gate: `stage_reg_en`: fft_8point.v:76

**Severity:** Medium

**Preliminary mitigation:** Add explicit `stage_real[i] <= 16'd0` initialization for all 8 elements in the reset block, ensuring a deterministic zero state at power-on and after any reset.

---

### CIA-A-03 · Assertion of Reset Mid-Computation Does Not Cleanly Signal Error to Firmware

**Description:**
If `rst_n` is asserted while the FFT is computing (state = STAGE1/STAGE2/STAGE3), the FSM asynchronously resets to IDLE, `busy` is cleared, and `done` is cleared. The peripheral also resets: `fft_start` and `done_flag` are cleared (peripheral.v:124–130). From the bus master's perspective, STATUS transitions from `busy=1` to `busy=0, done=0` with no `done=1` pulse — the computation was silently aborted.

A firmware driver that:
1. Wrote inputs and triggered an FFT
2. Was waiting for `user_interrupt` (done_flag=1) or polling STATUS.done
...will wait forever if reset is asserted and deasserted without asserting done. The driver has no way to distinguish "reset occurred during computation" from "computation not yet started."

There is no `aborted` status flag, no error interrupt, and no way to detect the partial-reset scenario without additional out-of-band signaling.

**Affected signals/registers:**
- `rst_n`: tt_wrapper.v:18, fft_8point.v:140
- `done_flag` reset: peripheral.v:126
- `done` reset: fft_8point.v:152
- `busy` reset: fft_8point.v:143

**Severity:** Medium

**Preliminary mitigation:** Add an `aborted` sticky flag that is set when reset is detected while `busy=1`; this flag would be readable in STATUS and clearable by firmware.

---

### CIA-A-04 · Interrupt Line Cannot Be Cleared Without Triggering a New Computation

**Description:**
The `user_interrupt` signal (peripheral.v:212) is driven directly by `done_flag`, a sticky latch (peripheral.v:135–137). `done_flag` is only cleared in two ways:
1. Writing CONTROL with bit 0=1 while `!fft_busy` (peripheral.v:157) — this simultaneously triggers a new FFT computation.
2. Asserting `rst_n` (peripheral.v:126).

There is **no interrupt-clear register** that allows firmware to acknowledge and de-assert the interrupt without launching a new FFT. This forces a firmware contract where "acknowledge interrupt" always equals "start next computation." If a firmware handler wants to acknowledge the interrupt but is not ready to start a new computation (e.g., it needs to first read and process the output), it cannot do so without leaving the interrupt line asserted, which would re-trigger the handler in an interrupt-driven system.

In a polling-based system this is manageable, but in any interrupt-driven TinyQV software environment, a stuck interrupt line is a denial-of-service condition on the CPU's interrupt controller.

**Affected signals/registers:**
- `user_interrupt` = `done_flag`: peripheral.v:212
- `done_flag` cleared only by: peripheral.v:157 (start+clear, atomic) or rst_n
- No standalone clear path

**Severity:** High

**Preliminary mitigation:** Add a dedicated CONTROL bit (e.g., bit 1 = `interrupt_clear`) that clears `done_flag` without asserting `fft_start`, decoupling interrupt acknowledgment from computation start.

---

### CIA-A-05 · `bfly_cnt` Default Recovery Silently Re-Executes Butterfly 0 — Potential Incorrect Output Without Lockup

**Description:**
Within each stage, the 4-bit `bfly_cnt` counter drives the sub-state sequencer. Valid values are 0–8; values 9–15 are handled by:
```verilog
default: bfly_cnt <= 4'd0;   // STAGE1: fft_8point.v:246; STAGE2: fft_8point.v:313; STAGE3: fft_8point.v:380
```

If `bfly_cnt` reaches an illegal value (e.g., due to a single-event upset flipping a bit from `4'd7` to `4'd15`), it is reset to 0, causing the current stage to silently restart from butterfly 0. The stage never stalls and never asserts an error. The FSM continues to DONE, where results are committed to output registers and `done=1` is asserted.

The output of a stage that re-executed butterfly 0 (overwriting stage_real[0]/stage_imag[0] and stage_real[1]/stage_imag[1] with results from a re-computed butterfly while stage registers 2–7 hold their correct partially-updated values) will be numerically incorrect — but the peripheral reports success.

**Affected signals/registers:**
- `bfly_cnt`: fft_8point.v:135
- Default recovery in STAGE1: fft_8point.v:246
- Default recovery in STAGE2: fft_8point.v:313
- Default recovery in STAGE3: fft_8point.v:380
- No error output from FSM

**Severity:** Medium (most likely from radiation/glitch; not software-exploitable, but produces silent wrong results)

**Preliminary mitigation:** Add an `fsm_error` output flag that is asserted when the default case fires in either the stage FSM or `bfly_cnt`, allowing firmware to detect anomalous execution.

---

### CIA-A-06 · Rapid CONTROL Writes Between Computations Can Trigger Unintended Back-to-Back FFTs

**Description:**
After an FFT completes (`done_flag=1`, `busy=0`), the peripheral is in the IDLE state and will accept a new `start` pulse. A `fft_start` pulse is generated on any write to CONTROL with bit 0=1 while `!fft_busy`. If firmware writes CONTROL=1 more than once while busy=0 (e.g., due to a firmware loop bug or a duplicate interrupt dispatch), each write will:
1. Set `fft_start=1` for one cycle
2. Transition the FSM to STAGE1

However, on the second write: the first write already moved the FSM to STAGE1 (busy=1), so subsequent writes within 28 cycles are blocked by the `!fft_busy` guard. The peripheral only triggers one FFT per write-sequence. This is correct behavior — but the window (1 cycle) between DONE returning to IDLE and busy going low means that a write on exactly that cycle starts a new FFT with **whatever values remain in the input registers** (which may be stale from the previous computation if new inputs have not been written).

**Affected signals/registers:**
- `fft_start` generation: peripheral.v:155–157
- DONE→IDLE transition with `busy=0`: fft_8point.v:396–397
- Input registers `in_real[0:7]`: peripheral.v:64

**Severity:** Low

**Preliminary mitigation:** Require firmware to write STATUS-confirm-zero (or explicitly write `done_flag_clear`) before accepting a new start command; or add a 2-cycle IDLE guard after DONE before accepting start.

---

## Summary Table

| Threat ID | Pillar | Description | Severity |
|-----------|--------|-------------|----------|
| CIA-C-01 | Confidentiality | Stale output data readable between computations | High |
| CIA-C-02 | Confidentiality | Stage working registers not cleared after completion | Medium |
| CIA-C-03 | Confidentiality | Butterfly pipeline registers retain partial results | Low |
| CIA-C-04 | Confidentiality | SPI test harness provides unauthenticated full-register access in production | High |
| CIA-C-05 | Confidentiality | Input sample registers readable after being written | Medium |
| CIA-C-06 | Confidentiality | FSM state leaked via dedicated output pins | Low |
| CIA-C-07 | Confidentiality | STATUS timing side-channel is negligible (documented) | Low |
| CIA-I-01 | Integrity | Writes to OUTPUT addresses silently discarded, no error | Low |
| CIA-I-02 | Integrity | CONTROL write during busy silently ignored, no abort | Medium |
| CIA-I-03 | Integrity | Input register writes during computation silently blocked | Medium |
| CIA-I-04 | Integrity | Q1.15 butterfly addition has no overflow saturation | High |
| CIA-I-05 | Integrity | Bit-reversed input ordering undocumented, silent wrong results | Low |
| CIA-I-06 | Integrity | No write acknowledgment or error return on bus interface | Medium |
| CIA-A-01 | Availability | FSM illegal-state recovery leaves busy=1 → permanent lockout | **Critical** |
| CIA-A-02 | Availability | Stage registers have no reset — indeterminate power-on state | Medium |
| CIA-A-03 | Availability | Mid-computation reset does not signal abort to firmware | Medium |
| CIA-A-04 | Availability | Interrupt cannot be cleared without triggering new computation | High |
| CIA-A-05 | Availability | bfly_cnt default recovery silently re-executes butterfly 0 | Medium |
| CIA-A-06 | Availability | Rapid CONTROL writes can trigger unintended back-to-back FFTs | Low |

---

*End of CIA Triad Analysis. Feed into: docs/STRIDE_ANALYSIS.md (Prompt 3), docs/DREAD_SCORES.md (Prompt 4), docs/CWE_FINDINGS.md (Prompt 5).*
