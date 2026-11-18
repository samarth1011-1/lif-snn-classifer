# LIF Neuron SNN Pattern Detector

A spiking-neural-network pattern detector in Verilog: 4 LIF neurons with fixed
synaptic weights recognize binary digit patterns (0–3) on a 5×5 grid.

## Structure

```
LIF_NEURON/
├── rtl/                        # Synthesizable RTL
│   ├── lif_neuron.v            # LIF core: leak, integration, threshold, spike reset
│   ├── weight_mac.v            # Combinational weighted dot product (packed weights)
│   ├── spike_counter.v         # Observation-window spike counter + argmax
│   └── snn_top_parallel.v      # 4-neuron parallel pattern detector top
├── tb/                         # Testbenches (Icarus Verilog)
│   ├── snn_parallel_tb.v       # Full 4-neuron classifier: digits 0-3, noisy, reject
│   ├── weighted_neuron_tb.v    # Single neuron tuned to digit 0
│   ├── generalised_pattern_tb.v# Single neuron vs all digits 0-9
│   ├── generalised_tb.sv       # Single neuron, parameterized digit
│   ├── weight_mac_tb.v         # MAC unit tests
│   └── lif_neuron_tb.sv        # LIF core unit tests
├── model/
│   └── lif_neuron.py           # Python reference model of the LIF neuron
├── scripts/
│   ├── run.tcl                 # Build & run weighted_neuron_tb
│   └── run_parallel.tcl        # Build & run the 4-neuron pattern detector TB
└── sim/                        # Build artifacts & VCD waveforms (gitignored)
```

## Running

From the project root:

```tcl
tclsh scripts/run_parallel.tcl   # 4-neuron pattern detector (main demo)
tclsh scripts/run.tcl            # single-neuron demo
```

Waveforms are written to `sim/*.vcd` — open in GTKWave to see membrane
potentials, spike buses, and the classification result.

## Architecture

```
pattern_in[24:0] ──► 4× (weight_mac → lif_neuron) ──► spike_counter + argmax
classify_start ──────────────────────────────────►►       │
                                                          ▼
                                              predicted_class + result_valid
```

- Weights: +16 for template-ON pixels, −32 for template-OFF pixels (strong
  inhibition keeps competitor neurons silent)
- Classification: count spikes per neuron over a 64-cycle window; argmax wins
- Rejection: an input matching no template drives all currents negative →
  zero spikes everywhere
