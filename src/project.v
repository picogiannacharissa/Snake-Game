/*
 * Snake  --  VGA Playground / Tiny Tapeout (Tiny VGA pinout)
 * SPDX-License-Identifier: Apache-2.0
 *
 * HOW TO RUN (vga-playground.com)
 *   1. Paste this whole file into the project.v tab (top module name must stay
 *      tt_um_vga_example).  No other file is needed - the VGA timing and the
 *      Gamepad Pmod receiver are inside this file.
 *   2. Click the gamepad icon above the display to get the on-screen D-pad,
 *      or use the ui_in switches:
 *         ui_in[0] = up     ui_in[1] = down    ui_in[2] = left
 *         ui_in[3] = right  ui_in[7] = start
 *      (ui_in[6:4] are the Gamepad Pmod data/clock/latch pins, like the
 *       "gamepad" preset.)
 *
 * HOW TO PLAY
 *   - Snake sits still (head blinks) until you press any button.
 *   - Steer with the D-pad.  Eat the red apple to grow; the score (two digits,
 *     top-left) goes up and the snake speeds up as it gets longer.
 *   - Hitting the brick wall or your own body ends the game (snake flashes
 *     red).  After about half a second any button starts a new game.
 *
 * SCREEN   640x480, 20x15 grid of 32x32 px cells; the outer ring of cells is wall.
 * SNAKE    up to MAXLEN (32) segments.
 */

`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // 25.175 MHz pixel clock
    input  wire       rst_n     // active-low reset
);

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;
  wire _unused_ok = &{ena, uio_in, 1'b0};

  // --------------------------------------------------------------------------
  // CONSTANTS
  // --------------------------------------------------------------------------
  localparam MAXLEN = 32;                      // max snake segments

  localparam [1:0] DIR_UP = 2'd0, DIR_RIGHT = 2'd1, DIR_DOWN = 2'd2, DIR_LEFT = 2'd3;
  localparam [1:0] S_INIT = 2'd0, S_IDLE = 2'd1, S_PLAY = 2'd2, S_DEAD = 2'd3;

  // colours, {R[1:0], G[1:0], B[1:0]}
  localparam [5:0] BLACK    = 6'b00_00_00;
  localparam [5:0] WHITE    = 6'b11_11_11;
  localparam [5:0] BG_A     = 6'b00_00_00;
  localparam [5:0] BG_B     = 6'b00_01_00;
  localparam [5:0] BODY     = 6'b00_11_00;
  localparam [5:0] BODY_SH  = 6'b00_10_00;
  localparam [5:0] HEAD     = 6'b01_11_00;
  localparam [5:0] HEAD_SH  = 6'b01_10_00;
  localparam [5:0] HEAD_HI  = 6'b11_11_01;
  localparam [5:0] APPLE    = 6'b11_00_00;
  localparam [5:0] APPLE_SH = 6'b10_00_00;
  localparam [5:0] SHINE    = 6'b11_10_10;
  localparam [5:0] STEM     = 6'b01_10_00;
  localparam [5:0] BRICK    = 6'b10_01_00;
  localparam [5:0] MORTAR   = 6'b01_01_01;
  localparam [5:0] RED_HI   = 6'b11_00_00;
  localparam [5:0] RED_LO   = 6'b10_00_00;

  // --------------------------------------------------------------------------
  // VGA TIMING  (640x480 @ 60 Hz, negative sync)
  // --------------------------------------------------------------------------
  reg [9:0] hpos, vpos;

  always @(posedge clk) begin
    if (!rst_n) begin
      hpos <= 10'd0;
      vpos <= 10'd0;
    end else if (hpos == 10'd799) begin
      hpos <= 10'd0;
      vpos <= (vpos == 10'd524) ? 10'd0 : vpos + 10'd1;
    end else begin
      hpos <= hpos + 10'd1;
    end
  end

  wire hs_n    = ~((hpos >= 10'd656) && (hpos <= 10'd751));
  wire vs_n    = ~((vpos >= 10'd490) && (vpos <= 10'd491));
  wire disp_on = (hpos < 10'd640) && (vpos < 10'd480);

  // one pulse per frame, at the start of vertical blanking: all game updates
  // happen here so the picture never tears
  wire frame_tick = (hpos == 10'd0) && (vpos == 10'd480);

  reg [5:0] frame_cnt;
  always @(posedge clk) begin
    if (!rst_n)          frame_cnt <= 6'd0;
    else if (frame_tick) frame_cnt <= frame_cnt + 6'd1;
  end

  // --------------------------------------------------------------------------
  // INPUT: Gamepad Pmod receiver (ui_in[4]=latch, [5]=clock, [6]=data)
  //        + direct switches on ui_in[3:0] / ui_in[7]
  // --------------------------------------------------------------------------
  reg [7:0]  ui_r;
  reg [1:0]  gp_data_s, gp_clk_s, gp_lat_s;
  reg        gp_clk_p, gp_lat_p;
  reg [11:0] gp_shift, gp_reg;

  always @(posedge clk) begin
    ui_r <= ui_in;
    if (!rst_n) begin
      gp_data_s <= 2'b00;
      gp_clk_s  <= 2'b00;
      gp_lat_s  <= 2'b00;
      gp_clk_p  <= 1'b0;
      gp_lat_p  <= 1'b0;
      gp_shift  <= 12'hFFF;
      gp_reg    <= 12'hFFF;
    end else begin
      gp_data_s <= {gp_data_s[0], ui_r[6]};
      gp_clk_s  <= {gp_clk_s[0],  ui_r[5]};
      gp_lat_s  <= {gp_lat_s[0],  ui_r[4]};
      gp_clk_p  <= gp_clk_s[1];
      gp_lat_p  <= gp_lat_s[1];
      if (gp_lat_s[1] & ~gp_lat_p) gp_reg   <= gp_shift;
      if (gp_clk_s[1] & ~gp_clk_p) gp_shift <= {gp_shift[10:0], gp_data_s[1]};
    end
  end

  // all-ones means "no controller connected"
  wire gp_present = (gp_reg != 12'hFFF);
  wire gp_b       = gp_present & gp_reg[11];
  wire gp_start   = gp_present & gp_reg[8];
  wire gp_up      = gp_present & gp_reg[7];
  wire gp_down    = gp_present & gp_reg[6];
  wire gp_left    = gp_present & gp_reg[5];
  wire gp_right   = gp_present & gp_reg[4];
  wire gp_a       = gp_present & gp_reg[3];

  wire in_up    = gp_up    | ui_r[0];
  wire in_down  = gp_down  | ui_r[1];
  wire in_left  = gp_left  | ui_r[2];
  wire in_right = gp_right | ui_r[3];
  wire in_start = gp_start | gp_a | gp_b | ui_r[7];
  wire any_press = in_up | in_down | in_left | in_right | in_start;

  // --------------------------------------------------------------------------
  // GAME STATE
  // --------------------------------------------------------------------------
  reg [1:0] state;
  reg [1:0] dir;          // direction of the last completed move
  reg [1:0] req_dir;      // direction requested for the next move
  reg [5:0] len;          // current snake length
  reg [4:0] sx [0:MAXLEN-1];   // segment 0 = head
  reg [3:0] sy [0:MAXLEN-1];
  reg [4:0] food_x;
  reg [3:0] food_y;
  reg       need_food;    // 1 = apple not placed yet
  reg [3:0] speed_cnt;
  reg [5:0] dead_cnt;
  reg [3:0] score_ones, score_tens;
  integer   i;

  // free-running LFSR -> pseudo-random apple position
  reg [15:0] lfsr;
  always @(posedge clk) begin
    if (!rst_n) lfsr <= 16'hACE1;
    else        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  // SPEED: the snake moves once every `period` video frames.
  //   The playground simulates the chip far slower than real time (the
  //   "FPS" counter above the display, ~9 in a browser), so 2 frames per
  //   move is already ~4-5 cells/s there.  On real hardware (60 fps) use
  //   FRAMES_PER_MOVE = 10 (about 6 cells/s).  The snake speeds up as it grows.
  localparam [3:0] FRAMES_PER_MOVE = 4'd2;

  wire [3:0] speedup = (len < 6'd8)  ? 4'd0 :
                       (len < 6'd16) ? 4'd1 : 4'd2;
  wire [3:0] period  = (FRAMES_PER_MOVE > speedup + 4'd1) ? (FRAMES_PER_MOVE - speedup) : 4'd1;

  // ---- where would the head go next?
  reg [4:0] nx;
  reg [3:0] ny;
  always @(*) begin
    nx = sx[0];
    ny = sy[0];
    case (req_dir)
      DIR_UP:    ny = sy[0] - 4'd1;
      DIR_RIGHT: nx = sx[0] + 5'd1;
      DIR_DOWN:  ny = sy[0] + 4'd1;
      DIR_LEFT:  nx = sx[0] - 5'd1;
    endcase
  end

  wire food_ok  = ~need_food;
  wire wall_hit = (nx == 5'd0) || (nx == 5'd19) || (ny == 4'd0) || (ny == 4'd14);
  wire eat      = food_ok && (nx == food_x) && (ny == food_y);
  wire grow     = eat && (len < 6'd32);

  // self collision: the tail cell is free again unless we are growing
  wire [31:0] hit_limit = grow ? {26'd0, len} : ({26'd0, len} - 32'd1);
  reg         self_hit;
  integer     kc;
  always @(*) begin
    self_hit = 1'b0;
    for (kc = 0; kc < MAXLEN; kc = kc + 1)
      if ((kc < hit_limit) && (sx[kc] == nx) && (sy[kc] == ny))
        self_hit = 1'b1;
  end

  // ---- candidate apple position (must be inside the playfield, not on snake)
  wire [4:0]  cand_x  = lfsr[4:0];
  wire [3:0]  cand_y  = lfsr[8:5];
  wire        cand_in = (cand_x >= 5'd1) && (cand_x <= 5'd18) &&
                        (cand_y >= 4'd1) && (cand_y <= 4'd13);
  wire [31:0] len_i   = {26'd0, len};
  reg         cand_hit;
  integer     kb;
  always @(*) begin
    cand_hit = 1'b0;
    for (kb = 0; kb < MAXLEN; kb = kb + 1)
      if ((kb < len_i) && (sx[kb] == cand_x) && (sy[kb] == cand_y))
        cand_hit = 1'b1;
  end

  // --------------------------------------------------------------------------
  // GAME FSM
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n || state == S_INIT) begin
      state      <= S_IDLE;
      dir        <= DIR_RIGHT;
      req_dir    <= DIR_RIGHT;
      len        <= 6'd3;
      for (i = 0; i < MAXLEN; i = i + 1) begin
        sx[i] <= (i == 0) ? 5'd10 : (i == 1) ? 5'd9 : (i == 2) ? 5'd8 : 5'd0;
        sy[i] <= 4'd7;
      end
      food_x     <= 5'd0;
      food_y     <= 4'd0;
      need_food  <= 1'b1;
      speed_cnt  <= 4'd0;
      dead_cnt   <= 6'd0;
      score_ones <= 4'd0;
      score_tens <= 4'd0;
    end else begin

      // steering: remember the latest request that is not a 180 degree turn
      if (state == S_IDLE || state == S_PLAY) begin
        if      (in_up    && dir != DIR_DOWN)  req_dir <= DIR_UP;
        else if (in_right && dir != DIR_LEFT)  req_dir <= DIR_RIGHT;
        else if (in_down  && dir != DIR_UP)    req_dir <= DIR_DOWN;
        else if (in_left  && dir != DIR_RIGHT) req_dir <= DIR_LEFT;
      end

      case (state)
        // ------------------------------------------------------------------
        S_IDLE: begin
          if (any_press) state <= S_PLAY;
        end

        // ------------------------------------------------------------------
        S_PLAY: begin
          // place the apple (a few clocks after start / after eating one)
          if (need_food && !frame_tick && cand_in && !cand_hit) begin
            food_x    <= cand_x;
            food_y    <= cand_y;
            need_food <= 1'b0;
          end

          if (frame_tick) begin
            if (speed_cnt >= period - 4'd1) begin
              speed_cnt <= 4'd0;
              dir       <= req_dir;

              if (wall_hit || self_hit) begin
                state    <= S_DEAD;
                dead_cnt <= 6'd0;
              end else begin
                // move: every segment takes the place of the one before it
                for (i = MAXLEN - 1; i > 0; i = i - 1) begin
                  sx[i] <= sx[i-1];
                  sy[i] <= sy[i-1];
                end
                sx[0] <= nx;
                sy[0] <= ny;

                if (eat) begin
                  need_food <= 1'b1;
                  if (grow) len <= len + 6'd1;
                  if (score_ones == 4'd9) begin
                    if (score_tens != 4'd9) begin
                      score_ones <= 4'd0;
                      score_tens <= score_tens + 4'd1;
                    end
                  end else begin
                    score_ones <= score_ones + 4'd1;
                  end
                end
              end
            end else begin
              speed_cnt <= speed_cnt + 4'd1;
            end
          end
        end

        // ------------------------------------------------------------------
        S_DEAD: begin
          if (frame_tick && dead_cnt != 6'd63) dead_cnt <= dead_cnt + 6'd1;
          if (dead_cnt[5] && any_press) state <= S_INIT;   // ~0.5 s lock-out
        end

        default: state <= S_INIT;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // RENDER, stage 0: which game objects are under the current pixel?
  // --------------------------------------------------------------------------
  wire [4:0] cell_x = hpos[9:5];     // 0..19
  wire [3:0] cell_y = vpos[8:5];     // 0..14

  reg     px_head, px_body;
  integer ka;
  always @(*) begin
    px_head = (sx[0] == cell_x) && (sy[0] == cell_y);
    px_body = 1'b0;
    for (ka = 1; ka < MAXLEN; ka = ka + 1)
      if ((ka < len_i) && (sx[ka] == cell_x) && (sy[ka] == cell_y))
        px_body = 1'b1;
  end

  // ---- score read-out: two 3x5 digits at 4x scale in the top wall
  localparam [14:0] G_0 = 15'b111_101_101_101_111;
  localparam [14:0] G_1 = 15'b010_110_010_010_111;
  localparam [14:0] G_2 = 15'b111_001_111_100_111;
  localparam [14:0] G_3 = 15'b111_001_111_001_111;
  localparam [14:0] G_4 = 15'b101_101_111_001_001;
  localparam [14:0] G_5 = 15'b111_100_111_001_111;
  localparam [14:0] G_6 = 15'b111_100_111_101_111;
  localparam [14:0] G_7 = 15'b111_001_001_010_010;
  localparam [14:0] G_8 = 15'b111_101_111_101_111;
  localparam [14:0] G_9 = 15'b111_101_111_001_111;

  wire panel     = (hpos >= 10'd44) && (hpos < 10'd80) && (vpos >= 10'd4) && (vpos < 10'd28);
  wire in_sy     = (vpos >= 10'd6)  && (vpos < 10'd26);
  wire in_tens_x = (hpos >= 10'd48) && (hpos < 10'd60);
  wire in_ones_x = (hpos >= 10'd64) && (hpos < 10'd76);
  wire [9:0] sdx = in_tens_x ? (hpos - 10'd48) : (hpos - 10'd64);
  wire [9:0] sdy = vpos - 10'd6;
  wire [3:0] dval    = in_tens_x ? score_tens : score_ones;
  wire [3:0] dtarget = {1'b0, sdy[4:2]} * 4'd3 + {2'b00, sdx[3:2]};

  reg [14:0] dglyph;
  always @(*) begin
    case (dval)
      4'd0:    dglyph = G_0;
      4'd1:    dglyph = G_1;
      4'd2:    dglyph = G_2;
      4'd3:    dglyph = G_3;
      4'd4:    dglyph = G_4;
      4'd5:    dglyph = G_5;
      4'd6:    dglyph = G_6;
      4'd7:    dglyph = G_7;
      4'd8:    dglyph = G_8;
      4'd9:    dglyph = G_9;
      default: dglyph = 15'b0;
    endcase
  end
  wire digit_px = in_sy && (in_tens_x || in_ones_x) && dglyph[4'd14 - dtarget];

  // --------------------------------------------------------------------------
  // RENDER, stage 1 registers
  // --------------------------------------------------------------------------
  reg       r1_on, r1_hs, r1_vs;
  reg [4:0] r1_lx, r1_ly;
  reg [4:0] r1_cx;
  reg [3:0] r1_cy;
  reg       r1_head, r1_body, r1_food, r1_wall, r1_panel, r1_digit;

  always @(posedge clk) begin
    r1_on    <= disp_on;
    r1_hs    <= hs_n;
    r1_vs    <= vs_n;
    r1_lx    <= hpos[4:0];
    r1_ly    <= vpos[4:0];
    r1_cx    <= cell_x;
    r1_cy    <= cell_y;
    r1_head  <= px_head;
    r1_body  <= px_body;
    r1_food  <= food_ok && (cell_x == food_x) && (cell_y == food_y);
    r1_wall  <= (cell_x == 5'd0) || (cell_x == 5'd19) || (cell_y == 4'd0) || (cell_y == 4'd14);
    r1_panel <= panel;
    r1_digit <= digit_px;
  end

  // --------------------------------------------------------------------------
  // RENDER, stage 2: shapes and colours
  // --------------------------------------------------------------------------
  // snake segment: 28x28 square with cut corners and a darker lower/right edge
  wire seg_in    = (r1_lx >= 5'd2) && (r1_lx < 5'd30) && (r1_ly >= 5'd2) && (r1_ly < 5'd30);
  wire seg_cut   = ((r1_lx < 5'd4) || (r1_lx >= 5'd28)) && ((r1_ly < 5'd4) || (r1_ly >= 5'd28));
  wire seg_shape = seg_in && !seg_cut;
  wire seg_shade = (r1_lx >= 5'd26) || (r1_ly >= 5'd26);

  // eyes sit on the side the snake is heading to
  reg eye;
  always @(*) begin
    case (dir)
      DIR_UP:    eye = (r1_ly >= 5'd6  && r1_ly < 5'd10) &&
                       ((r1_lx >= 5'd8 && r1_lx < 5'd12) || (r1_lx >= 5'd20 && r1_lx < 5'd24));
      DIR_RIGHT: eye = (r1_lx >= 5'd20 && r1_lx < 5'd24) &&
                       ((r1_ly >= 5'd8 && r1_ly < 5'd12) || (r1_ly >= 5'd20 && r1_ly < 5'd24));
      DIR_DOWN:  eye = (r1_ly >= 5'd20 && r1_ly < 5'd24) &&
                       ((r1_lx >= 5'd8 && r1_lx < 5'd12) || (r1_lx >= 5'd20 && r1_lx < 5'd24));
      default:   eye = (r1_lx >= 5'd6  && r1_lx < 5'd10) &&
                       ((r1_ly >= 5'd8 && r1_ly < 5'd12) || (r1_ly >= 5'd20 && r1_ly < 5'd24));
    endcase
  end

  // apple: round-ish body, shine spot, stem
  wire apple_in   = (r1_lx >= 5'd6) && (r1_lx < 5'd26) && (r1_ly >= 5'd8) && (r1_ly < 5'd28);
  wire apple_cut  = ((r1_lx < 5'd9) || (r1_lx >= 5'd23)) && ((r1_ly < 5'd11) || (r1_ly >= 5'd25));
  wire apple_body = apple_in && !apple_cut;
  wire apple_stem = (r1_lx >= 5'd15) && (r1_lx < 5'd18) && (r1_ly >= 5'd3) && (r1_ly < 5'd8);
  wire apple_shn  = (r1_lx >= 5'd10) && (r1_lx < 5'd13) && (r1_ly >= 5'd12) && (r1_ly < 5'd15);
  wire apple_shd  = (r1_lx >= 5'd21) || (r1_ly >= 5'd23);

  // brick wall: 16 px tall bricks, every second row offset by half a brick
  wire mortar = (r1_ly[3:0] == 4'd0) || (r1_lx == (r1_ly[4] ? 5'd0 : 5'd16));

  wire is_dead = (state == S_DEAD);
  wire is_idle = (state == S_IDLE);
  wire fl_dead = frame_cnt[3];
  wire fl_idle = frame_cnt[4];

  wire [5:0] body_col = is_dead ? (fl_dead ? RED_HI : RED_LO) :
                        (seg_shade ? BODY_SH : BODY);
  wire [5:0] head_col = is_dead ? (fl_dead ? RED_HI : RED_LO) :
                        (is_idle && fl_idle) ? HEAD_HI :
                        (seg_shade ? HEAD_SH : HEAD);

  reg [5:0] color;
  always @(*) begin
    if (!r1_on)
      color = BLACK;
    else if (r1_panel)
      color = r1_digit ? WHITE : BLACK;
    else if (r1_wall)
      color = mortar ? MORTAR : BRICK;
    else if (r1_head && seg_shape)
      color = eye ? BLACK : head_col;
    else if (r1_body && seg_shape)
      color = body_col;
    else if (r1_food && apple_stem)
      color = STEM;
    else if (r1_food && apple_body)
      color = apple_shn ? SHINE : (apple_shd ? APPLE_SH : APPLE);
    else
      color = (r1_cx[0] ^ r1_cy[0]) ? BG_B : BG_A;
  end

  // --------------------------------------------------------------------------
  // OUTPUT REGISTERS  (Tiny VGA pinout)
  // --------------------------------------------------------------------------
  reg [1:0] out_r, out_g, out_b;
  reg       out_hs, out_vs;
  always @(posedge clk) begin
    out_hs <= r1_hs;
    out_vs <= r1_vs;
    {out_r, out_g, out_b} <= color;
  end

  assign uo_out = {out_hs, out_b[0], out_g[0], out_r[0], out_vs, out_b[1], out_g[1], out_r[1]};

endmodule