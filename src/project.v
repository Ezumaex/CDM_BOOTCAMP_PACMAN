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

    // Synchronize physical buttons into the pixel-clock domain (single register stage to minimize area)
    reg [4:0] buttons;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buttons <= 5'd0;
        end else begin
            buttons <= ui_in[4:0];
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
    reg [5:0]  frame_ctr;       // Animation counter
    reg [63:0] dots;            // 8x8 Grid of dots
    reg [9:0]  power_timer;     // Powerup timer (600 frames = 10 sec)

    // Relative coordinates in arena [0..255]
    wire [8:0] px_rel = px[8:0] - 9'd192;
    wire [8:0] py_rel = py[8:0] - 9'd112;
    wire [2:0] p_col  = px_rel[7:5];
    wire [2:0] p_row  = py_rel[7:5];
    wire [5:0] p_idx  = {p_row, p_col};

    // Compact folded 4x4 quadrant maze wall checker (100% equivalent to MAZE[{r,c}])
    function is_wall;
        input [2:0] r, c;
        reg [1:0] rf, cf;
        begin
            rf = r[2] ? ~r[1:0] : r[1:0];
            cf = c[2] ? ~c[1:0] : c[1:0];
            is_wall = (rf == 2'd1 && (cf == 2'd1 || cf == 2'd2)) ||
                      (rf == 2'd2 && cf == 2'd1) ||
                      (rf == 2'd3 && cf == 2'd3);
        end
    endfunction

    // --- WALL COLLISION DETECTION ---
    wire [8:0] px_sub_11 = px_rel - 9'd11;
    wire [8:0] px_add_11 = px_rel + 9'd11;
    wire [8:0] py_sub_11 = py_rel - 9'd11;
    wire [8:0] py_add_11 = py_rel + 9'd11;

    wire [8:0] px_sub_13 = px_rel - 9'd13;
    wire [8:0] px_add_13 = px_rel + 9'd13;
    wire [8:0] py_sub_13 = py_rel - 9'd13;
    wire [8:0] py_add_13 = py_rel + 9'd13;

    wire [2:0] px_L = px_sub_11[7:5];
    wire [2:0] px_R = px_add_11[8] ? 3'd7 : px_add_11[7:5];
    wire [2:0] py_T = py_sub_11[7:5];
    wire [2:0] py_B = py_add_11[8] ? 3'd7 : py_add_11[7:5];

    wire [2:0] py_next_T = py_sub_13[7:5];
    wire [2:0] py_next_B = py_add_13[8] ? 3'd7 : py_add_13[7:5];
    wire [2:0] px_next_L = px_sub_13[7:5];
    wire [2:0] px_next_R = px_add_13[8] ? 3'd7 : px_add_13[7:5];

    wire can_move_U = !(is_wall(py_next_T, px_L) | is_wall(py_next_T, px_R));
    wire can_move_D = !(is_wall(py_next_B, px_L) | is_wall(py_next_B, px_R));
    wire can_move_L = !(is_wall(py_T, px_next_L) | is_wall(py_B, px_next_L));
    wire can_move_R = !(is_wall(py_T, px_next_R) | is_wall(py_B, px_next_R));

    // Ghost collision helpers
    wire [8:0] gx_rel = gx[8:0] - 9'd192;
    wire [8:0] gy_rel = gy[8:0] - 9'd112;

    wire [8:0] gx_sub_10 = gx_rel - 9'd10;
    wire [8:0] gx_add_10 = gx_rel + 9'd10;
    wire [8:0] gy_sub_10 = gy_rel - 9'd10;
    wire [8:0] gy_add_10 = gy_rel + 9'd10;

    wire [8:0] gx_sub_11 = gx_rel - 9'd11;
    wire [8:0] gx_add_11 = gx_rel + 9'd11;
    wire [8:0] gy_sub_11 = gy_rel - 9'd11;
    wire [8:0] gy_add_11 = gy_rel + 9'd11;

    wire [2:0] gx_L = gx_sub_10[7:5];
    wire [2:0] gx_R = gx_add_10[8] ? 3'd7 : gx_add_10[7:5];
    wire [2:0] gy_T = gy_sub_10[7:5];
    wire [2:0] gy_B = gy_add_10[8] ? 3'd7 : gy_add_10[7:5];

    wire [2:0] gy_next_T = gy_sub_11[7:5];
    wire [2:0] gy_next_B = gy_add_11[8] ? 3'd7 : gy_add_11[7:5];
    wire [2:0] gx_next_L = gx_sub_11[7:5];
    wire [2:0] gx_next_R = gx_add_11[8] ? 3'd7 : gx_add_11[7:5];

    wire g_can_move_U = !(is_wall(gy_next_T, gx_L) | is_wall(gy_next_T, gx_R));
    wire g_can_move_D = !(is_wall(gy_next_B, gx_L) | is_wall(gy_next_B, gx_R));
    wire g_can_move_L = !(is_wall(gy_T, gx_next_L) | is_wall(gy_B, gx_next_L));
    wire g_can_move_R = !(is_wall(gy_T, gx_next_R) | is_wall(gy_B, gx_next_R));

    wire ghost_scared = (power_timer > 0);

    // Fast single-comparison entity collision check (avoids chained signed comparators)
    wire [9:0] offset_x = px - gx + 10'd17;
    wire [9:0] offset_y = py - gy + 10'd17;
    wire entity_collision = (offset_x <= 10'd34) && (offset_y <= 10'd34);

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

    wire [9:0] hpos_rel = hpos - 10'd192;
    wire [9:0] vpos_rel = vpos - 10'd112;
    wire in_arena = (hpos_rel[9:8] == 2'b00) && (vpos_rel[9:8] == 2'b00);

    wire [9:0] hpos_border = hpos - 10'd188;
    wire [9:0] vpos_border = vpos - 10'd108;
    wire draw_wall = (hpos_border <= 10'd263 && vpos_border <= 10'd263) && !in_arena;

    wire [2:0] cell_col = hpos_rel[7:5];
    wire [2:0] cell_row = vpos_rel[7:5];
    wire [5:0] cell_idx = {cell_row, cell_col};
    wire [4:0] cx       = hpos_rel[4:0];
    wire [4:0] cy       = vpos_rel[4:0];

    // Maze Walls (Rendered as hollow blue squares)
    wire is_wall_cell = in_arena && is_wall(cell_row, cell_col);
    wire draw_maze_wall = is_wall_cell && ((cx[4:2] == 3'b000 || cx[4:2] == 3'b111) ||
                                           (cy[4:2] == 3'b000 || cy[4:2] == 3'b111));

    // Dots and Power Pellets
    wire is_power_cell = (cell_row == 3'd0 || cell_row == 3'd7) && (cell_col == 3'd0 || cell_col == 3'd7);
    wire draw_dot = in_arena && dots[cell_idx] &&
                    (is_power_cell ? (cx >= 10 && cx <= 21 && cy >= 10 && cy <= 21)   // Big Power Pellet
                                   : (cx >= 14 && cx <= 17 && cy >= 14 && cy <= 17)); // Normal Dot

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

    // Pacman Rendering (bounded 25x25 box eliminates wide comparators and subtractors)
    wire [9:0] p_diff_x = hpos - px + 10'd12;
    wire [9:0] p_diff_y = vpos - py + 10'd12;
    wire in_pac_box = (p_diff_x <= 10'd24) && (p_diff_y <= 10'd24);

    wire [3:0] abs_dx = (p_diff_x >= 10'd12) ? (p_diff_x[4:0] - 5'd12) : (5'd12 - p_diff_x[4:0]);
    wire [3:0] abs_dy = (p_diff_y >= 10'd12) ? (p_diff_y[4:0] - 5'd12) : (5'd12 - p_diff_y[4:0]);

    wire is_circle = in_pac_box && circle12({8'd0, abs_dx}, {8'd0, abs_dy});
    wire mouth_open = frame_ctr[4];
    wire horiz_mouth = (pac_dir == 0 && p_diff_x > 10'd12) || (pac_dir == 1 && p_diff_x < 10'd12);
    wire vert_mouth  = (pac_dir == 2 && p_diff_y < 10'd12) || (pac_dir == 3 && p_diff_y > 10'd12);
    wire is_mouth = mouth_open && (
        (horiz_mouth && abs_dy < abs_dx) ||
        (vert_mouth  && abs_dx < abs_dy)
    );
    wire draw_pac = is_circle && !is_mouth;

    // Ghost Rendering (bounded 25x25 box eliminates wide comparators and subtractors)
    wire [9:0] g_diff_x = hpos - gx + 10'd12;
    wire [9:0] g_diff_y = vpos - gy + 10'd12;
    wire in_ghost_box = (g_diff_x <= 10'd24) && (g_diff_y <= 10'd24);

    wire [3:0] abs_gdx = (g_diff_x >= 10'd12) ? (g_diff_x[4:0] - 5'd12) : (5'd12 - g_diff_x[4:0]);
    wire [3:0] abs_gdy = (g_diff_y >= 10'd12) ? (g_diff_y[4:0] - 5'd12) : (5'd12 - g_diff_y[4:0]);

    wire ghost_head = in_ghost_box && (g_diff_y <= 10'd12) && circle12({8'd0, abs_gdx}, {8'd0, abs_gdy});
    wire ghost_body = in_ghost_box && (g_diff_y > 10'd12);
    wire cut_leg = (g_diff_y > 10'd20) && (abs_gdx < 4'd8 && !abs_gdx[1]); // Wavy bottom (0, 1, 4, 5)

    wire draw_ghost_eye = in_ghost_box && (g_diff_y >= 10'd6 && g_diff_y <= 10'd10) && (abs_gdx >= 4'd3 && abs_gdx <= 4'd6);
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

    wire [1:0] r_out = is_lose_flash ? 2'b11 :
                       is_win_flash  ? 2'b00 :
                       draw_ghost_eye ? eye_r :
                       draw_ghost ? ghost_r :
                       draw_pac   ? 2'b11 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b00 : 2'b00;

    wire [1:0] g_out = is_lose_flash ? 2'b00 :
                       is_win_flash  ? 2'b11 :
                       draw_ghost_eye ? eye_g :
                       draw_ghost ? ghost_g :
                       draw_pac   ? 2'b11 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b01 : 2'b00;

    wire [1:0] b_out = is_lose_flash ? 2'b00 :
                       is_win_flash  ? 2'b00 :
                       draw_ghost_eye ? eye_b :
                       draw_ghost ? ghost_b :
                       draw_pac   ? 2'b00 :
                       draw_dot   ? (is_power_cell && frame_ctr[4] ? 2'b00 : 2'b11) :
                       (draw_maze_wall | draw_wall) ? 2'b11 : 2'b00;

    // VGA output mapping (RGB222 on Tiny VGA PMOD)
    assign uo_out[0] = display_on & r_out[1];
    assign uo_out[4] = display_on & r_out[0];
    assign uo_out[1] = display_on & g_out[1];
    assign uo_out[5] = display_on & g_out[0];
    assign uo_out[2] = display_on & b_out[1];
    assign uo_out[6] = display_on & b_out[0];
    assign uo_out[3] = vsync;
    assign uo_out[7] = hsync;

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Tie off ALL unused signals cleanly to satisfy the linter
    wire _unused = &{
        ena,
        uio_in,
        ui_in[7:5],
        px_sub_11[8], px_sub_11[4:0],
        px_add_11[4:0],
        py_sub_11[8], py_sub_11[4:0],
        py_add_11[4:0],
        px_sub_13[8], px_sub_13[4:0],
        px_add_13[4:0],
        py_sub_13[8], py_sub_13[4:0],
        py_add_13[4:0],
        gx_sub_10[8], gx_sub_10[4:0],
        gx_add_10[4:0],
        gy_sub_10[8], gy_sub_10[4:0],
        gy_add_10[4:0],
        gx_sub_11[8], gx_sub_11[4:0],
        gx_add_11[4:0],
        gy_sub_11[8], gy_sub_11[4:0],
        gy_add_11[4:0],
        1'b0
    };

endmodule
`default_nettype wire
