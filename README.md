# AI-HDL 2026 - 8-Point FFT Accelerator

**Team:** Devrem </br>
**Team Members:** <a href="https://www.linkedin.com/in/bhangun/" target="Batuhan Hangün">Batuhan Hangün</a> ,
                  <a href="https://www.linkedin.com/in/safak-sahin/" target="Şafak Şahin">Şafak Şahin</a> </br> 
**Competition:** AI-HDL 2026 Design Competition  
**Phase:** Design Phase 1 (DP1) </br> 

## Project Overview

This project implements an **8-Point FFT (Fast Fourier Transform) Accelerator** as a peripheral for the TinyQV RISC-V core. The design uses a Radix-2 Decimation-in-Time algorithm with fixed-point arithmetic.

## Architecture

### Block Diagram

The FFT accelerator integrates with the TinyQV RISC-V CPU through a memory-mapped peripheral interface:

![FFT Accelerator Block Diagram](fft_block_diagram.svg)

### Butterfly Structure

The 8-point FFT is computed using a 3-stage Radix-2 DIT (Decimation-in-Time) butterfly network:

![FFT Butterfly Flow](fft_butterfly_flow.svg)

**Key Algorithm Details:**

- **Stage 1:** 4 butterflies with W⁰ twiddle factor (distance 1)
- **Stage 2:** 4 butterflies with W⁰, W² twiddle factors (distance 2)
- **Stage 3:** 4 butterflies with W⁰, W¹, W², W³ twiddle factors (distance 4)
- **Bit-reversal:** Input samples are reordered (0,4,2,6,1,5,3,7) for in-place computation

## Features

- 8-point complex FFT computation
- 16-bit signed fixed-point arithmetic (Q1.15 format)
- Memory-mapped register interface
- Interrupt on completion
- ~15 clock cycles to complete

## Synthesis Results

| Metric | Value |
|--------|-------|
| Total Cells | 12,172 |
| Flip-Flops | 854 |
| Target | Sky130 (TinyTapeout) |

## File Structure

```text
├── src/
│   ├── fft_8point.v       # FFT computation core
│   ├── peripheral.v       # TinyQV bus interface wrapper
│   └── fft_8point_tb.v    # Testbench
├── docs/
│   ├── DESIGN_REPORT.md   # Detailed design write-up & PPA results
│   ├── LLM_PROMPT_LOG.md  # AI prompt history (required for DP1)
│   └── info.md            # Quick reference documentation
├── fft_block_diagram.svg  # Architecture block diagram
├── fft_butterfly_flow.svg # Butterfly structure diagram
├── synthesis_report.txt   # Yosys synthesis output
└── README.md
```

## Verification

All testbench tests pass:

- ✅ DC Signal test
- ✅ Impulse test  
- ✅ Nyquist frequency test
- ✅ Sine wave test
- ✅ Cosine wave test

## Tools Used

- **HDL Generation:** Claude (Anthropic)
- **Simulation:** Icarus Verilog
- **Synthesis:** Yosys
- **Waveform Viewer:** GTKWave

## Register Map

| Address | Name | Description |
|---------|------|-------------|
| 0x00-0x1C | INPUT_REAL[0-7] | Real input samples |
| 0x20-0x3C | INPUT_IMAG[0-7] | Imaginary input samples |
| 0x40 | CONTROL | Write 1 to start FFT |
| 0x44 | STATUS | bit0=busy, bit1=done |
| 0x48-0x64 | OUTPUT_REAL[0-7] | Real output |
| 0x68-0x84 | OUTPUT_IMAG[0-7] | Imaginary output |

## License

Apache 2.0
