minigolf.vhd:
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY minigolf IS
    PORT (
        clk_in     : IN  STD_LOGIC;
        VGA_red    : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_green  : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_blue   : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_hsync  : OUT STD_LOGIC;
        VGA_vsync  : OUT STD_LOGIC;
        BTNU       : IN  STD_LOGIC;
        BTND       : IN  STD_LOGIC;
        BTNL       : IN  STD_LOGIC;
        BTNR       : IN  STD_LOGIC;
        BTNC       : IN  STD_LOGIC;
        SEG7_anode : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
        SEG7_seg   : OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
    );
END minigolf;

ARCHITECTURE Behavioral OF minigolf IS
    SIGNAL pxl_clk     : STD_LOGIC := '0';
    SIGNAL S_vsync     : STD_LOGIC;
    SIGNAL S_pixel_row : STD_LOGIC_VECTOR (10 DOWNTO 0);
    SIGNAL S_pixel_col : STD_LOGIC_VECTOR (10 DOWNTO 0);

    -- Per-level RGB + pulses
    SIGNAL L1_r, L1_g, L1_b : STD_LOGIC;
    SIGNAL L2_r, L2_g, L2_b : STD_LOGIC;
    SIGNAL L3_r, L3_g, L3_b : STD_LOGIC;
    SIGNAL L4_r, L4_g, L4_b : STD_LOGIC;
    SIGNAL L5_r, L5_g, L5_b : STD_LOGIC;

    SIGNAL L1_stroke, L1_hole : STD_LOGIC := '0';
    SIGNAL L2_stroke, L2_hole : STD_LOGIC := '0';
    SIGNAL L3_stroke, L3_hole : STD_LOGIC := '0';
    SIGNAL L4_stroke, L4_hole : STD_LOGIC := '0';
    SIGNAL L5_stroke, L5_hole : STD_LOGIC := '0';

    SIGNAL S_r, S_g, S_b : STD_LOGIC;

    SIGNAL stroke_pulse_vs : STD_LOGIC := '0';
    SIGNAL hole_pulse_vs   : STD_LOGIC := '0';

    -- 0..4 = levels 1..5
    SIGNAL level_state : unsigned(2 DOWNTO 0) := (others => '0');

    -- Level active signals (static for PORT MAP)
    SIGNAL act1, act2, act3, act4, act5 : STD_LOGIC := '0';

    -- 7-seg scan clock
    SIGNAL count   : unsigned(20 DOWNTO 0) := (others => '0');
    SIGNAL led_mpx : STD_LOGIC_VECTOR(2 DOWNTO 0);

    -- Pulse sync to clk_in
    SIGNAL stroke_sync_0, stroke_sync_1, stroke_sync_d, stroke_rise : STD_LOGIC := '0';
    SIGNAL hole_sync_0,   hole_sync_1,   hole_sync_d,   hole_rise   : STD_LOGIC := '0';

    -- TOTAL score on 7-seg
    SIGNAL total_strokes : unsigned(15 DOWNTO 0) := (others => '0');

    -- Current hole strokes (accumulates until hole made)
    SIGNAL cur_hole_strokes : unsigned(7 DOWNTO 0) := (others => '0');

    -- Win state + restart button edge detect (clk_in domain)
    SIGNAL game_won  : STD_LOGIC := '0';
    SIGNAL btnc_d    : STD_LOGIC := '0';
    SIGNAL btnc_rise : STD_LOGIC := '0';

    -- BTNC lockout (prevents “exit win” press from also shooting on hole 1)
    SIGNAL btnc_lock : STD_LOGIC := '0';
    SIGNAL BTNC_game : STD_LOGIC := '0';

    -- WIN screen RGB (1-bit each, expanded into 4-bit bus later)
    SIGNAL win_r, win_g, win_b : STD_LOGIC := '0';

    COMPONENT vga_sync IS
        PORT (
            pixel_clk : IN  STD_LOGIC;
            red_in    : IN  STD_LOGIC_VECTOR (3 DOWNTO 0);
            green_in  : IN  STD_LOGIC_VECTOR (3 DOWNTO 0);
            blue_in   : IN  STD_LOGIC_VECTOR (3 DOWNTO 0);
            red_out   : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            green_out : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            blue_out  : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            hsync     : OUT STD_LOGIC;
            vsync     : OUT STD_LOGIC;
            pixel_row : OUT STD_LOGIC_VECTOR (10 DOWNTO 0);
            pixel_col : OUT STD_LOGIC_VECTOR (10 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT clk_wiz_0 IS
        PORT (
            clk_in1  : IN  STD_LOGIC;
            clk_out1 : OUT STD_LOGIC
        );
    END COMPONENT;

    COMPONENT leddec16 IS
        PORT (
            dig   : IN  STD_LOGIC_VECTOR (2 DOWNTO 0);
            data  : IN  STD_LOGIC_VECTOR (15 DOWNTO 0);
            anode : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            seg   : OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
        );
    END COMPONENT;

BEGIN
    ------------------------------------------------------------------
    -- 7-seg mux counter
    ------------------------------------------------------------------
    pos : PROCESS(clk_in)
    BEGIN
        IF rising_edge(clk_in) THEN
            count <= count + 1;
        END IF;
    END PROCESS;

    led_mpx <= std_logic_vector(count(19 DOWNTO 17));

    ------------------------------------------------------------------
    -- BTNC gating (lockout after leaving win screen)
    ------------------------------------------------------------------
    BTNC_game <= '0' WHEN (game_won='1' OR btnc_lock='1') ELSE BTNC;

    ------------------------------------------------------------------
    -- Level active decoding (static signals for port maps)
    ------------------------------------------------------------------
    act1 <= '1' WHEN (game_won='0' AND level_state = to_unsigned(0,3)) ELSE '0';
    act2 <= '1' WHEN (game_won='0' AND level_state = to_unsigned(1,3)) ELSE '0';
    act3 <= '1' WHEN (game_won='0' AND level_state = to_unsigned(2,3)) ELSE '0';
    act4 <= '1' WHEN (game_won='0' AND level_state = to_unsigned(3,3)) ELSE '0';
    act5 <= '1' WHEN (game_won='0' AND level_state = to_unsigned(4,3)) ELSE '0';

    ------------------------------------------------------------------
    -- LEVEL 1..5 instances
    -- NOTE: BTNC_game is used (NOT raw BTNC)
    ------------------------------------------------------------------
    L1_core : ENTITY work.minigolf_level1
    PORT MAP(
      v_sync => S_vsync, pixel_row => S_pixel_row, pixel_col => S_pixel_col,
      BTNU => BTNU, BTND => BTND, BTNL => BTNL, BTNR => BTNR, BTNC => BTNC_game,
      level_active => act1,
      red => L1_r, green => L1_g, blue => L1_b,
      stroke_pulse => L1_stroke, hole_pulse => L1_hole
    );

    L2_core : ENTITY work.minigolf_level2
    PORT MAP(
      v_sync => S_vsync, pixel_row => S_pixel_row, pixel_col => S_pixel_col,
      BTNU => BTNU, BTND => BTND, BTNL => BTNL, BTNR => BTNR, BTNC => BTNC_game,
      level_active => act2,
      red => L2_r, green => L2_g, blue => L2_b,
      stroke_pulse => L2_stroke, hole_pulse => L2_hole
    );

    L3_core : ENTITY work.minigolf_level3
    PORT MAP(
      v_sync => S_vsync, pixel_row => S_pixel_row, pixel_col => S_pixel_col,
      BTNU => BTNU, BTND => BTND, BTNL => BTNL, BTNR => BTNR, BTNC => BTNC_game,
      level_active => act3,
      red => L3_r, green => L3_g, blue => L3_b,
      stroke_pulse => L3_stroke, hole_pulse => L3_hole
    );

    L4_core : ENTITY work.minigolf_level4
    PORT MAP(
      v_sync => S_vsync, pixel_row => S_pixel_row, pixel_col => S_pixel_col,
      BTNU => BTNU, BTND => BTND, BTNL => BTNL, BTNR => BTNR, BTNC => BTNC_game,
      level_active => act4,
      red => L4_r, green => L4_g, blue => L4_b,
      stroke_pulse => L4_stroke, hole_pulse => L4_hole
    );

    L5_core : ENTITY work.minigolf_level5
    PORT MAP(
      v_sync => S_vsync, pixel_row => S_pixel_row, pixel_col => S_pixel_col,
      BTNU => BTNU, BTND => BTND, BTNL => BTNL, BTNR => BTNR, BTNC => BTNC_game,
      level_active => act5,
      red => L5_r, green => L5_g, blue => L5_b,
      stroke_pulse => L5_stroke, hole_pulse => L5_hole
    );

    ------------------------------------------------------------------
    -- Select RGB by level (game view)
    ------------------------------------------------------------------
    S_r <= L1_r WHEN level_state = to_unsigned(0,3) ELSE
           L2_r WHEN level_state = to_unsigned(1,3) ELSE
           L3_r WHEN level_state = to_unsigned(2,3) ELSE
           L4_r WHEN level_state = to_unsigned(3,3) ELSE
           L5_r;

    S_g <= L1_g WHEN level_state = to_unsigned(0,3) ELSE
           L2_g WHEN level_state = to_unsigned(1,3) ELSE
           L3_g WHEN level_state = to_unsigned(2,3) ELSE
           L4_g WHEN level_state = to_unsigned(3,3) ELSE
           L5_g;

    S_b <= L1_b WHEN level_state = to_unsigned(0,3) ELSE
           L2_b WHEN level_state = to_unsigned(1,3) ELSE
           L3_b WHEN level_state = to_unsigned(2,3) ELSE
           L4_b WHEN level_state = to_unsigned(3,3) ELSE
           L5_b;

    ------------------------------------------------------------------
    -- Select pulses by level
    ------------------------------------------------------------------
    stroke_pulse_vs <= L1_stroke WHEN level_state = to_unsigned(0,3) ELSE
                       L2_stroke WHEN level_state = to_unsigned(1,3) ELSE
                       L3_stroke WHEN level_state = to_unsigned(2,3) ELSE
                       L4_stroke WHEN level_state = to_unsigned(3,3) ELSE
                       L5_stroke;

    hole_pulse_vs   <= L1_hole WHEN level_state = to_unsigned(0,3) ELSE
                       L2_hole WHEN level_state = to_unsigned(1,3) ELSE
                       L3_hole WHEN level_state = to_unsigned(2,3) ELSE
                       L4_hole WHEN level_state = to_unsigned(3,3) ELSE
                       L5_hole;

    ------------------------------------------------------------------
    -- VGA sync + output mux (game view OR win view)
    ------------------------------------------------------------------
    vga_driver : vga_sync
    PORT MAP(
      pixel_clk => pxl_clk,
      red_in    => (win_r & "000") WHEN game_won='1' ELSE (S_r & "000"),
      green_in  => (win_g & "000") WHEN game_won='1' ELSE (S_g & "000"),
      blue_in   => (win_b & "000") WHEN game_won='1' ELSE (S_b & "000"),
      red_out   => VGA_red,
      green_out => VGA_green,
      blue_out  => VGA_blue,
      hsync     => VGA_hsync,
      vsync     => S_vsync,
      pixel_row => S_pixel_row,
      pixel_col => S_pixel_col
    );

    VGA_vsync <= S_vsync;

    clk_wiz_0_inst : clk_wiz_0
    PORT MAP(clk_in1 => clk_in, clk_out1 => pxl_clk);

    ------------------------------------------------------------------
    -- Sync pulses to clk_in + BTNC edge detect (raw BTNC only for win-exit)
    ------------------------------------------------------------------
    sync_proc : PROCESS(clk_in)
    BEGIN
      IF rising_edge(clk_in) THEN
        stroke_sync_0 <= stroke_pulse_vs;
        stroke_sync_1 <= stroke_sync_0;
        stroke_rise   <= stroke_sync_1 AND (NOT stroke_sync_d);
        stroke_sync_d <= stroke_sync_1;

        hole_sync_0 <= hole_pulse_vs;
        hole_sync_1 <= hole_sync_0;
        hole_rise   <= hole_sync_1 AND (NOT hole_sync_d);
        hole_sync_d <= hole_sync_1;

        btnc_rise <= (BTNC AND (NOT btnc_d));
        btnc_d    <= BTNC;
      END IF;
    END PROCESS;

    ------------------------------------------------------------------
    -- Score tracking (TOTAL) + win/restart + BTNC lockout handling
    ------------------------------------------------------------------
    score_proc : PROCESS(clk_in)
    BEGIN
      IF rising_edge(clk_in) THEN

        -- If lock is on, wait for button release to re-arm gameplay BTNC
        IF btnc_lock='1' THEN
          IF BTNC='0' THEN
            btnc_lock <= '0';
          END IF;
        END IF;

        IF (game_won='1') THEN
          -- Exit win screen with BTNC (raw), then lock out BTNC until release
          IF btnc_rise='1' THEN
            game_won <= '0';
            level_state <= to_unsigned(0,3);
            total_strokes <= (others => '0');
            cur_hole_strokes <= (others => '0');
            btnc_lock <= '1'; -- prevents immediate “shot” on hole 1
          END IF;

        ELSE
          -- Normal scoring
          IF stroke_rise='1' THEN
            total_strokes <= total_strokes + 1;
            cur_hole_strokes <= cur_hole_strokes + 1;
          END IF;

          -- Hole completion -> advance or win
          IF hole_rise='1' THEN
            cur_hole_strokes <= (others => '0');

            IF level_state = to_unsigned(4,3) THEN
              game_won <= '1';
            ELSE
              level_state <= level_state + 1;
            END IF;
          END IF;
        END IF;
      END IF;
    END PROCESS;

    ------------------------------------------------------------------
    -- WIN screen: ONLY “YOU WIN” (white text on blue background)
    ------------------------------------------------------------------
    win_draw : PROCESS(S_pixel_row, S_pixel_col)
      VARIABLE x, y : INTEGER;

      -- text placement + sizing
      CONSTANT X0 : INTEGER := 170;  -- left of text block
      CONSTANT Y0 : INTEGER := 230;  -- top of text block
      CONSTANT W  : INTEGER := 20;   -- letter stroke thickness
      CONSTANT H  : INTEGER := 70;   -- letter height
      CONSTANT GAP: INTEGER := 20;   -- gap between letters
      CONSTANT GAP_WORD : INTEGER := 45; -- gap between YOU and WIN

      VARIABLE on_text : BOOLEAN;

      -- helpers for letter regions
      VARIABLE lx : INTEGER;
    BEGIN
      x := to_integer(unsigned(S_pixel_col));
      y := to_integer(unsigned(S_pixel_row));

      -- blue background
      win_r <= '0';
      win_g <= '0';
      win_b <= '1';

      on_text := FALSE;

      -- We draw chunky block letters with simple rectangles.
      -- Baseline: Y0..Y0+H, thickness W.

      -- ---------- Y ----------
      lx := X0;
      -- upper left arm
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H/2) THEN on_text := TRUE; END IF;
      -- upper right arm
      IF (x>=lx+2*W AND x<lx+3*W) AND (y>=Y0 AND y<Y0+H/2) THEN on_text := TRUE; END IF;
      -- stem
      IF (x>=lx+W AND x<lx+2*W) AND (y>=Y0+H/2 AND y<Y0+H) THEN on_text := TRUE; END IF;

      -- ---------- O ----------
      lx := X0 + 3*W + GAP;
      IF (x>=lx AND x<lx+3*W) AND (y>=Y0 AND y<Y0+W) THEN on_text := TRUE; END IF;              -- top
      IF (x>=lx AND x<lx+3*W) AND (y>=Y0+H-W AND y<Y0+H) THEN on_text := TRUE; END IF;         -- bottom
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;               -- left
      IF (x>=lx+2*W AND x<lx+3*W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;         -- right

      -- ---------- U ----------
      lx := X0 + 6*W + 2*GAP;
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;               -- left
      IF (x>=lx+2*W AND x<lx+3*W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;         -- right
      IF (x>=lx AND x<lx+3*W) AND (y>=Y0+H-W AND y<Y0+H) THEN on_text := TRUE; END IF;         -- bottom

      -- Word gap
      lx := X0 + 9*W + 2*GAP + GAP_WORD;

      -- ---------- W ----------
      -- left post
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;
      -- right post
      IF (x>=lx+4*W AND x<lx+5*W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;
      -- inner left diagonal-ish (block)
      IF (x>=lx+W AND x<lx+2*W) AND (y>=Y0+H/2 AND y<Y0+H) THEN on_text := TRUE; END IF;
      -- inner right diagonal-ish (block)
      IF (x>=lx+3*W AND x<lx+4*W) AND (y>=Y0+H/2 AND y<Y0+H) THEN on_text := TRUE; END IF;
      -- bottom
      IF (x>=lx AND x<lx+5*W) AND (y>=Y0+H-W AND y<Y0+H) THEN on_text := TRUE; END IF;

      -- ---------- I ----------
      lx := lx + 5*W + GAP;
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;

      -- ---------- N ----------
      lx := lx + W + GAP;
      IF (x>=lx AND x<lx+W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;               -- left
      IF (x>=lx+3*W AND x<lx+4*W) AND (y>=Y0 AND y<Y0+H) THEN on_text := TRUE; END IF;         -- right
      IF (x>=lx+W AND x<lx+2*W) AND (y>=Y0 AND y<Y0+H) THEN
        -- thick middle “diagonal” as a full column (cheap + readable)
        on_text := TRUE;
      END IF;

      IF on_text THEN
        win_r <= '1';
        win_g <= '1';
        win_b <= '1';
      END IF;
    END PROCESS;

    ------------------------------------------------------------------
    -- 7-seg shows TOTAL strokes always
    ------------------------------------------------------------------
    led1 : leddec16
    PORT MAP(
      dig   => led_mpx,
      data  => std_logic_vector(total_strokes),
      anode => SEG7_anode,
      seg   => SEG7_seg
    );

END Behavioral;
