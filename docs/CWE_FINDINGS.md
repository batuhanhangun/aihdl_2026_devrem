# CWE Findings — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Inputs: src/fft_8point.v, src/peripheral.v, src/tt_wrapper.v, all docs/ | Generated: 2026-03-24*

---

## Overview

Nine hardware-relevant CWEs are evaluated against the RTL. Each finding includes applicability verdict, exact evidence from the source, cross-references to the STRIDE/CIA threat catalogue, and a concrete recommended fix.

**Verdicts used:**
- **YES** — CWE is fully and unambiguously applicable
- **PARTIAL** — CWE applies to a subset of the described pattern, or the design exhibits the root cause but not all consequences
- **NO** — CWE does not apply; design is clean for this pattern

---

## CWE-1234 · Hardware Internal or Debug Modes Allow Override of Locks

> *"The chip includes a debug or test mode that allows access that can override normal security policies."*

**Applicable: YES**

### Evidence

The `tt_um_tqv_peripheral_harness` wrapper is explicitly described in its own header comment as a test harness, yet it is synthesized unconditionally into the production netlist:

```verilog
/** TinyQV peripheral test using SPI */      // tt_wrapper.v:8
module tt_um_tqv_peripheral_harness (        // tt_wrapper.v:9
    ...
);
  // SPI access to registers
  ...
  spi_reg #(.ADDR_W(6), .REG_W(32)) i_spi_reg(    // tt_wrapper.v:82
    .clk(clk),
    .rstb(rst_reg_n),
    .ena(1'b1),                                      // tt_wrapper.v:85 — always enabled
    .spi_mosi(spi_mosi_sync),
    ...
    .reg_data_o(data_in),      // drives the peripheral's write-data bus
    .reg_addr_v(addr_valid),
    .reg_data_o_dv(data_valid),
    .reg_rw(data_rw),
    .txn_width(txn_n)
  );
```

*tt_wrapper.v:82–98*

There is no `ifdef SIMULATION` guard, no `ifdef FPGA_PROTO` guard, no lock bit, and no hardware strap. The `spi_reg` instance is enabled unconditionally (`ena(1'b1)` at line 85). On the physical chip, any entity that asserts `spi_cs_n` low (`uio_in[4]`) and clocks `spi_clk` (`uio_in[5]`) can access the full register file with no credential required.

The SPI path drives exactly the same signals (`address`, `data_in`, `data_write_n`, `data_read_n`) as the TinyQV CPU bus, so the peripheral cannot distinguish test-mode access from production-mode access. No lock register exists anywhere in `tqvp_fft8` or `fft_8point` that could restrict this path.

### Related threat IDs
`S-02`, `E-01`, `T-02`, `CIA-C-04`, `R-03`

### Recommended fix
Wrap the `spi_reg` instantiation and all SPI synchronisers in a synthesisable LOCK mechanism: add a one-time-writable `spi_lock` flip-flop (set-only, never cleared except by `rst_n`) that, when `1`, forces `data_write_n = 2'b11` and `data_read_n = 2'b11` on the SPI path, rendering all SPI transactions no-ops while leaving the CPU bus path fully functional.

---

## CWE-1231 · Improper Prevention of Lock Bit Modification

> *"The product uses a trusted lock bit for restricting access, but the lock bit can be set or cleared without properly verifying the requester's identity."*

**Applicable: PARTIAL**

### Evidence

This CWE assumes a lock bit exists and is improperly protected. In our design the situation is more fundamental: **no lock bit exists at all** for the SPI test path (CWE-1234 above). However, there is one pseudo-lock mechanism in the design — the `input_reg_wr_en` clock-gate that blocks input register writes while the FFT is busy:

```verilog
// [DP2] Clock gating: only allow input register writes when FFT is NOT busy
wire input_reg_wr_en = write_active & ~fft_busy;   // peripheral.v:119
```

*peripheral.v:119*

This acts as a one-bit "computation lock" on the input registers. It is asserted by hardware (`fft_busy` from the FFT core's state machine) and cannot be overridden by writing any register. However:

1. The lock applies **only to writes via the peripheral bus**. It has no effect on SPI reads of input registers (peripheral.v:174–183 unconditionally return input values on any read, regardless of `fft_busy`).
2. The lock applies **only to input registers**. The CONTROL register explicitly bypasses it: `// Control register (always writable)` at peripheral.v:153 — writes to CONTROL proceed regardless of `fft_busy`, with only the start-pulse gated by `!fft_busy` (peripheral.v:155).
3. There is no software-configurable lock for the SPI debug path, meaning the most important lock (against unauthenticated SPI access) is entirely absent.

CWE-1231 PARTIAL: the one lock that exists (`input_reg_wr_en`) is correctly implemented in hardware and cannot be modified by software — but its scope is narrow, and the more critical SPI-path lock does not exist.

### Related threat IDs
`S-02`, `E-01`, `T-01`, `T-02`, `CIA-I-03`, `CIA-C-04`

### Recommended fix
Implement the `spi_lock` flip-flop described in CWE-1234. Make it set-only (once written `1`, it stays `1` until `rst_n`) so it cannot be cleared by any bus master or SPI transaction — this satisfies the "requester identity verification" requirement by making the lock irrevocable within a power cycle.

---

## CWE-1239 · Improper Zeroization of Hardware Register

> *"The product does not properly zeroize data in a hardware register, allowing sensitive data to persist into subsequent operations."*

**Applicable: YES**

### Evidence

Four distinct register groups fail to be zeroized at the appropriate lifecycle boundary:

**1. FFT output registers — not cleared after computation completes**

The reset block (fft_8point.v:149–156) zeroes the output registers on `rst_n`, but the DONE state (fft_8point.v:384–398) that writes results to them never clears them afterward:

```verilog
DONE: begin
    out_real_0 <= stage_real[0]; out_imag_0 <= stage_imag[0];  // fft_8point.v:386
    // ... (copies results, but never zeroes after)
    done <= 1'b1;
    busy <= 1'b0;
    state <= IDLE;   // fft_8point.v:397 — returns to IDLE, outputs still hold results
end
```

*fft_8point.v:384–398*

After this transition, any subsequent bus master can read the complete FFT result.

**2. Input sample registers — not cleared after computation completes**

The peripheral reset clears them (peripheral.v:127–130), but the write logic never clears them on FFT completion:

```verilog
for (i = 0; i < 8; i = i + 1) begin
    in_real[i] <= 16'd0;   // peripheral.v:128 — reset only
    in_imag[i] <= 16'd0;   // peripheral.v:129 — reset only
end
```

*peripheral.v:127–130*

After an FFT completes, `in_real[0:7]` and `in_imag[0:7]` retain the original input samples indefinitely and are readable via the bus (peripheral.v:174–183) and via SPI.

**3. Stage working registers — no reset clause at all**

```verilog
reg signed [15:0] stage_real [0:7];   // fft_8point.v:70
reg signed [15:0] stage_imag [0:7];   // fft_8point.v:71
```

*fft_8point.v:70–71*

The reset block at fft_8point.v:141–157 contains explicit assignments for every other register but has no assignment for `stage_real` or `stage_imag`. At power-on, these 256 bits hold indeterminate silicon values. After computation, they retain the Stage 3 output values (identical to the FFT results) indefinitely.

**4. Butterfly pipeline registers — cleared on reset but not after DONE**

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_a_re  <= 16'sd0;    // fft_8point.v:459 — reset only
        pipe_a_im  <= 16'sd0;
        pipe_bw_re <= 16'sd0;
        pipe_bw_im <= 16'sd0;
        valid_out  <= 1'b0;
    end else begin
        pipe_a_re  <= a_re;      // fft_8point.v:465 — retains last butterfly values
        ...
    end
end
```

*fft_8point.v:457–471*

After the FSM returns to IDLE, the pipeline registers hold the last values from the final butterfly of Stage 3 — partial intermediate products of the last computation.

### Related threat IDs
`CIA-C-01`, `CIA-C-02`, `CIA-C-03`, `CIA-C-05`, `I-01`, `I-02`, `I-03`, `I-04`

### Recommended fix
Add explicit zeroization at the end of the DONE state: (a) clear `stage_real/imag` after copying to output registers; (b) clear `in_real/imag` in the peripheral's `fft_done` handler (after samples are already in stage registers); (c) add a `stage_real/imag` reset clause in the fft_8point reset block.

---

## CWE-1271 · Uninitialized Value on Reset

> *"Registers in a hardware design do not have proper reset values, potentially leading to indeterminate state after reset."*

**Applicable: YES**

### Evidence

The stage working registers (`stage_real[0:7]`, `stage_imag[0:7]`) are entirely absent from the reset block. Comparing the reset block against every register declaration confirms the omission:

```verilog
// What IS reset-initialised (fft_8point.v:141-157):
state     <= IDLE;
busy      <= 1'b0;
done      <= 1'b0;
bfly_cnt  <= 4'd0;
bfly_trivial_w <= 1'b0;
out_real_0 <= 16'd0; ... out_real_7 <= 16'd0;
out_imag_0 <= 16'd0; ... out_imag_7 <= 16'd0;

// What is NOT reset-initialised:
// stage_real[0:7]  ← MISSING (declared at fft_8point.v:70)
// stage_imag[0:7]  ← MISSING (declared at fft_8point.v:71)
// bfly_a_re, bfly_a_im  ← MISSING (declared at fft_8point.v:85-87)
// bfly_b_re, bfly_b_im
// bfly_w_re, bfly_w_im
```

*fft_8point.v:141–157 vs fft_8point.v:70–71, 85–87*

Additionally, `bfly_a_re`, `bfly_a_im`, `bfly_b_re`, `bfly_b_im`, `bfly_w_re`, `bfly_w_im` (fft_8point.v:85–87) have no reset assignments. These are written in the first active clock cycle of STAGE1 before they are read by the butterfly unit, so they do not affect functional correctness in normal operation. However, between `rst_n` deassertion and the first `start` pulse, they hold indeterminate values and drive the operand-isolation mux inputs. Since `bfly_active = (state != IDLE)` is false immediately after reset, the isolation mux forces zeroes to the butterfly unit — so no functional issue arises. But if the isolation mux were ever removed or its condition changed, these uninitialised registers would propagate.

The `stage_real/imag` gap is the more serious instance: these are both input-latching registers AND computation working registers. In silicon at power-on, before any FFT is run, these 256 bits contain process-dependent random values with no guaranteed reset to zero.

### Related threat IDs
`CIA-A-02`, `I-03`, `D-01`

### Recommended fix
Add `for (i=0; i<8; i=i+1) begin stage_real[i] <= 16'sd0; stage_imag[i] <= 16'sd0; end` inside the `if (!rst_n)` block of fft_8point.v, and add explicit reset assignments for `bfly_a_re/im`, `bfly_b_re/im`, `bfly_w_re/im` for completeness.

---

## CWE-1280 · Access Control Check Implemented After Asset Is Accessed

> *"The hardware product performs an access control check after the asset has already been accessed, creating a window in which unauthorized access can occur."*

**Applicable: PARTIAL**

### Evidence

The primary instance is the INPUT_REAL and INPUT_IMAG registers. These registers are described as write-only in the register map documentation, yet the combinational read path in `peripheral.v` returns their values with no access control check:

```verilog
always @(*) begin
    data_out = 32'd0;
    if (read_active) begin
        // Input Real registers (for verification)        ← peripheral.v:173
        if (word_addr >= ADDR_IN_REAL_BASE && word_addr < ADDR_IN_REAL_BASE + 8) begin
            data_out = {{16{in_real[word_addr - ADDR_IN_REAL_BASE][15]}},
                        in_real[word_addr - ADDR_IN_REAL_BASE]};   // peripheral.v:175-176
        end
        // Input Imag registers (for verification)        ← peripheral.v:178
        else if (word_addr >= ADDR_IN_IMAG_BASE && word_addr < ADDR_IN_IMAG_BASE + 8) begin
            data_out = {{16{in_imag[word_addr - ADDR_IN_IMAG_BASE][15]}},
                        in_imag[word_addr - ADDR_IN_IMAG_BASE]};   // peripheral.v:181-182
        end
```

*peripheral.v:169–201*

The asset (input sample data in `in_real[0:7]` and `in_imag[0:7]`) is returned to the read bus with no check on:
- Whether the requester is the same entity that wrote the samples
- Whether `fft_busy` is active (samples are "in use" but still readable)
- Whether a "read-back enable" mode flag is set

The comment `// for verification` suggests this read path was added as a debug aid and was never gated behind any authorisation condition.

A secondary partial instance exists in the write path. The check `!fft_busy` (peripheral.v:155) that gates the CONTROL start pulse is evaluated after `write_active` is already true and after the overall write block has been entered — but the CONTROL register state itself has not yet been modified by this write, so no intermediate access to the asset occurs. This is not a classic post-access-check pattern.

CWE-1280 is PARTIAL rather than YES because the input register read exposure is a deliberate architectural choice ("for verification") rather than a control-flow ordering error, and the write path ordering is correct.

### Related threat IDs
`CIA-C-05`, `CIA-I-03`, `I-02`, `E-02`

### Recommended fix
Remove or gate the input register read path behind a mode condition: either delete the `INPUT_REAL`/`INPUT_IMAG` read branches entirely (making them truly write-only) or guard them with a `debug_mode` status bit that is only set when the SPI LOCK is inactive (i.e., readable only in test mode, not production).

---

## CWE-1272 · Sensitive Information Uncleared Before Debug/Power State Transition

> *"The product does not properly clear sensitive information before a transition to a different state (debug, power-off, etc.), making that information available to unintended actors."*

**Applicable: YES**

### Evidence

Three state transitions expose sensitive data:

**Transition 1: DONE → IDLE (computation-to-idle)**

When the FSM returns from DONE to IDLE (fft_8point.v:397), neither the stage working registers nor the peripheral input registers are cleared:

```verilog
DONE: begin
    out_real_0 <= stage_real[0]; ...   // fft_8point.v:386 — results copied out
    done  <= 1'b1;
    busy  <= 1'b0;
    state <= IDLE;                      // fft_8point.v:397 — IDLE but data remains
end
// stage_real[0:7] still = Stage3 output values
// in_real[0:7] still = original input samples (in peripheral.v)
```

*fft_8point.v:384–398, peripheral.v:64–65*

**Transition 2: COMPUTING → RESET (mid-computation reset assertion)**

When `rst_n` is asserted during computation, the output registers are cleared (fft_8point.v:149–156) and input registers are cleared (peripheral.v:127–130), but `stage_real/imag` have no reset clause and retain whatever partial butterfly results were computed before reset:

```verilog
if (!rst_n) begin
    state <= IDLE;
    busy  <= 1'b0;
    done  <= 1'b0;
    // out_real_0 ... out_real_7 <= 16'd0;  ← cleared ✓
    // in_real[0:7] <= 16'd0;               ← cleared ✓ (in peripheral.v)
    // stage_real[0:7] ← NOT CLEARED        ← indeterminate after reset ✗
end
```

*fft_8point.v:141–157 (absence of stage_real/imag)*

**Transition 3: Activation of SPI Debug Path (idle → SPI-accessed)**

The "debug state transition" in this design is the activation of the SPI test harness — any moment when an external entity drives `spi_cs_n` low. At that instant, the full contents of INPUT_REAL, INPUT_IMAG, OUTPUT_REAL, and OUTPUT_IMAG are readable via the SPI bus with no notification to the CPU and no clearing of sensitive data before the debug session begins:

```verilog
assign spi_cs_n = uio_in[4];          // tt_wrapper.v:73 — always live
// No "pre-debug clear" logic exists anywhere in the design
```

*tt_wrapper.v:73–79*

### Related threat IDs
`CIA-C-01`, `CIA-C-02`, `CIA-C-05`, `CIA-A-02`, `CIA-A-03`, `I-01`, `I-02`, `I-03`

### Recommended fix
(a) Clear `stage_real/imag` at the end of the DONE state after copying results, and add a reset clause for them; (b) Clear `in_real/imag` in the peripheral on the `fft_done` pulse; (c) The SPI-access transition can be addressed by the LOCK mechanism from CWE-1234 — when locked, the SPI path sees only zeros regardless of actual register content.

---

## CWE-1262 · Improper Access Control for Register Interface

> *"The product does not properly restrict read/write access to system registers, allowing unintended functionality or access to sensitive data."*

**Applicable: YES**

### Evidence

Multiple access control failures exist across the register interface:

**1. No authentication on the SPI register access path**

```verilog
spi_reg #(.ADDR_W(6), .REG_W(32)) i_spi_reg(
    .ena(1'b1),                // tt_wrapper.v:85 — permanently enabled
    ...
    .reg_data_o(data_in),      // tt_wrapper.v:92 — drives peripheral write data
    .reg_data_o_dv(data_valid),
    .reg_rw(data_rw),
    .txn_width(txn_n)
);
```

*tt_wrapper.v:82–98*

Any physical actor driving `uio_in[4:6]` has unconditional full read/write access to all 18 registers.

**2. Input registers readable without restriction despite write-only intent**

```verilog
// Input Real registers (for verification)       ← peripheral.v:173
if (word_addr >= ADDR_IN_REAL_BASE && ...) begin
    data_out = { {16{in_real[...][15]}}, in_real[...] };  // peripheral.v:175-176
end
```

*peripheral.v:173–183*

No `read_permitted` check; any bus master reads raw input sample data.

**3. CONTROL register writable with no ownership or privilege check**

```verilog
// Control register (always writable)            ← peripheral.v:153
if (word_addr == ADDR_CONTROL) begin
    if (data_in[0] && !fft_busy) begin
        fft_start <= 1'b1;
        done_flag <= 1'b0;
    end
end
```

*peripheral.v:153–159*

Any bus master — including any software process given the absence of an MMU — can trigger an FFT computation or clear the done flag. No owner ID, no privilege level, no token.

**4. Writes to read-only and unmapped addresses silently accepted**

```verilog
wire write_active = (data_write_n != 2'b11);   // peripheral.v:115
// Write decode handles only IN_REAL, IN_IMAG, CONTROL.
// Writes to STATUS (read-only), OUTPUT_REAL, OUTPUT_IMAG,
// and all addresses > 0x21 fall through with no error.
```

*peripheral.v:115, 139–160*

The absence of an `else begin data_error <= 1'b1; end` clause means every out-of-range or read-only write silently succeeds from the master's perspective.

**5. Sub-word write width not enforced**

```verilog
wire write_active = (data_write_n != 2'b11);   // peripheral.v:115
// 2'b00 (8-bit), 2'b01 (16-bit), 2'b10 (32-bit) all treated identically
```

*peripheral.v:115*

An 8-bit-declared write transaction (`data_write_n=2'b00`) delivers and applies `data_in[15:0]` identically to a 32-bit write, violating the principle of minimum necessary access.

### Related threat IDs
`S-01`, `S-02`, `E-01`, `E-02`, `E-03`, `CIA-C-04`, `CIA-C-05`, `CIA-I-01`, `CIA-I-06`

### Recommended fix
Implement layered access control: (a) SPI LOCK bit gates entire SPI path; (b) remove or gate INPUT_REAL/IMAG read path; (c) add a `bus_error` output flag for writes to read-only or unmapped addresses; (d) add a width-check that enforces `data_write_n` encoding at the point of register capture.

---

## CWE-1245 · Improper Finite State Machines (FSMs) in Hardware Logic

> *"The product implements an FSM that does not properly handle transitions between states, which can lead to undefined or insecure behavior."*

**Applicable: YES**

### Evidence

Two FSM-level defects exist:

**Defect 1: Default state recovery does not clear `busy` — permanent deadlock**

The main state register is 3 bits wide (fft_8point.v:64), yielding 8 encodings of which only 5 (IDLE=0, STAGE1=1, STAGE2=2, STAGE3=3, DONE=4) are defined. The default recovery clause:

```verilog
default: state <= IDLE;    // fft_8point.v:400
```

*fft_8point.v:398–401*

forces the FSM back to IDLE but does NOT clear `busy` (which was set to `1'b1` when STAGE1 was entered at fft_8point.v:164). Entering any illegal state (3'd5–3'd7) while computing produces a deadlock: `state=IDLE` with `busy=1`. Since `fft_start` requires `!fft_busy` (peripheral.v:155), no new computation can ever be started without a hard reset. Critically, no error output is asserted — the FSM silently deadlocks.

```verilog
IDLE: begin
    if (start) begin
        busy <= 1'b1;       // fft_8point.v:164 — set on entry to STAGE1
        state <= STAGE1;
    end
end
// ... (no other place busy is set to 1)

DONE: begin
    busy <= 1'b0;           // fft_8point.v:396 — only cleared here
    state <= IDLE;
end

default: state <= IDLE;     // fft_8point.v:400 — missing: busy <= 1'b0
```

*fft_8point.v:162–401*

**Defect 2: `bfly_cnt` default recovery silently re-executes current butterfly**

The sub-state counter `bfly_cnt` is 4 bits (fft_8point.v:135) covering values 0–8; values 9–15 are illegal. Each stage has a default clause:

```verilog
default: bfly_cnt <= 4'd0;  // STAGE1: fft_8point.v:246
default: bfly_cnt <= 4'd0;  // STAGE2: fft_8point.v:313
default: bfly_cnt <= 4'd0;  // STAGE3: fft_8point.v:380
```

*fft_8point.v:246, 313, 380*

Resetting `bfly_cnt` to 0 re-executes butterfly 0 of the current stage, overwriting `stage_real[0]`, `stage_real[1]` and their imaginary counterparts with results computed from the already-partially-modified stage registers. The DONE state is still reached and `done=1` is asserted — the firmware receives a completion signal for a numerically incorrect result with no error indication.

**Additional FSM integrity concern: `valid_out` not used to gate STORE operations**

The `butterfly_pipelined` module asserts `valid_out` (fft_8point.v:104) one cycle after `valid_in`, signaling that output data is valid:

```verilog
wire bfly_out_valid;         // fft_8point.v:104
.valid_out(bfly_out_valid)   // fft_8point.v:125
```

*fft_8point.v:104, 125*

However, the main FSM's STORE sub-states (`bfly_cnt` == 2, 4, 6, 8) read `bfly_out_a_re`/`bfly_out_b_re` without checking `bfly_out_valid`. The FSM relies on fixed cycle counting rather than handshaking. If `valid_out` ever fails to assert at the expected cycle (e.g., due to a fault event that resets `valid_out` mid-computation), the FSM stores whatever combinational value is on the butterfly output wires — which may be invalid — and proceeds to DONE, asserting completion.

### Related threat IDs
`CIA-A-01`, `CIA-A-05`, `D-01`, `D-06`, `T-05`

### Recommended fix
(a) Add `busy <= 1'b0; done <= 1'b0;` to the `default` state recovery clause; (b) add an `fsm_error` output register that is set in the `default` case and in the `bfly_cnt` default cases, giving firmware a status flag to poll; (c) optionally gate STORE sub-states on `bfly_out_valid` rather than relying on fixed timing.

---

## CWE-1276 · Hardware Child Block Has Missing Bus Signal

> *"A hardware child block is missing a connection to a parent bus signal, causing undefined or incorrect behavior."*

**Applicable: PARTIAL**

### Evidence

The `butterfly_pipelined` submodule produces a `valid_out` handshake signal designed to indicate when its pipeline output is ready to be consumed:

```verilog
// In butterfly_pipelined port list:
output reg valid_out              // fft_8point.v:434

// In fft_8point, the connection is made:
wire bfly_out_valid;              // fft_8point.v:104 — wire declared
...
butterfly_pipelined bfly_unit (
    ...
    .valid_out(bfly_out_valid)    // fft_8point.v:125 — signal connected
);
```

*fft_8point.v:104, 109–125*

The signal is declared and connected at the instantiation level — so this is not a missing *port* connection. However, `bfly_out_valid` is **never read or used** anywhere in the `fft_8point` main state machine (fft_8point.v:139–401). A search for `bfly_out_valid` beyond line 125 finds zero references. The intended handshake between the pipeline and the state machine is broken: the pipeline asserts "my output is valid" and the state machine ignores it entirely.

```verilog
// STORE sub-state (fft_8point.v:200-209, typical):
4'd2: begin
    stage_real[0] <= bfly_out_a_re;   // reads pipeline output
    stage_real[1] <= bfly_out_b_re;
    // bfly_out_valid is NOT checked here — timing assumed from bfly_cnt
    ...
end
```

*fft_8point.v:200–209 (representative STORE state)*

The consequence is that the datapath relies entirely on the fixed-cycle-count assumption embedded in `bfly_cnt` rather than on the actual pipeline readiness signal. This creates a latent fragility: any future change to the pipeline depth (e.g., adding a third stage, inserting a hold cycle for power management) would require updating the FSM cycle counts, but the `valid_out` signal would not automatically flag the mismatch.

CWE-1276 is PARTIAL rather than YES because the signal *is* physically connected (wire present, port bound); the defect is that the consumer side of the handshake is unimplemented — effectively a one-sided bus connection.

A secondary observation: the `tqvp_fft8` peripheral has no `bus_error` output signal. The TinyQV peripheral bus protocol (as seen from `data_write_n`, `data_read_n`, `data_ready`) does not appear to define an error signal, so this may not constitute a missing bus signal per the protocol spec — but its absence amplifies every silent-failure scenario documented in CWE-1262.

### Related threat IDs
`CIA-A-05`, `D-06`, `CIA-I-06`

### Recommended fix
Gate every STORE sub-state on `bfly_out_valid`: `if (bfly_out_valid) begin stage_real[...] <= bfly_out_a_re; ... end` — replacing the implicit fixed-timing assumption with an explicit handshake. This makes the design robust to future pipeline depth changes and eliminates the latent FSM-pipeline decoupling risk.

---

## Summary Table

| CWE ID | Title | Verdict | Severity | Key Location | Fix Prompts |
|--------|-------|---------|----------|-------------|-------------|
| CWE-1234 | Debug Mode Overrides Locks | **YES** | High | tt_wrapper.v:82–98 | Prompt 9 |
| CWE-1231 | Improper Lock Bit Prevention | **PARTIAL** | Medium | peripheral.v:119, 153 | Prompt 9 |
| CWE-1239 | Improper Register Zeroization | **YES** | High | fft_8point.v:70–71, 384–398 | Prompts 7, 8 |
| CWE-1271 | Uninitialized Value on Reset | **YES** | Medium | fft_8point.v:70–71, 85–87 | Prompt 8 |
| CWE-1280 | Access Check After Asset Access | **PARTIAL** | Medium | peripheral.v:173–183 | Prompt 7 |
| CWE-1272 | Sensitive Info Uncleared on Transition | **YES** | High | fft_8point.v:397, peripheral.v:64–65 | Prompts 7, 8 |
| CWE-1262 | Improper Register Access Control | **YES** | High | peripheral.v:115, 153–159, tt_wrapper.v:85 | Prompts 7, 9 |
| CWE-1245 | Improper FSM Implementation | **YES** | Critical | fft_8point.v:400, 246, 313, 380 | Prompt 8 |
| CWE-1276 | Missing Child Block Bus Signal | **PARTIAL** | Medium | fft_8point.v:104, 125 (unused valid_out) | Prompt 8 |

**Fully applicable (YES): 5 of 9 CWEs**
**Partially applicable (PARTIAL): 4 of 9 CWEs**
**Not applicable (NO): 0 of 9 CWEs**

---

*End of CWE Findings. Feed into: docs/MITIGATION_PLAN.md (Prompt 6).*
