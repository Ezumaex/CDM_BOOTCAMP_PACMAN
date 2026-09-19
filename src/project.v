/*
 * Pacman-style Arena Minigame - DX Edition (Strict Linter Fixed)
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

module tt_um_ezumaex_pacman (
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

    // Synchronize physical buttons into the pixel-clock domain.
    reg [4:0] buttons_meta, buttons;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buttons_meta <= 5'd0;
            buttons <= 5'd0;
        end else begin
            buttons_meta <= ui_in[4:0];
            buttons <= buttons_meta;
        end
    end

    // Input Buttons
    wire btn_up    = buttons[0];
    wire btn_down  = buttons[1];
    wire btn_left  = buttons[2];
    wire btn_right = buttons[3];
    wire btn_reset = buttons[4];

    // Arena Boundaries
    localparam ARENA_L = 10'd192;
    localparam ARENA_R = 10'd448;
    localparam ARENA_T = 10'd112;
    localparam ARENA_B = 10'd368;
    localparam RADIUS  = 10'd11; // Collision radius
    localparam G_RADIUS = 10'd10; // Ghost Collision radius

    // 8x8 Maze Layout (1 = Wall, 0 = Path)
    localparam [63:0] MAZE = {
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
    reg [5:0] frame_ctr;       // Animation counter
    reg [63:0] dots;            // 8x8 Grid of dots
    reg [9:0]  power_timer;     // Powerup timer (600 frames = 10 sec)

    // Dot mapping (Pacman's current grid cell)
    wire [9:0] p_norm_x = px - ARENA_L;
    wire [9:0] p_norm_y = py - ARENA_T;
    wire [2:0] p_col = p_norm_x[7:5];
    wire [2:0] p_row = p_norm_y[7:5];
    wire [5:0] p_idx = {p_row, p_col};

    // Function to check if a cell is a wall in the 8x8 maze (100% equivalent to MAZE[{r,c}])
    function is_wall;
        input [2:0] r, c;
        begin
            case (r)
                3'd1, 3'd6: is_wall = (c == 3'd1 || c == 3'd2 || c == 3'd5 || c == 3'd6);
                3'd2, 3'd5: is_wall = (c == 3'd1 || c == 3'd6);
                3'd3, 3'd4: is_wall = (c == 3'd3 || c == 3'd4);
                default:    is_wall = 1'b0;
            endcase
        end
    endfunction

    // --- WALL COLLISION DETECTION ---
    wire [9:0] px_L_calc = px - 10'd203;
    wire [2:0] px_L = (px >= 10'd203) ? px_L_calc[7:5] : 3'd0;
    wire [9:0] px_R_calc = px - 10'd181;
    wire [2:0] px_R = (px < 10'd437) ? px_R_calc[7:5] : 3'd7;
    wire [9:0] py_T_calc = py - 10'd123;
    wire [2:0] py_T = (py >= 10'd123) ? py_T_calc[7:5] : 3'd0;
    wire [9:0] py_B_calc = py - 10'd101;
    wire [2:0] py_B = (py < 10'd357) ? py_B_calc[7:5] : 3'd7;

    wire [9:0] py_next_T_calc = py - 10'd125;
    wire [2:0] py_next_T = (py >= 10'd125) ? py_next_T_calc[7:5] : 3'd0;
    wire [9:0] py_next_B_calc = py - 10'd99;
    wire [2:0] py_next_B = (py < 10'd355) ? py_next_B_calc[7:5] : 3'd7;
    wire [9:0] px_next_L_calc = px - 10'd205;
    wire [2:0] px_next_L = (px >= 10'd205) ? px_next_L_calc[7:5] : 3'd0;
    wire [9:0] px_next_R_calc = px - 10'd179;
    wire [2:0] px_next_R = (px < 10'd435) ? px_next_R_calc[7:5] : 3'd7;

    wire can_move_U = !(is_wall(py_next_T, px_L) | is_wall(py_next_T, px_R));
    wire can_move_D = !(is_wall(py_next_B, px_L) | is_wall(py_next_B, px_R));
    wire can_move_L = !(is_wall(py_T, px_next_L) | is_wall(py_B, px_next_L));
    wire can_move_R = !(is_wall(py_T, px_next_R) | is_wall(py_B, px_next_R));

    // Ghost collision helpers
    wire [9:0] gx_L_calc = gx - 10'd202;
    wire [2:0] gx_L = (gx >= 10'd202) ? gx_L_calc[7:5] : 3'd0;
    wire [9:0] gx_R_calc = gx - 10'd182;
    wire [2:0] gx_R = (gx < 10'd438) ? gx_R_calc[7:5] : 3'd7;
    wire [9:0] gy_T_calc = gy - 10'd122;
    wire [2:0] gy_T = (gy >= 10'd122) ? gy_T_calc[7:5] : 3'd0;
    wire [9:0] gy_B_calc = gy - 10'd102;
    wire [2:0] gy_B = (gy < 10'd358) ? gy_B_calc[7:5] : 3'd7;

    wire [9:0] gy_next_T_calc = gy - 10'd123;
    wire [2:0] gy_next_T = (gy >= 10'd123) ? gy_next_T_calc[7:5] : 3'd0;
    wire [9:0] gy_next_B_calc = gy - 10'd101;
    wire [2:0] gy_next_B = (gy < 10'd357) ? gy_next_B_calc[7:5] : 3'd7;
    wire [9:0] gx_next_L_calc = gx - 10'd203;
    wire [2:0] gx_next_L = (gx >= 10'd203) ? gx_next_L_calc[7:5] : 3'd0;
    wire [9:0] gx_next_R_calc = gx - 10'd181;
    wire [2:0] gx_next_R = (gx < 10'd437) ? gx_next_R_calc[7:5] : 3'd7;

    wire g_can_move_U = !(is_wall(gy_next_T, gx_L) | is_wall(gy_next_T, gx_R));
    wire g_can_move_D = !(is_wall(gy_next_B, gx_L) | is_wall(gy_next_B, gx_R));
    wire g_can_move_L = !(is_wall(gy_T, gx_next_L) | is_wall(gy_B, gx_next_L));
    wire g_can_move_R = !(is_wall(gy_T, gx_next_R) | is_wall(gy_B, gx_next_R));

    wire ghost_scared = (power_timer > 0);

    // Fast entity collision check
    wire signed [10:0] diff_px_gx = $signed({1'b0, px}) - $signed({1'b0, gx});
    wire signed [10:0] diff_py_gy = $signed({1'b0, py}) - $signed({1'b0, gy});
    wire entity_collision = (diff_px_gx > -11'sd18 && diff_px_gx < 11'sd18) &&
                            (diff_py_gy > -11'sd18 && diff_py_gy < 11'sd18);

    // Update in vertical blanking so each visible frame is coherent.
    // Game Update Loop
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Hardware Asynchronous Reset
            state       <= 0;
            frame_ctr   <= 0;
            power_timer <= 0;
            dots        <= ~MAZE;
            px          <= 240; py <= 224;
            gx          <= 400; gy <= 256;
            pac_dir     <= 0;
        end else if (btn_reset) begin
            // Software Synchronous Reset
            state       <= 0;
            frame_ctr   <= 0;
            power_timer <= 0;
            dots        <= ~MAZE;
            px          <= 240; py <= 224;
            gx          <= 400; gy <= 256;
            pac_dir     <= 0;
        end else if (hpos == 10'd0 && vpos == 10'd480) begin
            frame_ctr <= frame_ctr + 1;

            if (power_timer > 0) power_timer <= power_timer - 1;

            if (state == 0) begin
                // --- Pacman Movement ---
                if (btn_up && py > ARENA_T + RADIUS + 1 && can_move_U) begin
                    py <= py - 10'd2; pac_dir <= 2;
                end else if (btn_down && py < ARENA_B - RADIUS - 1 && can_move_D) begin
                    py <= py + 10'd2; pac_dir <= 3;
                end else if (btn_left && px > ARENA_L + RADIUS + 1 && can_move_L) begin
                    px <= px - 10'd2; pac_dir <= 1;
                end else if (btn_right && px < ARENA_R - RADIUS - 1 && can_move_R) begin
                    px <= px + 10'd2; pac_dir <= 0;
                end

                // --- Dot & Powerup Eating ---
                if (dots[p_idx]) begin
                    dots[p_idx] <= 1'b0; // Eat it!
                    if ((p_row == 3'd0 || p_row == 3'd7) && (p_col == 3'd0 || p_col == 3'd7)) begin
                        power_timer <= 600; // 10 seconds power mode
                    end
                end

                // --- Ghost Movement (AI) ---
                if (ghost_scared) begin
                    // Run Away (Half Speed)
                    if (frame_ctr[0]) begin
                        if      (gx < px && g_can_move_L && gx > ARENA_L + G_RADIUS + 1) gx <= gx - 10'd1;
                        else if (gx > px && g_can_move_R && gx < ARENA_R - G_RADIUS - 1) gx <= gx + 10'd1;

                        else if (gy < py && g_can_move_U && gy > ARENA_T + G_RADIUS + 1) gy <= gy - 10'd1;
                        else if (gy > py && g_can_move_D && gy < ARENA_B - G_RADIUS - 1) gy <= gy + 10'd1;
                    end
                end else begin
                    // Chase Mode (Normal Speed)
                    if      (gx < px && g_can_move_R && gx < ARENA_R - G_RADIUS - 1) gx <= gx + 10'd1;
                    else if (gx > px && g_can_move_L && gx > ARENA_L + G_RADIUS + 1) gx <= gx - 10'd1;

                    else if (gy < py && g_can_move_D && gy < ARENA_B - G_RADIUS - 1) gy <= gy + 10'd1;
                    else if (gy > py && g_can_move_U && gy > ARENA_T + G_RADIUS + 1) gy <= gy - 10'd1;
                end

                // --- Entity Collision ---
                if (entity_collision) begin
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

    wire [9:0] hpos_norm = hpos - ARENA_L;
    wire [9:0] vpos_norm = vpos - ARENA_T;

    wire [2:0] cell_col = hpos_norm[7:5];
    wire [2:0] cell_row = vpos_norm[7:5];
    wire [5:0] cell_idx = {cell_row, cell_col};
    wire [4:0] cx       = hpos_norm[4:0];
    wire [4:0] cy       = vpos_norm[4:0];

    // Maze Walls (Rendered as hollow blue squares)
    wire is_wall_cell = in_arena && is_wall(cell_row, cell_col);
    wire draw_maze_wall = is_wall_cell && (cx < 4 || cx > 27 || cy < 4 || cy > 27);

    // Dots and Power Pellets
    wire is_power_cell = (cell_row == 3'd0 || cell_row == 3'd7) && (cell_col == 3'd0 || cell_col == 3'd7);
    wire draw_dot = in_arena && !is_wall_cell && dots[cell_idx] &&
                    (is_power_cell ? (cx >= 10 && cx <= 21 && cy >= 10 && cy <= 21)   // Big Power Pellet
                                   : (cx >= 14 && cx <= 17 && cy >= 14 && cy <= 17)); // Normal Dot

    // Pacman Rendering
    wire signed [11:0] dx = $signed({2'b00, hpos}) - $signed({2'b00, px});
    wire signed [11:0] dy = $signed({2'b00, vpos}) - $signed({2'b00, py});
    wire [11:0] abs_dx = dx[11] ? -dx : dx;
    wire [11:0] abs_dy = dy[11] ? -dy : dy;

    // Exact integer radius-12 circle, without four large squaring multipliers.
    function circle12;
        input [11:0] ax, ay;
        begin
            if (ax[11:4] != 8'd0 || ay[11:4] != 8'd0) begin
                circle12 = 1'b0;
            end else begin
                case (ay[3:0])
                    4'd0: circle12 = ax[3:0] <= 4'd12;
                    4'd1,4'd2,4'd3,4'd4: circle12 = ax[3:0] <= 4'd11;
                    4'd5,4'd6: circle12 = ax[3:0] <= 4'd10;
                    4'd7: circle12 = ax[3:0] <= 4'd9;
                    4'd8: circle12 = ax[3:0] <= 4'd8;
                    4'd9: circle12 = ax[3:0] <= 4'd7;
                    4'd10: circle12 = ax[3:0] <= 4'd6;
                    4'd11: circle12 = ax[3:0] <= 4'd4;
                    4'd12: circle12 = ax[3:0] == 4'd0;
                    default: circle12 = 1'b0;
                endcase
            end
        end
    endfunction
    wire is_circle = circle12(abs_dx, abs_dy);
    wire mouth_open = frame_ctr[4];
    wire horiz_mouth = (pac_dir == 0 && dx > 0) || (pac_dir == 1 && dx < 0);
    wire vert_mouth  = (pac_dir == 2 && dy < 0) || (pac_dir == 3 && dy > 0);
    wire is_mouth = mouth_open && (
        (horiz_mouth && abs_dy < abs_dx) ||
        (vert_mouth  && abs_dx < abs_dy)
    );
    wire draw_pac = is_circle && !is_mouth;

    // Ghost Rendering
    wire signed [11:0] gdx = $signed({2'b00, hpos}) - $signed({2'b00, gx});
    wire signed [11:0] gdy = $signed({2'b00, vpos}) - $signed({2'b00, gy});
    wire [11:0] abs_gdx    = gdx[11] ? -gdx : gdx;

    wire [11:0] abs_gdy = gdy[11] ? -gdy : gdy;
    wire ghost_head = circle12(abs_gdx, abs_gdy) && (gdy <= 0);
    wire ghost_body = (abs_gdx <= 12) && (gdy > 0 && gdy <= 12);
    wire cut_leg = (gdy > 8) && (abs_gdx[11:3] == 9'd0 && !abs_gdx[1]); // Wavy bottom (0, 1, 4, 5)

    wire draw_ghost_eye = (gdy >= -6 && gdy <= -2) && (abs_gdx >= 3 && abs_gdx <= 6);
    wire draw_ghost_base = (ghost_head || ghost_body) && !cut_leg;
    wire draw_ghost = draw_ghost_base && !draw_ghost_eye;

    // --- COLOR MIXING ---
    wire is_lose_flash = (state == 2) && frame_ctr[5];
    wire is_win_flash  = (state == 1) && frame_ctr[5];
    wire scared_flash  = (power_timer > 0 && power_timer < 120) && frame_ctr[4]; // Flashes when ending

    wire [1:0] ghost_r = ghost_scared ? (scared_flash ? 2'b11 : 2'b00) : 2'b11;
    wire [1:0] ghost_g = ghost_scared ? (scared_flash ? 2'b11 : 2'b01) : 2'b00;
    wire [1:0] ghost_b = ghost_scared ? (scared_flash ? 2'b11 : 2'b11) : 2'b00;

    wire [1:0] eye_r   = 2'b11;
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

    // Tie off ALL unused signals cleanly to satisfy the linter
    wire _unused = &{
        ena,
        uio_in,
        ui_in[7:5],
        p_norm_x[9:8], p_norm_x[4:0],
        p_norm_y[9:8], p_norm_y[4:0],
        px_L_calc[9:8], px_L_calc[4:0],
        px_R_calc[9:8], px_R_calc[4:0],
        py_T_calc[9:8], py_T_calc[4:0],
        py_B_calc[9:8], py_B_calc[4:0],
        py_next_T_calc[9:8], py_next_T_calc[4:0],
        py_next_B_calc[9:8], py_next_B_calc[4:0],
        px_next_L_calc[9:8], px_next_L_calc[4:0],
        px_next_R_calc[9:8], px_next_R_calc[4:0],
        gx_L_calc[9:8], gx_L_calc[4:0],
        gx_R_calc[9:8], gx_R_calc[4:0],
        gy_T_calc[9:8], gy_T_calc[4:0],
        gy_B_calc[9:8], gy_B_calc[4:0],
        gy_next_T_calc[9:8], gy_next_T_calc[4:0],
        gy_next_B_calc[9:8], gy_next_B_calc[4:0],
        gx_next_L_calc[9:8], gx_next_L_calc[4:0],
        gx_next_R_calc[9:8], gx_next_R_calc[4:0],
        hpos_norm[9:8],
        vpos_norm[9:8],
        1'b0
    };

endmodule
`default_nettype wire
