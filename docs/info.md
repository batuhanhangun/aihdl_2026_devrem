# 8-Point FFT Accelerator Peripheral

## Overview
This peripheral implements an 8-point Fast Fourier Transform (FFT) accelerator for the TinyQV RISC-V core. It uses a Radix-2 Decimation-in-Time (DIT) algorithm with fixed-point arithmetic.

## Features
- 8-point complex FFT computation
- 16-bit signed fixed-point arithmetic (Q1.15 for twiddle factors)
- Memory-mapped register interface
- Interrupt on completion
- ~15 clock cycles to complete FFT

## Register Map

| Address | Name | R/W | Description |
|---------|------|-----|-------------|
| 0x00-0x1C | INPUT_REAL[0-7] | W | Real part of input samples |
| 0x20-0x3C | INPUT_IMAG[0-7] | W | Imaginary part of input samples |
| 0x40 | CONTROL | W | Write 0x01 to start FFT |
| 0x44 | STATUS | R | Bit 0: busy, Bit 1: done |
| 0x48-0x64 | OUTPUT_REAL[0-7] | R | Real part of FFT output |
| 0x68-0x84 | OUTPUT_IMAG[0-7] | R | Imaginary part of FFT output |

## Usage Example (C code)
```c
#define FFT_BASE 0x80000000  // Peripheral base address

// Write input samples
for (int i = 0; i < 8; i++) {
    *(volatile int*)(FFT_BASE + i*4) = input_real[i];
    *(volatile int*)(FFT_BASE + 0x20 + i*4) = input_imag[i];
}

// Start FFT
*(volatile int*)(FFT_BASE + 0x40) = 1;

// Wait for completion
while (*(volatile int*)(FFT_BASE + 0x44) & 0x01);

// Read outputs
for (int i = 0; i < 8; i++) {
    output_real[i] = *(volatile int*)(FFT_BASE + 0x48 + i*4);
    output_imag[i] = *(volatile int*)(FFT_BASE + 0x68 + i*4);
}
```

## Architecture
The FFT uses a 3-stage butterfly structure:
- Stage 1: 4 butterflies with W8^0
- Stage 2: 4 butterflies with W8^0, W8^2
- Stage 3: 4 butterflies with W8^0, W8^1, W8^2, W8^3

## Synthesis Results
- Total cells: ~12,172
- Flip-flops: 854
- Target: TinyTapeout Sky130

## Files
- `fft_8point.v` - FFT computation core
- `peripheral.v` - TinyQV bus interface wrapper
- `fft_8point_tb.v` - Testbench
