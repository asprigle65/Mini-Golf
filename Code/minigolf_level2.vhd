LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY minigolf_level2 IS
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
END minigolf_level2;

ARCHITECTURE Behavioral OF minigolf_level2 IS
  CONSTANT H_RES      : INTEGER := 800;
  CONSTANT V_RES      : INTEGER := 600;

  CONSTANT BOX_LEFT   : INTEGER := 100;
  CONSTANT BOX_RIGHT  : INTEGER := 700;
  CONSTANT BOX_TOP    : INTEGER := 80;
  CONSTANT BOX_BOTTOM : INTEGER := 520;

  CONSTANT BALL_R     : INTEGER := 6;
  CONSTANT HOLE_R     : INTEGER := 10;

  CONSTANT START_X    : INTEGER := 160; -- bottom-left area
  CONSTANT START_Y    : INTEGER := 460;

  CONSTANT HOLE_X     : INTEGER := 640; -- top-right pocket
  CONSTANT HOLE_Y     : INTEGER := 140;

  -- inner walls (orange)
  CONSTANT W1_X       : INTEGER := 400;
  CONSTANT W1_TOP     : INTEGER := 150;
  CONSTANT W1_BOTTOM  : INTEGER := 450; -- vertical bar in the middle

  CONSTANT W2_Y       : INTEGER := 300;
  CONSTANT W2_LEFT    : INTEGER := 250;
  CONSTANT W2_RIGHT   : INTEGER := 650; -- horizontal bar

  -- small gap in horizontal wall near right side
  CONSTANT GAP_LEFT   : INTEGER := 560;
  CONSTANT GAP_RIGHT  : INTEGER := 610;

  -- water pools
  CONSTANT WAT1_L     : INTEGER := 300;
  CONSTANT WAT1_R     : INTEGER := 360;
  CONSTANT WAT1_T     : INTEGER := 400;
  CONSTANT WAT1_B     : INTEGER := 460;

  CONSTANT WAT2_L     : INTEGER := 480;
  CONSTANT WAT2_R     : INTEGER := 540;
  CONSTANT WAT2_T     : INTEGER := 180;
  CONSTANT WAT2_B     : INTEGER := 240;

  CONSTANT ARROW_SCALE : INTEGER := 4;
  CONSTANT ARROW_R     : INTEGER := 4;
  CONSTANT MAX_STEPS   : INTEGER := 100;

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

  SIGNAL BTNU_d, BTND_d, BTNL_d, BTNR_d, BTNC_d : STD_LOGIC := '0';

  SIGNAL ball_on  : STD_LOGIC := '0';
  SIGNAL wall_on  : STD_LOGIC := '0';
  SIGNAL water_on : STD_LOGIC := '0';
  SIGNAL hole_on  : STD_LOGIC := '0';
  SIGNAL arrow_on : STD_LOGIC := '0';

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
    VARIABLE px, py : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;
    VARIABLE arrow_x, arrow_y : INTEGER;
    VARIABLE adx, ady, ar2    : INTEGER;
  BEGIN
    px := CONV_INTEGER(pixel_col);
    py := CONV_INTEGER(pixel_row);

    wall_on  <= '0';
    water_on <= '0';
    ball_on  <= '0';
    hole_on  <= '0';
    arrow_on <= '0';

    -- outer box
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

    -- inner vertical wall
    IF (px >= W1_X - 4) AND (px <= W1_X + 4) AND
       (py >= W1_TOP)   AND (py <= W1_BOTTOM) THEN
      wall_on <= '1';
    END IF;

    -- inner horizontal wall, with a gap near right side
    IF (py >= W2_Y - 4) AND (py <= W2_Y + 4) THEN
      IF ((px >= W2_LEFT) AND (px <= GAP_LEFT)) OR
         ((px >= GAP_RIGHT) AND (px <= W2_RIGHT)) THEN
        wall_on <= '1';
      END IF;
    END IF;

    -- water pool 1
    IF (px >= WAT1_L) AND (px <= WAT1_R) AND
       (py >= WAT1_T) AND (py <= WAT1_B) THEN
      water_on <= '1';
    END IF;

    -- water pool 2
    IF (px >= WAT2_L) AND (px <= WAT2_R) AND
       (py >= WAT2_T) AND (py <= WAT2_B) THEN
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
      red   <= '1'; green <= '1'; blue  <= '1';
    ELSIF hole_on = '1' THEN
      red   <= '0'; green <= '0'; blue  <= '0';
    ELSIF water_on = '1' THEN
      red   <= '0'; green <= '0'; blue  <= '1';
    ELSIF wall_on = '1' THEN
      red   <= '1'; green <= '1'; blue  <= '0';
    ELSIF arrow_on = '1' THEN
      red   <= '1'; green <= '0'; blue  <= '1';
    ELSE
      red   <= '0'; green <= '1'; blue  <= '0';
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Game logic
  ------------------------------------------------------------------
  game_proc : PROCESS(v_sync)
    VARIABLE u_rise, d_rise, l_rise, r_rise, c_rise : STD_LOGIC;
    VARIABLE nx, ny : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;
    VARIABLE in_wall : BOOLEAN;
  BEGIN
    IF rising_edge(v_sync) THEN
      stroke_pulse_i <= '0';
      hole_pulse_i   <= '0';

      -- handle level activation
      IF (level_active = '1') AND (level_active_d = '0') THEN
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

      IF level_active = '0' THEN
        BTNU_d        <= BTNU;
        BTND_d        <= BTND;
        BTNL_d        <= BTNL;
        BTNR_d        <= BTNR;
        BTNC_d        <= BTNC;
        level_active_d <= level_active;
      ELSE
        -- edge detection
        u_rise := '0'; d_rise := '0';
        l_rise := '0'; r_rise := '0';
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

          -- bounce off outer box
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

          -- bounce off vertical inner wall
          in_wall := FALSE;
          IF (nx >= W1_X - 4 - BALL_R) AND (nx <= W1_X + 4 + BALL_R) AND
             (ny >= W1_TOP) AND (ny <= W1_BOTTOM) THEN
            in_wall := TRUE;
            IF ball_x < W1_X THEN
              nx    := W1_X - 4 - BALL_R;
            ELSE
              nx    := W1_X + 4 + BALL_R;
            END IF;
            vel_x <= -vel_x;
          END IF;

          -- bounce off horizontal inner wall (respecting gap)
          IF (ny >= W2_Y - 4 - BALL_R) AND (ny <= W2_Y + 4 + BALL_R) THEN
            IF ((nx >= W2_LEFT) AND (nx <= GAP_LEFT)) OR
               ((nx >= GAP_RIGHT) AND (nx <= W2_RIGHT)) THEN
              in_wall := TRUE;
              IF ball_y < W2_Y THEN
                ny    := W2_Y - 4 - BALL_R;
              ELSE
                ny    := W2_Y + 4 + BALL_R;
              END IF;
              vel_y <= -vel_y;
            END IF;
          END IF;

          -- water pools reset
          IF ((nx >= WAT1_L) AND (nx <= WAT1_R) AND
              (ny >= WAT1_T) AND (ny <= WAT1_B)) OR
             ((nx >= WAT2_L) AND (nx <= WAT2_R) AND
              (ny >= WAT2_T) AND (ny <= WAT2_B)) THEN
            ball_x     <= shot_start_x;
            ball_y     <= shot_start_y;
            shot_state <= '0';
          ELSE
            -- hole
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
        END IF;  -- shot_state
      END IF;    -- level_active
    END IF;      -- rising_edge
  END PROCESS;

END Behavioral;
