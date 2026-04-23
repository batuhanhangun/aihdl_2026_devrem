# AI-HDL 2026 - Final Project Report (DP1-DP4)

**Team:** Devrem
**Team Members:** Batuhan Hangun, Safak Sahin
**Project:** 8-Point FFT Accelerator Peripheral for TinyQV RISC-V
**Competition:** AI-HDL 2026 Design Competition
**Final Submission Date:** April 2026
**Technology:** SkyWater 130nm (sky130) via Tiny Tapeout

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Project Overview](#2-project-overview)
3. [Design Phase 1 — RTL Design & Verification](#3-design-phase-1--rtl-design--verification)
4. [Design Phase 2 — PPA Optimization](#4-design-phase-2--ppa-optimization)
5. [Design Phase 3 — Security Hardening](#5-design-phase-3--security-hardening)
6. [Design Phase 4 — Physical Design & Tapeout](#6-design-phase-4--physical-design--tapeout)
7. [Final PPA Metrics](#7-final-ppa-metrics)
8. [AI-Assisted Design Methodology](#8-ai-assisted-design-methodology)
9. [Lessons Learned & Reflections](#9-lessons-learned--reflections)
10. [Appendix](#10-appendix)

---

## 1. Executive Summary

This report documents the complete design journey of an **8-Point FFT (Fast Fourier Transform) Accelerator** from initial RTL concept to manufacturable GDSII layout, developed over four design phases spanning 16 weeks.

**Key Achievements Across All Phases:**

| Phase | Focus | Key Outcome |
|-------|-------|-------------|
| **DP1** | RTL Design | Fully functional 8-point FFT with SPI peripheral interface |
| **DP2** | PPA Optimization | 11.8% cell reduction via pipelining, clock gating, resource sharing |
| **DP3** | Security Hardening | 9 countermeasures (CM-A-I), 11/11 security tests pass, net 6.4% smaller than DP1 |
| **DP4** | Physical Design | Complete OpenLane ASIC flow: Synthesis, Floorplan, P&R, CTS, Sign-off, GDSII |

**Final Design Statistics:**

| Metric | Value |
|--------|-------|
| Technology | SkyWater 130nm (sky130) |
| Tile Size | 6x2 Tiny Tapeout (1030.4 x 225.76 um) |
| Target Clock | 71.5 MHz (14 ns period) |
| Standard Cells | 14,715 (post-PD, including buffers) |
| Core Utilization | 59.8% |
| Total Power | 6.30 mW |
| DRC / LVS | CLEAN / CLEAN |
| Security Tests | 11/11 PASS |
| Functional Tests | 3/3 PASS |

---

## 2. Project Overview

### 2.1 What is an FFT Accelerator?

The Fast Fourier Transform (FFT) converts signals from the time domain to the frequency domain. It is one of the most important algorithms in digital signal processing, used in audio processing, telecommunications (OFDM/5G), medical imaging, radar, and vibration analysis.

Our design implements an **8-point Radix-2 Decimation-in-Time (DIT)** FFT using 16-bit Q1.15 fixed-point arithmetic, delivering real-time frequency analysis capability to a resource-constrained RISC-V SoC.

### 2.2 System Architecture

```
                    TinyQV RISC-V CPU
                          |
                     CPU Bus (32-bit)
                          |
              +-----------+-----------+
              |   tqvp_fft8 Peripheral |
              |  (peripheral.v)        |
              |                        |
              |  +-----------------+   |
              |  | fft_8point Core |   |
              |  | 3-stage DIT     |   |
              |  | Pipelined BF    |   |
              |  +-----------------+   |
              |                        |
              +---+-------+-------+---+
                  |       |       |
              SPI I/F  ui_in   uo_out
              (test)   (sync)  (status)
```

**Module Hierarchy:**
- `tt_um_tqv_peripheral_harness` (top — Tiny Tapeout wrapper)
  - `tqvp_fft8` (peripheral — register interface + control)
    - `fft_8point` (FFT core — butterfly computation)
  - `spi_reg` (SPI test harness)
  - `synchronizer` (CDC for inputs)

### 2.3 Interface & Pinout

| Pin Group | Signals | Function |
|-----------|---------|----------|
| `ui_in[7:0]` | Dedicated inputs | Synchronized to peripheral (unused in current design) |
| `uo_out[7:0]` | Dedicated outputs | `[0]`=fft_busy, `[1]`=done_flag (masked when locked) |
| `uio[4]` | SPI CS_N | SPI chip select (active low) |
| `uio[5]` | SPI CLK | SPI clock input |
| `uio[6]` | SPI MOSI | SPI data in |
| `uio[3]` | SPI MISO | SPI data out |
| `uio[0]` | Interrupt | FFT computation complete |
| `uio[1]` | Data Ready | Register data available |

### 2.4 Register Map

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x00-0x1C | INPUT_REAL[0-7] | Write-only | Real input samples (16-bit Q1.15) |
| 0x20-0x3C | INPUT_IMAG[0-7] | Write-only | Imaginary input samples (16-bit Q1.15) |
| 0x40 | CONTROL | R/W | [0]=start [1]=int_clear [2]=spi_lock [3]=err_clear |
| 0x44 | STATUS | Read-only | [0]=busy [1]=done [2]=write_error |
| 0x48-0x64 | OUTPUT_REAL[0-7] | Read-only | Real FFT output |
| 0x68-0x84 | OUTPUT_IMAG[0-7] | Read-only | Imaginary FFT output |

---

## 3. Design Phase 1 — RTL Design & Verification

**Duration:** January 2026
**Objective:** Design a functional FFT accelerator peripheral from scratch using AI-assisted RTL generation.

### 3.1 Algorithm Choice

We selected the **Radix-2 DIT FFT** for its balance of simplicity and efficiency:
- 3 computation stages for 8 points
- Bit-reversed input ordering (0,4,2,6,1,5,3,7)
- Pre-computed twiddle factors stored as constants (W8^0 through W8^3)
- In-place computation possible

### 3.2 Implementation

The FFT core (`fft_8point.v`) implements:
- **State Machine:** IDLE -> STAGE1 -> STAGE2 -> STAGE3 -> DONE
- **Fixed-Point Arithmetic:** 16-bit Q1.15 format (1 sign bit, 15 fractional bits)
- **Twiddle Factors:** Hard-coded constants for W8^k (k=0..3)
- **Butterfly Unit:** Complex multiply-add/subtract with proper rounding

The peripheral wrapper (`peripheral.v`) provides:
- 32-bit aligned memory-mapped register interface
- Interrupt generation on FFT completion
- Compatible with TinyQV RISC-V core bus protocol

### 3.3 Verification

Three functional test cases validated the core:

| Test | Input | Expected | Result |
|------|-------|----------|--------|
| DC Signal | All inputs = 0x4000 | Energy in bin 0 only | **PASS** |
| Impulse | x[0]=0x7FFF, rest=0 | Flat magnitude spectrum | **PASS** |
| Nyquist | Alternating +/- max | Energy in bin 4 only | **PASS** |

### 3.4 DP1 Baseline Metrics

| Metric | Value |
|--------|-------|
| Total Cells | 12,172 |
| Flip-Flops | 854 |
| Logic Gates | 11,318 |
| Synthesis Errors | 0 |

---

## 4. Design Phase 2 — PPA Optimization

**Duration:** February 2026
**Objective:** Optimize Power, Performance, and Area while maintaining functional correctness.

### 4.1 Optimizations Applied

| # | Optimization | Target | Technique |
|---|-------------|--------|-----------|
| 1 | Butterfly Pipelining | Performance | 2-stage pipeline registers in multiply path (improved Fmax) |
| 2 | Clock Gating | Power | Gate stage/output/input registers when idle (reduce switching activity) |
| 3 | Operand Isolation | Power | Zero butterfly inputs when not computing (eliminate glitch power) |
| 4 | Trivial Twiddle Bypass | Area + Power | Skip multiplier for W8^0=1+j0 (67% of butterflies) |
| 5 | Synthesis Enhancement | Area | Flatten hierarchy + resource sharing in Yosys |

### 4.2 Results

| Metric | DP1 | DP2 | Change |
|--------|-----|-----|--------|
| Total Cells | 12,172 | 10,731 | **-11.8%** |
| Flip-Flops | 854 | 923 | +8.1% (pipeline regs) |
| Logic Gates | 11,318 | 9,808 | **-13.3%** |
| Latency | ~15 cycles | ~28 cycles | +87% (pipelining trade-off) |

**Trade-off:** The 2-stage pipeline doubled latency from ~15 to ~28 cycles but enabled higher clock frequency and significantly reduced area through better resource sharing. For an FFT accelerator peripheral, throughput matters more than single-computation latency.

### 4.3 Regression

All 3 functional tests continued to pass after optimization.

---

## 5. Design Phase 3 — Security Hardening

**Duration:** March 2026
**Objective:** Identify and mitigate security vulnerabilities through structured threat modeling.

### 5.1 Threat Modeling Process

We performed a comprehensive security analysis using three frameworks:

1. **CIA Triad Analysis** — Assessed Confidentiality, Integrity, and Availability across all data paths
2. **STRIDE Analysis** — Identified 18 threats across Spoofing, Tampering, Information Disclosure, Denial of Service, and Elevation of Privilege categories
3. **DREAD Scoring** — Quantified risk for each threat on a 1-10 scale to prioritize mitigations

Additionally, we mapped 9 hardware Common Weakness Enumerations (CWEs) relevant to our design.

### 5.2 Key Vulnerabilities Found

| Vulnerability | Severity | CWE | Description |
|--------------|----------|-----|-------------|
| SPI test harness always active | CRITICAL (8.6) | CWE-1191 | Production silicon has unauthenticated backdoor |
| Input registers readable | CRITICAL (8.0) | — | Data leakage via SPI read-back |
| No interrupt-clear path | CRITICAL (8.4) | — | DoS: can't acknowledge FFT completion without restart |
| Silent write drops | CRITICAL (7.6) | — | Software has no way to detect rejected writes |
| Butterfly overflow | HIGH (6.6) | CWE-682 | 16-bit addition silently wraps |
| FSM deadlock | HIGH (5.8) | CWE-1245 | Default state leaves busy=1 forever |

### 5.3 Countermeasures Implemented

| CM | Threat Addressed | Implementation |
|----|-----------------|----------------|
| **CM-A** | SPI backdoor (S-02/E-01) | One-time-writable LOCK bit gates all SPI transactions |
| **CM-B** | Data leakage (I-01/I-02) | Input/stage registers zeroized on FFT completion |
| **CM-C** | Interrupt DoS (D-02) | CONTROL[1] clears done_flag independently |
| **CM-D** | Silent failures (D-04) | STATUS[2] sticky write-error flag |
| **CM-E** | Arithmetic overflow (T-03) | 17-bit saturation with clamp on Stage 2 butterflies |
| **CM-F** | FSM deadlock (D-01) | Default clause recovery + fsm_error port |
| **CM-G** | Uninitialized regs (CWE-1271) | All DFFs reset-initialized to 0 |
| **CM-H** | Input read-back (I-02) | Input addresses removed from read mux |
| **CM-I** | State leakage (I-04) | uo_out masked to 0 when spi_lock=1 |

### 5.4 Validation Results

**Security regression:** 11/11 checks PASS

| Category | Tests | Result |
|----------|-------|--------|
| Write protection (CM-D) | 3 | PASS |
| Computation integrity (CM-B) | 1 | PASS |
| Data leakage prevention (CM-B, CM-H) | 2 | PASS |
| FSM robustness (CM-F, CM-G) | 2 | PASS |
| Debug lockout (CM-A, CM-I) | 3 | PASS |

**Functional regression:** 3/3 original tests PASS (security features do not break FFT computation)

### 5.5 PPA Impact

| Metric | DP2 | DP3 | Delta | DP3 vs DP1 |
|--------|-----|-----|-------|------------|
| Total Cells | 10,731 | 11,396 | +6.2% | **-6.4%** |
| Flip-Flops | 923 | 925 | +0.2% | +8.3% |
| Logic Gates | 9,808 | 10,471 | +6.8% | -7.5% |

The security overhead (~665 cells) is dominated by CM-G (reset mux on DFFs, ~200-250 cells) and CM-E (17-bit saturation, ~200-250 cells). Despite this, DP3 remains **6.4% smaller** than the DP1 baseline.

---

## 6. Design Phase 4 — Physical Design & Tapeout

**Duration:** April 2026
**Objective:** Take the DP3-hardened RTL through the complete ASIC physical design flow to produce a manufacturable GDSII layout.

### 6.1 OpenLane ASIC Flow

The physical design was performed using **OpenLane (LibreLane 3.0.2)** with the **SkyWater 130nm PDK** (sky130), targeting a **6x2 Tiny Tapeout tile** (~1030x226 um). The initial 1x2 tile was too small (356% utilization); a 4x2 attempt also failed at detailed placement due to congestion. The 6x2 tile provided adequate headroom at ~60% utilization.

#### Flow Steps Executed:

| Step | Tool | Purpose |
|------|------|---------|
| 1. Synthesis | Yosys + ABC | RTL to gate-level netlist with sky130 standard cells |
| 2. Floorplanning | OpenROAD | Die area definition, I/O pin placement, power grid |
| 3. Placement | OpenROAD | Standard cell placement + timing-driven optimization |
| 4. CTS | OpenROAD | Clock tree synthesis for balanced clock distribution |
| 5. Routing | OpenROAD | Global and detailed routing (met1-met4) |
| 6. STA | OpenSTA | Static timing analysis (setup + hold) |
| 7. DRC | Magic/KLayout | Design rule check for manufacturability |
| 8. LVS | Netgen | Layout vs. schematic verification |
| 9. GDSII | Magic | Final layout generation |

#### Configuration:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| CLOCK_PERIOD | 14 ns (~71.5 MHz) | TinyQV integration requirement |
| PL_TARGET_DENSITY_PCT | 65% | Adequate headroom for buffers and routing on 6x2 |
| FP_SIZING | absolute | Fixed die footprint for TT tile |
| RT_MAX_LAYER | met4 | TT standard (no met5 power rings) |
| RUN_CTS | 1 | Clock tree required for timing closure |
| Hold slack margin | 0.1 ns (placement) / 0.05 ns (GRT) | Guardband for manufacturing variation |
| Tile size | 6x2 | Required to fit 103K um² design + infrastructure |

### 6.2 Synthesis Results

| Metric | Value |
|--------|-------|
| Total Standard Cells | 14,715 |
| Sequential Cells (FFs) | 988 |
| Multi-Input Combinational | 7,508 |
| Timing Repair Buffers | 2,469 |
| Clock Buffers/Inverters | 157 |
| Antenna Diodes | 206 |
| Fill + Tap Cells | 30,460 |
| Total Instance Area | 134,989 um² (std cells) |
| Core Utilization | 59.8% |

### 6.3 Timing Results (STA)

Timing was analyzed across 9 PVT corners. The design meets timing at nominal and fast corners. The slow corner (ss_100C_1v60) has setup violations, which is expected for this clock frequency under extreme operating conditions.

| Corner | Setup Slack (ns) | Hold Slack (ns) | Setup Violations |
|--------|-----------------|-----------------|-----------------|
| nom_tt_025C_1v80 | **+3.17** | **+0.31** | 0 |
| nom_ff_n40C_1v95 | **+4.39** | **+0.10** | 0 |
| nom_ss_100C_1v60 | -5.38 | **+0.72** | 361 |
| min_tt_025C_1v80 | **+3.33** | **+0.31** | 0 |
| min_ff_n40C_1v95 | **+4.50** | **+0.10** | 0 |
| min_ss_100C_1v60 | -4.55 | **+0.80** | 361 |
| max_tt_025C_1v80 | **+3.04** | **+0.32** | 0 |
| max_ff_n40C_1v95 | **+4.30** | **+0.11** | 0 |
| max_ss_100C_1v60 | -6.24 | **+0.63** | 372 |

**Hold timing:** Zero violations across all corners.
**Setup timing:** Clean at nominal (tt) and fast (ff) corners. The slow corner (ss, 100C, 1.60V) violations are acceptable — this represents an extreme operating condition well beyond typical use.

### 6.4 Sign-off Results

| Check | Result | Details |
|-------|--------|---------|
| **DRC (Magic)** | **CLEAN** | 0 violations |
| **LVS (Netgen)** | **CLEAN** | 0 device/net/pin mismatches |
| **Antenna** | **CLEAN** | 0 violating nets, 0 violating pins |
| **Power Grid** | **CLEAN** | 0 violations (VPWR and VGND) |
| **Illegal Overlap** | **CLEAN** | 0 overlaps |
| **Routing DRC** | **CLEAN** | 0 errors after 11 iterations |

### 6.5 Power Analysis

| Power Component | Value |
|----------------|-------|
| Internal Power | 4.60 mW |
| Switching Power | 1.69 mW |
| Leakage Power | 0.25 uW |
| **Total Power** | **6.30 mW** |

### 6.6 Physical Design Summary

| Metric | Value |
|--------|-------|
| Die Area | 1030.4 x 225.76 um (6x2 tile) |
| Core Area | 1024.88 x 220.32 um = 225,802 um² |
| Core Utilization | 59.8% |
| Wire Length | 461,135 um |
| Via Count | 92,018 |
| Metal Layers Used | met1 - met4 |
| IR Drop (worst) | 0.161 mV (negligible) |
| Clock Tree Buffers | 149 buffers + 8 inverters |

---

## 7. Final PPA Metrics

### 7.1 Evolution Across Phases

| Metric | DP1 | DP2 | DP3 | DP4 (Physical) |
|--------|-----|-----|-----|-----|
| Cells (Yosys) | 12,172 | 10,731 | 11,396 | 14,715 (sky130) |
| Flip-Flops | 854 | 923 | 925 | 988 |
| Area (um^2) | — | — | — | 134,989 (std cells) |
| Die Area | — | — | — | 1030.4 x 225.76 um |
| Clock (MHz) | — | — | — | 71.5 (nom corner clean) |
| Power (mW) | — | — | — | 6.30 |
| DRC/LVS | — | — | — | **CLEAN / CLEAN** |
| Security Tests | 0/0 | 0/0 | 11/11 | 11/11 |
| Functional Tests | 3/3 | 3/3 | 3/3 | 3/3 |

### 7.2 Key Trade-offs

1. **Area vs. Security:** DP3 added ~665 cells (6.2% over DP2) for 9 security countermeasures. This is a favorable trade-off — the design remains 6.4% smaller than DP1 while being substantially more secure.

2. **Latency vs. Throughput:** DP2 pipelining doubled single-computation latency (~15 to ~28 cycles) but enabled higher clock frequency. For a peripheral accelerator, this is the correct trade-off.

3. **Tile Size vs. Routability:** The design required a 6x2 tile (originally targeted 1x2). The sky130 standard cell library produces physically larger cells than abstract gate estimates suggested. After accounting for timing repair buffers (+2,469 cells), clock tree (+157 cells), antenna diodes (+206 cells), and infrastructure (30,460 fill/tap cells), the 6x2 tile at 59.8% utilization provided clean DRC/LVS and adequate timing margins.

---

## 8. AI-Assisted Design Methodology

### 8.1 Tools & Models Used

| Tool | Purpose | Phase |
|------|---------|-------|
| **Claude (Anthropic)** | RTL generation, security analysis, documentation | All phases |
| **Icarus Verilog** | Functional simulation | DP1-DP3 |
| **Yosys** | RTL synthesis | DP1-DP3 |
| **OpenLane** | ASIC physical design flow | DP4 |
| **GTKWave** | Waveform visualization | DP1-DP3 |

### 8.2 AI-First Design Flow

Our methodology leveraged LLMs throughout the entire design process:

1. **DP1 — Architecture & RTL:** AI generated the initial FFT core architecture, butterfly computation, and peripheral interface. Human review ensured algorithmic correctness and TinyQV compatibility.

2. **DP2 — Optimization:** AI proposed and implemented five optimization categories. Human validated PPA improvements through synthesis comparison.

3. **DP3 — Security:** AI performed threat modeling (CIA, STRIDE, DREAD, CWE analysis) and designed countermeasures. Human reviewed threat severity and validated security tests.

4. **DP4 — Physical Design:** AI prepared OpenLane configuration and flow scripts. Human colleague executed the physical design tools and returned results for analysis.

### 8.3 Prompt Engineering

All significant AI interactions were logged in `docs/LLM_PROMPT_LOG.md`. Key prompt strategies:

- **Iterative refinement:** Start with high-level requirements, progressively add constraints
- **Context preservation:** Provide prior phase results as context for new phase work
- **Verification-first:** Always generate testbenches alongside RTL changes
- **Documentation alongside code:** Generate reports concurrent with implementation

---

## 9. Lessons Learned & Reflections

### 9.1 What Worked Well

1. **AI-generated RTL was surprisingly capable.** The FFT core produced by Claude was functionally correct from the first synthesis attempt, requiring only optimization and security hardening iterations.

2. **Structured threat modeling paid off.** The CIA/STRIDE/DREAD framework identified vulnerabilities that would have been easy to miss in a less systematic approach. The SPI test harness backdoor (CM-A) is a real-world vulnerability pattern.

3. **DP2 optimizations compounded well.** The 11.8% area reduction from DP2 provided "headroom" for DP3 security features, resulting in a net win despite adding 9 countermeasures.

4. **Incremental design phases forced good engineering.** Each phase built on a validated foundation, preventing the accumulation of untested changes.

### 9.2 Challenges Encountered

1. **Tile size estimation gap.** Our Yosys gate-level estimates (~11,400 cells) did not predict the physical area requirements (~103,292 um² with sky130 cells). The design needed a 6x2 tile instead of the expected 1x2. This is a common pitfall when moving from abstract synthesis to physical design — sky130 standard cells are significantly larger than generic gates, and the OpenLane flow adds substantial infrastructure (timing repair buffers, clock tree, antenna diodes, fill/tap cells).

2. **Security vs. area trade-offs.** Some countermeasures (CM-G: reset initialization on all DFFs) have a per-register cost that scales with design size. Careful analysis was needed to ensure the overhead was acceptable.

3. **Clock domain crossing.** The SPI interface operates on an external clock domain, requiring proper synchronization (2-stage CDC) on all input paths. This is a common but critical correctness requirement.

4. **Slow-corner timing closure.** The ss_100C_1v60 corner has setup violations at 71.5 MHz. While acceptable for this project (nominal corner is clean), achieving timing closure across all PVT corners would require either relaxing the clock period or more aggressive optimization.

### 9.3 What We Would Do Differently

1. **Start with security requirements.** Retrofitting security (DP3) is harder than designing it in from DP1. A threat model before RTL would have avoided the SPI backdoor entirely.

2. **Formal verification.** While simulation-based testing caught our bugs, formal methods (e.g., SymbiYosys) could provide stronger guarantees, especially for security properties.

3. **Power estimation earlier.** Physical design power numbers (DP4) may differ significantly from gate-level estimates. Earlier power analysis would inform optimization decisions.

---

## 10. Appendix

### 10.1 Repository Structure

```
aihdl_2026_devrem/
|-- gds/
|   |-- tt_um_tqv_peripheral_harness.gds  # Final GDSII layout
|   |-- tt_um_tqv_peripheral_harness.lef  # Abstract layout (LEF)
|   |-- chip_render.png                   # KLayout render of chip
|   `-- metrics.json                      # OpenLane metrics
|-- src/
|   |-- fft_8point.v            # FFT core (DP2 pipeline + DP3 security)
|   |-- peripheral.v            # Register interface (DP3 hardened)
|   |-- tt_wrapper.v            # Tiny Tapeout top-level wrapper
|   |-- fft_8point_tb.v         # Functional testbench (DP1)
|   |-- security_tb.v           # Security regression (DP3, 11 checks)
|   |-- config.json             # OpenLane configuration
|   |-- synth.ys                # Yosys synthesis script
|   `-- test_harness/           # SPI test infrastructure
|       |-- synchronizer.sv
|       |-- spi_reg.sv
|       |-- rising_edge_detector.sv
|       |-- falling_edge_detector.sv
|       `-- reclocking.sv
|-- docs/
|   |-- DESIGN_REPORT.md            # DP1 report
|   |-- DP2_OPTIMIZATION_REPORT.md  # DP2 report
|   |-- DP3_SECURITY_REPORT.md      # DP3 report
|   |-- DP4_FINAL_PROJECT_REPORT.md # This report (DP4 / final)
|   |-- ATTACK_SURFACE_MAP.md       # DP3 threat surface
|   |-- CIA_ANALYSIS.md             # DP3 CIA analysis
|   |-- STRIDE_ANALYSIS.md          # DP3 STRIDE catalogue
|   |-- DREAD_SCORES.md             # DP3 risk ranking
|   |-- CWE_FINDINGS.md             # DP3 hardware CWEs
|   |-- MITIGATION_PLAN.md          # DP3 countermeasure specs
|   |-- SECURITY_VALIDATION_RESULTS.md
|   |-- PPA_IMPACT_ANALYSIS.md
|   |-- REGRESSION_RESULTS.md
|   |-- DP4_OPENLANE_INSTRUCTIONS.md # OpenLane run guide
|   `-- LLM_PROMPT_LOG.md
|-- info.yaml                   # Tiny Tapeout project metadata
|-- README.md                   # Project overview
|-- fft_block_diagram.svg       # Architecture diagram
|-- fft_butterfly_flow.svg      # Butterfly structure diagram
|-- synthesis_report.txt        # DP1 synthesis output
`-- synthesis_report_dp2.txt    # DP2 synthesis output
```

### 10.2 How to Build

**Functional simulation:**
```bash
cd src/
iverilog -o fft_test fft_8point.v peripheral.v fft_8point_tb.v
vvp fft_test
```

**Security tests:**
```bash
cd src/
iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v
vvp sec_test
```

**Yosys synthesis:**
```bash
cd src/
yosys synth.ys 2>&1 | tee ../synthesis_report_dp3.txt
```

**OpenLane physical design:**
See `docs/DP4_OPENLANE_INSTRUCTIONS.md` for complete instructions.

### 10.3 GitHub Tags

| Tag | Phase | Description |
|-----|-------|-------------|
| DP1-Submission | DP1 | Initial functional RTL design |
| DP2-Submission | DP2 | PPA-optimized design |
| DP3-Submission | DP3 | Security-hardened design |
| DP4-Submission | DP4 | Final tapeout-ready design with GDSII |

### 10.4 References

- Cooley, J.W. and Tukey, J.W. (1965). "An algorithm for the machine calculation of complex Fourier series." *Mathematics of Computation*, 19(90), pp.297-301.
- TinyTapeout Documentation: https://tinytapeout.com
- OpenLane Documentation: https://openlane.readthedocs.io
- SkyWater 130nm PDK: https://github.com/google/skywater-pdk
- MITRE CWE Hardware Design Weaknesses: https://cwe.mitre.org/data/definitions/1194.html
- AI-HDL Competition: https://csm.arizona.edu/AIHDL
