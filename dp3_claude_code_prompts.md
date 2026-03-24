# AI-HDL 2026 — DP3 Claude Code Prompts (v2)
## Team Devrem | 8-Point FFT Accelerator on tinyQV
### Complete Prompt Sequence for Phase 3: Security Evaluation & Threat Mitigation

---

> **Workflow:**
> 1. Run prompts in Claude Code from your repo root (`D:\Cursor_And_Antigravity_Projects\aihdl_2026_devrem`)
> 2. All file paths are relative — `src/`, `docs/` — no absolute paths needed.
> 3. Prompts 1–10 run entirely in Claude Code (file creation & RTL edits).
> 4. After Prompt 10: push to GitHub → colleague pulls on WSL → runs iverilog & yosys → sends output back.
> 5. Prompts 11b & 12b ingest those results. Prompts 13–14 finalize everything.
> 6. Final push + tag to GitHub for submission.
>
> **If a Claude Code session breaks**, start the next prompt with:
> *"Read all files in src/ and docs/ to restore context, then proceed with Prompt N."*

---

## WEEK 1 — Security Assessment & Implementing Security Features

---

### Prompt 1 · Codebase Ingestion & Attack Surface Mapping

```
Read every Verilog source file in src/ (fft_8point.v, peripheral.v, tt_wrapper.v, fft_8point_tb.v)
and the synthesis script src/synth.ys. Also read docs/DESIGN_REPORT.md and 
docs/DP2_OPTIMIZATION_REPORT.md for architectural context.

This is an 8-Point FFT accelerator peripheral for a tinyQV RISC-V core. It uses:
- Memory-mapped registers (INPUT_REAL 0x00-0x1C, INPUT_IMAG 0x20-0x3C, CONTROL 0x40, 
  STATUS 0x44, OUTPUT_REAL 0x48-0x64, OUTPUT_IMAG 0x68-0x84)
- 16-bit signed fixed-point Q1.15 arithmetic
- 3-stage Radix-2 DIT butterfly with DP2 pipelining
- Clock gating, operand isolation, and W⁰ bypass optimizations

After reading, produce a structured "Attack Surface Map" as a markdown file 
docs/ATTACK_SURFACE_MAP.md that lists:

1. Every external interface (bus signals, memory-mapped registers, control/status bits,
   interrupt line, SPI test harness signals, TinyTapeout wrapper I/O).
2. Every trust boundary (CPU ↔ peripheral bus, peripheral ↔ FFT core, 
   test harness ↔ production logic).
3. Every state machine and its transitions (idle, computing, done, etc.).
4. Data flow paths: where user-supplied data enters, how it propagates through 
   butterfly stages, where results are read back.
5. Any clock/reset domain crossings.
6. Any debug or test-only logic that exists in the RTL.

Format each entry with: Name | Type | Location (file:line) | Trust Level | Notes.
This map will feed the threat model in the next step.
```

---

### Prompt 2 · CIA Triad Analysis

```
Read docs/ATTACK_SURFACE_MAP.md you just created.

Perform a CIA Triad analysis for our FFT accelerator peripheral. For each pillar, 
identify concrete threats specific to OUR design (not generic ones):

**Confidentiality:**
- Can a subsequent user read stale FFT output data from a previous computation?
- Are intermediate butterfly-stage registers cleared after completion?
- Can the SPI test harness be used to exfiltrate internal state in production?
- Can timing side-channels on the STATUS register leak information about input data?

**Integrity:**
- Can writing to OUTPUT registers corrupt results?
- What happens if CONTROL is written mid-computation — does the FSM corrupt state?
- Can overlapping writes to INPUT registers during active computation produce 
  wrong results silently (no error flag)?
- Are there integer overflow/underflow paths in the Q1.15 butterfly multiplications?

**Availability:**
- Can the FSM be locked into a permanent "busy" state by malformed input sequences?
- What happens on reset during mid-computation — does the peripheral recover cleanly?
- Can rapid repeated CONTROL writes starve the bus or hang the peripheral?

Write the analysis to docs/CIA_ANALYSIS.md. For each finding, include:
- Threat ID (CIA-C-01, CIA-I-01, CIA-A-01, etc.)
- Description of the specific vulnerability
- Affected signals/registers (reference file:line)
- Severity: Critical / High / Medium / Low
- Preliminary mitigation idea (one sentence)
```

---

### Prompt 3 · STRIDE Threat Model

```
Read docs/ATTACK_SURFACE_MAP.md and docs/CIA_ANALYSIS.md.

Apply the STRIDE threat model to our FFT accelerator. For each STRIDE category, 
analyze threats SPECIFIC to our memory-mapped FFT peripheral on tinyQV:

**Spoofing:** Can an unprivileged process access our peripheral's address range 
(0x00–0x84)? The tinyQV has no MMU — what does this imply? Could a rogue peripheral 
on the bus impersonate our FFT accelerator?

**Tampering:** Can input registers be modified AFTER computation starts but BEFORE 
results are latched? Can the CONTROL register be written from the test harness? 
Can output registers be overwritten by software to fake results?

**Repudiation:** Is there any logging or record of who initiated an FFT computation? 
Can we distinguish between a legitimate CPU-initiated FFT and one triggered via 
the SPI test path?

**Information Disclosure:** After FFT completes, do input registers still hold the 
original data? Do intermediate butterfly pipeline registers retain partial results? 
Is there a timing difference between all-zero input and non-zero input that leaks 
information?

**Denial of Service:** What is the minimum sequence to deadlock the FSM? Can 
rapid CONTROL toggles cause undefined behavior? What if reset is asserted and 
deasserted during stage 2 of computation?

**Elevation of Privilege:** Can the SPI test harness access registers that normal 
bus transactions cannot? Can writing to reserved/unused address offsets trigger 
unintended behavior? Does the peripheral respond to addresses outside 0x00–0x84?

Write the full STRIDE analysis to docs/STRIDE_ANALYSIS.md. For each threat, include:
- Threat ID (S-01, T-01, R-01, I-01, D-01, E-01, etc.)
- Category (which STRIDE letter)
- Attack scenario (2-3 sentences, specific to our RTL)
- Affected module and signals
- Cross-reference to CIA findings where applicable
- Severity: Critical / High / Medium / Low
```

---

### Prompt 4 · DREAD Risk Scoring

```
Read docs/CIA_ANALYSIS.md and docs/STRIDE_ANALYSIS.md.

Take every unique threat identified across both documents and score each one using 
the DREAD model (1-10 scale per dimension):

- **Damage:** How severe is the impact if exploited? (10 = full system compromise, 
  1 = cosmetic)
- **Reproducibility:** How easy is it to reproduce? (10 = every time, 1 = rare 
  race condition)
- **Exploitability:** What skill/access is needed? (10 = any bus master, 
  1 = needs physical probe)
- **Affected Users:** How many use-cases are impacted? (10 = all FFT users, 
  1 = single edge case)
- **Discoverability:** How easy is it to find? (10 = obvious from register map, 
  1 = requires differential power analysis)

Create docs/DREAD_SCORES.md with a ranked table sorted by average DREAD score 
(highest = most urgent). Include columns:
Threat ID | Description | D | R | E | A | D | Average | Priority Tier

Priority tiers:
- Average >= 7.0 → CRITICAL — must fix in DP3
- Average 5.0-6.9 → HIGH — should fix in DP3
- Average 3.0-4.9 → MEDIUM — document mitigation plan
- Average < 3.0 → LOW — acknowledge only

At the bottom, write a "Triage Summary" paragraph identifying the top 3-5 threats 
that we MUST address in our DP3 countermeasure implementation.
```

---

### Prompt 5 · CWE Identification

```
Read src/fft_8point.v, src/peripheral.v, src/tt_wrapper.v, and all docs created 
so far in docs/.

Search the codebase for vulnerabilities matching these hardware-relevant CWEs 
(Common Weakness Enumerations). For each CWE, check if it applies to our design 
and cite the specific file:line:

- CWE-1234: Hardware Internal or Debug Modes Allow Override of Locks
  → Check: Does our SPI test harness bypass any access controls?
  
- CWE-1231: Improper Prevention of Lock Bit Modification
  → Check: Can CONTROL register be written while STATUS shows busy?
  
- CWE-1239: Improper Zeroization of Hardware Register
  → Check: Are input/output/intermediate registers cleared after FFT completion 
    or on reset?

- CWE-1271: Uninitialized Value on Reset
  → Check: Do all registers in fft_8point.v and peripheral.v have defined 
    reset values?

- CWE-1280: Access Control Check Implemented After Asset Is Accessed
  → Check: Is data latched before the address decode validates the range?

- CWE-1272: Sensitive Information Uncleared Before Debug/Power State Transition
  → Check: What happens to FFT data registers during reset or if the peripheral 
    is clock-gated off?

- CWE-1262: Improper Access Control for Register Interface
  → Check: Does the peripheral respond to out-of-range addresses? Are output 
    registers writable by the CPU?

- CWE-1245: Improper Finite State Machines (FSMs) in Hardware Logic
  → Check: Are there unreachable states? Can external input force the FSM into 
    an undefined state? Is there a default case?

- CWE-1276: Hardware Child Block Has Missing Bus Signal
  → Check: Are all bus protocol signals (ready, valid, error) properly connected 
    between peripheral.v and the tinyQV bus?

Write findings to docs/CWE_FINDINGS.md. For each applicable CWE, include:
- CWE ID and title
- Applicable? YES/NO/PARTIAL
- Evidence: exact code snippet and file:line
- Link to related STRIDE/CIA threat IDs
- Recommended fix (1-2 sentences)
```

---

### Prompt 6 · Mitigation Plan

```
Read docs/DREAD_SCORES.md, docs/CWE_FINDINGS.md, docs/STRIDE_ANALYSIS.md, and 
docs/CIA_ANALYSIS.md.

Create a comprehensive docs/MITIGATION_PLAN.md that maps every identified 
vulnerability to a concrete RTL fix. Structure it as follows:

## Section 1: Critical Priority Countermeasures (MUST implement in DP3)
For each CRITICAL/HIGH threat from DREAD scoring:
- Threat ID and one-line description
- Root cause in RTL (file:line)
- Countermeasure design — describe the exact Verilog logic to add/modify:

  Likely countermeasures for our FFT accelerator include:
  a) **Register Zeroization:** Clear all input, output, and intermediate butterfly 
     registers on reset AND on FFT completion. Prevents data leakage between computations.
  b) **FSM Hardening:** Add a default/illegal-state recovery. If the FSM enters 
     an undefined state, force transition to IDLE and assert an error flag.
  c) **Bus Write Protection:** Make OUTPUT registers read-only from the bus. 
     Ignore writes to CONTROL while STATUS.busy=1 (or latch them for "next" operation).
  d) **Input Validation:** Reject or ignore writes to INPUT registers while 
     computation is active. Optionally flag an error.
  e) **Address Range Guard:** For bus addresses outside 0x00–0x84, return zero 
     and do not alter any internal state.
  f) **Debug/Test Lockout:** Add a LOCK bit or hardware strap that disables the 
     SPI test harness path in production mode.

- Validation approach — how will the testbench prove this fix works?
- Expected PPA impact (qualitative: negligible / small / moderate)

## Section 2: Medium/Low Priority (Document Only)
For remaining threats: state the risk acceptance rationale.

## Section 3: Implementation Order
Number the countermeasures in the order they should be coded, considering 
dependencies (e.g., FSM hardening before write-protection, since the FSM 
state is used in the guard logic).

## Section 4: Regression Risk Assessment
Which existing testbench tests (DC, impulse, Nyquist, sine, cosine) might 
be affected by each change? Flag any tests that need modification.
```

---

## WEEK 2 — Validation, Hardening & Documentation

---

### Prompt 7 · Implement Security Countermeasures — peripheral.v

```
Read docs/MITIGATION_PLAN.md and src/peripheral.v.

Implement the following security countermeasures in src/peripheral.v. Make each 
change surgically — do not refactor unrelated logic or break the existing 
bus interface protocol.

1. **Output Register Write-Protection:**
   - OUTPUT_REAL and OUTPUT_IMAG registers (addresses 0x48–0x84) must be READ-ONLY 
     from the bus side. Ignore any write transactions targeting these addresses.
   - The FFT core should still be able to write results to these registers internally.

2. **CONTROL Write Guard:**
   - If STATUS.busy == 1, ignore writes to the CONTROL register (address 0x40).
   - This prevents restarting a computation mid-flight.

3. **Input Register Lock During Computation:**
   - While STATUS.busy == 1, ignore writes to INPUT_REAL and INPUT_IMAG registers 
     (addresses 0x00–0x3C). This preserves data integrity during computation.

4. **Address Range Guard:**
   - For any bus read to an address outside the defined register map (0x00–0x84), 
     return 32'h0.
   - For any bus write to an address outside the defined register map, do nothing 
     (no side effects).

5. **Register Zeroization on Reset:**
   - On assertion of reset, clear ALL input, output, and status registers to zero.
   - Verify this is already the case; if not, add it.

6. **Post-Computation Input Clearing (Optional but recommended):**
   - When STATUS transitions from busy to done, clear INPUT_REAL and INPUT_IMAG 
     registers to zero. This prevents stale input data leakage.

After making changes, show me a summary diff of what was modified. Do NOT touch 
fft_8point.v in this prompt — that's next.
```

---

### Prompt 8 · Implement Security Countermeasures — fft_8point.v

```
Read docs/MITIGATION_PLAN.md and src/fft_8point.v.

Implement the following security countermeasures in src/fft_8point.v:

1. **FSM Hardening:**
   - Identify the FSM (state register and next-state logic).
   - Add a default case in the state transition logic that forces the FSM 
     back to IDLE state and asserts an error flag (add a new 1-bit output 
     signal `fsm_error` if one doesn't exist).
   - If the FSM uses a one-hot encoding, add an illegal-state detector: 
     if more than one bit is set or no bits are set, force to IDLE.

2. **Intermediate Register Zeroization:**
   - After the final FFT stage completes and results are latched to output 
     registers, clear ALL intermediate butterfly pipeline registers to zero.
   - This prevents partial-result leakage from internal state.

3. **Overflow Saturation (if not present):**
   - In the butterfly multiply-accumulate paths, check if the Q1.15 
     multiplication results are being truncated or if they can silently 
     overflow. If truncation is used, add saturation logic: clamp to 
     16'h7FFF (max positive) or 16'h8000 (max negative) on overflow.
   - This is both a correctness and integrity safeguard.

4. **Clean Reset Behavior:**
   - Verify that ALL internal state (stage registers, twiddle intermediates, 
     pipeline registers, FSM state) is driven to a known value on reset.
   - There should be no uninitialized flip-flops after reset deassertion.

After making changes, show me a summary diff. Flag any changes that might affect 
the critical timing path identified in DP2 (the pipelined butterfly multiply chain).
```

---

### Prompt 9 · Implement Test Harness Lockout — tt_wrapper.v

```
Read src/tt_wrapper.v and docs/MITIGATION_PLAN.md.

Implement a production lockout mechanism for any debug or SPI test paths:

1. Examine tt_wrapper.v for any test/debug signal paths (SPI test harness, 
   direct register access bypasses, scan chain enables, etc.).

2. Add a LOCK mechanism — choose the most appropriate approach:
   a) A dedicated input pin that, when tied high, disables all test/debug paths.
   b) A one-time-writable lock bit register: once set, test paths are permanently 
      disabled until reset.
   c) If the test harness is purely for simulation and shouldn't exist in synthesis, 
      wrap it in `ifdef SIMULATION` / `endif` guards.

3. When locked, any access through the test path should:
   - Return zeros for reads
   - Ignore writes
   - NOT affect the functional peripheral in any way

4. Update the port list if new signals were added. Make sure the wrapper still 
   conforms to the TinyTapeout pin budget (ui_in[7:0], uo_out[7:0], uio[7:0], 
   ena, clk, rst_n).

Show me the diff and explain which approach you chose and why.
```

---

### Prompt 10 · Security Validation Testbench

```
Read src/fft_8point_tb.v and all the RTL changes made in prompts 7-9.

Create a new testbench file src/security_tb.v that specifically validates 
every security countermeasure. Include these test cases:

**Test Group 1: Write Protection**
- TEST_SEC_01: Write to OUTPUT_REAL[0] (addr 0x48), then read it back. 
  Verify the write was ignored (value should be from last FFT, not the write).
- TEST_SEC_02: Write to an out-of-range address (e.g., 0x90), verify no 
  side effects on any register.

**Test Group 2: Computation Integrity Guards**
- TEST_SEC_03: Start FFT (write CONTROL=1). While STATUS.busy=1, attempt 
  to write CONTROL=1 again. Verify it's ignored (only one computation runs).
- TEST_SEC_04: Start FFT. While busy, write new values to INPUT_REAL[0]. 
  Wait for completion. Verify output matches the ORIGINAL input, not the 
  attempted overwrite.

**Test Group 3: Data Leakage Prevention**
- TEST_SEC_05: Run a full FFT with known non-zero inputs. After completion, 
  read INPUT registers — verify they are zeroed (if post-computation clearing 
  was implemented) or document that they retain values.
- TEST_SEC_06: Run FFT #1 with data pattern A. Run FFT #2 with data pattern B. 
  Verify FFT #2 output has NO residue from FFT #1 in any output register.

**Test Group 4: FSM Robustness**
- TEST_SEC_07: Assert reset mid-computation (during the busy state). 
  Deassert reset. Verify FSM returns to IDLE cleanly and all registers 
  are in a known-good state. Then run a normal FFT and verify correct output.
- TEST_SEC_08: Rapid CONTROL toggling — write 1, write 0, write 1 in 
  consecutive cycles. Verify the FSM handles this gracefully (either 
  runs one FFT or stays idle — no lockup).

**Test Group 5: Debug Lockout**
- TEST_SEC_09: If a LOCK mechanism was added, verify that when LOCK=1, 
  the test/debug path returns zeros and cannot modify peripheral state.

Each test must print PASS/FAIL and a descriptive message. At the end, 
print a summary: "SECURITY TESTS: X/Y PASSED".

Also output the exact commands our colleague should run on WSL after 
pulling from GitHub:
  cd src/
  iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v
  vvp sec_test
```

---

### ── HANDOFF POINT ──
> **After Prompt 10:**
> 1. Commit & push all changes to GitHub.
> 2. Colleague pulls on WSL.
> 3. Colleague runs the simulation commands from Prompts 10, 11a, and 12a.
> 4. Colleague sends you the terminal outputs.
> 5. You paste the outputs into Prompts 11b and 12b.

---

### Prompt 11a · Regression Test Preparation (run BEFORE colleague simulates)

```
Read src/fft_8point_tb.v and all RTL changes made in prompts 7-9.

Analyze whether any of our security changes could break the original 
5 functional tests (DC, Impulse, Nyquist, Sine, Cosine). Specifically:
- If we added post-computation input clearing, does the testbench 
  read input registers after completion and expect original values?
- Did we change any signal timing, latency, or handshake behavior 
  that the testbench depends on?

If the testbench needs modifications to accommodate our security 
changes, make those changes now and clearly comment each one with:
  // DP3-SEC: Modified because [security feature] changed [behavior]

Then output the exact commands our colleague should run on WSL:
  cd src/
  iverilog -o fft_test fft_8point.v peripheral.v fft_8point_tb.v
  vvp fft_test

Also remind them to run the security testbench if they haven't already:
  iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v
  vvp sec_test

Tell them to copy the FULL terminal output of both runs and send it back.
```

---

### Prompt 11b · Regression Test Analysis (run AFTER receiving colleague's output)

```
Here are the simulation results from our colleague's WSL environment.

=== REGRESSION TEST OUTPUT ===
<PASTE YOUR COLLEAGUE'S fft_test TERMINAL OUTPUT HERE>

=== SECURITY TEST OUTPUT ===
<PASTE YOUR COLLEAGUE'S sec_test TERMINAL OUTPUT HERE>

Analyze all results:

**Regression tests (DC, Impulse, Nyquist, Sine, Cosine):**
- Report PASS/FAIL for each
- If any failed, diagnose root cause — is it from our security changes?
- If a fix is needed, make it now (either RTL or testbench)

**Security tests (TEST_SEC_01 through TEST_SEC_09):**
- Report PASS/FAIL for each
- If any failed, diagnose and fix the RTL or testbench

Create docs/REGRESSION_RESULTS.md documenting:
- Table: Test Name | Type (Functional/Security) | Status | Notes
- Any modifications made and justification
- If fixes were made, output updated commands for colleague to re-run

Create docs/SECURITY_VALIDATION_RESULTS.md documenting:
- Each security test, what it validated, and the result
- "Break your own design" narrative for 2-3 attack scenarios
```

---

### Prompt 12a · Synthesis Preparation (run BEFORE colleague synthesizes)

```
Read src/synth.ys, synthesis_report.txt, and synthesis_report_dp2.txt.

Verify that synth.ys will correctly synthesize the hardened design:
- Are all modified source files listed in read_verilog commands?
- If any new modules, ports, or files were added in prompts 7-9, 
  update synth.ys accordingly.
- Make sure the top module and hierarchy are correct.

After verifying/updating synth.ys, output the exact commands our 
colleague should run on WSL:

  cd src/
  yosys synth.ys 2>&1 | tee ../synthesis_report_dp3.txt

Tell them to send back the full contents of synthesis_report_dp3.txt.
```

---

### Prompt 12b · PPA Impact Analysis (run AFTER receiving synthesis report)

```
Here is the DP3 synthesis report from our colleague:

=== SYNTHESIS REPORT DP3 ===
<PASTE FULL CONTENTS OF synthesis_report_dp3.txt HERE>

Also read the existing synthesis_report.txt (DP1) and synthesis_report_dp2.txt 
(DP2) from the repo root for historical comparison.

Create docs/PPA_IMPACT_ANALYSIS.md with:

1. **Side-by-Side Comparison Table:**
   | Metric              | DP1      | DP2      | DP3 (Secure) | Delta DP2→DP3 |
   |---------------------|----------|----------|--------------|---------------|
   | Total Cells         |          |          |              |               |
   | Flip-Flops          |          |          |              |               |
   | Logic Levels        |          |          |              |               |
   | Critical Path (ns)  |          |          |              |               |
   | Est. Max Freq (MHz) |          |          |              |               |

2. **Per-Feature Overhead Breakdown:**
   For each security feature added (output write-protect, FSM hardening, 
   zeroization, address guard, input lock, debug lockout), estimate its 
   individual contribution to area overhead. Use reasoning like:
   "Address range guard adds ~5-10 comparators = ~20-40 cells."

3. **Cost-Benefit Assessment:**
   For each feature: overhead cells vs. threat severity mitigated.
   Conclude whether the security overhead is justified.

4. **Timing Impact:**
   Did any security logic land on the critical path? If so, which feature 
   and is there a way to mitigate it (e.g., register the guard output)?
```

---

### Prompt 13 · DP3 Security Report

```
Read ALL docs created during this phase:
- docs/ATTACK_SURFACE_MAP.md
- docs/CIA_ANALYSIS.md
- docs/STRIDE_ANALYSIS.md
- docs/DREAD_SCORES.md
- docs/CWE_FINDINGS.md
- docs/MITIGATION_PLAN.md
- docs/REGRESSION_RESULTS.md
- docs/SECURITY_VALIDATION_RESULTS.md
- docs/PPA_IMPACT_ANALYSIS.md

Also read the current state of src/fft_8point.v, src/peripheral.v, and 
src/tt_wrapper.v for the final implemented code.

Create docs/DP3_SECURITY_REPORT.md — the final submission document. Structure:

# DP3 Security Report — 8-Point FFT Accelerator
## Team Devrem | AI-HDL 2026

### 1. Executive Summary
Brief paragraph: what the design is, what threats were found, what was fixed, 
and the PPA cost.

### 2. Security Assessment
#### 2.1 Attack Surface Overview (summarize the map)
#### 2.2 CIA Triad Analysis (summarize key findings)
#### 2.3 STRIDE Threat Model (summarize with threat count per category)
#### 2.4 DREAD Risk Scoring (include the ranked table, highlight top threats)
#### 2.5 CWE Findings (list applicable CWEs with status)

### 3. Countermeasure Implementation
For each implemented security feature:
- What vulnerability it addresses (threat IDs)
- RTL changes made (describe logic, reference files)
- Code snippet showing the key security logic added

### 4. Validation Results
#### 4.1 Security Test Results (from security_tb.v — table of all tests)
#### 4.2 Regression Test Results (from original testbench — all pass/fail)
#### 4.3 "Break Your Own Design" Narrative — describe 2-3 specific attack 
     scenarios you simulated and how the hardened design blocked them.

### 5. PPA Overhead Analysis
Include the comparison table from PPA_IMPACT_ANALYSIS.md and the cost-benefit 
conclusion.

### 6. Trade-offs & Limitations
What threats remain unmitigated and why? What would you add with more time?

### 7. LLM Usage Log
List the Claude Code prompts used (reference this prompt document) and briefly 
note what each accomplished.

Make this report comprehensive but concise — aim for a document that a judge 
can read in 15 minutes and come away confident in the team's security work.
```

---

### Prompt 14 · Final Tagging & Submission Prep

```
We're preparing the final DP3 submission. Do the following:

1. Verify the repo structure is clean. List all files and confirm:
   - src/fft_8point.v (hardened)
   - src/peripheral.v (hardened)
   - src/tt_wrapper.v (hardened)
   - src/fft_8point_tb.v (original or lightly modified)
   - src/security_tb.v (new — security validation)
   - src/synth.ys (updated if needed)
   - docs/DP3_SECURITY_REPORT.md
   - docs/ (all supporting analysis documents)
   - synthesis_report_dp3.txt
   - README.md

2. Update README.md:
   - Add a "Design Phase 3 (DP3)" section under the existing DP2 content
   - List the security features added
   - Add run instructions for the security testbench
   - Update the PPA table with DP3 numbers
   - Update the file structure listing

3. Update docs/LLM_PROMPT_LOG.md:
   - Append entries for all DP3 prompts used
   - Format: Prompt # | Purpose | Key Output | Date

4. Show me the exact git commands to run on my machine:
   git add -A
   git commit -m "DP3: Security evaluation, countermeasures, and validation"
   git tag -a DP3-Submission -m "Design Phase 3 - Security hardened FFT accelerator"
   git push origin main --tags

5. Do a final sanity check:
   - Are there any .Zone.Identifier files that should be gitignored?
   - Is there any sensitive data accidentally committed?
   - Does the .gitignore cover synthesis artifacts that shouldn't be in the repo?
```

---

## QUICK REFERENCE — Prompt Dependency Chain & Workflow

```
═══════════════════════════════════════════════════════════════
  YOUR PC (Claude Code)          COLLEAGUE'S WSL
═══════════════════════════════════════════════════════════════

  Prompt 1  (Attack Surface)
      ├─→ Prompt 2  (CIA)
      ├─→ Prompt 3  (STRIDE)
      │       └─→ Prompt 4  (DREAD)
      └─→ Prompt 5  (CWE)
                  └──→ Prompt 6  (Mitigation Plan)
                          │
                  ┌───────┘
                  ▼
          Prompt 7  (Fix peripheral.v)
          Prompt 8  (Fix fft_8point.v)
          Prompt 9  (Fix tt_wrapper.v)
          Prompt 10 (Security testbench)
          Prompt 11a (Regression prep)
          Prompt 12a (Synthesis prep)
                  │
                  ▼
          ┌── git push ──────────────→  git pull
          │                             iverilog (func test)
          │                             iverilog (sec test)
          │                             yosys synth.ys
          │   ←── terminal output ────  sends results back
          │
          Prompt 11b (Analyze test results)
          Prompt 12b (PPA analysis)
          Prompt 13  (Final report)
          Prompt 14  (README + tag)
                  │
                  ▼
          ┌── git push + tag ────────→  Final repo state
          │
       DP3-Submission ✓
```

---

## TIPS FOR BEST RESULTS

- **Run Prompts 1–6 in one Claude Code session** so it retains full codebase context.
- **Run Prompts 7–10 + 11a + 12a in a second session** — start with: *"Read all files in src/ and docs/ to restore context."*
- **Run Prompts 11b + 12b + 13 + 14 in a third session** — start with: *"Read all files in src/ and docs/ to restore context."*
- **Push to GitHub after Prompt 12a** so your colleague has all the files.
- **If any tests fail in 11b**, fix and push again → colleague re-runs → re-paste. Iterate until clean.
- **Add those .Zone.Identifier files to .gitignore** — they're Windows artifacts and shouldn't be in the repo.
