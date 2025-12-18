LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY minigolf_level5 IS
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
END minigolf_level5;

ARCHITECTURE Behavioral OF minigolf_level5 IS
  CONSTANT H_RES : INTEGER := 800;
  CONSTANT V_RES : INTEGER := 600;

  CONSTANT BOX_LEFT   : INTEGER := 60;
  CONSTANT BOX_RIGHT  : INTEGER := 740;
  CONSTANT BOX_TOP    : INTEGER := 60;
  CONSTANT BOX_BOTTOM : INTEGER := 540;

  CONSTANT BALL_R_BASE : INTEGER := 6;
  CONSTANT HOLE_R      : INTEGER := 10;

  CONSTANT START_X : INTEGER := 120;
  CONSTANT START_Y : INTEGER := 300;

  CONSTANT HOLE_X  : INTEGER := 680;
  CONSTANT HOLE_Y  : INTEGER := 300;

  -- Big water in middle (NOW top-to-bottom)
  CONSTANT WATER_L : INTEGER := 260;
  CONSTANT WATER_R : INTEGER := 540;
  CONSTANT WATER_T : INTEGER := BOX_TOP + 5;
  CONSTANT WATER_B : INTEGER := BOX_BOTTOM - 5;

  -- Ramp tile (red)
  CONSTANT RAMP_L  : INTEGER := 235;
  CONSTANT RAMP_R  : INTEGER := 265;
  CONSTANT RAMP_T  : INTEGER := 275;
  CONSTANT RAMP_B  : INTEGER := 325;

  CONSTANT ARROW_SCALE : INTEGER := 4;
  CONSTANT ARROW_R     : INTEGER := 4;
  CONSTANT MAX_STEPS   : INTEGER := 140;

  SIGNAL ball_x : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL ball_y : INTEGER RANGE 0 TO V_RES-1 := START_Y;

  SIGNAL aim_vx : INTEGER RANGE -16 TO 16 := 4;
  SIGNAL aim_vy : INTEGER RANGE -16 TO 16 := 0;

  SIGNAL vel_x  : INTEGER RANGE -32 TO 32 := 0;
  SIGNAL vel_y  : INTEGER RANGE -32 TO 32 := 0;

  SIGNAL shot_start_x : INTEGER RANGE 0 TO H_RES-1 := START_X;
  SIGNAL shot_start_y : INTEGER RANGE 0 TO H_RES-1 := START_Y;

  SIGNAL shot_state : STD_LOGIC := '0';
  SIGNAL shot_timer : INTEGER RANGE 0 TO 255 := 0;

  -- airborne mechanic
  SIGNAL airborne     : STD_LOGIC := '0';
  SIGNAL air_timer    : INTEGER RANGE 0 TO 255 := 0;
  SIGNAL ball_r_draw  : INTEGER RANGE 0 TO 40 := BALL_R_BASE;

  SIGNAL BTNU_d, BTND_d, BTNL_d, BTNR_d, BTNC_d : STD_LOGIC := '0';

  SIGNAL ball_on  : STD_LOGIC := '0';
  SIGNAL wall_on  : STD_LOGIC := '0';
  SIGNAL water_on : STD_LOGIC := '0';
  SIGNAL hole_on  : STD_LOGIC := '0';
  SIGNAL arrow_on : STD_LOGIC := '0';
  SIGNAL ramp_on  : STD_LOGIC := '0';

  SIGNAL stroke_pulse_i : STD_LOGIC := '0';
  SIGNAL hole_pulse_i   : STD_LOGIC := '0';
  SIGNAL level_active_d : STD_LOGIC := '0';

  FUNCTION iabs(x : INTEGER) RETURN INTEGER IS
  BEGIN
    IF x < 0 THEN RETURN -x; ELSE RETURN x; END IF;
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
    hole_on  <= '0';
    ramp_on  <= '0';
    ball_on  <= '0';
    arrow_on <= '0';

    -- outer walls (yellow)
    IF ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_TOP) AND (py <= BOX_TOP+5)) OR
       ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_BOTTOM-5) AND (py <= BOX_BOTTOM)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_LEFT) AND (px <= BOX_LEFT+5)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_RIGHT-5) AND (px <= BOX_RIGHT)) THEN
      wall_on <= '1';
    END IF;

    -- water (blue) now forces ramp usage
    IF (px >= WATER_L) AND (px <= WATER_R) AND (py >= WATER_T) AND (py <= WATER_B) THEN
      water_on <= '1';
    END IF;

    -- ramp (red)
    IF (px >= RAMP_L) AND (px <= RAMP_R) AND (py >= RAMP_T) AND (py <= RAMP_B) THEN
      ramp_on <= '1';
    END IF;

    -- ball
    dx := ball_x - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := ball_y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= ball_r_draw*ball_r_draw THEN ball_on <= '1'; END IF;

    -- hole
    dx := HOLE_X - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := HOLE_Y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= HOLE_R*HOLE_R THEN hole_on <= '1'; END IF;

    -- arrow
    IF (shot_state='0') AND ((aim_vx/=0) OR (aim_vy/=0)) THEN
      arrow_x := ball_x + aim_vx * ARROW_SCALE;
      arrow_y := ball_y + aim_vy * ARROW_SCALE;
      adx := arrow_x - px; IF adx < 0 THEN adx := -adx; END IF;
      ady := arrow_y - py; IF ady < 0 THEN ady := -ady; END IF;
      ar2 := adx*adx + ady*ady;
      IF ar2 <= ARROW_R*ARROW_R THEN arrow_on <= '1'; END IF;
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Colors
  ------------------------------------------------------------------
  ColorLogic : PROCESS(ball_on, hole_on, ramp_on, water_on, wall_on, arrow_on)
  BEGIN
    IF ball_on='1' THEN
      red<='1'; green<='1'; blue<='1';
    ELSIF hole_on='1' THEN
      red<='0'; green<='0'; blue<='0';
    ELSIF ramp_on='1' THEN
      red<='1'; green<='0'; blue<='0';
    ELSIF water_on='1' THEN
      red<='0'; green<='0'; blue<='1';
    ELSIF wall_on='1' THEN
      red<='1'; green<='1'; blue<='0';
    ELSIF arrow_on='1' THEN
      red<='1'; green<='0'; blue<='1';
    ELSE
      red<='0'; green<='1'; blue<='0';
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Game logic
  ------------------------------------------------------------------
  game_proc : PROCESS(v_sync)
    VARIABLE u_rise, d_rise, l_rise, r_rise, c_rise : STD_LOGIC;
    VARIABLE nx, ny : INTEGER;
    VARIABLE dx, dy, r2 : INTEGER;
    VARIABLE speed_mag : INTEGER;
  BEGIN
    IF rising_edge(v_sync) THEN
      stroke_pulse_i <= '0';
      hole_pulse_i   <= '0';

      IF (level_active='1') AND (level_active_d='0') THEN
        ball_x <= START_X; ball_y <= START_Y;
        aim_vx <= 4; aim_vy <= 0;
        vel_x <= 0; vel_y <= 0;
        shot_state <= '0'; shot_timer <= 0;
        shot_start_x <= START_X; shot_start_y <= START_Y;
        airborne <= '0'; air_timer <= 0;
        ball_r_draw <= BALL_R_BASE;
      END IF;

      IF level_active='0' THEN
        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;
        level_active_d <= level_active;
      ELSE
        -- edges
        u_rise:='0'; d_rise:='0'; l_rise:='0'; r_rise:='0'; c_rise:='0';
        IF (BTNU='1') AND (BTNU_d='0') THEN u_rise:='1'; END IF;
        IF (BTND='1') AND (BTND_d='0') THEN d_rise:='1'; END IF;
        IF (BTNL='1') AND (BTNL_d='0') THEN l_rise:='1'; END IF;
        IF (BTNR='1') AND (BTNR_d='0') THEN r_rise:='1'; END IF;
        IF (BTNC='1') AND (BTNC_d='0') THEN c_rise:='1'; END IF;

        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;

        -- airborne size animation
        IF airborne='1' THEN
          IF air_timer > 0 THEN
            air_timer <= air_timer - 1;
            ball_r_draw <= BALL_R_BASE + (air_timer / 6);
          ELSE
            airborne <= '0';
            ball_r_draw <= BALL_R_BASE;
          END IF;
        ELSE
          ball_r_draw <= BALL_R_BASE;
        END IF;

        IF shot_state='0' THEN
          IF u_rise='1' THEN aim_vy <= aim_vy - 1; END IF;
          IF d_rise='1' THEN aim_vy <= aim_vy + 1; END IF;
          IF l_rise='1' THEN aim_vx <= aim_vx - 1; END IF;
          IF r_rise='1' THEN aim_vx <= aim_vx + 1; END IF;

          IF aim_vx > 8 THEN aim_vx <= 8; ELSIF aim_vx < -8 THEN aim_vx <= -8; END IF;
          IF aim_vy > 8 THEN aim_vy <= 8; ELSIF aim_vy < -8 THEN aim_vy <= -8; END IF;

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

          -- outer bounce always
          IF nx <= BOX_LEFT + BALL_R_BASE THEN nx := BOX_LEFT + BALL_R_BASE; vel_x <= -vel_x;
          ELSIF nx >= BOX_RIGHT - BALL_R_BASE THEN nx := BOX_RIGHT - BALL_R_BASE; vel_x <= -vel_x; END IF;

          IF ny <= BOX_TOP + BALL_R_BASE THEN ny := BOX_TOP + BALL_R_BASE; vel_y <= -vel_y;
          ELSIF ny >= BOX_BOTTOM - BALL_R_BASE THEN ny := BOX_BOTTOM - BALL_R_BASE; vel_y <= -vel_y; END IF;

          -- ramp trigger
          IF (airborne='0') AND
             (nx >= RAMP_L) AND (nx <= RAMP_R) AND (ny >= RAMP_T) AND (ny <= RAMP_B) THEN
            speed_mag := iabs(vel_x) + iabs(vel_y);
            air_timer <= 20 + speed_mag * 3;
            airborne <= '1';
          END IF;

          IF airborne='0' THEN
            -- water reset (now unavoidable without ramp)
            IF (nx >= WATER_L) AND (nx <= WATER_R) AND (ny >= WATER_T) AND (ny <= WATER_B) THEN
              ball_x <= shot_start_x;
              ball_y <= shot_start_y;
              shot_state <= '0';
            ELSE
              ball_x <= nx; ball_y <= ny;
            END IF;
          ELSE
            -- airborne ignores water
            ball_x <= nx; ball_y <= ny;
          END IF;

          -- hole always sinks
          dx := nx - HOLE_X; IF dx < 0 THEN dx := -dx; END IF;
          dy := ny - HOLE_Y; IF dy < 0 THEN dy := -dy; END IF;
          r2 := dx*dx + dy*dy;
          IF r2 <= HOLE_R*HOLE_R THEN
            hole_pulse_i <= '1';
            shot_state <= '0';
            ball_x <= START_X; ball_y <= START_Y;
            airborne <= '0'; air_timer <= 0; ball_r_draw <= BALL_R_BASE;
          ELSE
            shot_timer <= shot_timer + 1;
            IF shot_timer >= MAX_STEPS THEN shot_state <= '0'; END IF;
          END IF;
        END IF;

        level_active_d <= level_active;
      END IF;
    END IF;
  END PROCESS;

END Behavioral;
