LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY minigolf_level4 IS
  PORT(
    v_sync       : IN  STD_LOGIC;
    pixel_row    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
    pixel_col    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
    BTNU         : IN  STD_LOGIC;
    BTND         : IN  STD_LOGIC;
    BTNL         : IN  STD_LOGIC;
    BTNR         : IN  STD_LOGIC;
    BTNC         : IN  STD_LOGIC;
    level_active : IN  STD_LOGIC;
    red          : OUT STD_LOGIC;
    green        : OUT STD_LOGIC;
    blue         : OUT STD_LOGIC;
    stroke_pulse : OUT STD_LOGIC;
    hole_pulse   : OUT STD_LOGIC
  );
END minigolf_level4;

ARCHITECTURE Behavioral OF minigolf_level4 IS
  CONSTANT H_RES : INTEGER := 800;
  CONSTANT V_RES : INTEGER := 600;

  -- play box
  CONSTANT BOX_LEFT   : INTEGER := 60;
  CONSTANT BOX_RIGHT  : INTEGER := 740;
  CONSTANT BOX_TOP    : INTEGER := 60;
  CONSTANT BOX_BOTTOM : INTEGER := 540;
  CONSTANT WALL_THK   : INTEGER := 6;

  -- Ball illusion
  CONSTANT BALL_R_BASE   : INTEGER := 6;
  CONSTANT BALL_R_SLOPE  : INTEGER := 5;
  CONSTANT BALL_R_TOP    : INTEGER := 4;
  CONSTANT BALL_R_WATER  : INTEGER := 7;

  CONSTANT HOLE_R : INTEGER := 10;

  -- start
  CONSTANT START_X : INTEGER := 140;
  CONSTANT START_Y : INTEGER := 300;

  -- Hill (slope) big rectangle (yellow)
  CONSTANT HILL_L : INTEGER := 270;
  CONSTANT HILL_R : INTEGER := 640;
  CONSTANT HILL_T : INTEGER := 120;
  CONSTANT HILL_B : INTEGER := 500;

  -- Top (white) smaller rectangle on hill
  CONSTANT TOP_L : INTEGER := 360;
  CONSTANT TOP_R : INTEGER := 560;
  CONSTANT TOP_T : INTEGER := 220;
  CONSTANT TOP_B : INTEGER := 420;

  -- Hole on top (slightly right of center)
  CONSTANT HOLE_X : INTEGER := (TOP_L + TOP_R)/2 + 30;
  CONSTANT HOLE_Y : INTEGER := (TOP_T + TOP_B)/2;

  -- Water behind hill (punish overshoot)
  CONSTANT WATER_L : INTEGER := 660;
  CONSTANT WATER_R : INTEGER := 720;
  CONSTANT WATER_T : INTEGER := 120;
  CONSTANT WATER_B : INTEGER := 500;

  -- aiming dot
  CONSTANT ARROW_SCALE : INTEGER := 4;
  CONSTANT ARROW_R     : INTEGER := 4;

  CONSTANT MAX_STEPS   : INTEGER := 180;

  -- physics tuning
  CONSTANT VEL_CLAMP   : INTEGER := 18;
  CONSTANT FRICTION    : INTEGER := 1;

  -- hill effect:
  --   FIX: remove strong drag, add a stronger "uphill assist"
  CONSTANT SLOPE_DRAG  : INTEGER := 0;  -- was 1 (this was killing motion)
  CONSTANT SLOPE_NUDGE : INTEGER := 2;  -- was 1 (too weak to climb)

  SIGNAL ball_x : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL ball_y : INTEGER RANGE 0 TO V_RES-1 := START_Y;

  SIGNAL aim_vx : INTEGER RANGE -16 TO 16 := 6;
  SIGNAL aim_vy : INTEGER RANGE -16 TO 16 := 0;

  SIGNAL vel_x  : INTEGER RANGE -32 TO 32 := 0;
  SIGNAL vel_y  : INTEGER RANGE -32 TO 32 := 0;

  SIGNAL shot_start_x : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL shot_start_y : INTEGER RANGE 0 TO H_RES-1 := START_Y;

  SIGNAL shot_state : STD_LOGIC := '0';
  SIGNAL shot_timer : INTEGER RANGE 0 TO 255 := 0;

  SIGNAL BTNU_d, BTND_d, BTNL_d, BTNR_d, BTNC_d : STD_LOGIC := '0';

  SIGNAL ball_on  : STD_LOGIC := '0';
  SIGNAL wall_on  : STD_LOGIC := '0';
  SIGNAL water_on : STD_LOGIC := '0';
  SIGNAL hill_on  : STD_LOGIC := '0';
  SIGNAL top_on   : STD_LOGIC := '0';
  SIGNAL hole_on  : STD_LOGIC := '0';
  SIGNAL arrow_on : STD_LOGIC := '0';

  SIGNAL stroke_pulse_i : STD_LOGIC := '0';
  SIGNAL hole_pulse_i   : STD_LOGIC := '0';

  SIGNAL level_active_d : STD_LOGIC := '0';
  SIGNAL ball_r_draw    : INTEGER RANGE 0 TO 40 := BALL_R_BASE;

  FUNCTION iabs(x : INTEGER) RETURN INTEGER IS
  BEGIN
    IF x < 0 THEN RETURN -x; ELSE RETURN x; END IF;
  END;

  FUNCTION clampi(x, lo, hi : INTEGER) RETURN INTEGER IS
  BEGIN
    IF x < lo THEN RETURN lo;
    ELSIF x > hi THEN RETURN hi;
    ELSE RETURN x;
    END IF;
  END;

BEGIN
  stroke_pulse <= stroke_pulse_i;
  hole_pulse   <= hole_pulse_i;

  ------------------------------------------------------------------
  -- Drawing
  ------------------------------------------------------------------
  draw_proc : PROCESS(pixel_row, pixel_col, ball_x, ball_y, ball_r_draw, shot_state, aim_vx, aim_vy)
    VARIABLE px, py : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;
    VARIABLE arrow_x, arrow_y : INTEGER;
    VARIABLE adx, ady, ar2 : INTEGER;
  BEGIN
    px := CONV_INTEGER(pixel_col);
    py := CONV_INTEGER(pixel_row);

    wall_on  <= '0';
    water_on <= '0';
    hill_on  <= '0';
    top_on   <= '0';
    ball_on  <= '0';
    hole_on  <= '0';
    arrow_on <= '0';

    -- walls
    IF ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_TOP) AND (py <= BOX_TOP + WALL_THK)) OR
       ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_BOTTOM - WALL_THK) AND (py <= BOX_BOTTOM)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_LEFT) AND (px <= BOX_LEFT + WALL_THK)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_RIGHT - WALL_THK) AND (px <= BOX_RIGHT)) THEN
      wall_on <= '1';
    END IF;

    -- water behind hill
    IF (px >= WATER_L) AND (px <= WATER_R) AND (py >= WATER_T) AND (py <= WATER_B) THEN
      water_on <= '1';
    END IF;

    -- hill slope + top
    IF (px >= HILL_L) AND (px <= HILL_R) AND (py >= HILL_T) AND (py <= HILL_B) THEN
      hill_on <= '1';
    END IF;

    IF (px >= TOP_L) AND (px <= TOP_R) AND (py >= TOP_T) AND (py <= TOP_B) THEN
      top_on <= '1';
    END IF;

    -- ball
    dx := ball_x - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := ball_y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= ball_r_draw*ball_r_draw THEN
      ball_on <= '1';
    END IF;

    -- hole
    dx := HOLE_X - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := HOLE_Y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= HOLE_R*HOLE_R THEN
      hole_on <= '1';
    END IF;

    -- arrow (must be visible on top/slope)
    IF (shot_state = '0') AND ((aim_vx /= 0) OR (aim_vy /= 0)) THEN
      arrow_x := ball_x + aim_vx * ARROW_SCALE;
      arrow_y := ball_y + aim_vy * ARROW_SCALE;

      adx := arrow_x - px; IF adx < 0 THEN adx := -adx; END IF;
      ady := arrow_y - py; IF ady < 0 THEN ady := -ady; END IF;
      ar2 := adx*adx + ady*ady;
      IF ar2 <= ARROW_R*ARROW_R THEN
        arrow_on <= '1';
      END IF;
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Colors (priority)
  ------------------------------------------------------------------
  ColorLogic : PROCESS(ball_on, hole_on, arrow_on, water_on, top_on, hill_on, wall_on)
  BEGIN
    IF ball_on='1' THEN
      red<='1'; green<='1'; blue<='1';
    ELSIF hole_on='1' THEN
      red<='0'; green<='0'; blue<='0';
    ELSIF arrow_on='1' THEN
      red<='1'; green<='0'; blue<='1';
    ELSIF water_on='1' THEN
      red<='0'; green<='0'; blue<='1';
    ELSIF top_on='1' THEN
      red<='1'; green<='1'; blue<='1'; -- white top
    ELSIF hill_on='1' THEN
      red<='1'; green<='1'; blue<='0'; -- yellow slope
    ELSIF wall_on='1' THEN
      red<='1'; green<='1'; blue<='0';
    ELSE
      red<='0'; green<='1'; blue<='0';
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Game logic (v_sync)
  ------------------------------------------------------------------
  game_proc : PROCESS(v_sync)
    VARIABLE u_rise, d_rise, l_rise, r_rise, c_rise : STD_LOGIC;
    VARIABLE nx, ny : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;

    VARIABLE vx_cur, vy_cur : INTEGER;

    VARIABLE on_hill : BOOLEAN;
    VARIABLE on_top  : BOOLEAN;
    VARIABLE in_water: BOOLEAN;

    VARIABLE cx, cy : INTEGER;

    VARIABLE hill_fric : INTEGER;
  BEGIN
    IF rising_edge(v_sync) THEN
      stroke_pulse_i <= '0';
      hole_pulse_i   <= '0';

      IF (level_active='1') AND (level_active_d='0') THEN
        ball_x <= START_X; ball_y <= START_Y;
        aim_vx <= 6; aim_vy <= 0;
        vel_x <= 0; vel_y <= 0;
        shot_state <= '0'; shot_timer <= 0;
        shot_start_x <= START_X; shot_start_y <= START_Y;
        ball_r_draw <= BALL_R_BASE;
      END IF;

      IF level_active='0' THEN
        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;
        level_active_d <= level_active;
      ELSE
        u_rise:='0'; d_rise:='0'; l_rise:='0'; r_rise:='0'; c_rise:='0';
        IF (BTNU='1') AND (BTNU_d='0') THEN u_rise:='1'; END IF;
        IF (BTND='1') AND (BTND_d='0') THEN d_rise:='1'; END IF;
        IF (BTNL='1') AND (BTNL_d='0') THEN l_rise:='1'; END IF;
        IF (BTNR='1') AND (BTNR_d='0') THEN r_rise:='1'; END IF;
        IF (BTNC='1') AND (BTNC_d='0') THEN c_rise:='1'; END IF;

        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;

        -- radius illusion based on current position (even while aiming)
        on_hill := (ball_x>=HILL_L) AND (ball_x<=HILL_R) AND (ball_y>=HILL_T) AND (ball_y<=HILL_B);
        on_top  := (ball_x>=TOP_L)  AND (ball_x<=TOP_R)  AND (ball_y>=TOP_T)  AND (ball_y<=TOP_B);
        in_water:= (ball_x>=WATER_L) AND (ball_x<=WATER_R) AND (ball_y>=WATER_T) AND (ball_y<=WATER_B);

        IF in_water THEN
          ball_r_draw <= BALL_R_WATER;
        ELSIF on_top THEN
          ball_r_draw <= BALL_R_TOP;
        ELSIF on_hill THEN
          ball_r_draw <= BALL_R_SLOPE;
        ELSE
          ball_r_draw <= BALL_R_BASE;
        END IF;

        IF shot_state='0' THEN
          IF u_rise='1' THEN aim_vy <= aim_vy - 1; END IF;
          IF d_rise='1' THEN aim_vy <= aim_vy + 1; END IF;
          IF l_rise='1' THEN aim_vx <= aim_vx - 1; END IF;
          IF r_rise='1' THEN aim_vx <= aim_vx + 1; END IF;

          -- keep aim bounded (this level uses 16, match your other files if desired)
          IF aim_vx > 16 THEN aim_vx <= 16; ELSIF aim_vx < -16 THEN aim_vx <= -16; END IF;
          IF aim_vy > 16 THEN aim_vy <= 16; ELSIF aim_vy < -16 THEN aim_vy <= -16; END IF;

          IF c_rise='1' THEN
            IF (aim_vx/=0) OR (aim_vy/=0) THEN
              vel_x <= aim_vx; vel_y <= aim_vy;
              shot_start_x <= ball_x; shot_start_y <= ball_y;
              shot_state <= '1'; shot_timer <= 0;
              stroke_pulse_i <= '1';
            END IF;
          END IF;

        ELSE
          nx := ball_x + vel_x;
          ny := ball_y + vel_y;

          vx_cur := vel_x;
          vy_cur := vel_y;

          -- bounce off outer walls
          IF nx <= BOX_LEFT + BALL_R_BASE + WALL_THK THEN
            nx := BOX_LEFT + BALL_R_BASE + WALL_THK;
            vx_cur := -vx_cur;
          ELSIF nx >= BOX_RIGHT - BALL_R_BASE - WALL_THK THEN
            nx := BOX_RIGHT - BALL_R_BASE - WALL_THK;
            vx_cur := -vx_cur;
          END IF;

          IF ny <= BOX_TOP + BALL_R_BASE + WALL_THK THEN
            ny := BOX_TOP + BALL_R_BASE + WALL_THK;
            vy_cur := -vy_cur;
          ELSIF ny >= BOX_BOTTOM - BALL_R_BASE - WALL_THK THEN
            ny := BOX_BOTTOM - BALL_R_BASE - WALL_THK;
            vy_cur := -vy_cur;
          END IF;

          -- water punish: reset to shot start, stop
          in_water := (nx>=WATER_L) AND (nx<=WATER_R) AND (ny>=WATER_T) AND (ny<=WATER_B);
          IF in_water THEN
            ball_x <= shot_start_x;
            ball_y <= shot_start_y;
            vel_x <= 0; vel_y <= 0;
            shot_state <= '0';
          ELSE
            -- hill effects
            on_hill := (nx>=HILL_L) AND (nx<=HILL_R) AND (ny>=HILL_T) AND (ny<=HILL_B);
            on_top  := (nx>=TOP_L)  AND (nx<=TOP_R)  AND (ny>=TOP_T)  AND (ny<=TOP_B);

            -- FIX: less friction on slope so it can climb
            hill_fric := FRICTION;
            IF on_hill AND (NOT on_top) THEN
              hill_fric := 0; -- slope should not “brick wall” the shot
            END IF;

            -- friction
            IF vx_cur > 0 THEN vx_cur := vx_cur - hill_fric; ELSIF vx_cur < 0 THEN vx_cur := vx_cur + hill_fric; END IF;
            IF vy_cur > 0 THEN vy_cur := vy_cur - hill_fric; ELSIF vy_cur < 0 THEN vy_cur := vy_cur + hill_fric; END IF;

            -- on slope (but not top): mild assist toward top center (climb helper)
            IF on_hill AND (NOT on_top) THEN
              -- optional tiny drag (currently 0)
              IF vx_cur > 0 THEN vx_cur := vx_cur - SLOPE_DRAG; ELSIF vx_cur < 0 THEN vx_cur := vx_cur + SLOPE_DRAG; END IF;
              IF vy_cur > 0 THEN vy_cur := vy_cur - SLOPE_DRAG; ELSIF vy_cur < 0 THEN vy_cur := vy_cur + SLOPE_DRAG; END IF;

              cx := (TOP_L + TOP_R)/2;
              cy := (TOP_T + TOP_B)/2;

              -- nudge toward top center
              IF nx < cx THEN vx_cur := vx_cur + SLOPE_NUDGE; ELSIF nx > cx THEN vx_cur := vx_cur - SLOPE_NUDGE; END IF;
              IF ny < cy THEN vy_cur := vy_cur + SLOPE_NUDGE; ELSIF ny > cy THEN vy_cur := vy_cur - SLOPE_NUDGE; END IF;
            END IF;

            vx_cur := clampi(vx_cur, -VEL_CLAMP, VEL_CLAMP);
            vy_cur := clampi(vy_cur, -VEL_CLAMP, VEL_CLAMP);

            -- hole test
            dx := nx - HOLE_X; IF dx < 0 THEN dx := -dx; END IF;
            dy := ny - HOLE_Y; IF dy < 0 THEN dy := -dy; END IF;
            r2 := dx*dx + dy*dy;

            IF r2 <= HOLE_R*HOLE_R THEN
              hole_pulse_i <= '1';
              shot_state <= '0';
              ball_x <= START_X; ball_y <= START_Y;
              vel_x <= 0; vel_y <= 0;
              ball_r_draw <= BALL_R_BASE;
            ELSE
              ball_x <= nx; ball_y <= ny;
              vel_x <= vx_cur; vel_y <= vy_cur;

              shot_timer <= shot_timer + 1;
              IF shot_timer >= MAX_STEPS THEN shot_state <= '0'; END IF;
              IF (vx_cur = 0) AND (vy_cur = 0) THEN shot_state <= '0'; END IF;
            END IF;
          END IF;
        END IF;

        level_active_d <= level_active;
      END IF;
    END IF;
  END PROCESS;

END Behavioral;

