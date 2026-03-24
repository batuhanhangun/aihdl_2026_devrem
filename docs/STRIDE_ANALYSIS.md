# STRIDE Threat Model — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Inputs: docs/ATTACK_SURFACE_MAP.md, docs/CIA_ANALYSIS.md | Generated: 2026-03-24*

---

## Overview

STRIDE is applied at the RTL level against the actual signal paths, state transitions, and trust boundaries identified in the Attack Surface Map. Each threat is grounded in specific Verilog behavior — not generic software patterns.

**STRIDE categories:**
- **S** — Spoofing (false identity)
- **T** — Tampering (unauthorized data modification)
- **R** — Repudiation (deniability of actions)
- **I** — Information Disclosure (data leakage)
- **D** — Denial of Service (availability degradation)
- **E** — Elevation of Privilege (exceeding authorized access)

Severity: **Critical / High / Medium / Low**

---

## S — Spoofing

### S-01 · No Process Isolation: Any Code Can Access the FFT Peripheral
**Category:** Spoofing
**Severity:** High

**Attack scenario:**
TinyQV has no Memory Management Unit (MMU) and no hardware privilege separation between user-mode and kernel-mode code. Any piece of software executing on the core — including untrusted application code, a malicious library, or a compromised interrupt handler — can issue bus transactions to the FFT peripheral address range (0x00–0x84) with equal authority to privileged firmware. A rogue process can read FFT results belonging to another process's computation, overwrite input registers, or trigger FFT computations, all without any hardware check.

**Affected module/signals:**
- `address[5:0]`, `data_write_n[1:0]` — peripheral.v:30,42 (no requester identity information)
- TinyQV system bus — no MMU or peripheral firewall present

**CIA cross-reference:** CIA-C-01 (stale outputs), CIA-C-05 (input readback), CIA-I-03 (silent write block)

---

### S-02 · SPI Test Harness Provides an Alternate Identity-Less Access Path
**Category:** Spoofing
**Severity:** High

**Attack scenario:**
The production-synthesized SPI harness (`spi_reg` instance at tt_wrapper.v:82–98) gives any entity with physical access to `uio_in[4:6]` the ability to initiate bus transactions that are indistinguishable from legitimate CPU transactions at the peripheral level. The `tqvp_fft8` peripheral receives `address`, `data_in`, `data_write_n`, and `data_read_n` signals regardless of whether they originated from the CPU or the SPI decoder — there is no "source" tag on any bus signal. An attacker driving the SPI pins can impersonate the CPU as the bus master for all FFT register accesses.

**Affected module/signals:**
- `spi_mosi` (`uio_in[6]`), `spi_cs_n` (`uio_in[4]`), `spi_clk` (`uio_in[5]`) — tt_wrapper.v:73–75
- `spi_reg` → `address`, `data_in`, `data_write_n` — tt_wrapper.v:82–98
- Peripheral has no origin field: peripheral.v:30–43

**CIA cross-reference:** CIA-C-04 (unauthenticated SPI access)

---

### S-03 · Peripheral Cannot Verify That `rst_n` Is a Legitimate System Reset
**Category:** Spoofing
**Severity:** Low

**Attack scenario:**
The `rst_n` pin (tt_wrapper.v:18) is an external physical pad with no authentication. An attacker with physical access can assert a momentary `rst_n` pulse to force the peripheral to IDLE, clearing `busy`, `done_flag`, and all output registers — mimicking a legitimate power-on reset. From the peripheral's perspective, this is indistinguishable from a system reset. If the CPU is not also reset, it may be left in a state where it is waiting for `done_flag` that will never arrive, while the peripheral has already re-initialized.

**Affected module/signals:**
- `rst_n` — tt_wrapper.v:18, fft_8point.v:140, peripheral.v:123
- `rst_reg_n` (negedge-registered): tt_wrapper.v:35–37

**CIA cross-reference:** CIA-A-03 (abort without signal)

---

## T — Tampering

### T-01 · Input Registers Writable Between Loading and Start — Race Window
**Category:** Tampering
**Severity:** Medium

**Attack scenario:**
In a multi-process scenario (possible since TinyQV has no MMU — see S-01), Process A writes FFT input samples to INPUT_REAL and INPUT_IMAG registers and is then preempted before writing CONTROL=1. Process B (or an SPI master) then overwrites some or all of those input registers with different values. When Process A resumes and writes CONTROL=1, the FFT computes on the tampered inputs without any indication that substitution occurred. The result is attributed to Process A's computation but reflects Process B's data.

**Affected module/signals:**
- `in_real[0:7]`, `in_imag[0:7]` — peripheral.v:64–65 (writable while busy=0)
- `input_reg_wr_en` — peripheral.v:119 (only protects against writes while busy=1, not between-load tampering)
- `fft_start` generation — peripheral.v:155–157

**CIA cross-reference:** CIA-I-03 (write blocking), CIA-I-06 (no error return)

---

### T-02 · CONTROL Register Writable via SPI — Computation Can Be Triggered or Aborted Without CPU Involvement
**Category:** Tampering
**Severity:** High

**Attack scenario:**
The SPI harness (tt_wrapper.v:82–98) has full write access to the CONTROL register (word addr 0x10). An attacker with physical access to the SPI pins can write CONTROL=1 at any time when `fft_busy=0`, triggering an FFT computation using whatever values currently reside in the INPUT_REAL and INPUT_IMAG registers. This can be used to: (1) trigger unauthorized computations, (2) consume the peripheral while the CPU is trying to use it, or (3) force a computation with adversarially controlled inputs if the attacker first writes INPUT registers and then writes CONTROL — all without the CPU's knowledge or participation.

**Affected module/signals:**
- CONTROL register write: peripheral.v:154–159
- `fft_start` pulse: peripheral.v:156
- `done_flag` cleared: peripheral.v:157
- SPI write path: tt_wrapper.v:104–106

**CIA cross-reference:** CIA-C-04 (SPI unauthenticated access), CIA-A-04 (interrupt manipulation)

---

### T-03 · Output Registers Are Physically Write-Protected (Strength — Documented)
**Category:** Tampering
**Severity:** None (design strength)

**Attack scenario:**
Software attempting to forge FFT results by writing to OUTPUT_REAL or OUTPUT_IMAG addresses (word addr 0x12–0x21) will find the writes silently discarded. The output registers are implemented as `wire` declarations in peripheral.v (lines 78–79) driven directly by the FFT core's registered outputs — they have no write path from the bus side. This is a structural write-protection that cannot be circumvented by software.

**Affected module/signals:**
- `out_real[0:7]`, `out_imag[0:7]` — peripheral.v:78–79 (wire, no bus write path)
- Write decode: peripheral.v:139–160 (no output register branch)

**CIA cross-reference:** CIA-I-01 (silent discard, no error)
**Note:** This is a design strength. The write-protection is reliable; the only weakness is the absence of a bus error signal confirming protection is active.

---

### T-04 · Twiddle Factor Constants Are ROM-Equivalent — Cannot Be Tampered at Runtime
**Category:** Tampering
**Severity:** None (design strength)

**Attack scenario:**
The four twiddle factors W₈⁰–W₈³ are implemented as `localparam` constants (fft_8point.v:46–53). They are synthesized as constants in the netlist — not as registers or ROM cells accessible via the bus. An attacker cannot modify twiddle factor values through any bus transaction, SPI access, or software path.

**Affected module/signals:**
- `W0_RE`, `W0_IM`, `W1_RE`, `W1_IM`, `W2_RE`, `W2_IM`, `W3_RE`, `W3_IM` — fft_8point.v:46–53

**CIA cross-reference:** None
**Note:** Design strength. If the chip were subject to focused ion beam (FIB) attack, these constants could potentially be modified at the silicon level, but that is outside the software/bus threat model.

---

### T-05 · `bfly_trivial_w` Flag Can Influence Whether Multiplication Is Bypassed
**Category:** Tampering
**Severity:** Low

**Attack scenario:**
The `bfly_trivial_w` flag (fft_8point.v:90) controls whether the butterfly unit performs a full complex multiplication or simply passes `b` through as `b×W⁰=b`. This flag is set by the main FSM state machine based on which twiddle factor applies to the current butterfly. It is not bus-accessible. However, any fault injection that flips this flag from `1'b0` to `1'b1` during a Stage 2 or Stage 3 butterfly (which should use W² or W³) would cause the multiplication to be bypassed silently, producing a wrong result with no error signal. The `bfly_triv_iso` operand isolation mux (fft_8point.v:99) zeroes this when idle, but has no effect during active computation.

**Affected module/signals:**
- `bfly_trivial_w` — fft_8point.v:90
- `bfly_triv_iso` — fft_8point.v:99
- `butterfly_pipelined.trivial_w` mux — fft_8point.v:450–451

**CIA cross-reference:** CIA-A-05 (bfly_cnt default recovery)
**Note:** Not software-exploitable; requires fault injection. Included for completeness.

---

### T-06 · `done_flag` Can Be Cleared by a Third Party Before the Owning Process Reads It
**Category:** Tampering
**Severity:** Medium

**Attack scenario:**
After an FFT computation completes, `done_flag=1` is the only signal the owning firmware process has to confirm computation completion. Since TinyQV has no MMU (S-01) and the SPI harness has full write access (S-02), any third party can write CONTROL=1 (which clears `done_flag` and starts a new computation) before the owning process has had a chance to read results and acknowledge completion. The owning process loses its completion acknowledgment, may miss its results window, and the peripheral immediately begins a new computation with unknown inputs (the input registers were not updated before the rogue CONTROL write).

**Affected module/signals:**
- `done_flag` cleared: peripheral.v:157
- `fft_start` generated simultaneously: peripheral.v:156
- No ownership token on computations

**CIA cross-reference:** CIA-A-04 (interrupt clear), CIA-A-06 (rapid CONTROL writes), CIA-I-02 (CONTROL during busy)

---

## R — Repudiation

### R-01 · No Audit Trail of Computation Initiators
**Category:** Repudiation
**Severity:** Medium

**Attack scenario:**
The FFT peripheral has no mechanism for recording which bus master or SPI transaction triggered a computation. The `fft_start` pulse (peripheral.v:156) is generated identically whether it originated from CPU firmware, a buggy interrupt handler, a malicious application process, or an external SPI master. After the FFT completes, there is no log entry, no transaction ID, no timestamp, and no initiator field in any status register. An attacker who triggers unauthorized computations, reads the results via SPI, and then allows the system to continue cannot be detected or attributed after the fact.

**Affected module/signals:**
- `fft_start` — peripheral.v:156 (single-bit pulse, no source tagging)
- `done_flag` — peripheral.v:73 (cleared on next start, no history)
- No `initiator_id` or `transaction_log` register exists

**CIA cross-reference:** CIA-C-04 (SPI access), CIA-C-01 (stale results)

---

### R-02 · Clearing `done_flag` Destroys Evidence of Completion
**Category:** Repudiation
**Severity:** Low

**Attack scenario:**
The `done_flag` bit in the STATUS register (peripheral.v:187) is the only record that a computation completed. It is cleared atomically when a new computation is started (peripheral.v:157). There is no "previous completion" bit, no completion counter, and no way to determine after a second FFT has been triggered whether the first completed normally or was interrupted by reset. If an attacker triggers a second computation immediately after the first, any evidence that the first computation completed (including its results, which are overwritten in DONE state) is destroyed without trace.

**Affected module/signals:**
- `done_flag`: peripheral.v:73 (cleared at peripheral.v:157)
- Output registers: fft_8point.v:386–393 (overwritten on each DONE)

**CIA cross-reference:** CIA-A-04 (interrupt clear coupling)

---

### R-03 · CPU vs. SPI Transactions Are Indistinguishable at the Peripheral
**Category:** Repudiation
**Severity:** Medium

**Attack scenario:**
The `tqvp_fft8` peripheral receives `address`, `data_in`, `data_write_n`, and `data_read_n` signals without any source identifier. Both the TinyQV CPU bus path and the SPI harness path (tt_wrapper.v:100–113) produce exactly the same signal types. There is no "CPU transaction" bit and no "SPI transaction" bit in any register. If a forensic investigation asks "did the CPU or the SPI master trigger this computation?", the RTL provides no answer — all transactions are repudiable by both parties.

**Affected module/signals:**
- Bus interface: peripheral.v:30–43 (no source field)
- SPI path: tt_wrapper.v:100–113 (drives same signals as CPU)
- `fft_start`: peripheral.v:156 (one bit, no context)

**CIA cross-reference:** CIA-C-04 (SPI path), R-01

---

## I — Information Disclosure

### I-01 · FFT Output Registers Hold Stale Results Until Next Computation
**Category:** Information Disclosure
**Severity:** High

**Attack scenario:**
After an FFT completes, the 16 output registers (`out_real_0`–`out_real_7`, `out_imag_0`–`out_imag_7`) retain the computed values indefinitely — they are only updated in the next DONE state and cleared only on `rst_n` assertion (fft_8point.v:149–156). Any bus master, including one that did not perform or initiate the computation, can read the full complex FFT output at any time by accessing OUTPUT_REAL and OUTPUT_IMAG. In a shared embedded system, this means Process B can read Process A's FFT output data without synchronization or authorization.

**Affected module/signals:**
- `out_real_0`–`out_real_7`, `out_imag_0`–`out_imag_7` — fft_8point.v:31–34
- DONE update: fft_8point.v:386–393
- Read path: peripheral.v:191–199

**CIA cross-reference:** CIA-C-01

---

### I-02 · Input Sample Registers Are Readable After Being Written — Persistent Input Exposure
**Category:** Information Disclosure
**Severity:** Medium

**Attack scenario:**
The INPUT_REAL and INPUT_IMAG registers (peripheral.v:64–65) are read back via the combinational read path (peripheral.v:174–183), despite being documented as write-only. After a process writes its input samples and triggers an FFT, those same sample values remain in the input registers: they are not cleared on FFT start (the FFT reads from them at start but does not zero them) and not cleared on FFT completion. A second process can read them back to learn the exact input samples of the previous computation.

**Affected module/signals:**
- `in_real[0:7]`, `in_imag[0:7]` — peripheral.v:64–65
- Read path (INPUT_REAL): peripheral.v:174–177
- Read path (INPUT_IMAG): peripheral.v:179–183
- No zeroization on start or completion

**CIA cross-reference:** CIA-C-05

---

### I-03 · Intermediate Stage Registers Leak Via Power/EM Side-Channel
**Category:** Information Disclosure
**Severity:** Medium

**Attack scenario:**
The 16 stage working registers (`stage_real[0:7]`, `stage_imag[0:7]`) hold all intermediate butterfly results in-place and are never zeroized (no reset clause, no post-DONE clear — fft_8point.v:70–71). After computation, these registers hold Stage 3 output values identical to the final results. Although not bus-accessible, their switching activity during computation is directly proportional to data values processed, making them susceptible to Differential Power Analysis (DPA) or Electromagnetic Analysis (EMA). An attacker with a power probe or near-field EM sensor can correlate power traces with known plaintexts to recover input values.

**Affected module/signals:**
- `stage_real[0:7]`, `stage_imag[0:7]` — fft_8point.v:70–71
- `pipe_a_re`, `pipe_a_im`, `pipe_bw_re`, `pipe_bw_im` — fft_8point.v:454–455
- Clock gate `stage_reg_en` reduces idle activity but doesn't prevent in-computation leakage

**CIA cross-reference:** CIA-C-02, CIA-C-03

---

### I-04 · SPI MISO Exposes All Register Values to Physical Bus Observers
**Category:** Information Disclosure
**Severity:** High

**Attack scenario:**
Every read transaction delivered through the SPI harness causes the `spi_miso` line (`uio_out[3]`, tt_wrapper.v:117) to serialize the contents of `data_out_masked` onto the physical SPI bus. Any entity passively monitoring the SPI bus lines — without asserting chip-select or driving any active signals — can observe all FFT output values, input register values, and status bits as they are read out by the legitimate SPI master. This passive observation attack requires only a logic analyzer or oscilloscope connected to the `uio_out[3]` pad.

**Affected module/signals:**
- `spi_miso` = `uio_out[3]` — tt_wrapper.v:117
- `data_out_masked`: tt_wrapper.v:60, 111–113
- `data_out[31:0]` — peripheral.v:45 (source of all read data)

**CIA cross-reference:** CIA-C-04, CIA-C-01, CIA-C-05

---

### I-05 · FSM State Continuously Exposed on Dedicated Output Pins
**Category:** Information Disclosure
**Severity:** Low

**Attack scenario:**
The `uo_out[1:0]` pins are hardwired to `{done_flag, fft_busy}` (peripheral.v:218). These values are driven combinationally and continuously — not gated by any lock or mode signal. An attacker monitoring these two pins with a logic analyzer can determine: (1) exactly when an FFT computation starts (`fft_busy` rising edge), (2) exactly when it completes (`done_flag` rising edge), and (3) whether the result has been acknowledged yet. This timing information can serve as a precise trigger for side-channel measurement campaigns or for timing attacks coordinated with SPI register reads.

**Affected module/signals:**
- `uo_out[1:0]` = `{done_flag, fft_busy}` — peripheral.v:218
- `uio_out[0]` = `user_interrupt` = `done_flag` — tt_wrapper.v:119

**CIA cross-reference:** CIA-C-06

---

### I-06 · Computation Latency Is Data-Independent — No Timing Side-Channel (Strength)
**Category:** Information Disclosure
**Severity:** None (design strength)

**Attack scenario:**
The FFT computation latency is exactly 28 clock cycles for all input combinations (9 sub-cycles × 3 stages + 1 DONE cycle). The `bfly_trivial_w` flag (fft_8point.v:90) selects between a multiply and a bypass path, but both paths use the same number of pipeline stages — the bypass path (fft_8point.v:450–451) is a mux before the same pipeline register, not a separate fast path. Therefore, the time from `start` to `done` is constant regardless of input values, eliminating timing side-channels that would leak information about the magnitude or pattern of input data.

**CIA cross-reference:** CIA-C-07
**Note:** Design strength. Constant-time computation is the correct property for a cryptographic-adjacent accelerator. This property must be preserved if future optimizations are added.

---

## D — Denial of Service

### D-01 · FSM Deadlock: Illegal State Entry Permanently Asserts `busy=1`
**Category:** Denial of Service
**Severity:** Critical

**Attack scenario:**
If the `state` register (fft_8point.v:64) enters an illegal value (3'd5, 3'd6, or 3'd7) while `busy=1` — possible via single-event upset, power-glitch fault injection, or a future synthesis optimization that exploits don't-care states — the default recovery clause forces `state <= IDLE` (fft_8point.v:400) but does **not** clear `busy`. In the next cycle, the FSM is in IDLE with `busy=1`. Since the peripheral's `fft_start` generation checks `!fft_busy` (peripheral.v:155), no new start pulse can ever be generated. Since IDLE only exits on a `start` pulse (fft_8point.v:163), and no start pulse can arrive, the FSM is permanently stuck in IDLE with `busy=1`. The peripheral is completely unusable until `rst_n` is asserted. The minimum triggering condition is a single bit-flip in `state` at the right moment — three illegal states (5, 6, 7) can trigger this.

**Affected module/signals:**
- `state[2:0]` — fft_8point.v:64
- Default case: fft_8point.v:400 (missing `busy <= 1'b0`)
- `busy` cleared only in DONE: fft_8point.v:396
- `fft_start` guard: peripheral.v:155

**CIA cross-reference:** CIA-A-01
**Recovery:** `rst_n` assertion only. No software recovery path exists.

---

### D-02 · Persistent Interrupt: `done_flag` Cannot Be Cleared Without Starting a New Computation
**Category:** Denial of Service
**Severity:** High

**Attack scenario:**
In an interrupt-driven system, the CPU's interrupt controller responds to the `user_interrupt` line (`uio_out[0]`, driven by `done_flag`). Once an FFT completes and `done_flag=1`, the interrupt line is permanently asserted until a new FFT computation is started (clearing `done_flag` at peripheral.v:157) or `rst_n` is asserted. If the firmware interrupt handler needs to: (1) read output values, (2) validate them, (3) decide whether to run another FFT — it cannot acknowledge the interrupt while performing step (2) without also starting the computation at step (3). If the handler returns without writing CONTROL=1, the interrupt immediately re-fires, creating an infinite interrupt loop that starves all other interrupt sources and the main program loop.

**Affected module/signals:**
- `user_interrupt` = `done_flag` — peripheral.v:212
- `done_flag` clear: peripheral.v:157 (only via CONTROL=1 + start)
- No standalone clear register

**CIA cross-reference:** CIA-A-04

---

### D-03 · Reset Mid-Computation Silently Aborts FFT — Firmware Hangs Waiting for `done`
**Category:** Denial of Service
**Severity:** Medium

**Attack scenario:**
If `rst_n` is asserted while the FFT is computing (state = STAGE1/2/3), the asynchronous reset (fft_8point.v:140) immediately forces the FSM to IDLE, clears `busy`, and clears `done`. In the peripheral, `done_flag` is also cleared (peripheral.v:126). The CPU firmware that initiated the computation — whether polling STATUS.done or waiting for the `user_interrupt` line — will never see `done=1`. The polling loop runs indefinitely, and the interrupt-waiting handler is never dispatched. Unless the firmware has an independent watchdog timer, this is an unrecoverable hang.

**Affected module/signals:**
- Async reset: fft_8point.v:140 (negedge rst_n)
- `done` cleared on reset: fft_8point.v:152
- `done_flag` cleared on reset: peripheral.v:126
- No `aborted` status bit

**CIA cross-reference:** CIA-A-03

---

### D-04 · Writes to Input Registers While Busy Are Silently Dropped — Driver Data Corruption
**Category:** Denial of Service
**Severity:** Medium

**Attack scenario:**
The `input_reg_wr_en` guard (peripheral.v:119) blocks input register writes while `fft_busy=1`. All blocked writes return `data_ready=1` immediately (peripheral.v:207), giving the bus master no indication of failure. A firmware driver that pre-loads the next FFT's input samples while the current computation is running (a reasonable optimization to maximize throughput) will lose all those writes without knowing it. The next FFT computation will proceed with the stale input data from the previous run, producing wrong results silently. This is a latent correctness hazard that manifests as an availability/integrity failure.

**Affected module/signals:**
- `input_reg_wr_en` — peripheral.v:119
- `in_real[0:7]`, `in_imag[0:7]` — peripheral.v:64–65
- `data_ready` — peripheral.v:207

**CIA cross-reference:** CIA-I-03, CIA-A-03

---

### D-05 · SPI Write Flood Cannot Trigger Rapid FFTs but Consumes Bus Bandwidth
**Category:** Denial of Service
**Severity:** Low

**Attack scenario:**
Since `data_ready` is always `1'b1` and the SPI harness has no rate limiting, an external SPI master can write to the CONTROL register at the maximum SPI clock rate. However, the `fft_busy` guard (peripheral.v:155) ensures that only one FFT can be triggered per completion cycle (~28 clock cycles). Repeated CONTROL writes during a computation are silently discarded. While this cannot trigger rapid back-to-back FFTs faster than the hardware allows, the SPI transaction overhead (serialization, deserialization) can consume the SPI clock and the `spi_reg` logic at full rate, potentially interfering with legitimate SPI bus usage if the SPI infrastructure is shared.

**Affected module/signals:**
- `fft_start` guard: peripheral.v:155 (`!fft_busy`)
- SPI harness: tt_wrapper.v:82–98
- `data_ready`: peripheral.v:207

**CIA cross-reference:** CIA-A-06

---

### D-06 · `bfly_cnt` Glitch Causes Silent Stage Re-execution — Computation Delay Without Alert
**Category:** Denial of Service
**Severity:** Medium

**Attack scenario:**
If the 4-bit `bfly_cnt` counter (fft_8point.v:135) is corrupted to an illegal value (9–15) by a glitch during computation, the `default: bfly_cnt <= 4'd0` clause (e.g., fft_8point.v:246) resets it to zero, causing the current stage to restart from butterfly 0. The stage never advances until all butterflies complete in correct sequence. In the extreme case where the glitch recurs on every attempt, the FSM loops indefinitely within one stage. The stage transition condition (`bfly_cnt==8` at e.g. fft_8point.v:243–244) is never reached, and `done` is never asserted. Firmware waiting for completion hangs. While unlikely in a non-adversarial environment, this is a potential issue under EMI or at voltage/temperature extremes.

**Affected module/signals:**
- `bfly_cnt` — fft_8point.v:135
- Default cases: fft_8point.v:246, 313, 380
- Stage exit conditions: fft_8point.v:243–244, 310–311, 377–378

**CIA cross-reference:** CIA-A-05

---

## E — Elevation of Privilege

### E-01 · SPI Test Harness Bypasses All CPU Software-Level Access Controls
**Category:** Elevation of Privilege
**Severity:** High

**Attack scenario:**
In a real deployment, the TinyQV firmware might enforce access control policies at the software level — for example, only a privileged OS component or a trusted driver is allowed to configure and trigger FFT computations. The SPI test harness (tt_wrapper.v:82–98), synthesized into production silicon, provides a completely parallel access path that bypasses every layer of CPU software access control. An attacker with physical access to `uio_in[4:6]` operates at the hardware level, below the OS, firmware, hypervisor, or any software policy. They have the full register read/write capability of any bus master with no authentication requirement — effectively elevating from "physically present" to "has full peripheral control."

**Affected module/signals:**
- SPI path: tt_wrapper.v:73–98
- Full register access with no credential: peripheral.v:139–199
- `tt_um_tqv_peripheral_harness` header: "TinyQV peripheral test" — tt_wrapper.v:9

**CIA cross-reference:** CIA-C-04, S-02, R-03

---

### E-02 · Unmapped Address Writes Are Silently Accepted — No Privilege Escalation But No Enforcement
**Category:** Elevation of Privilege
**Severity:** Low

**Attack scenario:**
The peripheral's write decode covers word addresses 0x00–0x10 (inputs + control). Word addresses 0x11 (STATUS, read-only) and 0x12–0x21 (outputs, read-only) receive writes that fall through all conditions silently. Word addresses above 0x21 (byte address above 0x84) also receive writes that fall through with no effect. While no privilege escalation results from these ignored writes (no internal state changes), the peripheral provides no error, fault, or access violation signal. A buggy driver writing to a wrong address receives silent confirmation of success. The absence of address range enforcement means the peripheral's access control perimeter is completely invisible to callers.

**Affected module/signals:**
- Write decode: peripheral.v:139–160 (no out-of-range branch)
- `data_ready`: peripheral.v:207 (always 1)
- `address[5:0]`: peripheral.v:30 (6-bit, covers 64 words; no mapping above word 0x21)

**CIA cross-reference:** CIA-I-01, CIA-I-06

---

### E-03 · Sub-Word Write Width Encoding Is Not Enforced in the Write Path
**Category:** Elevation of Privilege
**Severity:** Low

**Attack scenario:**
The `data_write_n[1:0]` signal encodes write width as `2'b00`=8-bit, `2'b01`=16-bit, `2'b10`=32-bit, `2'b11`=no transaction. The peripheral's write-active decode is simply `data_write_n != 2'b11` (peripheral.v:115) — all three active width codes are treated identically. For a 16-bit register write, an 8-bit transaction (`2'b00`) delivers the full `data_in[31:0]` to the write logic, and `data_in[15:0]` is captured into the register. This means an SPI transaction that declares itself as 8-bit but carries a full 32-bit payload can write a 16-bit register value using what appears to be an 8-bit transaction from the protocol perspective. No privilege escalation results, but the mismatch between declared and actual write scope violates the principle of minimum authority.

**Affected module/signals:**
- `write_active` decode: peripheral.v:115 (ignores write width)
- `data_write_n[1:0]` — peripheral.v:42
- `data_in[15:0]` captured for input registers: peripheral.v:144, 149

**CIA cross-reference:** CIA-I-06

---

### E-04 · Reserved CONTROL Register Bits Are Write-Accepted With No Effect — Future Expansion Risk
**Category:** Elevation of Privilege
**Severity:** Low

**Attack scenario:**
The CONTROL register (word addr 0x10) currently uses only bit 0 (start FFT). Bits [31:1] are reserved. A write to CONTROL with any value causes the peripheral to evaluate `data_in[0]` for the start condition (peripheral.v:155) and ignore all other bits. There is no "reserved bits must be zero" check and no error for non-zero reserved bits. If future RTL revisions assign functionality to bits [31:1] (e.g., a clear-interrupt bit, an interrupt-mask bit, or a mode-select bit), existing drivers that write arbitrary values to CONTROL bits [31:1] may inadvertently activate those functions, escalating their access without any code change.

**Affected module/signals:**
- CONTROL write: peripheral.v:154–159
- `data_in[31:1]` — unused, not validated

**CIA cross-reference:** None (forward-looking risk)

---

### E-05 · `ui_in[7:0]` Is Synchronized and Passed Into Peripheral But Has No Defined Function
**Category:** Elevation of Privilege
**Severity:** Low

**Attack scenario:**
The 8-bit `ui_in` dedicated input port is synchronized via a 2-stage synchronizer (tt_wrapper.v:31) and passed as `ui_in_sync` to the `tqvp_fft8` peripheral (tt_wrapper.v:44). The peripheral receives and ports `ui_in` (peripheral.v:26) but does not use it internally — no logic in peripheral.v or fft_8point.v reads `ui_in_sync`. The signal is present in the module port list, routing it through synthesis, but its functional use is undefined (it may be a template placeholder). If a future RTL revision adds a use for `ui_in` (e.g., as a hardware key, a configuration input, or a mode selector), all 8 bits are physically reachable by anyone with pad access, and existing security analysis would need to be repeated.

**Affected module/signals:**
- `ui_in[7:0]` — tt_wrapper.v:11
- `ui_in_sync` — tt_wrapper.v:31
- `ui_in` passed to peripheral but unused: peripheral.v:26

**CIA cross-reference:** ATTACK_SURFACE_MAP §1.1 (`ui_in` note)

---

## Consolidated Threat Summary

| Threat ID | Category | Description | Severity |
|-----------|----------|-------------|----------|
| S-01 | Spoofing | No process isolation — any code accesses peripheral | High |
| S-02 | Spoofing | SPI harness is identity-less alternate access path | High |
| S-03 | Spoofing | `rst_n` can be asserted by external actor | Low |
| T-01 | Tampering | Input registers writable between load and start (race) | Medium |
| T-02 | Tampering | CONTROL writable via SPI — unauthorized computation trigger | High |
| T-03 | Tampering | Output registers are write-protected (strength) | — |
| T-04 | Tampering | Twiddle factors are ROM-equivalent (strength) | — |
| T-05 | Tampering | `bfly_trivial_w` can be flipped by fault injection | Low |
| T-06 | Tampering | `done_flag` cleared by third party before owner reads results | Medium |
| R-01 | Repudiation | No audit trail of computation initiators | Medium |
| R-02 | Repudiation | `done_flag` clear destroys completion evidence | Low |
| R-03 | Repudiation | CPU vs SPI transactions indistinguishable | Medium |
| I-01 | Info Disclosure | Output registers hold stale results until next computation | High |
| I-02 | Info Disclosure | Input registers readable after write — persistent exposure | Medium |
| I-03 | Info Disclosure | Stage registers leak via power/EM side-channel | Medium |
| I-04 | Info Disclosure | SPI MISO exposes all register values to bus observers | High |
| I-05 | Info Disclosure | FSM state exposed on dedicated output pins | Low |
| I-06 | Info Disclosure | Constant-time computation — no timing side-channel (strength) | — |
| D-01 | Denial of Service | FSM illegal-state → `busy=1` in IDLE → permanent lockout | **Critical** |
| D-02 | Denial of Service | Persistent interrupt — no standalone clear register | High |
| D-03 | Denial of Service | Reset mid-computation silently aborts, firmware hangs | Medium |
| D-04 | Denial of Service | Busy-blocked input writes silently dropped, data lost | Medium |
| D-05 | Denial of Service | SPI write flood consumes bus bandwidth | Low |
| D-06 | Denial of Service | `bfly_cnt` glitch causes silent stage re-execution | Medium |
| E-01 | Elevation of Privilege | SPI harness bypasses all CPU software access controls | High |
| E-02 | Elevation of Privilege | Unmapped address writes silently accepted | Low |
| E-03 | Elevation of Privilege | Sub-word write width not enforced | Low |
| E-04 | Elevation of Privilege | Reserved CONTROL bits write-accepted | Low |
| E-05 | Elevation of Privilege | `ui_in` synchronized but functionally undefined | Low |

**Totals by severity:** 1 Critical, 9 High, 10 Medium, 9 Low (3 entries are design strengths, not threats)

---

*End of STRIDE Analysis. Feed into: docs/DREAD_SCORES.md (Prompt 4).*
