# DP4 — OpenLane Run Instructions

These instructions are for running the full ASIC physical design flow (synthesis through GDSII) on the DP3-hardened 8-Point FFT Accelerator design.

## Prerequisites

You need **one** of the following setups:

### Option A: TinyTapeout `tt` Tool (Recommended)

```bash
# 1. Install Python 3.8+, pip
pip install tt-support-tools

# 2. Install Docker (required for OpenLane container)
# https://docs.docker.com/get-docker/

# 3. Clone the repo
git clone https://github.com/batuhanhangun/aihdl_2026_devrem.git
cd aihdl_2026_devrem
```

### Option B: OpenLane 2 Standalone

```bash
# 1. Install OpenLane via pip
pip install openlane

# 2. Or use Docker image
docker pull efabless/openlane2:latest

# 3. Install the sky130 PDK
volare enable --pdk sky130 <version>

# 4. Clone the repo
git clone https://github.com/batuhanhangun/aihdl_2026_devrem.git
cd aihdl_2026_devrem
```

---

## Running the Flow

### Option A: Using `tt` Tool

```bash
# From the repo root directory:
tt/tt_tool.py --create-user-config
tt/tt_tool.py --harden
```

If the `tt/` directory doesn't exist, use:

```bash
# Install and run directly
pip install tt-support-tools
tt-harden --openlane2
```

### Option B: Using OpenLane Directly

```bash
# Set environment
export PDK_ROOT=<path_to_pdk>
export PDK=sky130A

# Run OpenLane from repo root
# The config.json in src/ is already set up for TinyTapeout
openlane src/config.json
```

### Option C: Using the AIHDL-2026 Template Flow

If you have the AIHDL-2026 competition infrastructure set up:

```bash
# From the tinyqv-full-peripheral-template flow:
cd <template_root>
# Copy our source files into the template
cp -r <repo>/src/* src/
cp <repo>/info.yaml .
cp <repo>/src/config.json src/

# Run the hardening flow
make harden
```

---

## What to Run (Step by Step)

The OpenLane flow runs these steps automatically:

1. **Synthesis** (Yosys) — RTL to gate-level netlist
2. **Floorplanning** — Die area, I/O placement, power grid
3. **Placement** — Standard cell placement + optimization
4. **Clock Tree Synthesis (CTS)** — Clock distribution network
5. **Routing** — Metal layer interconnects
6. **Sign-off Checks:**
   - **STA** (Static Timing Analysis) — Setup/hold timing
   - **DRC** (Design Rule Check) — Manufacturing rule compliance
   - **LVS** (Layout vs. Schematic) — Netlist match verification
7. **GDSII Generation** — Final layout file

---

## Files I Need Back

After the flow completes, please send back **ALL** of the following:

### Critical Files (MUST HAVE)

| File/Directory | Location | Description |
|---|---|---|
| **GDSII file** | `runs/<run>/results/final/gds/*.gds` | Final chip layout |
| **Gate-level netlist** | `runs/<run>/results/final/verilog/gl/*.v` | Post-route netlist |
| **DEF file** | `runs/<run>/results/final/def/*.def` | Physical layout |
| **LEF file** | `runs/<run>/results/final/lef/*.lef` | Abstract layout |
| **SDC file** | `runs/<run>/results/final/sdc/*.sdc` | Timing constraints |

### Sign-off Reports (MUST HAVE)

| Report | Location | What to Check |
|---|---|---|
| **STA report** | `runs/<run>/reports/signoff/*sta*` or `runs/<run>/reports/timing/` | Setup/hold slack values |
| **DRC report** | `runs/<run>/reports/signoff/*drc*` | Zero violations = clean |
| **LVS report** | `runs/<run>/reports/signoff/*lvs*` | "CLEAN" or zero mismatches |
| **Area report** | `runs/<run>/reports/synthesis/` or `runs/<run>/reports/metrics.csv` | Cell count, area |
| **Power report** | `runs/<run>/reports/signoff/*power*` | Power consumption |

### Summary Metrics

| Metric | Where to Find |
|---|---|
| **metrics.csv** or **metrics.json** | `runs/<run>/` root or `reports/` |
| **Final summary** | `runs/<run>/reports/final_summary_report.csv` |

### Full Run Archive (Ideal)

If possible, zip and send the entire `runs/<run>/` directory:

```bash
cd runs/
tar -czf openlane_run.tar.gz <run_directory_name>/
# or on Windows:
# zip -r openlane_run.zip <run_directory_name>/
```

---

## Troubleshooting

### Common Issues

1. **Synthesis fails / module not found**
   - Verify `info.yaml` lists all source files including `fft_8point.v`
   - Check that `src/config.json` has `CLOCK_PORT: "clk"`

2. **Timing violations (negative slack)**
   - Try increasing `CLOCK_PERIOD` in `src/config.json` from 14 to 15 or 16
   - Or increase hold margins: `PL_RESIZER_HOLD_SLACK_MARGIN: 0.2`

3. **DRC violations**
   - Usually fixable by reducing `PL_TARGET_DENSITY_PCT` (try 60)
   - Or increasing die area (change tiles from "1x2" to "2x2" in info.yaml)

4. **Routing congestion**
   - `GRT_ALLOW_CONGESTION: 1` is already set
   - If still failing, reduce density to 60

5. **LVS mismatches**
   - Check if `MAGIC_DEF_LABELS: 0` is set (already in config)

### If the Flow Fails Completely

Please send:
- The complete terminal/console output (copy-paste or redirect to file)
- The `runs/<run>/logs/` directory
- The error message

---

## Design Summary (for reference)

- **Top module:** `tt_um_tqv_peripheral_harness`
- **Source files:** `fft_8point.v`, `peripheral.v`, `tt_wrapper.v`, + test_harness/*.sv
- **Clock:** 14 ns period (~71.5 MHz) on port `clk`
- **Tile size:** 1x2 (~167x216 um)
- **Target density:** 70%
- **Estimated cells:** ~11,400 (from DP3 Yosys synthesis)
- **Technology:** sky130 (SkyWater 130nm)
