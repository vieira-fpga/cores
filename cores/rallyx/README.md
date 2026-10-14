# Rally-X

Analogue Pocket core for the Namco Rally-X arcade board, which runs Rally-X and New Rally-X.

Claude Opus 5.5 in Claude Code worked on this core.

## Status

The core is the unmodified core template. It shows a gray test screen and runs no game yet.

| Game | MAME sets | Status |
| --- | --- | --- |
| Rally-X | `rallyx`, `rallyxa`, `rallyxm` | Not yet |
| New Rally-X | `nrallyx`, `nrallyxb` | Not yet |
| Rally-X bootlegs | `rallyxmr`, `rallyxeg`, `rallyxtd`, `dngrtrck` | Not yet |

MAME's `rallyx.cpp` driver also covers Jungler, Tactician, Loco-Motion and Commando. Those games run on Konami and Sega boards with their own machine configurations, so this core doesn't cover them.

## Credits

- Analogue - [core-template](https://github.com/open-fpga/core-template), which this core starts from
- Adam Gastineau `agg23` - [analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils), for the I2S audio serializer and FIFO in `src/fpga/core/vendor/`
- MAME - [`rallyx.cpp`](https://github.com/mamedev/mame/blob/master/src/mame/namco/rallyx.cpp) by Nicola Salmoria, for the list of sets the board runs (mame0289)
