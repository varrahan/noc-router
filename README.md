# Parameterized Network-on-Chip (NoC) Router

A 5-port NoC router implementing wormhole switching,
X-Y deterministic routing, credit-based virtual channel flow control, and round-robin
switch arbitration. Designed for 2D mesh topologies in multi-core SoC environments.

---

## Quick Start

```bash
# From the project root
cd scripts/

# Compile and simulate (produces VCD in ../sim/)
make sim

# Open waveform in GTKWave
make wave

# Lint only
make lint

# Clean all generated files
make clean
```

Prerequisites: `iverilog`, `vvp`, `gtkwave` on your PATH.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      noc_router_top                             │
│                                                                 │
│  ┌──────────┐   ┌─────────┐   ┌──────────┐   ┌──────────────┐   │
│  │  Input   │   │  Route  │   │    VC    │   │   Switch     │   │
│  │  Buffer  │──>│Compute  │──>│Allocator │──>│  Allocator   │   │
│  │  (FIFO)  │   │  (X-Y)  │   │ (RR/VC)  │   │  (RR/Port)   │   │
│  └──────────┘   └─────────┘   └──────────┘   └───────┬──────┘   │
│  (per port,                                          │          │
│   per VC)                                    ┌───────▼──────┐   │
│                                              │   Crossbar   │   │
│                                              │   Switch     │   │
│                                              └───────┬──────┘   │
│                                                      │          │
│  Credits <───────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### 5-port layout in a 2D mesh

```
         NORTH (port 1)
              │
WEST (4) ───  ● ─── EAST (3)
              │
         SOUTH (port 2)
              │
          LOCAL (0)  <->  Processing Element
```

### Pipeline (4–5 cycles per flit)

| Stage | Name | Description                          |
|-------|------|--------------------------------------|
| ST1   | BW   | Buffer Write – flit enters FIFO      |
| ST2   | RC   | Route Compute – X-Y decision (comb.) |
| ST3   | VA   | VC Allocate – downstream VC assigned |
| ST4   | SA   | Switch Allocate – arbitration        |
| ST5   | ST   | Switch Traversal – crossbar output   |

---

## File Structure

```
noc_router_project/
├── src/
│   ├── noc_router_top.v      Top-level integration
│   ├── input_buffer.v        Parameterized FIFO (per port, per VC)
│   ├── route_compute.v       X-Y routing (combinational)
│   ├── vc_allocator.v        Downstream VC assignment (round-robin)
│   ├── switch_allocator.v    Crossbar arbitration (round-robin)
│   └── crossbar_switch.v     Physical multiplexing fabric
├── tb/
│   ├── router_tb.v           Main testbench (10 test cases)
│   └── traffic_gen.v         LFSR-based flit generator
├── scripts/
│   └── Makefile
├── docs/
│   ├── register_map.md       Flit format, port map, parameters
│   └── architecture_diagram.png
└── README.md
```

---

## Parameters

| Parameter    | Default | Range / Notes                          |
|--------------|---------|----------------------------------------|
| DATA_WIDTH   | 32      | 8 / 32 / 64 / 128 bits                 |
| COORD_W      | 4       | Supports grids up to 16×16             |
| FLIT_SIZE    | 40      | Must satisfy: >= 3 + 2×COORD_W + 1      |
| BUFFER_DEPTH | 8       | Must be a power of 2                   |
| NUM_VCS      | 2       | 1–4 VCs per physical port              |
| ROUTER_X_ID  | 0       | Static X coordinate in the mesh        |
| ROUTER_Y_ID  | 0       | Static Y coordinate in the mesh        |

Override at instantiation:

```verilog
noc_router_top #(
    .DATA_WIDTH   (64),
    .FLIT_SIZE    (80),
    .BUFFER_DEPTH (16),
    .NUM_VCS      (4),
    .ROUTER_X_ID  (3),
    .ROUTER_Y_ID  (1)
) my_router ( ... );
```

---

## Test Cases

| TC  | Description                                     |
|-----|-------------------------------------------------|
| TC1 | LOCAL → EAST (positive X routing)               |
| TC2 | LOCAL → WEST (negative X routing)               |
| TC3 | LOCAL → SOUTH (Y routing, positive)             |
| TC4 | LOCAL → NORTH (Y routing, negative)             |
| TC5 | LOCAL → LOCAL (self-destined / loopback)        |
| TC6 | Concurrent injection on two input ports         |
| TC7 | Back-pressure: downstream credits = 0           |
| TC8 | Multi-VC alternating injection                  |
| TC9 | Stress: 32-packet burst via traffic generator   |
| TC10| Back-to-back worm tail release                  |

---

## Design Properties

- **Deadlock-free**: X-Y routing eliminates all cyclic channel dependencies.
- **Starvation-free**: Round-robin arbitration at both the VC allocator and switch
  allocator ensures every requestor eventually wins.
- **Livelock-free**: Deterministic routing means a packet always makes progress
  toward its destination.
- **Synthesizable**: Written in clean Verilog-2001 compatible with Vivado and
  Quartus. No latches; all state in edge-triggered registers.

---

## Waveform Signals (GTKWave)

Key signals to examine after `make sim`:

| Signal                           | Meaning                                    |
|----------------------------------|--------------------------------------------|
| `in_valid[*]`                    | Upstream is sending a flit                 |
| `in_flit[*]`                     | Flit data (inspect head/tail bits)         |
| `out_valid[*]`                   | Router is emitting a flit                  |
| `out_flit[*]`                    | Emitted flit data                          |
| `credit_out[*]`                  | Credits returned to upstream               |
| `dut.worm_active[*][*]`          | VC holds an active worm allocation         |
| `dut.sa_grant_flat`              | Switch allocator grant matrix              |
| `dut.buf_empty[*][*]`            | FIFO empty status per port/VC              |