# Pacman Arena DX

A synthesizable maze game for Tiny Tapeout IHP, based on the supplied Pacman Arena DX design and the official ttihp-verilog-template.

[Play in VGA Playground](https://vga-playground.com/?repo=https://github.com/Ezumaex/CDM_BOOTCAMP_PACMAN&ref=main)

[Build and GDS checks](https://github.com/Ezumaex/CDM_BOOTCAMP_PACMAN/actions/workflows/gds.yaml)

Use the Playground input switches: 0 up, 1 down, 2 left, 3 right, 4 restart. Inputs are active high. Hold a direction to move; switch it off to stop. Direction priority is up, down, left, right. Reset the simulation once after loading if needed.

Collect all pellets to win. The four corner power pellets make the ghost flee at half speed for 600 frames (about ten seconds). Touching a frightened ghost returns it to its starting position and ends power mode. Touching a normal ghost loses the game. The screen flashes green on a win or red on a loss. Input 4 restarts the game without disturbing VGA timing.

## Hardware

- 25.175 MHz external pixel clock, 640x480 visible pixels, 800x525 total timing, active-low sync.
- RGB222 Tiny VGA PMOD pinout: uo[0]=R1, [1]=G1, [2]=B1, [3]=VSYNC, [4]=R0, [5]=G0, [6]=B0, [7]=HSYNC.
- ui[4:0] are synchronized with two flip-flops. Inputs 5-7 are unused; all bidirectional pins are inputs, with output data tied low.
- rst_n is the hardware reset. Assert it for at least two pixel clocks. ena follows the standard Tiny Tapeout selected-design convention.
- Allocation: 1x1 tile. Timing target: 39.72 ns.

## Implementation

`src/project.v` is the game and renderer; `src/hvsync_generator.v` supplies timing. `info.yaml` lists both files and the unique top module `tt_um_ezumaex_pacman`.

The radius-12 sprites use exact integer circle comparisons rather than multipliers. Game state advances once per frame in vertical blanking. The ghost chooses one legal axis per tick, preventing diagonal wall clipping. Its AI remains the simple local greedy chase/flee behavior of the original game; it is not a maze pathfinder and can get stuck behind obstacles.

## Verification

The standard GDS workflow builds the IHP layout, runs Tiny Tapeout precheck and simulates the resulting gate-level netlist. The same pin-only cocotb test checks every clock of a complete 420,000-clock frame for sync placement, pulse widths, RGB blanking, sprite/maze colors and safe bidirectional outputs. It also checks reset behavior.

The separate RTL behavioral test accelerates frame ticks to exercise movement, wall/boundary collision, pellets, the power timer, eating the ghost, loss, win and restart. It compares the multiplier-free circle against squared-distance geometry for all offsets in a 32x32 quadrant.

Run on Linux with Icarus Verilog and Python:

```sh
pip install -r test/requirements.txt
cd test
iverilog -g2012 -s game_tb -o /tmp/game_tb ../src/project.v ../src/hvsync_generator.v game_tb.v
vvp /tmp/game_tb
make
```

Local lint:

```sh
verilator --lint-only -Wall -Wno-DECLFILENAME --top-module tt_um_ezumaex_pacman src/project.v src/hvsync_generator.v
```

The repository uses the upstream `ttihp26b` GDS action. A successful simulation alone is not physical signoff: inspect all GDS workflow jobs for the exact commit you intend to submit. GitHub Pages must use GitHub Actions as its source for the layout viewer deployment.
