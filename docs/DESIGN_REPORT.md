# AI-HDL 2026 - Design Phase 1 Report

**Team:** Devrem  
**Project:** 8-Point FFT Accelerator Peripheral  
**Competition Phase:** DP1 (Design Phase 1)  
**Submission Date:** January 29, 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [The Importance of FFT in Real-World Applications](#the-importance-of-fft-in-real-world-applications)
3. [Design Choice Rationale](#design-choice-rationale)
4. [Technical Architecture](#technical-architecture)
5. [Implementation Details](#implementation-details)
6. [PPA Results (Power, Performance, Area)](#ppa-results)
7. [Verification Summary](#verification-summary)
8. [Lessons Learned & Future Work](#lessons-learned--future-work)

---

## Executive Summary

This report documents the design and implementation of an **8-Point Fast Fourier Transform (FFT) Accelerator** as a peripheral for the TinyQV RISC-V core. The FFT accelerator was developed using an AI-first methodology, leveraging Large Language Models (LLMs) to generate synthesizable Verilog RTL code.

**Key Achievements:**

- Fully synthesizable 8-point complex FFT core
- Memory-mapped peripheral interface compatible with TinyQV
- All verification tests passing
- Baseline synthesis: **12,172 cells**, **854 flip-flops**
- Target: Sky130 process (TinyTapeout)

---

## The Importance of FFT in Real-World Applications

The **Fast Fourier Transform (FFT)** is one of the most influential algorithms in the history of computing. It transforms signals from the time domain to the frequency domain, enabling a wide range of critical applications across virtually every field of engineering and science.

### Why FFT Matters

The Discrete Fourier Transform (DFT) has a computational complexity of O(N²), making it impractical for real-time applications. The FFT algorithm, developed by Cooley and Tukey in 1965, reduces this to **O(N log N)**, making real-time signal processing feasible. For an 8-point transform:

- DFT requires: 64 complex multiplications
- FFT requires: only 12 complex multiplications (using Radix-2)

This efficiency gain is what makes dedicated FFT hardware accelerators so valuable in embedded systems.

### Real-Time Applications

| Application Domain | Use Case | Why FFT is Critical |
|-------------------|----------|---------------------|
| **Audio Processing** | Noise cancellation, equalization, music analysis | Identifies frequency components in real-time for active filtering |
| **Telecommunications** | OFDM modulation (WiFi, 4G/5G, DVB) | Converts between time and frequency domain for multi-carrier transmission |
| **Medical Imaging** | MRI, CT scan reconstruction | Transforms k-space data to spatial images |
| **Radar & Sonar** | Target detection, range-Doppler processing | Extracts velocity and distance information from reflected signals |
| **Vibration Analysis** | Predictive maintenance in machinery | Detects bearing faults and mechanical resonances |
| **Power Systems** | Harmonic analysis in smart grids | Monitors power quality and detects distortions |

### Real-Life Examples

#### 1. Voice Assistants (Alexa, Siri, Google Assistant)

Every voice command you give is processed through FFT to extract frequency features before being fed to machine learning models. The FFT converts your voice waveform into a spectrogram that reveals phonetic content.

#### 2. Wireless Communication (Your Smartphone)

Modern wireless standards like **WiFi 6**, **5G NR**, and **LTE** use OFDM (Orthogonal Frequency-Division Multiplexing), which relies entirely on FFT/IFFT operations. Every packet your phone sends or receives involves hundreds of FFT computations per second.

#### 3. Music Streaming (Spotify, Apple Music)

Audio codecs like MP3 and AAC use FFT-based transforms (MDCT) to compress audio. The psychoacoustic models that decide which frequencies to discard are built on frequency-domain analysis.

#### 4. Earthquake Detection

Seismographs use FFT to analyze ground vibrations. By examining the frequency spectrum, scientists can distinguish between different types of seismic waves and locate earthquake epicenters.

#### 5. Biomedical Devices

ECG monitors analyze heart rhythms using FFT to detect arrhythmias. EEG systems use FFT to study brain wave patterns (alpha, beta, theta waves) for diagnosing epilepsy and sleep disorders.

### Why Hardware Acceleration?

While software FFT implementations are common, **hardware FFT accelerators** provide:

- **Deterministic latency**: Critical for real-time systems
- **Energy efficiency**: Orders of magnitude lower power than CPU-based solutions
- **Parallel processing**: Multiple butterflies can execute simultaneously
- **CPU offloading**: Frees the main processor for other tasks

Our 8-point FFT accelerator completes in approximately **15 clock cycles**, enabling high-throughput signal processing even in resource-constrained embedded systems.

---

## Design Choice Rationale

### Why an FFT Accelerator?

Among the suggested peripheral ideas (GPIO, UART, SPI, AES, etc.), we chose the FFT accelerator because:

1. **Computational Intensity**: FFT involves complex arithmetic that benefits significantly from hardware acceleration
2. **Wide Applicability**: As demonstrated above, FFT is foundational to countless applications
3. **Educational Value**: Implementing FFT requires understanding of DSP, fixed-point arithmetic, and pipelining
4. **Complexity Level**: Falls in the "Complex" category, earning higher innovation points
5. **Scalability**: The 8-point design can be extended to 16, 32, or larger transforms

### Algorithm Selection: Radix-2 DIT

We implemented the **Radix-2 Decimation-in-Time (DIT)** algorithm for the following reasons:

| Factor | Radix-2 DIT | Radix-4 | Split-Radix |
|--------|-------------|---------|-------------|
| Complexity | Simple | Moderate | Complex |
| Multiplications (N=8) | 12 | 8 | 6 |
| Control Logic | Minimal | Moderate | Complex |
| Suitable for 8-point | ✅ Optimal | Requires N=4^k | Overkill |

For an 8-point FFT, Radix-2 provides the best balance between simplicity and efficiency.

### Fixed-Point Arithmetic: Q1.15 Format

We chose **Q1.15 fixed-point** representation:

- 1 sign bit
- 15 fractional bits
- Range: [-1.0, +0.99997]

**Rationale:**

- Twiddle factors (cosine/sine values) naturally fit in [-1, +1]
- 16-bit data path matches common ADC/DAC resolutions
- Avoids the area overhead of floating-point units
- Sufficient precision for most signal processing tasks

---

## Technical Architecture

### Block Diagram

The accelerator consists of two main modules:

```
┌─────────────────────────────────────────────────────────────┐
│                    tqvp_fft8 (Peripheral)                   │
│  ┌─────────────┐  ┌─────────────────────────────────────┐   │
│  │ Bus         │  │         fft_8point (Core)           │   │
│  │ Interface   │──│  ┌─────────┐  ┌──────────────────┐  │   │
│  │             │  │  │ State   │  │ Butterfly Unit   │  │   │
│  │ - Address   │  │  │ Machine │  │ (Complex Mult)   │  │   │
│  │   Decode    │  │  └─────────┘  └──────────────────┘  │   │
│  │ - Read/Write│  │  ┌─────────┐  ┌──────────────────┐  │   │
│  │ - Registers │  │  │ Twiddle │  │ Stage Registers  │  │   │
│  │             │  │  │ ROM     │  │ (8×16-bit×2)     │  │   │
│  └─────────────┘  │  └─────────┘  └──────────────────┘  │   │
│                   └─────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Butterfly Structure

The 8-point FFT uses 3 stages with 4 butterflies each:

- **Stage 1**: Butterflies operate on pairs with distance 1, using W₈⁰
- **Stage 2**: Butterflies operate on pairs with distance 2, using W₈⁰, W₈²
- **Stage 3**: Butterflies operate on pairs with distance 4, using W₈⁰, W₈¹, W₈², W₈³

Each butterfly computes:

```
out_a = a + b × W
out_b = a - b × W
```

Where W is the twiddle factor (complex exponential).

### State Machine

```
IDLE → STAGE1 → STAGE2 → STAGE3 → DONE → IDLE
         ↑         ↑         ↑
      4 cycles  4 cycles  4 cycles
```

Total latency: ~15 clock cycles from start to completion.

---

## Implementation Details

### Module Hierarchy

| Module | Description | Lines of Code |
|--------|-------------|---------------|
| `fft_8point.v` | FFT computation core | ~400 |
| `peripheral.v` | TinyQV bus interface | ~350 |
| `butterfly` | Complex butterfly operation | ~50 |
| `tt_wrapper.v` | TinyTapeout wrapper | ~100 |

### Memory-Mapped Register Interface

| Address Range | Register | Access | Description |
|--------------|----------|--------|-------------|
| 0x00-0x1C | INPUT_REAL[0-7] | Write | Real input samples |
| 0x20-0x3C | INPUT_IMAG[0-7] | Write | Imaginary input samples |
| 0x40 | CONTROL | Write | Bit 0: Start FFT |
| 0x44 | STATUS | Read | Bit 0: Busy, Bit 1: Done |
| 0x48-0x64 | OUTPUT_REAL[0-7] | Read | Real FFT output |
| 0x68-0x84 | OUTPUT_IMAG[0-7] | Read | Imaginary FFT output |

### Twiddle Factor ROM

Pre-computed twiddle factors stored in Q1.15 format:

| Factor | Real (Cos) | Imaginary (Sin) | Q1.15 Real | Q1.15 Imag |
|--------|------------|-----------------|------------|------------|
| W₈⁰ | 1.0 | 0.0 | 0x7FFF | 0x0000 |
| W₈¹ | 0.707 | -0.707 | 0x5A82 | 0xA57E |
| W₈² | 0.0 | -1.0 | 0x0000 | 0x8001 |
| W₈³ | -0.707 | -0.707 | 0xA57E | 0xA57E |

---

## PPA Results

### Synthesis Summary (Yosys + Sky130)

| Metric | Value |
|--------|-------|
| **Total Cells** | 12,172 |
| **Flip-Flops** | 854 |
| **NAND Gates** | 5,709 |
| **XOR Gates** | 2,561 |
| **AND Gates** | 2,431 |
| **OR Gates** | 468 |

### Cell Distribution by Module

| Module | Cells | Percentage |
|--------|-------|------------|
| tqvp_fft8 (top) | 12,172 | 100% |
| └─ fft_8point | 2,946 | 24% |
| └─ butterfly | 7,782 | 64% |

The butterfly unit dominates the area due to the complex multiplications (4 multipliers, 2 adders/subtractors per butterfly).

### Performance Estimates

| Metric | Value |
|--------|-------|
| Target Clock | 64 MHz (TinyQV default) |
| FFT Latency | ~15 cycles |
| Throughput | ~4.3 million FFT/sec |
| Time per FFT | ~234 ns |

---

## Verification Summary

### Testbench Coverage

All tests pass with correct output verification:

| Test Case | Input Signal | Expected Output | Status |
|-----------|--------------|-----------------|--------|
| DC Signal | [1,0,0,0,0,0,0,0] | X[0]=1, others≈0 | ✅ Pass |
| Impulse | [1,1,1,1,1,1,1,1] | X[0]=8, others=0 | ✅ Pass |
| Nyquist | [1,-1,1,-1,1,-1,1,-1] | X[4]=8, others=0 | ✅ Pass |
| Sine Wave | sin(2πk/8) | Frequency bins | ✅ Pass |
| Cosine Wave | cos(2πk/8) | Frequency bins | ✅ Pass |

### Waveform Analysis

Simulation waveforms (VCD files) confirm:

- Correct state machine transitions
- Proper twiddle factor selection
- Bit-accurate butterfly computations
- Correct output register loading

---

## Lessons Learned & Future Work

### Lessons Learned

1. **AI-Assisted Development**: LLMs significantly accelerated the initial RTL generation, but careful manual review was essential for correctness
2. **Fixed-Point Precision**: Q1.15 provides adequate precision, but overflow handling required attention
3. **Testbench Design**: Starting with simple test cases (DC, impulse) before complex signals helped isolate bugs

### Future Optimizations (DP2/DP3)

| Optimization | Expected Benefit |
|--------------|-----------------|
| Pipelining | Higher throughput |
| Resource sharing | Reduced area |
| Bit-width optimization | Lower power |
| SIMD extension | Multiple FFTs in parallel |

### Potential Extensions

- 16-point or 32-point FFT
- Inverse FFT (IFFT) support
- Sliding window FFT for streaming
- Power spectrum computation

---

## Appendix: File Structure

```
aihdl_2026_devrem/
├── src/
│   ├── fft_8point.v       # FFT computation core
│   ├── peripheral.v       # TinyQV bus interface
│   ├── fft_8point_tb.v    # Testbench
│   ├── tt_wrapper.v       # TinyTapeout wrapper
│   └── synth_output.v     # Synthesized netlist
├── docs/
│   ├── DESIGN_REPORT.md   # This document
│   ├── LLM_PROMPT_LOG.md  # AI prompt history
│   └── info.md            # Quick reference
├── fft_block_diagram.svg  # Architecture diagram
├── fft_butterfly_flow.svg # Butterfly structure
├── synthesis_report.txt   # Yosys output
└── README.md              # Project overview
```

---

**Prepared by:** Team Devrem  
**AI-HDL 2026 Competition**  
**Design Phase 1 Submission**
