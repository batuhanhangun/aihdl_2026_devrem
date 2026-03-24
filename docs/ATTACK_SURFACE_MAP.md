# Attack Surface Map — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Generated: 2026-03-24*

---

## Purpose

This document enumerates every externally reachable interface, trust boundary, state machine, data flow path, clock/reset domain crossing, and debug artifact present in the RTL. It serves as the foundation for the DP3 threat model. Entries follow the format:

> **Name** | Type | Location (file:line) | Trust Level | Notes

Trust levels used:
- **UNTRUSTED** — controlled by an external actor with no authentication
- **SEMI-TRUSTED** — controlled by the CPU/firmware; assumed legitimate but exploitable by malicious software
- **TRUSTED** — internal design constants or reset-controlled state, not externally reachable at runtime

---

## 1. External Interfaces

### 1.1 TinyTapeout Physical Pin Interface

| Name | Type | Location | Trust Level | Notes |
|------|------|----------|-------------|-------|
| `ui_in[7:0]` | 8-bit chip input | tt_wrapper.v:11 | UNTRUSTED | Physical pads; fed through 2-stage synchronizer before use. Currently only used to carry `ui_in_sync` into the peripheral, which is wired to `fft_core` but the core ignores it. Presents an active, synchronized but **functionally unconnected** path into the peripheral. |
| `uo_out[7:0]` | 8-bit chip output | tt_wrapper.v:12 / peripheral.v:218 | TRUSTED (output) | Bits [1:0] expose internal state: `uo_out[0]=fft_busy`, `uo_out[1]=done_flag`. This **leaks real-time FSM state** to any observer on the physical output pins. Bits [7:2] are hardwired 0. |
| `uio_in[7:0]` | Bidirectional chip input | tt_wrapper.v:13 | UNTRUSTED | Only `uio_in[6:4]` are used (SPI). `uio_in[3:0]` and `uio_in[7]` are explicitly ignored via the `_unused` tie-off at tt_wrapper.v:130. |
| `uio_out[7:0]` | Bidirectional chip output | tt_wrapper.v:14 | TRUSTED (output) | `[0]=user_interrupt`, `[1]=data_ready` (always 1), `[3]=spi_miso`, `[7:4]` and `[2]` hardwired 0. |
| `uio_oe[7:0]` | IO direction control | tt_wrapper.v:15 | TRUSTED | `uio_oe[0]=1`, `uio_oe[1]=1`, `uio_oe[3]=1`; all others 0. Fixed combinationally. |
| `ena` | Power enable pin | tt_wrapper.v:16 | UNTRUSTED | Always 1 per TinyTapeout spec; tied to `_unused`. Design does not gate on `ena` — if `ena=0`, all logic still receives clock. |
| `clk` | System clock input | tt_wrapper.v:17 | UNTRUSTED | Drives all flip-flops. No internal PLL; frequency is dictated by the test board. A malicious or erroneous clock could violate timing. |
| `rst_n` | Active-low async reset | tt_wrapper.v:18 | UNTRUSTED | Physical pad. In tt_wrapper, this is re-registered on the **negedge** of `clk` (tt_wrapper.v:37) before being passed to the peripheral. Creates a half-cycle reset delay. The `fft_8point` butterfly unit uses it as an async negedge reset (fft_8point.v:457), while the main FSM also uses async negedge (fft_8point.v:140). |

### 1.2 SPI Test Harness Signals

| Name | Type | Location | Trust Level | Notes |
|------|------|----------|-------------|-------|
| `spi_cs_n` (`uio_in[4]`) | SPI chip-select (active low) | tt_wrapper.v:73 | UNTRUSTED | Synchronized via 2-stage synchronizer (tt_wrapper.v:77). No authentication. Any agent driving this pin can initiate SPI transactions. |
| `spi_clk` (`uio_in[5]`) | SPI clock | tt_wrapper.v:74 | UNTRUSTED | Synchronized (tt_wrapper.v:78). External SPI clock; glitching possible. |
| `spi_mosi` (`uio_in[6]`) | SPI master-out / data input | tt_wrapper.v:75 | UNTRUSTED | Synchronized (tt_wrapper.v:79). Carries all register addresses and write data into the peripheral. **Primary untrusted data entry point.** |
| `spi_miso` (`uio_out[3]`) | SPI master-in / data output | tt_wrapper.v:117 | TRUSTED (output) | Carries all register read-back data to the SPI master. Exposes FFT outputs, input register state, and status bits to anyone attached to the SPI bus. |
| `user_interrupt` / `uio_out[0]` | Level-triggered interrupt output | peripheral.v:212 / tt_wrapper.v:119 | TRUSTED (output) | Asserted **level-high** whenever `done_flag=1`. `done_flag` is sticky — it remains high until the next `start` command or `rst_n`. A consumer that never reads back and restarts will see a persistent interrupt. |
| `data_ready` / `uio_out[1]` | SPI ready handshake | tt_wrapper.v:121 | TRUSTED (output) | Hardwired to `1'b1` (peripheral.v:207). Always-ready signal — no flow control. The SPI master can pipeline writes at full speed with no backpressure. |

### 1.3 Memory-Mapped Registers (via SPI → peripheral bus)

| Name | Address | Type | Location | Trust Level | Notes |
|------|---------|------|----------|-------------|-------|
| `INPUT_REAL[0]`–`INPUT_REAL[7]` | 0x00–0x1C (byte) / word addr 0x00–0x07 | Read-Write | peripheral.v:64,144 | SEMI-TRUSTED | Written by CPU/SPI; only lower 16 bits of the 32-bit bus word are captured (`data_in[15:0]`). Upper 16 bits silently discarded. Write-protected when `fft_busy=1`. **Readable for verification** despite being documented as write-only. |
| `INPUT_IMAG[0]`–`INPUT_IMAG[7]` | 0x20–0x3C (byte) / word addr 0x08–0x0F | Read-Write | peripheral.v:65,148 | SEMI-TRUSTED | Same behavior as INPUT_REAL. Write-protected when busy. Readable. |
| `CONTROL` | 0x40 (byte) / word addr 0x10 | Write | peripheral.v:154 | SEMI-TRUSTED | Bit 0: start FFT. **No protection against writing reserved bits.** Writing any nonzero bit 0 when `fft_busy=0` launches a computation. `done_flag` is cleared atomically on start. The control register is **always writable** (even during FFT; the `!fft_busy` guard is inside the start-pulse logic, so writes to CONTROL while busy are accepted but silently do nothing). |
| `STATUS` | 0x44 (byte) / word addr 0x11 | Read | peripheral.v:186 | SEMI-TRUSTED | Bit 0: `fft_busy` (live wire from FSM). Bit 1: `done_flag` (sticky latch). Bits [31:2] always 0. No write effect; a write to STATUS address is decoded by the write path but falls through all conditions silently. |
| `OUTPUT_REAL[0]`–`OUTPUT_REAL[7]` | 0x48–0x64 (byte) / word addr 0x12–0x19 | Read | peripheral.v:191 | SEMI-TRUSTED | FFT output real parts. Hold **last computed values** across reset-less power cycles; stale data from a previous computation is readable until a new FFT completes. Sign-extended to 32 bits on read. |
| `OUTPUT_IMAG[0]`–`OUTPUT_IMAG[7]` | 0x68–0x84 (byte) / word addr 0x1A–0x21 | Read | peripheral.v:196 | SEMI-TRUSTED | FFT output imaginary parts. Same staleness concern. |

### 1.4 Internal Peripheral Bus (CPU ↔ tqvp_fft8)

| Name | Type | Location | Trust Level | Notes |
|------|------|----------|-------------|-------|
| `address[5:0]` | 6-bit word address bus | peripheral.v:30 | SEMI-TRUSTED | Only 6 bits wide — covers 64 word addresses (256 bytes). Addresses outside the mapped register ranges (above 0x21 word) silently return 0 on read and drop writes. No fault or error signaling for unmapped accesses. |
| `data_in[31:0]` | 32-bit write data | peripheral.v:31 | SEMI-TRUSTED | Write payload from CPU/SPI. Only bits [15:0] are used for input samples; bits [31:16] are discarded without error. For CONTROL, only bit 0 is functional. |
| `data_write_n[1:0]` | Write strobe, active-low encoded | peripheral.v:42 | SEMI-TRUSTED | `2'b00`=8-bit, `2'b01`=16-bit, `2'b10`=32-bit, `2'b11`=no transaction. The peripheral treats any value ≠ `2'b11` as a write, regardless of width encoding (peripheral.v:115). **Sub-word write widths are not differentiated in the write path** — all writes deliver the full `data_in[31:0]`, with only `data_out_masked` masking for reads. |
| `data_read_n[1:0]` | Read strobe, active-low encoded | peripheral.v:43 | SEMI-TRUSTED | Same encoding as write. The read path triggers on any value ≠ `2'b11`. |
| `data_out[31:0]` | 32-bit read data bus | peripheral.v:45 | TRUSTED (output) | Combinationally driven; always reflects current register state when `read_active`. |
| `data_ready` | Combinational ready signal | peripheral.v:207 | TRUSTED (output) | Hardwired `1'b1`. No wait states ever generated. |
| `user_interrupt` | Level interrupt to CPU | peripheral.v:212 | TRUSTED (output) | `done_flag` directly. CPU must clear by writing CONTROL with start=1 (which clears `done_flag`) or asserting `rst_n`. There is **no explicit interrupt-clear register**. |

---

## 2. Trust Boundaries

| Boundary | From | To | Crossing Point | Notes |
|----------|------|----|----------------|-------|
| **TB-1: Physical World → Chip** | External test board / PCB | TinyTapeout chip pads | `ui_in`, `uio_in`, `clk`, `rst_n`, `ena` | All physical inputs are UNTRUSTED. The synchronizers in tt_wrapper are the first defensive layer for metastability, not for security. |
| **TB-2: SPI Harness → Peripheral Bus** | `spi_reg` (SPI decoder) | `tqvp_fft8` (peripheral) | `address`, `data_in`, `data_write_n`, `data_read_n` | SPI master has full read/write access to all registers with no authentication. The `spi_reg` module decodes protocol framing but enforces no access control. |
| **TB-3: Peripheral → FFT Core** | `tqvp_fft8` (peripheral.v) | `fft_8point` (fft_8point.v) | `in_real[0:7]`, `in_imag[0:7]`, `fft_start` (peripheral.v:87–109) | The only explicit protection here is the `fft_busy` gate on `fft_start` and input register writes. The FFT core trusts all data presented to it unconditionally. |
| **TB-4: FFT Core → Butterfly Unit** | `fft_8point` (state machine) | `butterfly_pipelined` | Isolated inputs `bfly_a_re_iso`, etc. (fft_8point.v:93–99) | The operand isolation mux is a power optimization, not a security boundary. It forces zeros during IDLE but does not validate data during computation. |
| **TB-5: Test Harness → Production Logic** | `tt_um_tqv_peripheral_harness` (tt_wrapper.v) | `tqvp_fft8` (peripheral.v) | Module instantiation (tt_wrapper.v:41–53) | The wrapper is designated as simulation/test infrastructure ("TinyQV peripheral test using SPI", tt_wrapper.v:8). It injects the SPI harness and synchronizers. In physical tape-out, this wrapper **is synthesized and present on-chip**, meaning all SPI logic is production silicon, not gated off. |
| **TB-6: Synthesis Tool → RTL** | Yosys synthesis script | Gate-level netlist | synth.ys `-flatten` | Flattening and resource sharing during synthesis may merge logic across module boundaries, eliminating the `butterfly_pipelined` module as a distinct entity in the netlist. Trust boundary TB-4 may not exist post-synthesis. |

---

## 3. State Machines and Transitions

### 3.1 `fft_8point` Main FSM

**Location:** fft_8point.v:58–401
**State register:** `state[2:0]` (3 bits, states 0–4, value 5–7 unused)

```
           start=1
IDLE (0) ──────────────► STAGE1 (1)
   ▲                         │ bfly_cnt reaches 8
   │                         ▼
   │                     STAGE2 (2)
   │                         │ bfly_cnt reaches 8
   │                         ▼
   │                     STAGE3 (3)
   │                         │ bfly_cnt reaches 8
   │                         ▼
   └──── busy=0, done=1 ── DONE (4)

Any unrecognized state value → IDLE (default branch, fft_8point.v:400)
```

| State | Value | Entry Condition | Exit Condition | Key Actions | Notes |
|-------|-------|-----------------|----------------|-------------|-------|
| IDLE | 3'd0 | Reset or DONE completion | `start` pulse asserted | Loads bit-reversed samples into `stage_real/imag`; sets `busy=1` | `stage_reg_en=0` in IDLE — stage registers are clock-gated. Samples captured from live input bus at start edge. |
| STAGE1 | 3'd1 | `start` in IDLE | `bfly_cnt==8` completed | Executes 4 butterflies with W⁰ (trivial bypass). Sub-states via `bfly_cnt` 0–8 | `bfly_trivial_w=1` for all stage-1 butterflies. Pipeline adds 1-cycle wait per butterfly (SETUP→WAIT→STORE). |
| STAGE2 | 3'd2 | STAGE1 complete | `bfly_cnt==8` completed | 4 butterflies: W⁰,W²,W⁰,W² | Butterflies 0 and 2: trivial bypass. Butterflies 1 and 3: full complex multiply with W². |
| STAGE3 | 3'd3 | STAGE2 complete | `bfly_cnt==8` completed | 4 butterflies: W⁰,W¹,W²,W³ | Only butterfly 0 uses trivial bypass. Butterflies 1,2,3 use full multiply. |
| DONE | 3'd4 | STAGE3 complete | (combinational) → IDLE next cycle | Copies `stage_real/imag` to `out_real/imag`; asserts `done=1` (one-cycle pulse); clears `busy` | `output_reg_en=1` only here. `done` is a 1-cycle pulse. `fft_start` is a 1-cycle pulse from peripheral. |
| Illegal | 3'd5–7 | Hardware upset / glitch | Immediately | `state <= IDLE` | No busy/done cleanup on illegal state entry. `busy` may be left asserted after unexpected state recovery. |

### 3.2 `bfly_cnt` Sub-State Counter

**Location:** fft_8point.v:135
**Width:** 4 bits (values 0–8 used; 9–15 unused, covered by `default: bfly_cnt <= 4'd0`)

Each STAGE executes 4 butterflies sequentially, each taking 3 sub-cycles:

| `bfly_cnt` | Sub-cycle role |
|------------|----------------|
| 0, 2, 4, 6 | SETUP: Load butterfly inputs, select twiddle, set `bfly_trivial_w` |
| 1, 3, 5, 7 | WAIT: Pipeline latency (no operation; `bfly_out` not valid yet) |
| 2, 4, 6, 8 | STORE: Write `bfly_out` to `stage_real/imag`; simultaneously set up next butterfly |
| 8 | Final store + transition to next major state |

### 3.3 `butterfly_pipelined` Implicit Pipeline

**Location:** fft_8point.v:424–481
**Not a named FSM**, but has 2 pipeline stages:

| Stage | Type | Key Signal | Notes |
|-------|------|------------|-------|
| Stage 1 (multiply) | Registered | `valid_in` → registers `pipe_a_re/im`, `pipe_bw_re/im` | `trivial_w` mux applied before register. If `trivial_w=1`, stores `b` directly. |
| Stage 2 (add/sub) | Combinational | `valid_out` | Purely combinational; glitches propagate immediately to `out_a/b` wires. |

The `valid_out` signal (fft_8point.v:104,469) is registered from `valid_in` with 1-cycle latency but **is not used by the main FSM to gate the STORE action** — the FSM relies on fixed timing via `bfly_cnt` instead of handshaking.

### 3.4 SPI State Machine (spi_reg, referenced)

**Location:** tt_wrapper.v:82–98 (instantiation only; source not in scope)
Drives: `addr_valid`, `data_valid`, `data_rw`, `txn_n[1:0]`, `address[5:0]`, `data_in[31:0]`

The SPI state machine is not in the provided RTL but is the **primary sequencer for all external access**. Its output `data_valid && data_rw` gates write enable; `addr_valid && !data_rw` gates read enable (tt_wrapper.v:104–109).

---

## 4. Data Flow Paths

### 4.1 Write Path: External → FFT Input Registers

```
External SPI master
  → spi_mosi (uio_in[6], UNTRUSTED)
  → 2-stage synchronizer (tt_wrapper.v:79)
  → spi_reg decoder: extracts address[5:0] + data_in[31:0]
  → data_write_n = txn_n when data_valid && data_rw (tt_wrapper.v:104–106)
  → peripheral.v write logic (posedge clk, rst_n)
      └─ if input_reg_wr_en (= write_active & ~fft_busy)
          └─ word_addr 0x00–0x07: in_real[idx] ← data_in[15:0]   (peripheral.v:143–145)
          └─ word_addr 0x08–0x0F: in_imag[idx] ← data_in[15:0]   (peripheral.v:147–150)
  → (16-bit signed values held in in_real[0:7], in_imag[0:7])
```

**Observation:** Bits [31:16] of every write word are silently discarded. No error or alignment fault is generated.

### 4.2 Control Path: Start Trigger

```
SPI master writes 0x01 to CONTROL (word addr 0x10)
  → data_in[0] = 1, word_addr = ADDR_CONTROL (peripheral.v:154)
  → if !fft_busy: fft_start ← 1 (1-cycle pulse), done_flag ← 0
  → fft_8point.start receives pulse
  → FSM: IDLE → STAGE1 (fft_8point.v:163–178)
      └─ stage_real[0..7] ← bit-reversed in_real[]/in_imag[] (sampled at this clock edge)
```

**Observation:** The `in_real`/`in_imag` values are captured from the live register file at the moment `start` is processed. A race is possible if the SPI master writes samples and immediately writes CONTROL in rapid succession: the FFT will compute on whatever values are in the registers at the `start` clock edge.

### 4.3 Computation Path: Butterfly Datapath

```
stage_real[0:7], stage_imag[0:7]  (loaded at start, modified in-place per stage)
  → STAGE1: 4× butterfly pairs (0,1),(2,3),(4,5),(6,7) with W⁰ bypass
      ├─ operand isolation mux (bfly_active ? data : 0) (fft_8point.v:93–99)
      ├─ butterfly_pipelined.Stage1: trivial_w ? b : (b*w scaled)  (fft_8point.v:450–451)
      └─ butterfly_pipelined.Stage2: out_a=a+bw, out_b=a-bw       (fft_8point.v:476–479)
  → stage_real/imag updated in-place (no separate intermediate buffer)
  → STAGE2: 4× butterfly pairs (0,2),(1,3),(4,6),(5,7) with W⁰/W²
  → STAGE3: 4× butterfly pairs (0,4),(1,5),(2,6),(3,7) with W⁰/W¹/W²/W³
  → DONE: stage_real/imag → out_real[0:7]/out_imag[0:7]
```

**Overflow note:** The butterfly add/subtract at fft_8point.v:476–479 is 16-bit with no saturation — overflow wraps. Q1.15 inputs with magnitudes near ±1.0 can produce out-of-range sums.
**Rounding note:** Q1.15 scaling uses `(bw_full + 16384) >>> 15` (fft_8point.v:446–447); the rounding bias is always added unconditionally, even when `trivial_w=1` (though the mux makes the full-multiply path irrelevant in that case).

### 4.4 Read Path: FFT Output → External

```
FFT computation completes → done_flag=1 → user_interrupt asserted (level)
  → SPI master reads STATUS (word addr 0x11)
      ← data_out = {30'd0, done_flag, fft_busy}
  → SPI master reads OUTPUT_REAL[0..7] (word addr 0x12–0x19)
      ← data_out = sign_extended(out_real[idx])
  → SPI master reads OUTPUT_IMAG[0..7] (word addr 0x1A–0x21)
      ← data_out = sign_extended(out_imag[idx])
  → spi_reg serializes data_out_masked onto spi_miso
```

**Observation:** Output registers are readable at any time, including while a new FFT is in progress. A reader that polls during computation will see **partially updated stage results** that were written by a previous DONE state, since `out_real/imag` are only updated in DONE. The stage working registers (`stage_real/imag`) are not bus-accessible.

**Verification read-back:** INPUT_REAL and INPUT_IMAG registers are also readable (peripheral.v:174–183). This allows verification of written values but also means an attacker can confirm what data was loaded into the FFT input — a potential information-leakage path.

### 4.5 Interrupt / Status Path

```
fft_done (1-cycle pulse, fft_8point.v:395)
  → done_flag ← 1 (sticky latch, peripheral.v:135–137)
  → user_interrupt = done_flag (peripheral.v:212) — level-high, persistent
  → uio_out[0] = user_interrupt (tt_wrapper.v:119)
  → uo_out[1] = done_flag (peripheral.v:218) — also on dedicated output pin
```

**Cleared by:** Writing CONTROL with bit 0=1 (clears `done_flag`, peripheral.v:157) or `rst_n=0`.
**No explicit interrupt-clear register exists.**

---

## 5. Clock and Reset Domain Crossings

| Signal | Source Domain | Destination Domain | Mitigation | Location | Notes |
|--------|--------------|-------------------|------------|----------|-------|
| `ui_in[7:0]` | External async | `clk` domain | 2-stage synchronizer (WIDTH=8) | tt_wrapper.v:31 | Synchronized before use in peripheral. The 8-bit wide synchronizer may not fully prevent multi-bit metastability for simultaneous multi-bit transitions. |
| `spi_cs_n` | External async (SPI) | `clk` domain | 2-stage synchronizer (WIDTH=1) | tt_wrapper.v:77 | 1-bit; adequate. |
| `spi_clk` | External async (SPI) | `clk` domain | 2-stage synchronizer (WIDTH=1) | tt_wrapper.v:78 | SPI clock is re-clocked into the system clock domain. SPI data is sampled relative to the synchronized SPI clock edge, not the raw SPI clock. |
| `spi_mosi` | External async (SPI) | `clk` domain | 2-stage synchronizer (WIDTH=1) | tt_wrapper.v:79 | 1-bit; adequate. |
| `rst_n` | External async | `clk` domain | Registered on **negedge clk** → `rst_reg_n` | tt_wrapper.v:37 | This is a half-cycle early registration of reset. `rst_reg_n` is used as the reset for `tqvp_fft8` and `spi_reg`. The `butterfly_pipelined` module uses `rst_n` as async negedge reset (fft_8point.v:457); the main FSM also uses async negedge (fft_8point.v:140). Both ultimately receive `rst_reg_n` (passed through the peripheral hierarchy). **The async reset release (deassertion) is not synchronized**, which can cause flip-flops to exit reset at different clock edges. |
| `fft_done` (pulse) | `clk` domain internal | `clk` domain internal | N/A — same clock | peripheral.v:135 | No crossing; `done_flag` is a synchronous latch of the `fft_done` pulse. |
| `ena` | External async | (ignored) | Tied to `_unused` | tt_wrapper.v:130 | Not synchronized; not used. |

**Single clock domain:** The entire design operates on one clock (`clk`). There are no multi-clock-domain handshakes within the synthesized RTL. All crossing concerns are external-signal-to-chip-clock.

---

## 6. Debug and Test-Only Logic

| Name | Type | Location | Present in Synthesis? | Notes |
|------|------|----------|-----------------------|-------|
| `fft_8point_tb` module | Full simulation testbench | fft_8point_tb.v:11 | **No** (not in synth.ys) | Not synthesized. Contains `$dumpfile`, `$dumpvars`, `$display`, `$finish`. |
| VCD waveform dump | Simulation artifact | fft_8point_tb.v:136–137 | **No** | Writes `fft_8point_tb.vcd`; reveals all internal signal values during simulation. |
| Timeout watchdog | Simulation guard | fft_8point_tb.v:308–312 | **No** | 200,000 ns timeout; detects FSM hang or pipeline deadlock in simulation. |
| `check_results` task | Simulation checker | fft_8point_tb.v:109–129 | **No** | Signed arithmetic comparison; uses unsigned `tolerance` parameter — subtraction order not guarded for negative differences (potential false-pass if `out > expected` by more than tolerance). |
| `tt_um_tqv_peripheral_harness` | SPI test wrapper | tt_wrapper.v:9 | **Yes** — synthesized into production silicon | Header says "peripheral test using SPI". The SPI harness (`spi_reg` instance + synchronizers) is **production silicon**, not a simulation-only construct. This means every fabricated chip has a live, unauthenticated SPI port granting full register read/write access. |
| `data_out_masked` masking logic | SPI read-width masking | tt_wrapper.v:111–113 | **Yes** | Zeros upper bits of `data_out` based on `txn_n` for sub-32-bit reads. Applied only to SPI read path, not to the peripheral bus `data_out` directly. |
| `input_reg_wr_en` clock gate | Power optimization / write protection | peripheral.v:119 | **Yes** | Gate blocks input writes when FFT busy. This doubles as a functional correctness guard (prevents mid-compute input mutation) but is labeled as a DP2 clock-gating optimization, not a security feature. |
| `uo_out` status exposure | Live FSM state on output pins | peripheral.v:218 | **Yes** | `{6'b0, done_flag, fft_busy}` is driven to dedicated output pins on every cycle. Exposes real-time FSM state as side-channel. |
| Comment anomaly in `peripheral.v` | Source artifact | peripheral.v:25–43 | N/A | The port comments contain extreme repetition of the word "directly" (50+ times in a row) in block comments. This is an unusual artifact — possibly AI-generation noise. It has no functional impact but indicates the comment text was not human-written and should not be relied upon for documentation accuracy. |

---

## 7. Summary: High-Priority Attack Surface Points

The following entries represent the highest-risk intersections of trust boundaries and functional interfaces, to be prioritized in the threat model:

| Priority | Item | Reason |
|----------|------|--------|
| HIGH | SPI interface with no authentication (TB-2) | Any physical access to `uio_in[4:6]` gives full register read/write with no credential check |
| HIGH | `user_interrupt` is a persistent level signal with no clear register | Firmware that doesn't restart FFT on every interrupt will see a stuck interrupt line |
| HIGH | Output registers hold stale data between computations | A reader arriving after a reset but before a computation will read all-zeros; a reader after one computation will read previous results until overwritten |
| MEDIUM | `rst_n` async release not synchronized | Different flip-flop groups may exit reset on different clock edges, creating a brief undefined state |
| MEDIUM | `bfly_cnt` illegal sub-states (9–15) | Hardware upset or glitch in `bfly_cnt` forces it to 0 but does not restart the current butterfly correctly — partial results may be silently stored |
| MEDIUM | FSM illegal states (3'd5–7) do not clean up `busy` flag | `busy` may remain asserted after glitch-induced state recovery, permanently blocking new computations |
| MEDIUM | `uo_out` leaks FSM state as side-channel | Physical observation of output pins reveals computation timing and completion status |
| LOW | 16-bit butterfly add/subtract has no overflow protection | Carefully crafted input values near the Q1.15 boundary can produce wrap-around outputs |
| LOW | Unsigned `tolerance` in testbench `check_results` | Negative differences can evade the error check, hiding output errors in simulation |
| LOW | INPUT_REAL/IMAG readable after write | Written samples are readable back via bus — information leakage if samples are confidential |

---

*End of Attack Surface Map. Next step: DP3 Threat Model will assign STRIDE categories, likelihood, and impact ratings to each entry above.*
