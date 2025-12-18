minigolf_level1.vhd:
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY minigolf_level1 IS
  PORT(
    v_sync       : IN  STD_LOGIC;
    pixel_row    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
    pixel_col    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
    BTNU         : IN  STD_LOGIC;
    BTND         : IN  STD_LOGIC;
    BTNL         : IN  STD_LOGIC;
    BTNR         : IN  STD_LOGIC;
    BTNC         : IN  STD_LOGIC;
    level_active : IN  STD_LOGIC;  -- '1' when this level is currently shown
    red          : OUT STD_LOGIC;
    green        : OUT STD_LOGIC;
    blue         : OUT STD_LOGIC;
    stroke_pulse : OUT STD_LOGIC;  -- 1 v_sync tick per shot
    hole_pulse   : OUT STD_LOGIC   -- 1 v_sync tick when ball sinks
  );
END minigolf_level1;

ARCHITECTURE Behavioral OF minigolf_level1 IS
  ------------------------------------------------------------------
  -- Course layout constants
  ------------------------------------------------------------------
  CONSTANT H_RES      : INTEGER := 800;
  CONSTANT V_RES      : INTEGER := 600;

  CONSTANT BOX_LEFT   : INTEGER := 100;
  CONSTANT BOX_RIGHT  : INTEGER := 700;
  CONSTANT BOX_TOP    : INTEGER := 100;
  CONSTANT BOX_BOTTOM : INTEGER := 500;

  CONSTANT BALL_R     : INTEGER := 6;
  CONSTANT HOLE_R     : INTEGER := 10;

  CONSTANT START_X    : INTEGER := 150;
  CONSTANT START_Y    : INTEGER := 300;

  CONSTANT HOLE_X     : INTEGER := 650;
  CONSTANT HOLE_Y     : INTEGER := 300;

  -- valley attraction zone
  CONSTANT VALLEY_R   : INTEGER := 80;

  -- water in the middle
  CONSTANT WATER_LEFT   : INTEGER := 360;
  CONSTANT WATER_RIGHT  : INTEGER := 440;
  CONSTANT WATER_TOP    : INTEGER := 260;
  CONSTANT WATER_BOTTOM : INTEGER := 340;

  -- aiming "dot"
  CONSTANT ARROW_SCALE  : INTEGER := 4;
  CONSTANT ARROW_R      : INTEGER := 4;

  CONSTANT MAX_STEPS    : INTEGER := 80;

  ------------------------------------------------------------------
  -- Positions & state
  ------------------------------------------------------------------
  SIGNAL ball_x        : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL ball_y        : INTEGER RANGE 0 TO V_RES-1 := START_Y;

  SIGNAL aim_vx        : INTEGER RANGE -16 TO 16 := 4;
  SIGNAL aim_vy        : INTEGER RANGE -16 TO 16 := 0;

  SIGNAL vel_x         : INTEGER RANGE -32 TO 32 := 0;
  SIGNAL vel_y         : INTEGER RANGE -32 TO 32 := 0;

  SIGNAL shot_start_x  : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL shot_start_y  : INTEGER RANGE 0 TO V_RES-1 := START_Y;

  SIGNAL shot_state    : STD_LOGIC := '0';
  SIGNAL shot_timer    : INTEGER RANGE 0 TO 255 := 0;

  -- button edge detection
  SIGNAL BTNU_d, BTND_d, BTNL_d, BTNR_d, BTNC_d : STD_LOGIC := '0';

  -- drawing flags
  SIGNAL ball_on  : STD_LOGIC := '0';
  SIGNAL wall_on  : STD_LOGIC := '0';
  SIGNAL water_on : STD_LOGIC := '0';
  SIGNAL hole_on  : STD_LOGIC := '0';
  SIGNAL arrow_on : STD_LOGIC := '0';

  -- internal pulses
  SIGNAL stroke_pulse_i : STD_LOGIC := '0';
  SIGNAL hole_pulse_i   : STD_LOGIC := '0';

  SIGNAL level_active_d : STD_LOGIC := '0';
BEGIN
  stroke_pulse <= stroke_pulse_i;
  hole_pulse   <= hole_pulse_i;

  ------------------------------------------------------------------
  -- Drawing
  ------------------------------------------------------------------
  draw_proc : PROCESS(pixel_row, pixel_col, ball_x, ball_y,
                      shot_state, aim_vx, aim_vy)
    VARIABLE px, py     : INTEGER;
    VARIABLE dx, dy     : INTEGER;
    VARIABLE r2         : INTEGER;
    VARIABLE arrow_x    : INTEGER;
    VARIABLE arrow_y    : INTEGER;
    VARIABLE adx, ady   : INTEGER;
    VARIABLE ar2        : INTEGER;
  BEGIN
    px := CONV_INTEGER(pixel_col);
    py := CONV_INTEGER(pixel_row);

    wall_on  <= '0';
    water_on <= '0';
    ball_on  <= '0';
    hole_on  <= '0';
    arrow_on <= '0';

    -- box walls
    IF ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND
        (py >= BOX_TOP) AND (py <= BOX_TOP + 5)) OR
       ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND
        (py >= BOX_BOTTOM - 5) AND (py <= BOX_BOTTOM)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND
        (px >= BOX_LEFT) AND (px <= BOX_LEFT + 5)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND
        (px >= BOX_RIGHT - 5) AND (px <= BOX_RIGHT)) THEN
      wall_on <= '1';
    END IF;

    -- water
    IF (px >= WATER_LEFT) AND (px <= WATER_RIGHT) AND
       (py >= WATER_TOP)  AND (py <= WATER_BOTTOM) THEN
      water_on <= '1';
    END IF;

    -- ball
    dx := ball_x - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := ball_y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= BALL_R*BALL_R THEN
      ball_on <= '1';
    END IF;

    -- hole
    dx := HOLE_X - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := HOLE_Y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= HOLE_R*HOLE_R THEN
      hole_on <= '1';
    END IF;

    -- arrow dot
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
  -- Color priority
  ------------------------------------------------------------------
  ColorLogic : PROCESS(ball_on, hole_on, water_on, wall_on, arrow_on)
  BEGIN
    IF ball_on = '1' THEN
      red   <= '1'; green <= '1'; blue  <= '1'; -- white
    ELSIF hole_on = '1' THEN
      red   <= '0'; green <= '0'; blue  <= '0'; -- black
    ELSIF water_on = '1' THEN
      red   <= '0'; green <= '0'; blue  <= '1'; -- blue
    ELSIF wall_on = '1' THEN
      red   <= '1'; green <= '1'; blue  <= '0'; -- yellow
    ELSIF arrow_on = '1' THEN
      red   <= '1'; green <= '0'; blue  <= '1'; -- magenta
    ELSE
      red   <= '0'; green <= '1'; blue  <= '0'; -- green background
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Game logic: v_sync domain
  ------------------------------------------------------------------
  game_proc : PROCESS(v_sync)
    VARIABLE u_rise, d_rise, l_rise, r_rise, c_rise : STD_LOGIC;
    VARIABLE nx, ny : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;
  BEGIN
    IF rising_edge(v_sync) THEN
      stroke_pulse_i <= '0';
      hole_pulse_i   <= '0';

      -- detect level activation edge
      IF (level_active = '1') AND (level_active_d = '0') THEN
        -- re-init when entering this level
        ball_x       <= START_X;
        ball_y       <= START_Y;
        aim_vx       <= 4;
        aim_vy       <= 0;
        vel_x        <= 0;
        vel_y        <= 0;
        shot_state   <= '0';
        shot_timer   <= 0;
        shot_start_x <= START_X;
        shot_start_y <= START_Y;
      END IF;

      -- If level is inactive, just update delayed buttons & state, skip logic
      IF level_active = '0' THEN
        BTNU_d        <= BTNU;
        BTND_d        <= BTND;
        BTNL_d        <= BTNL;
        BTNR_d        <= BTNR;
        BTNC_d        <= BTNC;
        level_active_d <= level_active;
      ELSE
        ----------------------------------------------------------------
        -- Level is active: edge detection + game physics
        ----------------------------------------------------------------
        u_rise := '0';
        d_rise := '0';
        l_rise := '0';
        r_rise := '0';
        c_rise := '0';

        IF (BTNU = '1') AND (BTNU_d = '0') THEN u_rise := '1'; END IF;
        IF (BTND = '1') AND (BTND_d = '0') THEN d_rise := '1'; END IF;
        IF (BTNL = '1') AND (BTNL_d = '0') THEN l_rise := '1'; END IF;
        IF (BTNR = '1') AND (BTNR_d = '0') THEN r_rise := '1'; END IF;
        IF (BTNC = '1') AND (BTNC_d = '0') THEN c_rise := '1'; END IF;

        BTNU_d        <= BTNU;
        BTND_d        <= BTND;
        BTNL_d        <= BTNL;
        BTNR_d        <= BTNR;
        BTNC_d        <= BTNC;
        level_active_d <= level_active;

        IF shot_state = '0' THEN
          -- AIMING
          IF u_rise = '1' THEN aim_vy <= aim_vy - 1; END IF;
          IF d_rise = '1' THEN aim_vy <= aim_vy + 1; END IF;
          IF l_rise = '1' THEN aim_vx <= aim_vx - 1; END IF;
          IF r_rise = '1' THEN aim_vx <= aim_vx + 1; END IF;

          -- saturate
          IF aim_vx > 8 THEN
            aim_vx <= 8;
          ELSIF aim_vx < -8 THEN
            aim_vx <= -8;
          END IF;
          IF aim_vy > 8 THEN
            aim_vy <= 8;
          ELSIF aim_vy < -8 THEN
            aim_vy <= -8;
          END IF;

          -- shoot
          IF c_rise = '1' THEN
            IF (aim_vx /= 0) OR (aim_vy /= 0) THEN
              vel_x        <= aim_vx;
              vel_y        <= aim_vy;
              shot_start_x <= ball_x;
              shot_start_y <= ball_y;
              shot_state   <= '1';
              shot_timer   <= 0;
              stroke_pulse_i <= '1';
            END IF;
          END IF;

        ELSE
          -- BALL MOVING
          nx := ball_x + vel_x;
          ny := ball_y + vel_y;

          -- bounce off box walls
          IF nx <= BOX_LEFT + BALL_R THEN
            nx    := BOX_LEFT + BALL_R;
            vel_x <= -vel_x;
          ELSIF nx >= BOX_RIGHT - BALL_R THEN
            nx    := BOX_RIGHT - BALL_R;
            vel_x <= -vel_x;
          END IF;

          IF ny <= BOX_TOP + BALL_R THEN
            ny    := BOX_TOP + BALL_R;
            vel_y <= -vel_y;
          ELSIF ny >= BOX_BOTTOM - BALL_R THEN
            ny    := BOX_BOTTOM - BALL_R;
            vel_y <= -vel_y;
          END IF;

          -- water reset
          IF (nx >= WATER_LEFT) AND (nx <= WATER_RIGHT) AND
             (ny >= WATER_TOP)  AND (ny <= WATER_BOTTOM) THEN
            ball_x     <= shot_start_x;
            ball_y     <= shot_start_y;
            shot_state <= '0';
          ELSE
            ----------------------------------------------------------------
            -- VALLEY: if within radius, gently pull velocity toward hole
            ----------------------------------------------------------------
            dx := nx - HOLE_X; IF dx < 0 THEN dx := -dx; END IF;
            dy := ny - HOLE_Y; IF dy < 0 THEN dy := -dy; END IF;

            IF (dx*dx + dy*dy) <= (VALLEY_R*VALLEY_R) THEN
              IF nx < HOLE_X THEN
                IF vel_x < 8 THEN vel_x <= vel_x + 1; END IF;
              ELSIF nx > HOLE_X THEN
                IF vel_x > -8 THEN vel_x <= vel_x - 1; END IF;
              END IF;

              IF ny < HOLE_Y THEN
                IF vel_y < 8 THEN vel_y <= vel_y + 1; END IF;
              ELSIF ny > HOLE_Y THEN
                IF vel_y > -8 THEN vel_y <= vel_y - 1; END IF;
              END IF;
            END IF;

            -- hole detection
            dx := nx - HOLE_X; IF dx < 0 THEN dx := -dx; END IF;
            dy := ny - HOLE_Y; IF dy < 0 THEN dy := -dy; END IF;
            r2 := dx*dx + dy*dy;

            IF r2 <= HOLE_R*HOLE_R THEN
              hole_pulse_i <= '1';
              shot_state   <= '0';
              ball_x       <= START_X;
              ball_y       <= START_Y;
            ELSE
              ball_x <= nx;
              ball_y <= ny;
              shot_timer <= shot_timer + 1;
              IF shot_timer >= MAX_STEPS THEN
                shot_state <= '0';
              END IF;
            END IF;
          END IF;
        END IF;
      END IF; -- level_active
    END IF; -- rising_edge
  END PROCESS;

END Behavioral;
