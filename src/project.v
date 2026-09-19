/*
 * Pacman-style Arena Minigame - DX Edition (Fixed Bounds)
 * Features: Maze Walls, Power Pellets, Fleeing Ghost AI
 * 
 * Controls:
 * ui_in[0] = UP
 * ui_in[1] = DOWN
 * ui_in[2] = LEFT
 * ui_in[3] = RIGHT
 * ui_in[4] = RESET GAME
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // VGA signals from sync generator
    wire hsync, vsync, display_on;
    wire [9:0] hpos, vpos;

    // Instantiate the standard 640x480 sync generator
    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // Input Buttons
    wire btn_up    = ui_in[0];
    wire btn_down  = ui_in[1];
    wire btn_left  = ui_in[2];
    wire btn_right = ui_in[3];
    wire btn_reset = ui_in[4];

    // Arena Boundaries
    localparam ARENA_L = 10'd192;
    localparam ARENA_R = 10'd448;
    localparam ARENA_T = 10'd112;
    localparam ARENA_B = 10'd368;
    localparam RADIUS  = 10'd11; // Collision radius
    localparam G_RADIUS = 10'd10; // Ghost Collision radius

    // 8x8 Maze Layout (1 = Wall, 0 = Path)
    // Organized visually: row 0 is top, row 7 is bottom
    wire [63:0] MAZE = {
        8'b00000000, // Row 7 (Bottom)
        8'b01100110,
        8'b01000010,
        8'b00011000,
        8'b00011000,
        8'b01000010,
        8'b01100110,
        8'b00000000  // Row 0 (Top)
    };

    // Game State Registers
    reg [1:0]  state;           // 0=PLAY, 1=WIN, 2=LOSE
    reg [9:0]  px, py;          // Pacman coordinates
    reg [9:0]  gx, gy;          // Ghost coordinates
    reg [1:0]  pac_dir;         // Pacman facing: 0=R, 1=L, 2=U, 3=D
    reg [11:0] frame_ctr;       // Animation counter
    reg [63:0] dots;            // 8x8 Grid of dots
    reg [9:0]  power_timer;     // Powerup timer (600 frames = 10 sec)

    // Dot mapping (Pacman's current grid cell)
    wire [2:0] p_col = ((px - ARENA_L) >> 5);
    wire [2:0] p_row = ((py - ARENA_T) >> 5);
    wire [5:0] p_idx = {p_row, p_col};

    // --- WALL COLLISION DETECTION ---
    // Calculate bounding box edges mapped to grid cells safely
    wire [2:0] px_L = ((px - RADIUS) >= ARENA_L) ? ((px - RADIUS - ARENA_L) >> 5) : 0;
    wire [2:0] px_R = ((px + RADIUS) <= ARENA_R) ? ((px + RADIUS - ARENA_L) >> 5) : 7;
    wire [2:0] py_T = ((py - RADIUS) >= ARENA_T) ? ((py - RADIUS - ARENA_T) >> 5) : 0;
    wire [2:0] py_B = ((py + RADIUS) <= ARENA_B) ? ((py + RADIUS - ARENA_T) >> 5) : 7;

    wire [2:0] py_next_T = ((py - 2 - RADIUS) >= ARENA_T) ? ((py - 2 - RADIUS - ARENA_T) >> 5) : 0;
    wire [2:0] py_next_B = ((py + 2 + RADIUS) <= ARENA_B) ? ((py + 2 + RADIUS - ARENA_T) >> 5) : 7;
    wire [2:0] px_next_L = ((px - 2 - RADIUS) >= ARENA_L) ? ((px - 2 - RADIUS - ARENA_L) >> 5) : 0;
    wire [2:0] px_next_R = ((px + 2 + RADIUS) <= ARENA_R) ? ((px + 2 + RADIUS - ARENA_L) >> 5) : 7;

    wire can_move_U = !(MAZE[{py_next_T, px_L}] | MAZE[{py_next_T, px_R}]);
    wire can_move_D = !(MAZE[{py_next_B, px_L}] | MAZE[{py_next_B, px_R}]);
    wire can_move_L = !(MAZE[{py_T, px_next_L}] | MAZE[{py_B, px_next_L}]);
    wire can_move_R = !(MAZE[{py_T, px_next_R}] | MAZE[{py_B, px_next_R}]);

    // Ghost collision helpers
    wire [2:0] gx_L = ((gx - G_RADIUS) >= ARENA_L) ? ((gx - G_RADIUS - ARENA_L) >> 5) : 0;
    wire [2:0] gx_R = ((gx + G_RADIUS) <= ARENA_R) ? ((gx + G_RADIUS - ARENA_L) >> 5) : 7;
    wire [2:0] gy_T = ((gy - G_RADIUS) >= ARENA_T) ? ((gy - G_RADIUS - ARENA_T) >> 5) : 0;
    wire [2:0] gy_B = ((gy + G_RADIUS) <= ARENA_B) ? ((gy + G_RADIUS - ARENA_T) >> 5) : 7;

    wire [2:0] gy_next_T = ((gy - 1 - G_RADIUS) >= ARENA_T) ? ((gy - 1 - G_RADIUS - ARENA_T) >> 5) : 0;
    wire [2:0] gy_next_B = ((gy + 1 + G_RADIUS) <= ARENA_B) ? ((gy + 1 + G_RADIUS - ARENA_T) >> 5) : 7;
    wire [2:0] gx_next_L = ((gx - 1 - G_RADIUS) >= ARENA_L) ? ((gx - 1 - G_RADIUS - ARENA_L) >> 5) : 0;
    wire [2:0] gx_next_R = ((gx + 1 + G_RADIUS) <= ARENA_R) ? ((gx + 1 + G_RADIUS - ARENA_L) >> 5) : 7;

    wire g_can_move_U = !(MAZE[{gy_next_T, gx_L}] | MAZE[{gy_next_T, gx_R}]);
    wire g_can_move_D = !(MAZE[{gy_next_B, gx_L}] | MAZE[{gy_next_B, gx_R}]);
    wire g_can_move_L = !(MAZE[{gy_T, gx_next_L}] | MAZE[{gy_B, gx_next_L}]);
    wire g_can_move_R = !(MAZE[{gy_T, gx_next_R}] | MAZE[{gy_B, gx_next_R}]);

    wire ghost_scared = (power_timer > 0);

    // Game Update Loop
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || btn_reset) begin
            state       <= 0;
            frame_ctr   <= 0;
            power_timer <= 0;
            dots        <= ~MAZE;                 // Setup dots everywhere there isn't a wall
            px          <= 240; py <= 224;        // Pacman start (Left path)
            gx          <= 400; gy <= 256;        // Ghost start (Right path)
            pac_dir     <= 0;
        end else if (hpos == 0 && vpos == 0) begin
            frame_ctr <= frame_ctr + 1;
            
            if (power_timer > 0) power_timer <= power_timer - 1;
            
            if (state == 0) begin
                // --- Pacman Movement ---
                if (btn_up && py > ARENA_T + RADIUS + 1 && can_move_U) begin 
                    py <= py - 2; pac_dir <= 2; 
                end else if (btn_down && py < ARENA_B - RADIUS - 1 && can_move_D) begin 
                    py <= py + 2; pac_dir <= 3; 
                end else if (btn_left && px > ARENA_L + RADIUS + 1 && can_move_L) begin 
                    px <= px - 2; pac_dir <= 1; 
                end else if (btn_right && px < ARENA_R - RADIUS - 1 && can_move_R) begin 
                    px <= px + 2; pac_dir <= 0; 
                end
                
                // --- Dot & Powerup Eating ---
                if (px >= ARENA_L && px < ARENA_R && py >= ARENA_T && py < ARENA_B) begin
                    if (dots[p_idx]) begin
                        dots[p_idx] <= 1'b0; // Eat it!
                        // Check if it's a corner power pellet
                        if (p_idx == 0 || p_idx == 7 || p_idx == 56 || p_idx == 63) begin
                            power_timer <= 600; // 10 seconds power mode
                        end
                    end
                end

                // --- Ghost Movement (AI) ---
                if (ghost_scared) begin
                    // Run Away (Half Speed)
                    if (frame_ctr[0]) begin
                        // Move with strict boundaries to avoid escaping arena
                        if      (gx < px && g_can_move_L && gx > ARENA_L + G_RADIUS + 1) gx <= gx - 1;
                        else if (gx > px && g_can_move_R && gx < ARENA_R - G_RADIUS - 1) gx <= gx + 1;
                        
                        if      (gy < py && g_can_move_U && gy > ARENA_T + G_RADIUS + 1) gy <= gy - 1;
                        else if (gy > py && g_can_move_D && gy < ARENA_B - G_RADIUS - 1) gy <= gy + 1;
                    end
                end else begin
                    // Chase Mode (Normal Speed)
                    // Move with strict boundaries to avoid escaping arena
                    if      (gx < px && g_can_move_R && gx < ARENA_R - G_RADIUS - 1) gx <= gx + 1;
                    else if (gx > px && g_can_move_L && gx > ARENA_L + G_RADIUS + 1) gx <= gx - 1;
                    
                    if      (gy < py && g_can_move_D && gy < ARENA_B - G_RADIUS - 1) gy <= gy + 1;
                    else if (gy > py && g_can_move_U && gy > ARENA_T + G_RADIUS + 1) gy <= gy - 1;
                end

                // --- Entity Collision ---
                if ( (px > gx ? px - gx : gx - px) < 18 && 
                     (py > gy ? py - gy : gy - py) < 18 ) begin
                    if (ghost_scared) begin
                        gx <= 400; // Send ghost back to starting area
                        gy <= 256;
                        power_timer <= 0; // End power mode early
                    end else begin
                        state <= 2; // LOSE
                    end
                end
                
                // --- Win Condition ---
                if (dots == 64'd0) begin
                    state <= 1; // WIN
                end
            end
        end
    end

    // --- RENDERING LOGIC ---

    wire in_arena = (hpos >= ARENA_L && hpos < ARENA_R && vpos >= ARENA_T && vpos < ARENA_B);
    wire draw_wall = (hpos >= ARENA_L - 4 && hpos <= ARENA_R + 3 && 
                      vpos >= ARENA_T - 4 && vpos <= ARENA_B + 3) && !in_arena;

    wire [2:0] cell_col = (hpos - ARENA_L) >> 5;
    wire [2:0] cell_row = (vpos - ARENA_T) >> 5;
    wire [5:0] cell_idx = {cell_row, cell_col};
    wire [4:0] cx       = (hpos - ARENA_L) & 31;
    wire [4:0] cy       = (vpos - ARENA_T) & 31;
    
    // Maze Walls (Rendered as hollow blue squares)
    wire is_wall_cell = in_arena && MAZE[cell_idx];
    wire draw_maze_wall = is_wall_cell && (cx < 4 || cx > 27 || cy < 4 || cy > 27);

    // Dots and Power Pellets
    wire is_power_cell = (cell_idx == 0 || cell_idx == 7 || cell_idx == 56 || cell_idx == 63);
    wire draw_dot = in_arena && !is_wall_cell && dots[cell_idx] && 
                    (is_power_cell ? (cx >= 10 && cx <= 21 && cy >= 10 && cy <= 21)   // Big Power Pellet
                                   : (cx >= 14 && cx <= 17 && cy >= 14 && cy <= 17)); // Normal Dot

    // Pacman Rendering
    wire signed [11:0] dx = $signed({1'b0, hpos}) - $signed({1'b0, px});
    wire signed [11:0] dy = $signed({1'b0, vpos}) - $signed({1'b0, py});
    wire [23:0] pdist_sq  = dx*dx + dy*dy;
    wire [11:0] abs_dx = dx[11] ? -dx : dx;
    wire [11:0] abs_dy = dy[11] ? -dy : dy;

    wire is_circle = (pdist_sq <= 144);
    wire mouth_open = frame_ctr[4];
    wire is_mouth = mouth_open && (
        (pac_dir == 0 && dx > 0 && abs_dy < dx) ||
        (pac_dir == 1 && dx < 0 && abs_dy < -dx) ||
        (pac_dir == 2 && dy < 0 && abs_dx < -dy) ||
        (pac_dir == 3 && dy > 0 && abs_dx < dy)
    );
    wire draw_pac = is_circle && !is_mouth;

    // Ghost Rendering
    wire signed [11:0] gdx = $signed({1'b0, hpos}) - $signed({1'b0, gx});
    wire signed [11:0] gdy = $signed({1'b0, vpos}) - $signed({1'b0, gy});
    wire [23:0] gdist_sq   = gdx*gdx + gdy*gdy;
    wire [11:0] abs_gdx    = gdx[11] ? -gdx : gdx;

    wire ghost_head = (gdist_sq <= 144) && (gdy <= 0);
    wire ghost_body = (abs_gdx <= 12) && (gdy > 0 && gdy <= 12);
    wire cut_leg = (gdy > 8) && (abs_gdx == 4 || abs_gdx == 5 || abs_gdx == 0 || abs_gdx == 1); // Wavy bottom
    
    wire draw_ghost_eye = (gdy >= -6 && gdy <= -2) && ((gdx >= -6 && gdx <= -3) || (gdx >= 3 && gdx <= 6));
    wire draw_ghost_base = (ghost_head || ghost_body) && !cut_leg;
    wire draw_ghost = draw_ghost_base && !draw_ghost_eye;

    // --- COLOR MIXING ---
    wire is_lose_flash = (state == 2) && frame_ctr[5];
    wire is_win_flash  = (state == 1) && frame_ctr[5];
    wire scared_flash  = (power_timer > 0 && power_timer < 120) && frame_ctr[4]; // Flashes when ending

    wire [1:0] ghost_r = ghost_scared ? (scared_flash ? 2'b11 : 2'b00) : 2'b11;
    wire [1:0] ghost_g = ghost_scared ? (scared_flash ? 2'b11 : 2'b01) : 2'b00;
    wire [1:0] ghost_b = ghost_scared ? (scared_flash ? 2'b11 : 2'b11) : 2'b00;
    
    wire [1:0] eye_r   = ghost_scared ? (scared_flash ? 2'b11 : 2'b11) : 2'b11;
    wire [1:0] eye_g   = ghost_scared ? (scared_flash ? 2'b00 : 2'b11) : 2'b11;
    wire [1:0] eye_b   = ghost_scared ? (scared_flash ? 2'b00 : 2'b00) : 2'b11;

    wire [1:0] r_out = !display_on ? 2'b00 :
                       is_lose_flash ? 2'b11 :
                       is_win_flash  ? 2'b00 :
                       draw_ghost_eye ? eye_r :
                       draw_ghost ? ghost_r :
                       draw_pac   ? 2'b11 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b00 : 2'b00;

    wire [1:0] g_out = !display_on ? 2'b00 :
                       is_lose_flash ? 2'b00 :
                       is_win_flash  ? 2'b11 :
                       draw_ghost_eye ? eye_g :
                       draw_ghost ? ghost_g :
                       draw_pac   ? 2'b11 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b01 : 2'b00;

    wire [1:0] b_out = !display_on ? 2'b00 :
                       is_lose_flash ? 2'b00 :
                       is_win_flash  ? 2'b00 :
                       draw_ghost_eye ? eye_b :
                       draw_ghost ? ghost_b :
                       draw_pac   ? 2'b00 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b11 : 2'b00;

    // VGA output mapping (RGB222 on Tiny VGA PMOD)
    assign uo_out[0] = r_out[1];  
    assign uo_out[4] = r_out[0];  
    assign uo_out[1] = g_out[1];  
    assign uo_out[5] = g_out[0];  
    assign uo_out[2] = b_out[1];  
    assign uo_out[6] = b_out[0];  
    assign uo_out[3] = vsync;     
    assign uo_out[7] = hsync;     

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Tie off unused inputs
    wire _unused = &{ena, uio_in, ui_in[7:5], 1'b0};

endmodule