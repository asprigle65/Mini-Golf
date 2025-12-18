LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY minigolf_level3 IS
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
END minigolf_level3;

ARCHITECTURE Behavioral OF minigolf_level3 IS
  CONSTANT H_RES : INTEGER := 800;
  CONSTANT V_RES : INTEGER := 600;

  -- outer play box
  CONSTANT BOX_LEFT   : INTEGER := 80;
  CONSTANT BOX_RIGHT  : INTEGER := 720;
  CONSTANT BOX_TOP    : INTEGER := 80;
  CONSTANT BOX_BOTTOM : INTEGER := 520;

  CONSTANT WALL_THK   : INTEGER := 6;

  CONSTANT BALL_R_BASE : INTEGER := 6;
  CONSTANT HOLE_R      : INTEGER := 10;

  CONSTANT START_X : INTEGER := 120;
  CONSTANT START_Y : INTEGER := 470;

  -- Aiming dot
  CONSTANT ARROW_SCALE : INTEGER := 4;
  CONSTANT ARROW_R     : INTEGER := 4;

  CONSTANT MAX_STEPS   : INTEGER := 220;

  ------------------------------------------------------------------
  -- Regions: Valleys + Hills (axis-aligned rectangles)
  ------------------------------------------------------------------

  -- VALLEY A (center-ish)
  CONSTANT VA_SLOPE_L : INTEGER := 330;
  CONSTANT VA_SLOPE_R : INTEGER := 505;
  CONSTANT VA_SLOPE_T : INTEGER := 215;
  CONSTANT VA_SLOPE_B : INTEGER := 390;

  CONSTANT VA_PIT_L   : INTEGER := 392;
  CONSTANT VA_PIT_R   : INTEGER := 445;
  CONSTANT VA_PIT_T   : INTEGER := 268;
  CONSTANT VA_PIT_B   : INTEGER := 322;

  CONSTANT VA_CX      : INTEGER := (VA_PIT_L + VA_PIT_R) / 2;
  CONSTANT VA_CY      : INTEGER := (VA_PIT_T + VA_PIT_B) / 2;

  -- VALLEY B (right-bottom)  << hole moved here
  CONSTANT VB_SLOPE_L : INTEGER := 520;
  CONSTANT VB_SLOPE_R : INTEGER := 670;
  CONSTANT VB_SLOPE_T : INTEGER := 305;
  CONSTANT VB_SLOPE_B : INTEGER := 460;

  CONSTANT VB_PIT_L   : INTEGER := 565;
  CONSTANT VB_PIT_R   : INTEGER := 635;
  CONSTANT VB_PIT_T   : INTEGER := 350;
  CONSTANT VB_PIT_B   : INTEGER := 405;

  CONSTANT VB_CX      : INTEGER := (VB_PIT_L + VB_PIT_R) / 2;
  CONSTANT VB_CY      : INTEGER := (VB_PIT_T + VB_PIT_B) / 2;

  -- HOLE in bottom-right valley pit
  CONSTANT HOLE_X : INTEGER := VB_CX;
  CONSTANT HOLE_Y : INTEGER := VB_CY;

  -- HILL A (bottom-left)
  CONSTANT HA_SLOPE_L : INTEGER := 170;
  CONSTANT HA_SLOPE_R : INTEGER := 325;
  CONSTANT HA_SLOPE_T : INTEGER := 320;
  CONSTANT HA_SLOPE_B : INTEGER := 485;

  CONSTANT HA_TOP_L   : INTEGER := 220;
  CONSTANT HA_TOP_R   : INTEGER := 275;
  CONSTANT HA_TOP_T   : INTEGER := 370;
  CONSTANT HA_TOP_B   : INTEGER := 435;

  CONSTANT HA_CX      : INTEGER := (HA_TOP_L + HA_TOP_R) / 2;
  CONSTANT HA_CY      : INTEGER := (HA_TOP_T + HA_TOP_B) / 2;

  -- HILL B (top-right)
  CONSTANT HB_SLOPE_L : INTEGER := 535;
  CONSTANT HB_SLOPE_R : INTEGER := 675;
  CONSTANT HB_SLOPE_T : INTEGER := 145;
  CONSTANT HB_SLOPE_B : INTEGER := 290;

  CONSTANT HB_TOP_L   : INTEGER := 585;
  CONSTANT HB_TOP_R   : INTEGER := 625;
  CONSTANT HB_TOP_T   : INTEGER := 185;
  CONSTANT HB_TOP_B   : INTEGER := 255;

  CONSTANT HB_CX      : INTEGER := (HB_TOP_L + HB_TOP_R) / 2;
  CONSTANT HB_CY      : INTEGER := (HB_TOP_T + HB_TOP_B) / 2;

  ------------------------------------------------------------------
  -- Slope tuning: gentle and bounded
  ------------------------------------------------------------------
  CONSTANT VALLEY_ACC_SLOPE : INTEGER := 1;
  CONSTANT VALLEY_ACC_PIT   : INTEGER := 2;

  -- hills were rejecting too hard: keep gentle
  CONSTANT HILL_ACC_SLOPE   : INTEGER := 1;

  CONSTANT VEL_CAP          : INTEGER := 18;

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

  SIGNAL ball_on      : STD_LOGIC := '0';
  SIGNAL ball_edge_on : STD_LOGIC := '0';
  SIGNAL wall_on      : STD_LOGIC := '0';
  SIGNAL hole_on      : STD_LOGIC := '0';
  SIGNAL arrow_on     : STD_LOGIC := '0';

  SIGNAL valley_slope_on : STD_LOGIC := '0';
  SIGNAL valley_pit_on   : STD_LOGIC := '0';
  SIGNAL hill_slope_on   : STD_LOGIC := '0';
  SIGNAL hill_top_on     : STD_LOGIC := '0';

  SIGNAL stroke_pulse_i : STD_LOGIC := '0';
  SIGNAL hole_pulse_i   : STD_LOGIC := '0';

  SIGNAL level_active_d : STD_LOGIC := '0';

  SIGNAL ball_r_draw : INTEGER RANGE 0 TO 20 := BALL_R_BASE;

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
    VARIABLE dx, dy : INTEGER;
    VARIABLE r2      : INTEGER;
    VARIABLE r_outer : INTEGER;
    VARIABLE r_inner : INTEGER;
    VARIABLE arrow_x, arrow_y : INTEGER;
    VARIABLE adx, ady, ar2 : INTEGER;
  BEGIN
    px := CONV_INTEGER(pixel_col);
    py := CONV_INTEGER(pixel_row);

    wall_on  <= '0';
    ball_on  <= '0';
    ball_edge_on <= '0';
    hole_on  <= '0';
    arrow_on <= '0';

    valley_slope_on <= '0';
    valley_pit_on   <= '0';
    hill_slope_on   <= '0';
    hill_top_on     <= '0';

    -- outer box walls (yellow)
    IF ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_TOP) AND (py <= BOX_TOP + WALL_THK)) OR
       ((px >= BOX_LEFT) AND (px <= BOX_RIGHT) AND (py >= BOX_BOTTOM - WALL_THK) AND (py <= BOX_BOTTOM)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_LEFT) AND (px <= BOX_LEFT + WALL_THK)) OR
       ((py >= BOX_TOP) AND (py <= BOX_BOTTOM) AND (px >= BOX_RIGHT - WALL_THK) AND (px <= BOX_RIGHT)) THEN
      wall_on <= '1';
    END IF;

    -- slopes
    IF (px>=VA_SLOPE_L) AND (px<=VA_SLOPE_R) AND (py>=VA_SLOPE_T) AND (py<=VA_SLOPE_B) THEN
      valley_slope_on <= '1';
    END IF;
    IF (px>=VA_PIT_L) AND (px<=VA_PIT_R) AND (py>=VA_PIT_T) AND (py<=VA_PIT_B) THEN
      valley_pit_on <= '1';
    END IF;

    IF (px>=VB_SLOPE_L) AND (px<=VB_SLOPE_R) AND (py>=VB_SLOPE_T) AND (py<=VB_SLOPE_B) THEN
      valley_slope_on <= '1';
    END IF;
    IF (px>=VB_PIT_L) AND (px<=VB_PIT_R) AND (py>=VB_PIT_T) AND (py<=VB_PIT_B) THEN
      valley_pit_on <= '1';
    END IF;

    IF (px>=HA_SLOPE_L) AND (px<=HA_SLOPE_R) AND (py>=HA_SLOPE_T) AND (py<=HA_SLOPE_B) THEN
      hill_slope_on <= '1';
    END IF;
    IF (px>=HA_TOP_L) AND (px<=HA_TOP_R) AND (py>=HA_TOP_T) AND (py<=HA_TOP_B) THEN
      hill_top_on <= '1';
    END IF;

    IF (px>=HB_SLOPE_L) AND (px<=HB_SLOPE_R) AND (py>=HB_SLOPE_T) AND (py<=HB_SLOPE_B) THEN
      hill_slope_on <= '1';
    END IF;
    IF (px>=HB_TOP_L) AND (px<=HB_TOP_R) AND (py>=HB_TOP_T) AND (py<=HB_TOP_B) THEN
      hill_top_on <= '1';
    END IF;

    -- hole (black)
    dx := HOLE_X - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := HOLE_Y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;
    IF r2 <= HOLE_R*HOLE_R THEN hole_on <= '1'; END IF;

    -- ball + outline ring
    dx := ball_x - px; IF dx < 0 THEN dx := -dx; END IF;
    dy := ball_y - py; IF dy < 0 THEN dy := -dy; END IF;
    r2 := dx*dx + dy*dy;

    r_outer := ball_r_draw;
    r_inner := ball_r_draw - 2;
    IF r_inner < 1 THEN r_inner := 1; END IF;

    IF r2 <= (r_outer*r_outer) THEN
      IF r2 >= (r_inner*r_inner) THEN
        ball_edge_on <= '1'; -- black outline
      ELSE
        ball_on <= '1';      -- white fill
      END IF;
    END IF;

    -- arrow dot (magenta), drawn OVER slopes/hill
    IF (shot_state = '0') AND ((aim_vx /= 0) OR (aim_vy /= 0)) THEN
      arrow_x := ball_x + aim_vx * ARROW_SCALE;
      arrow_y := ball_y + aim_vy * ARROW_SCALE;

      adx := arrow_x - px; IF adx < 0 THEN adx := -adx; END IF;
      ady := arrow_y - py; IF ady < 0 THEN ady := -ady; END IF;
      ar2 := adx*adx + ady*ady;
      IF ar2 <= ARROW_R*ARROW_R THEN arrow_on <= '1'; END IF;
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Color priority:
  -- ball fill > ball outline > hole > arrow > regions > walls > bg
  ------------------------------------------------------------------
  ColorLogic : PROCESS(ball_on, ball_edge_on, hole_on, arrow_on,
                      valley_pit_on, hill_top_on, valley_slope_on, hill_slope_on, wall_on)
  BEGIN
    IF ball_on = '1' THEN
      red <= '1'; green <= '1'; blue <= '1';
    ELSIF ball_edge_on = '1' THEN
      red <= '0'; green <= '0'; blue <= '0';
    ELSIF hole_on = '1' THEN
      red <= '0'; green <= '0'; blue <= '0';
    ELSIF arrow_on = '1' THEN
      red <= '1'; green <= '0'; blue <= '1';
    ELSIF hill_top_on = '1' THEN
      red <= '1'; green <= '1'; blue <= '1';
    ELSIF valley_pit_on = '1' THEN
      red <= '1'; green <= '0'; blue <= '1';
    ELSIF hill_slope_on = '1' THEN
      red <= '1'; green <= '1'; blue <= '0';
    ELSIF valley_slope_on = '1' THEN
      red <= '0'; green <= '1'; blue <= '1';
    ELSIF wall_on = '1' THEN
      red <= '1'; green <= '1'; blue <= '0';
    ELSE
      red <= '0'; green <= '1'; blue <= '0';
    END IF;
  END PROCESS;

  ------------------------------------------------------------------
  -- Game logic (v_sync) — FIXED: variable-based velocity so bounces never get overwritten
  ------------------------------------------------------------------
  game_proc : PROCESS(v_sync)
    VARIABLE u_rise, d_rise, l_rise, r_rise, c_rise : STD_LOGIC;

    VARIABLE nx, ny : INTEGER;
    VARIABLE vxv, vyv : INTEGER;

    VARIABLE dx, dy, r2 : INTEGER;

    VARIABLE ax, ay : INTEGER;

    VARIABLE in_VA_s, in_VA_p : BOOLEAN;
    VARIABLE in_VB_s, in_VB_p : BOOLEAN;
    VARIABLE in_HA_s, in_HA_t : BOOLEAN;
    VARIABLE in_HB_s, in_HB_t : BOOLEAN;

    VARIABLE near_wall : BOOLEAN;
  BEGIN
    IF rising_edge(v_sync) THEN
      stroke_pulse_i <= '0';
      hole_pulse_i   <= '0';

      IF (level_active = '1') AND (level_active_d = '0') THEN
        ball_x <= START_X; ball_y <= START_Y;
        aim_vx <= 6; aim_vy <= 0;
        vel_x <= 0; vel_y <= 0;
        shot_state <= '0';
        shot_timer <= 0;
        shot_start_x <= START_X; shot_start_y <= START_Y;
        ball_r_draw <= BALL_R_BASE;
      END IF;

      IF level_active = '0' THEN
        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;
        level_active_d <= level_active;
      ELSE
        u_rise := '0'; d_rise := '0'; l_rise := '0'; r_rise := '0'; c_rise := '0';
        IF (BTNU='1') AND (BTNU_d='0') THEN u_rise:='1'; END IF;
        IF (BTND='1') AND (BTND_d='0') THEN d_rise:='1'; END IF;
        IF (BTNL='1') AND (BTNL_d='0') THEN l_rise:='1'; END IF;
        IF (BTNR='1') AND (BTNR_d='0') THEN r_rise:='1'; END IF;
        IF (BTNC='1') AND (BTNC_d='0') THEN c_rise:='1'; END IF;

        BTNU_d <= BTNU; BTND_d <= BTND; BTNL_d <= BTNL; BTNR_d <= BTNR; BTNC_d <= BTNC;

        IF shot_state = '0' THEN
          IF u_rise='1' THEN aim_vy <= aim_vy - 1; END IF;
          IF d_rise='1' THEN aim_vy <= aim_vy + 1; END IF;
          IF l_rise='1' THEN aim_vx <= aim_vx - 1; END IF;
          IF r_rise='1' THEN aim_vx <= aim_vx + 1; END IF;

          IF aim_vx > 8 THEN aim_vx <= 8; ELSIF aim_vx < -8 THEN aim_vx <= -8; END IF;
          IF aim_vy > 8 THEN aim_vy <= 8; ELSIF aim_vy < -8 THEN aim_vy <= -8; END IF;

          IF c_rise='1' THEN
            IF (aim_vx /= 0) OR (aim_vy /= 0) THEN
              vel_x <= aim_vx; vel_y <= aim_vy;
              shot_start_x <= ball_x; shot_start_y <= ball_y;
              shot_state <= '1';
              shot_timer <= 0;
              stroke_pulse_i <= '1';
            END IF;
          END IF;

        ELSE
          -- pull current velocity into variables (so bounce can't be overwritten)
          vxv := vel_x;
          vyv := vel_y;

          -- move
          nx := ball_x + vxv;
          ny := ball_y + vyv;

          -- bounce off outer box walls (using variables only)
          IF nx <= BOX_LEFT + BALL_R_BASE THEN
            nx := BOX_LEFT + BALL_R_BASE;
            vxv := -vxv;
          ELSIF nx >= BOX_RIGHT - BALL_R_BASE THEN
            nx := BOX_RIGHT - BALL_R_BASE;
            vxv := -vxv;
          END IF;

          IF ny <= BOX_TOP + BALL_R_BASE THEN
            ny := BOX_TOP + BALL_R_BASE;
            vyv := -vyv;
          ELSIF ny >= BOX_BOTTOM - BALL_R_BASE THEN
            ny := BOX_BOTTOM - BALL_R_BASE;
            vyv := -vyv;
          END IF;

          -- region checks
          in_VA_s := (nx>=VA_SLOPE_L) AND (nx<=VA_SLOPE_R) AND (ny>=VA_SLOPE_T) AND (ny<=VA_SLOPE_B);
          in_VA_p := (nx>=VA_PIT_L)   AND (nx<=VA_PIT_R)   AND (ny>=VA_PIT_T)   AND (ny<=VA_PIT_B);

          in_VB_s := (nx>=VB_SLOPE_L) AND (nx<=VB_SLOPE_R) AND (ny>=VB_SLOPE_T) AND (ny<=VB_SLOPE_B);
          in_VB_p := (nx>=VB_PIT_L)   AND (nx<=VB_PIT_R)   AND (ny>=VB_PIT_T)   AND (ny<=VB_PIT_B);

          in_HA_s := (nx>=HA_SLOPE_L) AND (nx<=HA_SLOPE_R) AND (ny>=HA_SLOPE_T) AND (ny<=HA_SLOPE_B);
          in_HA_t := (nx>=HA_TOP_L)   AND (nx<=HA_TOP_R)   AND (ny>=HA_TOP_T)   AND (ny<=HA_TOP_B);

          in_HB_s := (nx>=HB_SLOPE_L) AND (nx<=HB_SLOPE_R) AND (ny>=HB_SLOPE_T) AND (ny<=HB_SLOPE_B);
          in_HB_t := (nx>=HB_TOP_L)   AND (nx<=HB_TOP_R)   AND (ny>=HB_TOP_T)   AND (ny<=HB_TOP_B);

          -- avoid hill "extra rejection" when we're jammed against a wall
          near_wall := (nx <= BOX_LEFT + BALL_R_BASE + 2) OR
                       (nx >= BOX_RIGHT - BALL_R_BASE - 2) OR
                       (ny <= BOX_TOP + BALL_R_BASE + 2) OR
                       (ny >= BOX_BOTTOM - BALL_R_BASE - 2);

          ax := 0; ay := 0;

          -- Valleys pull TOWARD center (pit stronger)
          IF in_VA_s THEN
            IF nx < VA_CX THEN ax := ax + VALLEY_ACC_SLOPE; ELSIF nx > VA_CX THEN ax := ax - VALLEY_ACC_SLOPE; END IF;
            IF ny < VA_CY THEN ay := ay + VALLEY_ACC_SLOPE; ELSIF ny > VA_CY THEN ay := ay - VALLEY_ACC_SLOPE; END IF;
          END IF;
          IF in_VA_p THEN
            IF nx < VA_CX THEN ax := ax + VALLEY_ACC_PIT; ELSIF nx > VA_CX THEN ax := ax - VALLEY_ACC_PIT; END IF;
            IF ny < VA_CY THEN ay := ay + VALLEY_ACC_PIT; ELSIF ny > VA_CY THEN ay := ay - VALLEY_ACC_PIT; END IF;
          END IF;

          IF in_VB_s THEN
            IF nx < VB_CX THEN ax := ax + VALLEY_ACC_SLOPE; ELSIF nx > VB_CX THEN ax := ax - VALLEY_ACC_SLOPE; END IF;
            IF ny < VB_CY THEN ay := ay + VALLEY_ACC_SLOPE; ELSIF ny > VB_CY THEN ay := ay - VALLEY_ACC_SLOPE; END IF;
          END IF;
          IF in_VB_p THEN
            IF nx < VB_CX THEN ax := ax + VALLEY_ACC_PIT; ELSIF nx > VB_CX THEN ax := ax - VALLEY_ACC_PIT; END IF;
            IF ny < VB_CY THEN ay := ay + VALLEY_ACC_PIT; ELSIF ny > VB_CY THEN ay := ay - VALLEY_ACC_PIT; END IF;
          END IF;

          -- Hills push AWAY from center (only on yellow slope, and not when hugging a wall)
          IF (NOT near_wall) THEN
            IF in_HA_s AND (NOT in_HA_t) THEN
              IF nx < HA_CX THEN ax := ax - HILL_ACC_SLOPE; ELSIF nx > HA_CX THEN ax := ax + HILL_ACC_SLOPE; END IF;
              IF ny < HA_CY THEN ay := ay - HILL_ACC_SLOPE; ELSIF ny > HA_CY THEN ay := ay + HILL_ACC_SLOPE; END IF;
            END IF;

            IF in_HB_s AND (NOT in_HB_t) THEN
              IF nx < HB_CX THEN ax := ax - HILL_ACC_SLOPE; ELSIF nx > HB_CX THEN ax := ax + HILL_ACC_SLOPE; END IF;
              IF ny < HB_CY THEN ay := ay - HILL_ACC_SLOPE; ELSIF ny > HB_CY THEN ay := ay + HILL_ACC_SLOPE; END IF;
            END IF;
          END IF;

          -- apply + cap
          vxv := clampi(vxv + ax, -VEL_CAP, VEL_CAP);
          vyv := clampi(vyv + ay, -VEL_CAP, VEL_CAP);

          -- ball size illusion tied to height/terrain
          IF in_HA_t OR in_HB_t THEN
            ball_r_draw <= BALL_R_BASE + 2;
          ELSIF in_HA_s OR in_HB_s THEN
            ball_r_draw <= BALL_R_BASE + 1;
          ELSIF in_VA_p OR in_VB_p THEN
            ball_r_draw <= BALL_R_BASE - 2;
          ELSIF in_VA_s OR in_VB_s THEN
            ball_r_draw <= BALL_R_BASE - 1;
          ELSE
            ball_r_draw <= BALL_R_BASE;
          END IF;

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
            vel_x <= vxv; vel_y <= vyv;

            shot_timer <= shot_timer + 1;
            IF shot_timer >= MAX_STEPS THEN
              shot_state <= '0';
            END IF;
          END IF;
        END IF;
      END IF;

      level_active_d <= level_active;
    END IF;
  END PROCESS;

END Behavioral;
