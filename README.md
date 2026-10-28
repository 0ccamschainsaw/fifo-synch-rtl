# Synchronous FIFO

A parameterized, single-clock FIFO in Verilog with a self-checking SystemVerilog
testbench, bound assertions, hand-rolled functional coverage, and a Python
regression runner for Vivado xsim.

## Features

- Configurable depth (`DEPTH >= 2`) and word width (`DATAW >= 1`).
- Registered read output: accepted reads update `data_out` at the active clock
  edge.
- Explicit overflow/underflow policy and wraparound for non-power-of-two depths.

## Interface

| Name | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | FIFO clock |
| `rstn` | input | 1 | Active-low synchronous reset |
| `w_en` | input | 1 | Request a write |
| `r_en` | input | 1 | Request a read |
| `data_in` | input | `DATAW` | Write data |
| `data_out` | output | `DATAW` | Registered read data |
| `full` | output | 1 | FIFO contains `DEPTH` words |
| `empty` | output | 1 | FIFO contains no words |

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEPTH` | 8 | Number of entries; must be at least 2 |
| `DATAW` | 8 | Bits per entry; must be at least 1 |

## Behavior

- `full` blocks writes, and `empty` blocks reads. Requests are accepted only
  when the corresponding boundary flag permits them.
- `data_out` is registered and changes on a clock edge that accepts a read.
- Simultaneous read/write requests are independently accepted according to
  the flags at the start of that edge. Thus, at full only the read is accepted;
  at empty only the write is accepted; at an intermediate occupancy both are
  accepted and occupancy is unchanged.
- Reset is synchronous and active low. It clears the pointers, occupancy, and
  output register; storage contents are not required to be reset.

## Verification

```text
clocking-block driver --> sync_fifo --> accepted-transfer monitor
                                          |
                                   queue scoreboard
                                          |
                       occupancy checks + functional coverage
```

The plain-module testbench in [`tb/sync/`](tb/sync/) uses a queue scoreboard,
compares registered read data, and checks flags against independently modeled
occupancy. `sync_fifo_sva.sv` binds protocol assertions to the DUT and adds
assertions comparing flags with the testbench occupancy model.

The suite includes reset, fill/drain, overflow/underflow, simultaneous
read/write at empty/middle/full, pointer wraparound, three seeded random traffic
profiles, and reset during traffic. Coverage tracks occupancy, rejected
requests, boundary simultaneous operations, and pointer wraps. A full-suite run
reports any uncovered bins as `COVERAGE HOLE`; a selected individual test
reports measurements without requiring unrelated test bins.
Each pointer-wrap bin requires at least two observed wraps.

[`docs/waveforms/waveform_tb1.png`](docs/waveforms/waveform_tb1.png) is the
existing directed-test waveform.

## Run the regression

With Vivado's `xvlog`, `xelab`, and `xsim` on `PATH`:
D:\AMDDesignTools\2025.2\Vivado\settings64.bat

```powershell
python scripts\run_sim.py --seeds 20 --sweep
```

This tests 12 `(DEPTH, DATAW)` combinations with seeds 1 through 20. A focused
run is also available:

```powershell
python scripts\run_sim.py --depth 3 --dataw 8 --test wraparound --seed 42
```

The testbench accepts `+seed=<n>` and `+test=<name>` at runtime. Generated
build products and per-run logs are placed in the ignored `build/` directory.
The runner writes a summary to [`docs/results.md`](docs/results.md), enforces a
per-simulation timeout, and prints an exact replay command for failed runs.

## Limitations and extensions

This design is synchronous and does not provide asynchronous clock-domain
crossing
include those features after the present behavior and verification are stable.
