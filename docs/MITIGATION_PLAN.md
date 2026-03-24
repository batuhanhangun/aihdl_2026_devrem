# Mitigation Plan — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Inputs: DREAD_SCORES.md, CWE_FINDINGS.md, STRIDE_ANALYSIS.md, CIA_ANALYSIS.md | Generated: 2026-03-24*

---

## Overview

Nine countermeasures (CM-A through CM-I) address all CRITICAL and HIGH DREAD threats. Each maps to specific RTL lines across three source files. Medium/Low threats are documented in Section 2. Implementation order and regression impact follow in Sections 3 and 4.

**Files modified:** `src/peripheral.v`, `src/fft_8point.v`, `src/tt_wrapper.v`

---

## Section 1: Critical Priority Countermeasures

---

### CM-A · SPI Test Harness Lockout (LOCK Bit)

**Threats addressed:** S-02/E-01 (8.6 CRITICAL), T-02 (8.2 CRITICAL), I-04 (7.0 CRITICAL), D-05 (5.2 HIGH), R-03 (6.4 HIGH), I-05 (6.8 HIGH — combined with CM-I)
**CWEs addressed:** CWE-1234, CWE-1262, CWE-1231

**Root cause in RTL:**
- `spi_reg` instantiated with `ena(1'b1)` and no disable path — tt_wrapper.v:82–98
- No lock register exists in `tqvp_fft8` — peripheral.v throughout

**Countermeasure design:**

*In `peripheral.v` — add `spi_lock` register and output port:*
```verilog
// New output port on tqvp_fft8:
output wire spi_lock,

// New register (set-only, cleared only by rst_n):
reg spi_lock_reg;
assign spi_lock = spi_lock_reg;

// In reset block (alongside existing resets):
spi_lock_reg <= 1'b0;

// In write logic, after existing CONTROL decode — add CONTROL[2] handling:
// CONTROL[0] = start FFT  (unchanged)
// CONTROL[1] = interrupt clear  (CM-C)
// CONTROL[2] = set SPI LOCK (one-time-writable, set-only)
if (word_addr == ADDR_CONTROL) begin
    if (data_in[2]) spi_lock_reg <= 1'b1;   // once set, stays until rst_n
    if (data_in[1]) done_flag <= 1'b0;       // CM-C interrupt clear
    if (data_in[0] && !fft_busy) begin
        fft_start <= 1'b1;
        done_flag <= 1'b0;
    end
end
```

*In `tt_wrapper.v` — gate the SPI transaction path and MISO output:*
```verilog
// Add spi_lock to tqvp_fft8 port connection:
tqvp_fft8 user_peripheral(
    ...
    .spi_lock(spi_lock),    // new port
    ...
);

// Replace the existing always @(*) mux block with lock-gated version:
always @(*) begin
    data_write_n = 2'b11;   // default: no transaction
    data_read_n  = 2'b11;

    if (!spi_lock) begin     // SPI path disabled when locked
        if (data_valid && data_rw)    data_write_n = txn_n;
        if (addr_valid && !data_rw)   data_read_n  = txn_n;
    end

    // Return zeros on MISO when locked; mask by width otherwise
    data_out_masked = spi_lock ? 32'd0 : data_out;
    if (!spi_lock) begin
        if (txn_n[1] == 1'b0) data_out_masked[31:16] = 0;
        if (txn_n == 2'b00)   data_out_masked[15:8]  = 0;
    end
end
```

The `spi_lock` bit is set-only: once firmware writes CONTROL[2]=1, no SPI transaction can reach the peripheral until `rst_n` is asserted. The CPU bus path is completely unaffected — `data_write_n` and `data_read_n` for the CPU originate from a different (unimplemented in provided RTL but assumed) bus decode layer.

**Validation approach:**
- Security test TEST_SEC_09: write CONTROL[2]=1 to set lock; verify subsequent SPI write to INPUT_REAL is ignored (value unchanged); verify SPI read returns 0x00000000.
- Verify CONTROL[2] cannot be cleared by any SPI or CPU write (only `rst_n` deasserts it).
- Verify CPU bus writes to INPUT registers still succeed after lock is set.

**Expected PPA impact:** Negligible — 1 flip-flop for `spi_lock_reg`; ~8 gate cells for the SPI mux; no impact on the critical butterfly path.

---

### CM-B · Register Zeroization on Completion and Reset

**Threats addressed:** I-01 (8.6 CRITICAL), I-02 (8.0 CRITICAL), CIA-A-02 (5.0 HIGH), CIA-C-02, CIA-C-03
**CWEs addressed:** CWE-1239, CWE-1271, CWE-1272

**Root cause in RTL:**
- `stage_real[0:7]`, `stage_imag[0:7]` have no reset clause — fft_8point.v:70–71 (absent from reset block at 141–157)
- `stage_real/imag` not cleared after DONE — fft_8point.v:384–398
- `in_real[0:7]`, `in_imag[0:7]` not cleared after computation — peripheral.v:64–65

**Countermeasure design:**

*In `fft_8point.v` — add reset clause and post-DONE zeroization for stage registers:*
```verilog
// In the reset block (if (!rst_n) begin ... end):
// ADD after existing output register clears:
stage_real[0] <= 16'sd0;  stage_imag[0] <= 16'sd0;
stage_real[1] <= 16'sd0;  stage_imag[1] <= 16'sd0;
stage_real[2] <= 16'sd0;  stage_imag[2] <= 16'sd0;
stage_real[3] <= 16'sd0;  stage_imag[3] <= 16'sd0;
stage_real[4] <= 16'sd0;  stage_imag[4] <= 16'sd0;
stage_real[5] <= 16'sd0;  stage_imag[5] <= 16'sd0;
stage_real[6] <= 16'sd0;  stage_imag[6] <= 16'sd0;
stage_real[7] <= 16'sd0;  stage_imag[7] <= 16'sd0;
bfly_a_re <= 16'sd0;  bfly_a_im <= 16'sd0;
bfly_b_re <= 16'sd0;  bfly_b_im <= 16'sd0;
bfly_w_re <= 16'sd0;  bfly_w_im <= 16'sd0;

// In the DONE state — AFTER copying to outputs, zeroize stage registers:
DONE: begin
    // Copy to output registers (unchanged)
    out_real_0 <= stage_real[0];  out_imag_0 <= stage_imag[0];
    out_real_1 <= stage_real[1];  out_imag_1 <= stage_imag[1];
    out_real_2 <= stage_real[2];  out_imag_2 <= stage_imag[2];
    out_real_3 <= stage_real[3];  out_imag_3 <= stage_imag[3];
    out_real_4 <= stage_real[4];  out_imag_4 <= stage_imag[4];
    out_real_5 <= stage_real[5];  out_imag_5 <= stage_imag[5];
    out_real_6 <= stage_real[6];  out_imag_6 <= stage_imag[6];
    out_real_7 <= stage_real[7];  out_imag_7 <= stage_imag[7];

    // ADD: Zeroize stage registers (non-blocking: outputs get old values ✓)
    stage_real[0] <= 16'sd0;  stage_imag[0] <= 16'sd0;
    stage_real[1] <= 16'sd0;  stage_imag[1] <= 16'sd0;
    stage_real[2] <= 16'sd0;  stage_imag[2] <= 16'sd0;
    stage_real[3] <= 16'sd0;  stage_imag[3] <= 16'sd0;
    stage_real[4] <= 16'sd0;  stage_imag[4] <= 16'sd0;
    stage_real[5] <= 16'sd0;  stage_imag[5] <= 16'sd0;
    stage_real[6] <= 16'sd0;  stage_imag[6] <= 16'sd0;
    stage_real[7] <= 16'sd0;  stage_imag[7] <= 16'sd0;

    done  <= 1'b1;
    busy  <= 1'b0;
    state <= IDLE;
end
```

*In `peripheral.v` — zeroize input registers when FFT signals done:*
```verilog
// In the write always block, in the fft_done handler:
if (fft_done) begin
    done_flag <= 1'b1;
    // ADD: Clear input registers (samples already latched into stage_real/imag
    // at the start of computation; zeroizing here does not affect results)
    for (i = 0; i < 8; i = i + 1) begin
        in_real[i] <= 16'd0;
        in_imag[i] <= 16'd0;
    end
end
```

Non-blocking assignment semantics guarantee correctness: in the DONE state, `out_real_N <= stage_real[N]` and `stage_real[N] <= 0` both evaluate with the old `stage_real[N]` value, so outputs receive the correct FFT results.

**Validation approach:**
- TEST_SEC_05: Run FFT with non-zero inputs. After `done_flag=1`, read INPUT_REAL[0]–INPUT_REAL[7]. Verify all return 0x00000000.
- TEST_SEC_06: Run FFT #1 with pattern A, run FFT #2 with pattern B. Verify FFT #2 results contain no residue from FFT #1's stage registers.
- Verify existing DC/impulse/Nyquist/sine/cosine tests still pass (outputs must still be correct, proving non-blocking zeroization doesn't corrupt results).

**Expected PPA impact:** Small — 256 additional reset-capable flip-flops for `stage_real/imag` (changing DFFE_PP → DFFE_PN0P in Sky130). Additional mux conditions in DONE state add ~32 gate cells. No critical path impact.

---

### CM-C · Interrupt-Clear Register Bit (CONTROL[1])

**Threats addressed:** D-02 (8.4 CRITICAL), T-06 (5.8 HIGH)
**CWEs addressed:** CWE-1262 (partial)

**Root cause in RTL:**
- `done_flag` clearable only by `data_in[0] && !fft_busy` (forces new computation) or `rst_n` — peripheral.v:157, 126
- No standalone interrupt acknowledge path

**Countermeasure design:**

*In `peripheral.v` — split CONTROL[0] (start) from CONTROL[1] (interrupt clear):*
```verilog
// Updated CONTROL register decode (replaces peripheral.v:154-159):
if (word_addr == ADDR_CONTROL) begin
    if (data_in[2]) spi_lock_reg <= 1'b1;        // CONTROL[2]: set lock (CM-A)

    if (data_in[1]) done_flag <= 1'b0;            // CONTROL[1]: clear interrupt only
                                                   //   does NOT start FFT

    if (data_in[0] && !fft_busy) begin            // CONTROL[0]: start FFT
        fft_start  <= 1'b1;
        done_flag  <= 1'b0;                        // also clears interrupt
    end
end
// Note: if both [1] and [0] are set simultaneously, [0] wins (both clear done_flag,
// but [0] also starts computation). Priority is harmless; both clear the flag.
```

The updated CONTROL register bit map:
- `CONTROL[0]` — Start FFT (existing, unchanged behavior)
- `CONTROL[1]` — Clear `done_flag`/interrupt without starting FFT *(new)*
- `CONTROL[2]` — Set SPI LOCK bit, one-time-writable *(new, from CM-A)*
- `CONTROL[31:3]` — Reserved, ignored

**Validation approach:**
- TEST_SEC_03: Run FFT; wait for done. Write CONTROL=0x02 (bit 1 only). Verify `user_interrupt` deasserts and `done_flag=0` in STATUS. Verify no new computation started (busy stays 0). Read OUTPUT registers — results should still be present (outputs not cleared by interrupt-clear alone).
- Verify CONTROL=0x01 still starts computation and clears interrupt as before.

**Expected PPA impact:** Negligible — 1 additional AND gate (`data_in[1] && write_active && word_addr==ADDR_CONTROL`) feeding the `done_flag` clear condition.

---

### CM-D · Bus Write Error Flag (STATUS[2])

**Threats addressed:** D-04 (7.6 CRITICAL), E-02 (6.8 HIGH), CIA-I-01, CIA-I-02, CIA-I-03, CIA-I-06
**CWEs addressed:** CWE-1262, CWE-1276 (partial)

**Root cause in RTL:**
- `data_ready` hardwired to `1'b1` — peripheral.v:207
- No error output port on `tqvp_fft8`
- All rejected/ignored writes silently appear successful to the bus master

**Countermeasure design:**

*In `peripheral.v` — add `write_error` sticky flag:*
```verilog
// New register:
reg write_error;  // sticky flag, cleared by CONTROL[3] write

// In reset block:
write_error <= 1'b0;

// In write logic — ADD write_error detection after existing decode:
if (write_active) begin
    // Existing input/control decode (unchanged)...

    // ADD: Detect and flag rejected writes
    // Case 1: Input register write while FFT is busy (write silently dropped)
    if (!input_reg_wr_en &&
        ((word_addr >= ADDR_IN_REAL_BASE && word_addr < ADDR_IN_REAL_BASE + 8) ||
         (word_addr >= ADDR_IN_IMAG_BASE && word_addr < ADDR_IN_IMAG_BASE + 8))) begin
        write_error <= 1'b1;
    end
    // Case 2: Write to any read-only address (STATUS, OUTPUT_REAL, OUTPUT_IMAG)
    if (word_addr == ADDR_STATUS ||
        (word_addr >= ADDR_OUT_REAL_BASE && word_addr < ADDR_OUT_REAL_BASE + 8) ||
        (word_addr >= ADDR_OUT_IMAG_BASE && word_addr < ADDR_OUT_IMAG_BASE + 8)) begin
        write_error <= 1'b1;
    end
    // Case 3: Write to unmapped address
    if (word_addr > ADDR_OUT_IMAG_BASE + 7) begin
        write_error <= 1'b1;
    end

    // ADD CONTROL[3] as write_error clear:
    if (word_addr == ADDR_CONTROL && data_in[3]) write_error <= 1'b0;
end

// In STATUS read — expose write_error as STATUS[2]:
// (replaces peripheral.v:187):
data_out = {29'd0, write_error, done_flag, fft_busy};
```

Updated STATUS register bit map:
- `STATUS[0]` — `fft_busy` (existing)
- `STATUS[1]` — `done_flag` (existing)
- `STATUS[2]` — `write_error` sticky flag *(new)*
- `STATUS[31:3]` — Reserved, zero

Updated CONTROL[3] — Clear `write_error` flag *(new)*.

**Validation approach:**
- TEST_SEC_01: Start FFT; while busy, attempt to write INPUT_REAL[0]. Read STATUS; verify STATUS[2]=1. Write CONTROL=0x08 (CONTROL[3]); verify STATUS[2] clears to 0.
- TEST_SEC_02: Write to OUTPUT_REAL[0] (0x48); verify STATUS[2]=1.
- TEST_SEC_02b: Write to unmapped address 0x90; verify STATUS[2]=1 and no register state changed.

**Expected PPA impact:** Negligible — 1 flip-flop for `write_error`; ~15–20 comparator/gate cells for the three error conditions; 1-bit wider STATUS read mux.

---

### CM-E · Butterfly Overflow Saturation

**Threats addressed:** CIA-I-04 (6.6 HIGH)
**CWEs addressed:** None directly; correctness/integrity improvement

**Root cause in RTL:**
- 16-bit addition/subtraction with no overflow guard — fft_8point.v:476–479
- Signed wrap-around on large-amplitude inputs produces silently incorrect FFT output

**Countermeasure design:**

*In `butterfly_pipelined` — replace plain 16-bit assignments with saturating arithmetic:*
```verilog
// REMOVE (fft_8point.v:476-479):
// assign out_a_re = pipe_a_re + pipe_bw_re;
// assign out_a_im = pipe_a_im + pipe_bw_im;
// assign out_b_re = pipe_a_re - pipe_bw_re;
// assign out_b_im = pipe_a_im - pipe_bw_im;

// REPLACE WITH 17-bit sign-extended saturating arithmetic:
// Each intermediate is 17 bits (1 overflow-detect bit + 16 data bits).
// Overflow is detected when bit[16] (extended sign) != bit[15] (result MSB).
// On overflow, clamp to max positive (0x7FFF) or min negative (0x8000).

wire signed [16:0] wide_a_re = {pipe_a_re[15], pipe_a_re} + {pipe_bw_re[15], pipe_bw_re};
wire signed [16:0] wide_a_im = {pipe_a_im[15], pipe_a_im} + {pipe_bw_im[15], pipe_bw_im};
wire signed [16:0] wide_b_re = {pipe_a_re[15], pipe_a_re} - {pipe_bw_re[15], pipe_bw_re};
wire signed [16:0] wide_b_im = {pipe_a_im[15], pipe_a_im} - {pipe_bw_im[15], pipe_bw_im};

// Overflow when extended sign bit differs from result sign bit:
wire ovf_a_re = wide_a_re[16] ^ wide_a_re[15];
wire ovf_a_im = wide_a_im[16] ^ wide_a_im[15];
wire ovf_b_re = wide_b_re[16] ^ wide_b_re[15];
wire ovf_b_im = wide_b_im[16] ^ wide_b_im[15];

// Saturate: if positive overflow → 0x7FFF; if negative overflow → 0x8000
assign out_a_re = ovf_a_re ? (wide_a_re[16] ? 16'sh8000 : 16'sh7FFF) : wide_a_re[15:0];
assign out_a_im = ovf_a_im ? (wide_a_im[16] ? 16'sh8000 : 16'sh7FFF) : wide_a_im[15:0];
assign out_b_re = ovf_b_re ? (wide_b_re[16] ? 16'sh8000 : 16'sh7FFF) : wide_b_re[15:0];
assign out_b_im = ovf_b_im ? (wide_b_im[16] ? 16'sh8000 : 16'sh7FFF) : wide_b_im[15:0];
```

The 17-bit sign-extended addition is the standard technique for Q1.15 saturation. The overflow flag and mux add minimal logic (~10 cells per output, 40 cells total). The wider adder adds one gate level on the butterfly output path.

**Validation approach:**
- Write a new testbench test: load INPUT_REAL[0–7] all with `16'h7FFF` (maximum positive Q1.15). Run FFT. Verify outputs are `16'h7FFF` (saturated), not wrapped-around negative values.
- Verify the five existing functional tests still pass — their input magnitudes (max ±8000) are well within the safe range and will not be affected by saturation logic.

**Expected PPA impact:** Small — 4 × 17-bit adder (vs 4 × 16-bit) plus 8 XOR gates (overflow detect) plus 8 muxes (saturate select). Estimated +40–50 cells above baseline butterfly (~0.5% of total design). The 17-bit adder extends the Stage 2 combinational path by approximately one gate delay; monitor whether this affects the critical path registered at the DONE→IDLE transition.

---

### CM-F · FSM Hardening (State Machine and Sub-Counter)

**Threats addressed:** D-01 (5.8 HIGH — CRITICAL impact), D-06 (4.0 MEDIUM), CIA-A-01, CIA-A-05
**CWEs addressed:** CWE-1245, CWE-1276

**Root cause in RTL:**
- `default: state <= IDLE` does not clear `busy` — fft_8point.v:400
- `default: bfly_cnt <= 4'd0` does not assert error — fft_8point.v:246, 313, 380
- `bfly_out_valid` produced by butterfly but never checked by FSM — fft_8point.v:104, 125

**Countermeasure design:**

*In `fft_8point.v` — add `fsm_error` output port and fix default clauses:*
```verilog
// ADD to module port list:
output reg fsm_error,

// In reset block — initialize fsm_error:
fsm_error <= 1'b0;

// REPLACE default state recovery (fft_8point.v:400):
// BEFORE:
//   default: state <= IDLE;
// AFTER:
default: begin
    state     <= IDLE;
    busy      <= 1'b0;    // ← Critical fix: prevents busy=1-in-IDLE deadlock
    done      <= 1'b0;
    bfly_cnt  <= 4'd0;
    fsm_error <= 1'b1;    // ← Firmware-visible error flag
end

// REPLACE default bfly_cnt recovery in all three stage case statements
// (fft_8point.v:246, 313, 380):
// BEFORE:
//   default: bfly_cnt <= 4'd0;
// AFTER (same in all three STAGE cases):
default: begin
    bfly_cnt  <= 4'd0;
    fsm_error <= 1'b1;    // signal to firmware that sub-state was corrupted
end

// ADD: Clear fsm_error when a new computation starts successfully:
IDLE: begin
    if (start) begin
        busy      <= 1'b1;
        fsm_error <= 1'b0;    // clear on successful restart
        bfly_cnt  <= 4'd0;
        ...
    end
end
```

*Optional — gate STORE sub-states on `bfly_out_valid` (CWE-1276 fix):*
```verilog
// In each STORE sub-state (bfly_cnt == 2, 4, 6, 8), add valid_out check:
// Example — STAGE1, bfly_cnt == 2 (fft_8point.v:200):
4'd2: begin
    if (bfly_out_valid) begin   // only store when pipeline output is confirmed valid
        stage_real[0] <= bfly_out_a_re;  stage_imag[0] <= bfly_out_a_im;
        stage_real[1] <= bfly_out_b_re;  stage_imag[1] <= bfly_out_b_im;
    end else begin
        fsm_error <= 1'b1;     // pipeline did not produce valid output — flag it
    end
    // Continue to next butterfly regardless (don't stall stage)
    bfly_a_re <= stage_real[2]; ...
    bfly_cnt  <= 4'd3;
end
// (repeat for all STORE sub-states in STAGE2 and STAGE3)
```

**Validation approach:**
- TEST_SEC_07: Assert `rst_n=0` mid-computation. Deassert. Check FSM is in IDLE with `busy=0` and `done=0`. Run a complete FFT; verify correct output — FSM must recover cleanly.
- TEST_SEC_08: Write CONTROL=1 rapidly (CONTROL=1, CONTROL=0, CONTROL=1 in consecutive cycles). Verify exactly one FFT runs; no lockup; `busy` toggles exactly once.
- For `fsm_error`: In the security testbench, it suffices to verify that after normal operation, `fsm_error=0`. The flag itself cannot be exercised in software simulation without injecting illegal state values.

**Expected PPA impact:** Negligible — `fsm_error` adds 1 flip-flop; the updated default clauses add a few gate cells for the additional assignments; `bfly_out_valid` gating adds 4 × 2-input AND gates (one per STORE state, to gate each pair of stage register writes). No critical path impact.

---

### CM-G · Stage Register Reset Initialization

**Threats addressed:** CIA-A-02 (5.0 HIGH), CWE-1271, partially I-03
**CWEs addressed:** CWE-1271

**Root cause in RTL:**
- `stage_real[0:7]`, `stage_imag[0:7]` declared at fft_8point.v:70–71 with no reset clause
- `bfly_a_re/im`, `bfly_b_re/im`, `bfly_w_re/im` declared at fft_8point.v:85–87 with no reset clause

**Countermeasure design:**

*In `fft_8point.v` — add to the `if (!rst_n) begin` block:*
```verilog
// ADD after existing reset assignments (after fft_8point.v:156):
stage_real[0] <= 16'sd0;  stage_imag[0] <= 16'sd0;
stage_real[1] <= 16'sd0;  stage_imag[1] <= 16'sd0;
stage_real[2] <= 16'sd0;  stage_imag[2] <= 16'sd0;
stage_real[3] <= 16'sd0;  stage_imag[3] <= 16'sd0;
stage_real[4] <= 16'sd0;  stage_imag[4] <= 16'sd0;
stage_real[5] <= 16'sd0;  stage_imag[5] <= 16'sd0;
stage_real[6] <= 16'sd0;  stage_imag[6] <= 16'sd0;
stage_real[7] <= 16'sd0;  stage_imag[7] <= 16'sd0;
bfly_a_re <= 16'sd0;  bfly_a_im <= 16'sd0;
bfly_b_re <= 16'sd0;  bfly_b_im <= 16'sd0;
bfly_w_re <= 16'sd0;  bfly_w_im <= 16'sd0;
fsm_error <= 1'b0;          // (from CM-F, listed here for completeness)
```

**Note:** This change converts 16 × 16-bit = 256 DFF (no reset) flip-flops into DFFE-with-reset flip-flops. In Yosys/Sky130, this changes the cell type from `$_DFFE_PP_` to `$_DFFE_PN0P_` (or similar), which carries a slight area premium. This is unavoidable for correct reset behavior.

**Validation approach:**
- Verify in simulation that immediately after `rst_n` deassertion (before any `start`), `stage_real[0:7]` and `stage_imag[0:7]` are all zero. Add an `$display` check in the testbench after the reset block.
- All five existing functional tests must pass unchanged.

**Expected PPA impact:** Small — 256 flip-flops gain a reset terminal, increasing per-cell area slightly. Estimated +40–60 cells vs baseline (Sky130 DFFE_PN0P is approximately 1.15× the area of DFFE_PP). No timing impact.

---

### CM-H · Input Register Read-Back Removal

**Threats addressed:** I-02 (8.0 CRITICAL), CIA-C-05, CWE-1280
**CWEs addressed:** CWE-1280, CWE-1272

**Root cause in RTL:**
- INPUT_REAL and INPUT_IMAG registers have a full read path labeled "for verification" — peripheral.v:173–183
- No access control check gates this read; any bus master sees raw input sample data

**Countermeasure design:**

*In `peripheral.v` — remove the INPUT_REAL/IMAG read branches from the combinational read path:*
```verilog
// REMOVE the following blocks from the always @(*) read path (peripheral.v:172-183):
//
// // Input Real registers (for verification)
// if (word_addr >= ADDR_IN_REAL_BASE && word_addr < ADDR_IN_REAL_BASE + 8) begin
//     data_out = {{16{in_real[word_addr - ADDR_IN_REAL_BASE][15]}},
//                  in_real[word_addr - ADDR_IN_REAL_BASE]};
// end
//
// // Input Imag registers (for verification)
// else if (word_addr >= ADDR_IN_IMAG_BASE && word_addr < ADDR_IN_IMAG_BASE + 8) begin
//     data_out = {{16{in_imag[word_addr - ADDR_IN_IMAG_BASE][15]}},
//                  in_imag[word_addr - ADDR_IN_IMAG_BASE]};
// end
//
// After removal, reads to INPUT addresses (word 0x00–0x0F) return data_out=32'd0
// (the default assignment at the top of the always block).
```

**Trade-off note:** Removing the read-back path eliminates a software "verify what I wrote" capability. The recommended software workaround is for the driver to maintain a shadow copy of input registers in software memory. This is standard practice for write-only hardware registers. If the "verification" use case is considered essential for hardware bring-up, an alternative is to gate the read path behind the SPI lock: `if (!spi_lock_reg && word_addr >= ...)` — this makes inputs readable only in unlocked/test mode and unreadable in locked/production mode.

**Validation approach:**
- TEST_SEC_05: Write INPUT_REAL[0] = 0x1234. Read back INPUT_REAL[0]. Verify read returns 0x00000000 (write-only enforced).
- Verify existing functional tests pass — they do not read back input registers.

**Expected PPA impact:** Negligible — removes ~20–30 mux cells from the read path (slight area reduction).

---

### CM-I · Output Pin State Masking

**Threats addressed:** I-05 (6.8 HIGH), CIA-C-06
**CWEs addressed:** CWE-1272 (partial)

**Root cause in RTL:**
- `uo_out[1:0]` = `{done_flag, fft_busy}` always driven — peripheral.v:218
- FSM timing information continuously visible on physical output pads regardless of operational mode

**Countermeasure design:**

*In `peripheral.v` — gate `uo_out` behind `spi_lock_reg`:*
```verilog
// REPLACE (peripheral.v:218):
// assign uo_out = {6'b0, done_flag, fft_busy};
// WITH:
assign uo_out = spi_lock_reg ? 8'd0 : {6'b0, done_flag, fft_busy};
```

When locked (production mode), `uo_out` is driven to `0x00`, preventing FSM state observation via physical output pins. When unlocked (test mode), behavior is unchanged.

Similarly, gate the `uio_out[0]` interrupt line in `tt_wrapper.v` (already gated by CM-A's SPI path disable — the interrupt line `uio_out[0] = user_interrupt` at tt_wrapper.v:119 can be gated the same way if desired, but this may interfere with legitimate CPU interrupt routing on the TinyQV. Recommend leaving `uio_out[0]` ungated since the CPU needs the interrupt in production, and `uo_out` is the purely-observational side-channel.)

**Validation approach:**
- Write CONTROL[2]=1 (set LOCK). Read `uo_out` via simulation monitoring. Verify `uo_out = 0x00` regardless of `fft_busy` and `done_flag` state.
- Verify `uo_out` correctly shows status before the lock is set.

**Expected PPA impact:** Negligible — 2 AND gates on `uo_out[1:0]`.

---

## Section 2: Medium and Low Priority — Documented Only

The following threats are acknowledged but **not implemented as RTL changes** in DP3, for the reasons stated:

| Threat ID | Avg | Reason Not Fixed in RTL |
|-----------|-----|--------------------------|
| **S-01** (No MMU) | 8.0 CRIT | System architecture property of tinyQV; cannot add an MMU to a peripheral. Mitigated indirectly by all CM-A through CM-I hardening, which reduces the value of unauthorized bus access. |
| **R-01** (No audit trail) | 6.8 HIGH | Requires a hardware transaction-log register (counter + timestamp). Significant area overhead for a niche forensic requirement in an embedded accelerator. Accept: firmware should maintain software-level audit logs. |
| **R-02** (Evidence destroyed on restart) | 6.4 HIGH | Inherent in the single-register status model. Mitigation would require a "previous_done" register, adding complexity without significant security benefit. Accept. |
| **R-03** (CPU vs SPI indistinguishable) | 6.4 HIGH | CM-A (LOCK bit) distinguishes test-mode from production-mode access at the path level but does not log which path was used. Full attribution requires a source-tagging register — out of scope for DP3 area budget. |
| **S-03** (rst_n external) | 6.0 HIGH | Physical reset assertion is a system-level design property. Recommend board-level protection (reset supervisory IC with voltage monitoring) rather than RTL change. |
| **T-01** (Input register race window) | 5.8 HIGH | Exploitable only when two concurrent actors (CPU + SPI or two CPU processes) have access simultaneously. CM-A's LOCK eliminates the SPI attack vector. The CPU-CPU race requires an OS-level mutex, not RTL. Accept with documentation. |
| **T-06** (done_flag cleared by third party) | 5.8 HIGH | CM-C decouples interrupt clear from FFT start, reducing the window. Full ownership semantics require an MMU (S-01) or a per-process token system — out of scope. Accept residual risk. |
| **E-03** (Sub-word write width not enforced) | 5.8 HIGH | The only accessible registers are 16-bit wide, so an 8-bit-declared write delivering 16 bits causes no unintended state beyond the intended 16-bit write. The protocol mismatch is benign in the current register map. Document; address in a future revision. |
| **E-04** (Reserved CONTROL bits accepted) | 5.8 HIGH | CM-A adds CONTROL[2] (lock) and CM-C adds CONTROL[1] (interrupt clear), CM-D adds CONTROL[3] (error clear), consuming previously reserved bits. All new bits are defined. Remaining bits [31:4] are reserved and silently ignored — acceptable behavior per standard peripheral design practice. |
| **D-03** (Reset abort — no aborted flag) | 5.0 HIGH | CM-F's `fsm_error` provides a partial signal (will be set if reset occurs in an illegal-state path). A dedicated `aborted` flag would require reset-domain handshaking logic. Accept: firmware should use a watchdog timer for FFT completion. |
| **I-03** (DPA side-channel) | 4.2 MED | CM-B (zeroization) shortens the data lifetime in stage registers, reducing the number of post-computation traces an attacker can gather. True DPA resistance requires noise injection or algorithmic masking — out of scope for this design complexity level. Accept residual risk. |
| **D-06** (bfly_cnt glitch) | 4.0 MED | CM-F's `fsm_error` now flags illegal `bfly_cnt` values. The restart-from-zero behavior is unchanged, but firmware can now detect the event and retry. Full mitigation (e.g., TMR on bfly_cnt) would require significant area overhead. Accept with flag. |
| **T-05** (trivial_w fault injection) | 3.8 MED | Requires physical fault injection equipment. Outside the software threat model. No RTL mitigation without triple-modular redundancy on the `bfly_trivial_w` register. Accept. |
| **E-05** (ui_in undefined) | 3.4 MED | `ui_in[7:0]` is synchronized and passed to the peripheral but unused. Until a functional use is defined, it presents no attack surface beyond synchronization noise. Flag for DP4 architecture review. |

---

## Section 3: Implementation Order

Countermeasures must be implemented in the following order due to signal and logic dependencies:

```
Step 1 ── CM-G  Stage register reset initialization
           fft_8point.v only; no dependencies; simplest change
           Establishes clean power-on state foundation for all subsequent changes.

Step 2 ── CM-F  FSM hardening (default clauses + fsm_error output)
           fft_8point.v only; depends on nothing; adds fsm_error port
           Must precede CM-B because CM-B's stage zeroization lives inside
           the DONE state that CM-F also modifies (avoid merge conflicts).

Step 3 ── CM-E  Butterfly overflow saturation
           fft_8point.v only; modifies butterfly_pipelined Stage 2
           Independent of other changes; complete it while still inside
           fft_8point.v to avoid re-opening the file.

Step 4 ── CM-B  Register zeroization (stage regs in DONE + input regs in peripheral)
           fft_8point.v (DONE state) + peripheral.v (fft_done handler)
           Depends on CM-F completing the DONE state restructuring first.
           Cross-file change: complete fft_8point.v changes before opening peripheral.v.

Step 5 ── CM-C  Interrupt-clear bit (CONTROL[1])
           peripheral.v only; extends the CONTROL register decode
           Must precede CM-D because CM-D adds CONTROL[3]; define all new
           CONTROL bits in one coherent edit pass.

Step 6 ── CM-D  Bus write error flag (STATUS[2], CONTROL[3])
           peripheral.v only; extends STATUS and CONTROL register logic
           Depends on CM-C having already updated the CONTROL decode block.

Step 7 ── CM-H  Input register read-back removal
           peripheral.v only; removes read branches from always @(*)
           Independent; grouped with peripheral.v changes for efficiency.

Step 8 ── CM-A  SPI lock bit (peripheral.v register + tt_wrapper.v gate)
           peripheral.v: add spi_lock_reg, spi_lock output port, CONTROL[2] decode
           tt_wrapper.v: connect spi_lock port, gate SPI mux
           Depends on CM-C/CM-D completing the CONTROL register definition
           so that CONTROL[2] does not conflict. Must be last peripheral.v change
           because it adds a new output port (requires matching tt_wrapper update).

Step 9 ── CM-I  Output pin state masking (uo_out gating)
           peripheral.v only; one-line change to uo_out assign
           Depends on CM-A having defined spi_lock_reg.
```

**Summary by file and step:**

| Step | CM | File(s) | New signals introduced |
|------|----|---------|-----------------------|
| 1 | CM-G | fft_8point.v | (none, only reset additions) |
| 2 | CM-F | fft_8point.v | `fsm_error` output port |
| 3 | CM-E | fft_8point.v | `wide_a/b_re/im`, `ovf_*` wires |
| 4 | CM-B | fft_8point.v + peripheral.v | (none, only new assignments) |
| 5 | CM-C | peripheral.v | CONTROL[1] decode |
| 6 | CM-D | peripheral.v | `write_error` reg, STATUS[2], CONTROL[3] |
| 7 | CM-H | peripheral.v | (none, removal only) |
| 8 | CM-A | peripheral.v + tt_wrapper.v | `spi_lock_reg`, `spi_lock` output, CONTROL[2] |
| 9 | CM-I | peripheral.v | (none, one assign change) |

---

## Section 4: Regression Risk Assessment

The existing functional testbench (`src/fft_8point_tb.v`) directly instantiates `fft_8point` — it does not use `peripheral.v` or `tt_wrapper.v`. Therefore most countermeasures (CM-A, CM-C, CM-D, CM-H, CM-I) are entirely invisible to the existing testbench.

| Countermeasure | Test 1 DC | Test 2 Impulse | Test 3 Nyquist | Test 4 Sine | Test 5 Cosine | Testbench change needed? |
|----------------|-----------|----------------|-----------------|-------------|----------------|--------------------------|
| CM-G Stage reset | ✅ No impact | ✅ | ✅ | ✅ | ✅ | No — reset values are zero, same as before |
| CM-F FSM hardening | ✅ No impact | ✅ | ✅ | ✅ | ✅ | **Minor**: `fft_8point` gains `fsm_error` output port; the testbench DUT instantiation should add `.fsm_error()` (empty connection) to avoid a lint warning. Not functionally required. |
| CM-E Overflow saturation | ✅ No impact | ✅ | ✅ | ✅ | ✅ | No — test inputs (max ±8000 in Q1.15) are far below overflow threshold. Saturation logic never activates. |
| CM-B Zeroization | ✅ No impact | ✅ | ✅ | ✅ | ✅ | No — testbench does not read stage registers or input registers after computation; outputs are still correct due to non-blocking assignment semantics |
| CM-A SPI lock | N/A (tb doesn't use tt_wrapper) | N/A | N/A | N/A | N/A | No |
| CM-C Interrupt clear | N/A (tb doesn't use peripheral) | N/A | N/A | N/A | N/A | No |
| CM-D Write error flag | N/A | N/A | N/A | N/A | N/A | No |
| CM-H Read path removal | N/A | N/A | N/A | N/A | N/A | No |
| CM-I Pin masking | N/A | N/A | N/A | N/A | N/A | No |

**Required testbench change:**
Only CM-F requires a testbench update — adding the new `fsm_error` output to the DUT instantiation in `fft_8point_tb.v`. This is a one-line addition and does not affect test logic or expected output values:

```verilog
// In fft_8point_tb.v, DUT instantiation — ADD:
fft_8point dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .busy(busy),
    .done(done),
    .fsm_error(),       // ← ADD THIS LINE (unconnected; monitored in security_tb.v)
    ...
);
```

**No existing test is expected to fail** as a result of any DP3 countermeasure, provided that:
1. The zeroization in DONE state uses non-blocking assignments (guaranteed correct by Verilog semantics).
2. The overflow saturation with test inputs (max ±8000) does not activate the clamp path (arithmetic check: max DC test output = 8 × 1000 = 8000, within ±32767 — no overflow).
3. The FSM default clause change does not alter the normal five-state execution path.

---

*End of Mitigation Plan. Implement in order CM-G → CM-F → CM-E → CM-B → CM-C → CM-D → CM-H → CM-A → CM-I. Feed into: Prompts 7 (peripheral.v), 8 (fft_8point.v), 9 (tt_wrapper.v).*
