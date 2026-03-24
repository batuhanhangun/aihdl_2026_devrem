# DREAD Risk Scoring — 8-Point FFT Accelerator Peripheral
**AI-HDL 2026 | Team Devrem | Design Phase 3**
*Inputs: docs/CIA_ANALYSIS.md, docs/STRIDE_ANALYSIS.md | Generated: 2026-03-24*

---

## Scoring Methodology

Each threat is scored 1–10 on five DREAD dimensions:

| Dimension | 10 (Maximum) | 1 (Minimum) |
|-----------|-------------|-------------|
| **D**amage | Full peripheral compromise / data loss | Cosmetic only |
| **R**eproducibility | Succeeds every attempt | Extremely rare race condition |
| **E**xploitability | Any bus master, zero skill | Physical chip probe + specialist skills |
| **A**ffected users | All FFT use cases impacted | Single narrow edge case |
| **D**iscoverability | Obvious from register map / first code read | Requires DPA or silicon analysis |

**Priority tiers:**
- Average **≥ 7.0** → **CRITICAL** — must fix in DP3
- Average **5.0–6.9** → **HIGH** — should fix in DP3
- Average **3.0–4.9** → **MEDIUM** — document mitigation plan
- Average **< 3.0** → **LOW** — acknowledge only

Threats marked *(combined)* share a single root cause across multiple STRIDE categories.

---

## Ranked Threat Table

| Rank | Threat ID | Description | D | R | E | A | D | **Avg** | **Tier** |
|------|-----------|-------------|---|---|---|---|---|---------|---------|
| 1 | **S-02 / E-01** *(combined)* | SPI test harness synthesised into production silicon — unauthenticated full register read/write | 8 | 10 | 7 | 9 | 9 | **8.6** | CRITICAL |
| 2 | **I-01** | FFT output registers hold stale results — readable by any bus master between computations | 6 | 10 | 10 | 8 | 9 | **8.6** | CRITICAL |
| 3 | **D-02** | `done_flag` has no standalone interrupt-clear register — persistent interrupt starves CPU | 7 | 10 | 10 | 7 | 8 | **8.4** | CRITICAL |
| 4 | **T-02** | CONTROL register writable via SPI — unauthorized computation trigger without CPU involvement | 7 | 10 | 7 | 8 | 9 | **8.2** | CRITICAL |
| 5 | **S-01** | No MMU on tinyQV — any process can access peripheral address space with full authority | 6 | 10 | 10 | 6 | 8 | **8.0** | CRITICAL |
| 6 | **I-02** | INPUT_REAL / INPUT_IMAG registers readable at any time — expose input samples post-write | 5 | 10 | 10 | 6 | 9 | **8.0** | CRITICAL |
| 7 | **D-04** | Input register writes silently dropped while `fft_busy=1` — `data_ready=1` gives false success | 7 | 8 | 10 | 6 | 7 | **7.6** | CRITICAL |
| 8 | **I-04** | SPI MISO serialises all register values onto the physical bus — passive observation attack | 6 | 9 | 5 | 8 | 7 | **7.0** | CRITICAL |
| 9 | **R-01** | No audit trail of computation initiators — CPU and SPI paths produce identical peripheral state | 3 | 10 | 8 | 5 | 8 | **6.8** | HIGH |
| 10 | **I-05** | `uo_out[1:0]` = `{done_flag, fft_busy}` continuously exposed on dedicated output pins | 2 | 10 | 8 | 5 | 9 | **6.8** | HIGH |
| 11 | **E-02** | Writes to unmapped addresses (outside 0x00–0x84) silently dropped — no bus error returned | 2 | 10 | 10 | 4 | 8 | **6.8** | HIGH |
| 12 | **CIA-I-04** | Q1.15 butterfly add/subtract has no overflow saturation — silent wrap-around on large inputs | 7 | 6 | 8 | 5 | 7 | **6.6** | HIGH |
| 13 | **R-02** | Clearing `done_flag` (via CONTROL=1) destroys completion evidence — no history retained | 2 | 10 | 10 | 3 | 7 | **6.4** | HIGH |
| 14 | **R-03** | CPU-originated vs SPI-originated transactions are indistinguishable at the peripheral | 3 | 10 | 8 | 4 | 7 | **6.4** | HIGH |
| 15 | **S-03** | `rst_n` is an external physical pad — can be asserted by attacker to abort computation | 5 | 8 | 5 | 6 | 6 | **6.0** | HIGH |
| 16 | **T-01** | Input registers writable between sample load and `start` — race window in multi-process use | 7 | 5 | 7 | 4 | 6 | **5.8** | HIGH |
| 17 | **T-06** | Third party can write CONTROL=1 to clear `done_flag` before owner reads results | 6 | 6 | 7 | 4 | 6 | **5.8** | HIGH |
| 18 | **D-01** | FSM illegal-state default leaves `busy=1` in IDLE — permanent lockout until `rst_n` | 9 | 3 | 2 | 8 | 7 | **5.8** | HIGH |
| 19 | **E-03** | `data_write_n` sub-word encoding not enforced — 8-bit transaction writes full 16-bit register | 2 | 9 | 9 | 3 | 6 | **5.8** | HIGH |
| 20 | **E-04** | Reserved CONTROL bits [31:1] silently accepted — future expansion could break existing code | 1 | 10 | 10 | 2 | 6 | **5.8** | HIGH |
| 21 | **D-05** | SPI write flood — CONTROL spammed at SPI clock rate consumes bus bandwidth | 3 | 8 | 7 | 3 | 5 | **5.2** | HIGH |
| 22 | **CIA-A-02** | Stage working registers have no reset clause — indeterminate silicon state at power-on | 4 | 5 | 4 | 5 | 7 | **5.0** | HIGH |
| 23 | **D-03** | Reset mid-computation silently aborts FFT — firmware polling `done` hangs indefinitely | 6 | 5 | 3 | 5 | 6 | **5.0** | HIGH |
| 24 | **I-03** | Stage/pipeline registers retain intermediate results — observable via differential power analysis | 5 | 4 | 2 | 5 | 5 | **4.2** | MEDIUM |
| 25 | **D-06** | `bfly_cnt` default recovery silently restarts butterfly 0 — produces wrong results without alert | 5 | 2 | 2 | 6 | 5 | **4.0** | MEDIUM |
| 26 | **T-05** | `bfly_trivial_w` flip via fault injection bypasses multiplication — silent wrong results | 6 | 2 | 2 | 5 | 4 | **3.8** | MEDIUM |
| 27 | **E-05** | `ui_in[7:0]` is synchronized and passed to peripheral but has no defined function | 1 | 5 | 5 | 2 | 4 | **3.4** | MEDIUM |

---

## Scores by Tier

### CRITICAL (Average ≥ 7.0) — Must Fix in DP3

| Threat ID | Avg | Primary Risk |
|-----------|-----|-------------|
| S-02 / E-01 | **8.6** | Unauthenticated SPI access to all registers in production silicon |
| I-01 | **8.6** | Stale output data readable cross-computation, cross-process |
| D-02 | **8.4** | Persistent interrupt with no standalone clear — CPU interrupt storm |
| T-02 | **8.2** | CONTROL writable via SPI — unauthorized FFT triggering |
| S-01 | **8.0** | No MMU — process isolation entirely absent |
| I-02 | **8.0** | Input registers always readable — input sample exposure |
| D-04 | **7.6** | Silent write drop while busy — driver receives false success |
| I-04 | **7.0** | SPI MISO exposes all register reads to passive physical observer |

### HIGH (Average 5.0–6.9) — Should Fix in DP3

| Threat ID | Avg | Primary Risk |
|-----------|-----|-------------|
| R-01 | 6.8 | No initiator audit trail — attacks unattributable |
| I-05 | 6.8 | FSM state leaks on output pins — computation timing observable |
| E-02 | 6.8 | Unmapped write silence — no feedback on failed transactions |
| CIA-I-04 | 6.6 | Overflow wrap-around in butterfly additions — silent wrong results |
| R-02 | 6.4 | Evidence of completion destroyed when next computation starts |
| R-03 | 6.4 | CPU vs SPI origin indistinguishable — repudiation possible |
| S-03 | 6.0 | External `rst_n` can abort computation and clear outputs |
| T-01 | 5.8 | Multi-process input tampering race window |
| T-06 | 5.8 | Third party can steal/destroy done_flag before owner reads |
| D-01 | 5.8 | FSM glitch → permanent busy deadlock (CRITICAL impact, low exploitability) |
| E-03 | 5.8 | Sub-word write width mismatch silently accepted |
| E-04 | 5.8 | Reserved CONTROL bits silently accepted — forward compatibility risk |
| D-05 | 5.2 | SPI write flood consumes bus bandwidth |
| CIA-A-02 | 5.0 | Stage registers without reset — indeterminate power-on state |
| D-03 | 5.0 | Mid-computation reset aborts silently — firmware hangs |

### MEDIUM (Average 3.0–4.9) — Document Mitigation Plan

| Threat ID | Avg | Primary Risk |
|-----------|-----|-------------|
| I-03 | 4.2 | Differential power analysis on stage registers |
| D-06 | 4.0 | `bfly_cnt` glitch causes silent stage re-execution |
| T-05 | 3.8 | Fault-injected `bfly_trivial_w` flip bypasses multiplication |
| E-05 | 3.4 | Undefined `ui_in` functionality is a latent attack surface |

---

## Score Distribution Notes

**Why S-01 scores CRITICAL despite being a system architecture issue:**
The absence of an MMU is a tinyQV platform property that cannot be fixed in our peripheral RTL. However, its DREAD score reflects real exploitability (R:10, E:10) because it enables every other bus-level attack. It is scored to ensure the threat model is complete; its "fix" is a combination of software access conventions and the peripheral-level hardening we can apply (e.g., register zeroization reduces the value of unauthorized reads even without MMU protection).

**Why D-01 (FSM deadlock) scores HIGH rather than CRITICAL:**
The underlying CIA severity was rated Critical (permanent lockout) but DREAD scores it HIGH (5.8) because Reproducibility (3) and Exploitability (2) are very low — it requires a hardware fault event (radiation upset, voltage glitch), not a software attack sequence. The high Damage and Affected-Users scores bring it to 5.8. The architectural fix (clearing `busy` in the default clause) is trivial and should still be implemented.

**Why S-02/E-01 are combined:**
The SPI test harness (S-02: identity spoofing; E-01: privilege elevation) is a single root cause with two STRIDE manifestations. Combining avoids double-counting while reflecting the full severity.

**CIA-I-04 (Q1.15 overflow)** appears in the CIA analysis but not in the STRIDE document (an omission corrected here). It scores 6.6 (HIGH) due to silent wrong results from any bus master writing large-amplitude inputs.

---

## Triage Summary

The following five threats represent the highest-risk, most-actionable vulnerabilities and **must be addressed** in the DP3 countermeasure implementation:

---

**Priority 1 — S-02/E-01 (avg 8.6): SPI Test Harness Lock**

The production-synthesized SPI harness is the single largest attack surface expansion in the design. It gives any physical attacker full register read/write access with no authentication, bypassing all CPU software controls. Fixing this one root cause simultaneously mitigates T-02 (unauthorized CONTROL write via SPI), R-03 (indistinguishable origins), I-04 (MISO leakage), and partially I-01/I-02 (stale data reads via SPI). **Countermeasure:** Add a one-time-writable LOCK bit that, once set, disables all SPI write paths and returns zeros for SPI reads. This is the highest-leverage single RTL change available.

---

**Priority 2 — I-01 / I-02 (avg 8.6 / 8.0): Register Zeroization**

Stale output data and always-readable input data are both pure data-lifetime failures. Both are fixable in the same zeroization pass. **Countermeasure:** (a) Zero all OUTPUT_REAL/IMAG registers after results are copied in DONE state; (b) Zero all INPUT_REAL/IMAG registers when the DONE→IDLE transition occurs (inputs already latched into stage registers — zeroizing the peripheral input banks does not affect computation). This also reduces DPA leakage (I-03) at no timing cost.

---

**Priority 3 — D-02 (avg 8.4): Interrupt-Clear Register Bit**

The inability to acknowledge an interrupt without immediately triggering a new computation is a systemic firmware design flaw that causes CPU availability failures in any interrupt-driven TinyQV software. **Countermeasure:** Add CONTROL register bit 1 as `interrupt_clear` — when written 1, clears `done_flag` without asserting `fft_start`. This decouples "I have read the result" from "start the next computation" and eliminates the interrupt storm scenario.

---

**Priority 4 — D-04 (avg 7.6): Bus Write Error Signaling**

Silent write failures are the root cause of D-04 (inputs dropped while busy) and amplify every other silent-discard behavior (E-02, T-01 race, CIA-I-02). A firmware driver has no reliable way to know whether its write succeeded. **Countermeasure:** Add a `write_error` sticky flag (STATUS register bit 2) that is set whenever a write is silently ignored (busy-blocked input write, write to read-only/unmapped address). Firmware can poll or interrupt on this flag to detect and retry failed writes. This requires minimal additional logic (a few comparators and a flip-flop) but provides a critical feedback channel.

---

**Priority 5 — CIA-I-04 (avg 6.6): Butterfly Overflow Saturation**

Undetected arithmetic overflow in the butterfly addition/subtraction path produces silently wrong FFT results for any input with per-sample amplitudes above the Q1.15 safe range (~0.5 in normalized terms). Unlike the other threats above, this is a correctness-integrity issue with no bus-level workaround — it must be fixed in the arithmetic. **Countermeasure:** Replace plain 16-bit add/subtract in `butterfly_pipelined` Stage 2 (fft_8point.v:476–479) with saturating arithmetic: detect signed overflow by comparing operand and result sign bits, then clamp to `16'h7FFF` (max positive) or `16'h8000` (min negative). Expected area overhead: ~8–12 comparison + mux cells per output (4 outputs × ~10 cells = ~40 additional cells, <1% area increase).

---

*End of DREAD Scoring. Feed into: docs/CWE_FINDINGS.md (Prompt 5) and docs/MITIGATION_PLAN.md (Prompt 6).*
