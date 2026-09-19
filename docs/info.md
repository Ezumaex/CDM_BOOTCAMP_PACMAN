## How it works

Pacman Arena DX is a VGA maze game. Collect every pellet while avoiding a red ghost. The corner power pellets turn the ghost blue, make it flee at half speed and allow it to be eaten. Power mode lasts up to 600 frames. Win and loss flash the screen green and red respectively.

The renderer produces 640x480 RGB222 VGA at a 25.175 MHz pixel clock. Horizontal timing is 640 visible + 16 front porch + 96 sync + 48 back porch; vertical timing is 480 + 10 + 2 + 33. Both sync pulses are active low. Game updates occur in vertical blanking. Integer circle comparisons eliminate sprite multipliers.

## How to test

Connect the Tiny VGA PMOD to the dedicated outputs, supply a 25.175 MHz clock and assert hardware reset for at least two clocks. Drive ui[0] high for up, ui[1] down, ui[2] left or ui[3] right. Hold a direction to keep moving; release it to stop. ui[4] restarts the game. All buttons are active high and pass through two synchronizer stages. Unused inputs may be tied low.

The same source can be loaded using the repository link in VGA Playground. The ghost uses simple local chase/flee decisions, not full maze pathfinding.

## External hardware

Tiny VGA PMOD and VGA monitor; five active-high buttons with appropriate pull-down resistors, or a controller driving the five inputs. No external memory is required.
