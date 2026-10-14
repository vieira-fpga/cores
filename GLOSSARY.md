# Cores

Analogue Pocket openFPGA cores, each a copy of the core template in `cores/<name>`. Every core talks to the Pocket's operating system, APF, over the bridge.

## Bridge

**Bridge**:
The 32-bit address and data bus APF uses to read and write the core, on `clk_74a`.
_Avoid_: SPI bus, PMP bus

**Bridge map**:
The split of bridge addresses into regions: the core's own devices at `0x10xxxxxx` and APF's registers at `0xF8xxxxxx`, which hold the host command, target command, and datatable regions.
_Avoid_: address decoder, memory map

**User region**:
The part of the bridge map that belongs to the core's own devices, such as its memories and registers. The core decides what it holds.
_Avoid_: core region, user space

**Host command**:
A request APF makes of the core, such as reset enter, a data slot update, or an RTC update. APF writes the command, then polls until the core answers.
_Avoid_: bridge command, APF command

**Target command**:
A request the core makes of APF, such as reading a data slot into the core's memory. The core starts it, and APF answers.
_Avoid_: core command

**Concept module**:
The part of the bridge that owns one kind of command and its handshake with the core: data slot requests, savestates, RTC and menu notices, or target commands. Each host command belongs to at most one concept module.
_Avoid_: command handler, sub-handler

**Data slot**:
A file APF loads into or saves from the core, as `data.json` lists it.
_Avoid_: asset, file slot

**Datatable**:
A table that APF and the core share in the bridge map. APF writes each data slot's size there, and it holds the core's build date and time.

**Default responder**:
The fixed answers a core gives for the parts of the bridge it doesn't use: acks for data slot requests, savestates reported unsupported, and no target commands.
_Avoid_: stub, dummy handler

## Clocks and resets

**Core clock**:
The clock from the PLL that drives the core's own logic, such as its video.

**PLL lock**:
The PLL's report that its outputs run at their set frequencies. The core treats every PLL clock as unusable until lock.
_Avoid_: PLL ready

**Core reset**:
The reset for logic on the core clock. It holds that logic in reset until APF releases the core and the PLL has locked, and it changes only on core clock edges.
_Avoid_: video reset

**Level synchronizer**:
A circuit that carries a signal that stays at a value, such as "in the menu", into another clock domain. It carries one bit, and never a multi-bit value.
_Avoid_: sync, CDC flop

**Pulse synchronizer**:
A circuit that carries a one-cycle event, such as an RTC update, into another clock domain, as one event at the other side. Events on one signal must arrive far enough apart for the slower clock to see each one.
_Avoid_: edge synchronizer, pulse stretcher
