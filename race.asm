; ═══════════════════════════════════════════════════════════════════════════════
;  ▀█▀ █▀█ ▄▀█ █▀▀ █▄▀   █▀▄ ▄▀█ █▄█   █▀█ ▄▀█ █▀▀ █ █▄ █ █▀▀
;   █  █▀▄ █▀█ █▄▄ █ █   █▄▀ █▀█  █    █▀▄ █▀█ █▄▄ █ █ ▀█ █▄█
; ═══════════════════════════════════════════════════════════════════════════════
;
;  A high-speed racing experience for the Foenix F256 family of computers
;  for the Oct-Dec 2025 Foenix Game Jam
;
;  Author:        Michael Cassera
;  Year:          2025
;  CPU:           WDC 65C02 (8-bit mode on 65C816 hardware)
;  Target:        Foenix F256K, F256K2, F256Jr, F256Jr2
;  Graphics:      TinyVicky II (Tilemap + Sprite Engine)
;  Sound:         PSG + SID
;
;  Features:      • Player car with analog-style physics
;                 • 3 AI-controlled opponents with pathfinding
;                 • Dynamic helicopter camera
;                 • Track position system with waypoints
;                 • Collision detection and response
;                 • Parallax scrolling tilemap
;                 • Real-time speedometer
;                 • Background music and SFX
;
;  Build:         64tass --output-exec=start --c256-pgz race.asm --output race.pgz
;
; ═══════════════════════════════════════════════════════════════════════════════
;


; --------------------------------------------------------------------------
; Zero-page temporary variables and aliases
; Purpose: Scratch storage for AI, math, waypoint and collision routines.
; These zero-page locations are used for temporary buffers, 16-bit deltas,
; 32-bit accumulators, and similar ephemeral values. Keep allocations
; compact and document intended usage to avoid accidental overlapping use
; across routines.
;
; Naming & size conventions:
;  - Names ending with _L/_H are the low/high bytes of 16-bit values.
;  - Names containing LL/LH/HL/HH form little-endian 32-bit words
;    (LL = least-significant byte).
;  - Some aliases intentionally overlap to provide different typed views
;    of the same zero-page bytes; callers must ensure lifetimes do not
;    conflict before reusing the region.
; --------------------------------------------------------------------------

; average_X_/average_Y - 32-bit little-endian words used to hold the
; quotient result produced by the DIV/ADD sequence when computing the
; average position of all cars (player + AI). The helicopter AI reads
; these bytes to determine an averaged target point to steer toward.
; After accumulation the DIV/ADD engine stores the quotient into QUOU_*;
; code copies the relevant bytes here for convenient zero-page access.

; temporary storage for average position results
average_X_L = $60    ; average X low byte (LSB of quotient)
average_X_H = $61    ; average X next byte
average_Y_L = $62    ; average Y low byte (LSB of quotient)
average_Y_H = $63    ; average Y next byte

; temporary MULU result storage (little-endian 32-bit)
m_result_LL = $64    ; MULU result low byte (LSB)
m_result_LH = $65    ; MULU result low-high byte
m_result_HL = $66    ; MULU result high-low byte
m_result_HH = $67    ; MULU result high byte (MSB)

TileTempX_L = $68       ; Temporary tile X low byte
TileTempX_H = $69       ; Temporary tile X high byte
TileTempY_L = $6A       ; Temporary tile Y low byte
TileTempY_H = $6B       ; Temporary tile Y high byte
off_road = $6C          ; Off-road flag
player_off_road = $6D   ; Player off-road flag

; Right-outrigger / right-side 16-bit X,Y (low/high)
RRXL = $70    ; Right outrigger X low byte
RRXH = $71    ; Right outrigger X high byte
RRYL = $72    ; Right outrigger Y low byte
RRYH = $73    ; Right outrigger Y high byte

; Left-outrigger / left-side 16-bit X,Y (low/high)
LRXL = $74    ; Left outrigger X low byte
LRXH = $75    ; Left outrigger X high byte
LRYL = $76    ; Left outrigger Y low byte
LRYH = $77    ; Left outrigger Y high byte

; 16-bit deltas (right and left) used for difference/squared computations
RDXL = $78    ; Right delta X low
RDXH = $79    ; Right delta X high
RDYL = $7A    ; Right delta Y low
RDYH = $7B    ; Right delta Y high
LDXL = $7C    ; Left delta X low
LDXH = $7D    ; Left delta X high
LDYL = $7E    ; Left delta Y low
LDYH = $7F    ; Left delta Y high

; 32-bit temporaries for squared components / shifted values (little-endian)
; Stored as bytes: LL (LSB), LH, HL, HH (MSB)
RDXSLL = $80  ; Right delta X 32-bit byte 0 (LSB)
RDXSLH = $81  ; byte 1
RDXSHL = $82  ; byte 2
RDXSHH = $83  ; byte 3 (MSB)
RDYSLL = $84  ; Right delta Y 32-bit byte 0 (LSB)
RDYSLH = $85  ; byte 1
RDYSHL = $86  ; byte 2
RDYSHH = $87  ; byte 3 (MSB)

LDXSLL = $88  ; Left delta X 32-bit byte 0 (LSB)
LDXSLH = $89  ; byte 1
LDXSHL = $8A  ; byte 2
LDXSHH = $8B  ; byte 3 (MSB)
LDYSLL = $8C  ; Left delta Y 32-bit byte 0 (LSB)
LDYSLH = $8D  ; byte 1
LDYSHL = $8E  ; byte 2
LDYSHH = $8F  ; byte 3 (MSB)

; 32-bit accumulators for distance/sum results (little-endian)
RDISTLL = $90  ; Right distance/result byte 0 (LSB)
RDISTLH = $91
RDISTHL = $92
RDISTHH = $93  ; Right distance/result MSB
LDISTLL = $94  ; Left distance/result byte 0
LDISTLH = $95
LDISTHL = $96
LDISTHH = $97  ; Left distance/result MSB

; 32-bit DIFF storage (difference between left/right distances)
DIFFLL = $9A
DIFFLH = $9B
DIFFHL = $9C
DIFFHH = $9D

; Small single-byte temporaries / aliases
; R1/R2 are often used as generic temp bytes; note these overlap with
; the earlier 32-bit LDXS area ($88/$89). This overlap is intentional
; — do not use R1/R2 while the 32-bit left-delta is live.
R1   = $88    ; temp byte alias (shares space with LDXSLL)
R2   = $89    ; temp byte alias (shares space with LDXSLH)

; Frequently-used 16-bit coordinate aliases used by waypoint checks and
; other routines. These intentionally alias the RDXS/RDYS bytes so the
; same zero-page region can be treated as either 32-bit temporaries or
; 16-bit coordinate pairs depending on context.
X1L = $80      ; X1 low  (alias of RDXSLL)
X1H = $81      ; X1 high (alias of RDXSLH)
Y1L = $82      ; Y1 low  (alias of RDXSHL)
Y1H = $83      ; Y1 high (alias of RDXSHH)
X2L = $84      ; X2 low  (alias of RDYSLL)
X2H = $85      ; X2 high (alias of RDYSLH)
Y2L = $86      ; Y2 low  (alias of RDYSHL)
Y2H = $87      ; Y2 high (alias of RDYSHH)
DISTX_L = $8a  ; DISTX low byte (alias of RDISTLL)
DISTX_H = $8b  ; DISTX high byte (alias of RDISTLH)
DISTY_L = $8c  ; DISTY low byte (alias of LDISTLL)
DISTY_H = $8d  ; DISTY high byte (alias of LDISTLH)
RAW_DISTX_L = $90  ; RAW_DISTX low byte (alias of RDISTLL)
RAW_DISTX_H = $91  ; RAW_DISTX high byte (alias of RDISTLH)
RAW_DISTY_L = $92  ; RAW_DISTY low byte (alias of LDISTLL)
RAW_DISTY_H = $93  ; RAW_DISTY high byte (alias of LDISTLH)
Collision_car:= $94  ; ; Car index involved in collision (alias of LDISTLL)
XSIGN = $95        ; Sign of X difference (alias of LDISTLH)
YSIGN = $96        ; Sign of Y difference (alias of LDISTHL)
speed_transfer_F = $97  ; Speed transfer fraction (alias of LDISTHH)
speed_transfer_L = $98  ; Speed transfer low byte
speed_transfer_H = $99  ; Speed transfer high byte
; ============================================================================
; SPRITE SYSTEM OVERVIEW
; ============================================================================
; The Foenix F256 sprite system uses 64 sprite slots numbered 0-63. Each slot
; occupies 8 consecutive bytes in the sprite register area starting at VKY_SP0.
; Lower-numbered slots have higher display priority and appear on top of 
; higher-numbered slots when overlapping.
;
; This program allocates sprites strategically by priority:
; - UI elements (speedometer) use slot 0 for maximum visibility
; - Animation elements (helicopter rotor, lamps) use low slots for prominence
; - Shadows use high slots to appear beneath their parent sprites
; - Player and AI cars use slots 20+ allowing room for future expansion
;
; Each sprite slot is accessed via: VKY_SP0 + (8 * slot_number)
; ============================================================================

; ============================================================================
; SPRITE SLOT ALLOCATION
; ============================================================================
; Slot# | Register Base         | Purpose                 | Size     | Priority
; ------+-----------------------+-------------------------+----------+---------
;   0   | Speedo_sprite_base    | Speedometer             | 8  x  8  | Highest
;   1   | helicopter_blade      | Helicopter rotor        | 32 x 32  | High
;   2   | helicopter_base       | Helicopter body         | 32 x 32  | High
;   3   | lamps_base            | Lamps (10 total)        | 8  x  8  | High
;   4   |  lamp                 |                         | 8  x  8  | High
;   5   |  lamp                 |                         | 8  x  8  | High
;   6   |  lamp                 |                         | 8  x  8  | High
;   7   |  lamp                 |                         | 8  x  8  | High
;   8   |  lamp                 |                         | 8  x  8  | High
;   9   |  lamp                 |                         | 8  x  8  | High
;  10   |  lamp                 |                         | 8  x  8  | High
;  11   |  lamp                 |                         | 8  x  8  | High
;  12   |  lamp                 |                         | 8  x  8  | High
;  13   |  unused               |                         |          | High
;  14   |  unused               |                         |          | High
;  15   | christmas_tree_left   | Christmas tree left     | 32 x 32  | Medium
;  16   | christmas_tree_right  | Christmas tree right    | 32 x 32  | Medium
;  17   | unused                |                         |          | Low
;  18   | helicopter_S_blade    | Shadow rotor            | 32 x 32  | Low
;  19   | helicopter_shadow     | Helicopter shadow       | 32 x 32  | Low
;  20   | car_sprite_base       | Player + AI cars        | 16 x 16  | Lowest
;  21   |  AI car               |                         | 16 x 16  | Lowest
;  22   |  AI car               |                         | 16 x 16  | Lowest
;  23   |  AI car               |                         | 16 x 16  | Lowest
;  24   |  AI car 0 face        |                         | 32 x 32  | Lowest
;  25   |  AI car 1 face        |                         | 32 x 32  | Lowest
;  26   |  AI car 2 face        |                         | 32 x 32  | Lowest
;  27   |  player face          |                         | 32 x 32  | Lowest
; ---------------------------------------------------------------------------


; ============================================================================
; Note: Lower slot numbers have higher display priority (drawn on top)
;       Each sprite slot is 8 bytes; slot N -> VKY_SP0 + (8*N)
; ============================================================================

car_sprite_base         = VKY_SP0+(8*20)        ; Sprite register base for player + AI cars (slot 20)
                                                ; Each sprite slot is 8 bytes; slot N -> VKY_SP0 + (8*N)
ai_car_base             = VKY_SP0+(8*21)        ; Sprite register base for AI car 1 (slot 21)
helicopter_base         = VKY_SP0+(8*2)         ; Sprite register base for helicopter body (slot 2)
helicopter_blade        = VKY_SP0+(8*1)         ; Sprite register base for helicopter rotor (slot 1)
helicopter_shadow       = VKY_SP0+(8*19)        ; Sprite register base for helicopter shadow (slot 19)
helicopter_S_blade      = VKY_SP0+(8*18)        ; Sprite register base for shadow rotor (slot 18)
Speedo_sprite_base      = VKY_SP0+(8*0)         ; Sprite register base for speedometer (slot 0, highest priority)
christmas_tree_left     = VKY_SP0+(8*15)        ; Sprite register base for Christmas tree left (slot 15)
christmas_tree_right    = VKY_SP0+(8*16)        ; Sprite register base for Christmas tree right (slot 16)
lamps_base              = VKY_SP0+(8*3)         ; Sprite register base for lamps (slot 3) There are 10 lamps total
player_face             = VKY_SP0+(8*27)        ; Sprite register base for player face (slot 24)
ai_car_0_face           = VKY_SP0+(8*24)        ; Sprite register base for AI car 0 face (slot 25)
ai_car_1_face           = VKY_SP0+(8*25)        ; Sprite register base for AI car 1 face (slot 26)
ai_car_2_face           = VKY_SP0+(8*26)        ; Sprite register base for AI car 2 face (slot 27)


tile_x_offset = 160                     ; Player car screen center X offset (pixels)
tile_y_offset = 136                     ; Player car screen center Y offset (pixels)
ai_x_offset = 24                        ; AI car screen-relative X offset (pixels)
ai_y_offset = 24                        ; AI car screen-relative Y offset (pixels)
heli_x_offset = 16                      ; Helicopter screen-relative X offset (pixels)
heli_y_offset = 16                      ; Helicopter screen-relative Y offset (pixels)
speedo_scale = $20                      ; Speedometer scaling factor

christmas_tree_left_X = 150                  ; Christmas tree X position
christmas_tree_left_Y = 96                 ; Christmas tree Y position
christmas_tree_right_X = 182                ; Christmas tree X position
christmas_tree_right_Y = 96                 ; Christmas tree Y position

lamp1_X   = 147                  ; Lamp 1 X position
lamp1_Y   = 113                  ; Lamp 1 Y position


.cpu "65816"                                  ; set the cpu to Western Digital 65C816
                                              ; even though we are using 65C02 mode, this allows
                                              ; us to use 24 bit addressing for easier memory management
.include "setup.asm"                          ; all of our initial settings


*=$a0                                         ; Set up buffer for Kernel communication
.dsection zp                                  ; Define position for zp (zero page)
.cerror * > $af, "Too many Zero page variables"

.include "api.asm"                           ; This is the Kernel API for communication

; Include the kernel API (kernel call/IPC definitions)
; This file exposes the kernel argument structures and service calls used
; throughout the program (e.g. timer, event queue, Sprite/Video helpers).
; Keeping the API in a separate file keeps the main codebase cleaner and
; makes it easy to update kernel interfaces independently.

;SetupKernel:                                ; Set up the API to work with (conceptual)

; Allocate zero page space for the kernel event structure(s).
; The kernel and many system routines expect a pointer to an event queue
; placed in zero page for fast access. We define `event` here using the
; kernel-provided data structure descriptor so assembler lays out the fields
; correctly.
.section zp                                  ; Zero page section $a0 to $a8
event:  .dstruct    kernel.event.event_t     ; kernel.event.event_t defines the event layout
.send                                       ; mark end of the zero page structure


; **************************************************************************************************************
*=$1000                                ; Set code start address
                                       ; We normally start at $2000 because it is a start of an 8K
                                       ; block of memory. Moving to $1000 gives us 4k more space without
                                       ; any issues.

; **************************************************************************************************************
; start - Main program entry point and hardware initialization
; Purpose: Initialize all game systems including video, audio, memory management, and kernel interface
;          Configure TinyVicky II graphics hardware, load fonts and color tables, setup sprites
; Algorithm:
;   1. Configure kernel event queue pointer in zero page
;   2. Initialize TinyVicky master control registers (graphics/sprites/text)
;   3. Configure 4 tilesets (background, speedometer, title, crowds)
;   4. Setup 3 tilemaps (main game, speedometer overlay, title screen)
;   5. Load custom font to character RAM and apply italic transformation
;   6. Load color lookup table (CLUT) for sprite graphics
;   7. Initialize all game sprites (player, AI cars, helicopter, UI elements)
;   8. Configure audio systems (PSG crowd noise, SID engine sounds)
;   9. Enable random number generator and start background music
;   10. Configure kernel frame timer and enter main event loop
; Inputs: None (reads from data tables in ROM)
; Outputs:
;   All hardware registers configured for gameplay
;   Sprites positioned and ready for display
;   Audio systems initialized
;   Kernel event queue active
; Memory Map:
;   Character RAM: $C100-$C3FF (font data)
;   Graphics CLUT: $D000-$D3FF (color tables)
;   Sprite Registers: $D900-$D9FF (64 sprites × 8 bytes)
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL, all temp variables
; Notes: Never returns - falls through to infinite event loop
; **************************************************************************************************************
start:
    ; **************************************************************************************************************
    ; SECTION 1: Kernel Event Queue Initialization
    ; Purpose: Register event buffer with kernel for timer, keyboard, and joystick events
    ; **************************************************************************************************************
    
    stz MMU_IO_CTRL                          ; Ensure I/O page 0 selected (normal operation mode)
    
    ; --- Setup kernel event queue pointer ---
    ; Kernel expects 16-bit pointer to event structure in kernel.args.events
    ; Point to our zero-page event buffer defined at $A0-$A8
    lda #<event                             ; Load event buffer address low byte
    sta kernel.args.events                  ; Store in kernel args (low byte)
    lda #>event                             ; Load event buffer address high byte
    sta kernel.args.events+1                ; Store in kernel args (high byte)

    ; **************************************************************************************************************
    ; SECTION 2: TinyVicky II Master Control Configuration
    ; Purpose: Enable graphics modes, sprite engine, and text overlay for HUD
    ; **************************************************************************************************************
    
    ; --- Configure Graphics Mode and Display Options ---
    ; Enable bitmap graphics, sprites, tilemaps, and text overlay for HUD
    lda #%00110111                           ; Master control register 0:              |xx|GM|SP|TL|BM|GR|OV|TX|
    sta VKY_MSTR_CTRL_0                      ; Graphics Mode, Sprites, Tiles, Text     | 0| 0| 1| 1| 0| 1| 1| 1|
    
    lda #%00000100                           ; Master control register 1:              |xx|xx|FS|FO|MS|2Y|2X|70|
    sta VKY_MSTR_CTRL_1                      ; 320×240, 60Hz, double Y scan            | 0| 0| 0| 0| 0| 1| 0| 0|
    
    stz VKY_BRDR_CTRL                        ; Disable border (no colored border around screen)
    
    ; --- Set Background Color (Black) ---
    lda #$00                                 ; Black background RGB = (0,0,0)
    sta VKY_BKG_COL_R                        ; Red component = 0
    sta VKY_BKG_COL_G                        ; Green component = 0
    sta VKY_BKG_COL_B                        ; Blue component = 0
    
    jsr clrScreen                            ; Clear text screen (fill with spaces)

    ; **************************************************************************************************************
    ; SECTION 3: Layer Control Configuration
    ; Purpose: Define display priority for 3 tilemap layers (background, speedometer, title)
    ; **************************************************************************************************************
    
    ; --- Layer Priority Assignment ---
    ; Layer 0 (top)    = Tilemap 2 (title screen)
    ; Layer 1 (middle) = Tilemap 1 (speedometer HUD)
    ; Layer 2 (bottom) = Tilemap 0 (race track background)
    lda #%01010110                           ; Layer control 0:                        |xx| LAYER1 |xx| LAYER0 |
    sta VKY_LAYER_CTRL_0                     ; L0=TM2 (title), L1=TM1 (speedo)         | 0| 1| 0| 1| 0| 1| 1| 0|
    lda #%00000100                           ; Layer control 1:                        |xx|xx|xx|xx|xx| LAYER2 |
    sta VKY_LAYER_CTRL_1                     ; L2=TM0 (background)                     | 0| 0| 0| 0| 0| 1| 0| 0|

    ; **************************************************************************************************************
    ; SECTION 4: Tileset Graphics Data Pointers
    ; Purpose: Configure 24-bit pointers to tile graphics data for 4 tilesets
    ; **************************************************************************************************************
    
    ; --- Tileset 0: Race Track Background ---
    ; Contains road tiles, grass, barriers, and track decorations
    lda #<tileset                            ; Load tileset address bits 0-7
    sta VKY_TS0_AD_L                         ; Write to tileset 0 address low
    lda #>tileset                            ; Load tileset address bits 8-15
    sta VKY_TS0_AD_M                         ; Write to tileset 0 address mid
    lda #`tileset                            ; Load tileset address bits 16-23 (bank)
    sta VKY_TS0_AD_H                         ; Write to tileset 0 address high
    
    ; --- Tileset 1: Speedometer and HUD Elements ---
    ; Contains numbers, gauges, and UI graphics for player display
    lda #<speedo_tileset                     ; Load speedometer tileset address low
    sta VKY_TS1_AD_L                         ; Write to tileset 1 address low
    lda #>speedo_tileset                     ; Load speedometer tileset address mid
    sta VKY_TS1_AD_M                         ; Write to tileset 1 address mid
    lda #`speedo_tileset                     ; Load speedometer tileset address high
    sta VKY_TS1_AD_H                         ; Write to tileset 1 address high
    
    ; --- Tileset 2: Title Screen Graphics ---
    ; Contains logo, menu text, and title screen decorative elements
    lda #<title_tileset                      ; Load title tileset address low
    sta VKY_TS2_AD_L                         ; Write to tileset 2 address low
    lda #>title_tileset                      ; Load title tileset address mid
    sta VKY_TS2_AD_M                         ; Write to tileset 2 address mid
    lda #`title_tileset                      ; Load title tileset address high
    sta VKY_TS2_AD_H                         ; Write to tileset 2 address high
    
    ; --- Tileset 3: Animated Crowd Sprites ---
    ; Contains crowd animation frames for trackside spectators
    lda #<crowd_tileset                      ; Load crowd tileset address low
    sta VKY_TS3_AD_L                         ; Write to tileset 3 address low
    lda #>crowd_tileset                      ; Load crowd tileset address mid
    sta VKY_TS3_AD_M                         ; Write to tileset 3 address mid
    lda #`crowd_tileset                      ; Load crowd tileset address high
    sta VKY_TS3_AD_H                         ; Write to tileset 3 address high

    ; **************************************************************************************************************
    ; SECTION 5: Tilemap Configuration and Positioning
    ; Purpose: Configure tilemap dimensions, data pointers, and screen positions
    ; **************************************************************************************************************
    
    ; --- Tilemap 0: Race Track Background (50×41 tiles, 16×16 pixels each) ---
    ; Main game area tilemap, scrolls with player movement
    lda #%00000001                           ; Tilemap control: 16×16 tiles, enabled      |xx|xx|xx|TS|xx|xx|xx|EN|
    sta VKY_TM0_CTRL                         ;                                            | 0| 0| 0| 0| 0| 0| 0| 1|
    lda #50                                  ; Tilemap width in tiles (50 tiles = 800 pixels)
    sta VKY_TM0_SZ_X                         ; Write to size X register
    lda #41                                  ; Tilemap height in tiles (41 tiles = 656 pixels)
    sta VKY_TM0_SZ_Y                         ; Write to size Y register
    
    lda #<tilemap                            ; Load tilemap data address bits 0-7
    sta VKY_TM0_AD_L                         ; Write to tilemap 0 address low
    lda #>tilemap                            ; Load tilemap data address bits 8-15
    sta VKY_TM0_AD_M                         ; Write to tilemap 0 address mid
    lda #`tilemap                            ; Load tilemap data address bits 16-23
    sta VKY_TM0_AD_H                         ; Write to tilemap 0 address high
    
    ; --- Tilemap 1: Speedometer HUD (20×15 tiles, 16×16 pixels each) ---
    ; Fixed position overlay for player information display
    lda #%00000001                           ; Tilemap control: 16×16 tiles, enabled      |xx|xx|xx|TS|xx|xx|xx|EN|
    sta VKY_TM1_CTRL                         ;                                            | 0| 0| 0| 0| 0| 0| 0| 1|
    lda #20                                  ; Tilemap width in tiles (20 tiles = 320 pixels)
    sta VKY_TM1_SZ_X                         ; Write to size X register
    lda #15                                  ; Tilemap height in tiles (15 tiles = 240 pixels)
    sta VKY_TM1_SZ_Y                         ; Write to size Y register
    
    lda #<speedo_tilemap                     ; Load speedometer tilemap address low
    sta VKY_TM1_AD_L                         ; Write to tilemap 1 address low
    lda #>speedo_tilemap                     ; Load speedometer tilemap address mid
    sta VKY_TM1_AD_M                         ; Write to tilemap 1 address mid
    lda #`speedo_tilemap                     ; Load speedometer tilemap address high
    sta VKY_TM1_AD_H                         ; Write to tilemap 1 address high
    
    stz VKY_TM1_POS_X_L                      ; Position tilemap at screen origin X=0
    stz VKY_TM1_POS_X_H                      ; (high byte = 0)
    stz VKY_TM1_POS_Y_L                      ; Position tilemap at screen origin Y=0
    stz VKY_TM1_POS_Y_H                      ; (high byte = 0)
    
    ; --- Tilemap 2: Title Screen (20×15 tiles, 16×16 pixels each) ---
    ; Animated title screen, starts at Y=0 and scrolls off during gameplay
    lda #%00000001                           ; Tilemap control: 16×16 tiles, enabled      |xx|xx|xx|TS|xx|xx|xx|EN|
    sta VKY_TM2_CTRL                         ;                                            | 0| 0| 0| 0| 0| 0| 0| 1|
    lda #20                                  ; Tilemap width in tiles (20 tiles = 320 pixels)
    sta VKY_TM2_SZ_X                         ; Write to size X register
    lda #15                                  ; Tilemap height in tiles (15 tiles = 240 pixels)
    sta VKY_TM2_SZ_Y                         ; Write to size Y register
    
    lda #<title_tilemap                      ; Load title tilemap address low
    sta VKY_TM2_AD_L                         ; Write to tilemap 2 address low
    lda #>title_tilemap                      ; Load title tilemap address mid
    sta VKY_TM2_AD_M                         ; Write to tilemap 2 address mid
    lda #`title_tilemap                      ; Load title tilemap address high
    sta VKY_TM2_AD_H                         ; Write to tilemap 2 address high
    
    stz VKY_TM2_POS_X_L                      ; Position tilemap at screen origin X=0
    stz VKY_TM2_POS_X_H                      ; (high byte = 0)
    stz VKY_TM2_POS_Y_L                      ; Position tilemap at screen origin Y=0
    stz VKY_TM2_POS_Y_H                      ; (high byte = 0)

    ; **************************************************************************************************************
    ; SECTION 6: Custom Font Loading and Transformation
    ; Purpose: Load custom bitmap font to character RAM and apply italic slant effect
    ; **************************************************************************************************************

; **************************************************************************************************************
; setFont - Load custom font into character RAM
; Purpose: Copy 3 pages (768 bytes) of font data from ROM to character memory at $C100
;          Each character is 8×8 pixels, 256 characters total
; Algorithm:
;   1. Setup source pointer to font data in ROM
;   2. Setup destination pointer to $C100 (character RAM)
;   3. Switch to I/O page 1 (character memory access)
;   4. Copy 3 complete pages (256 bytes each) using Y-indexed loop
;   5. Restore I/O page 0 (normal operation)
; Inputs:
;   font = Source data table in ROM (768 bytes)
; Outputs:
;   Character RAM at $C100-$C3FF filled with font bitmap data
; Memory Layout:
;   Each character: 8 bytes (1 byte per scanline)
;   Total: 256 chars × 8 bytes = 2048 bytes (uses first 768 bytes)
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL
; **************************************************************************************************************
setFont:
    ; --- Setup source pointer to font data in ROM ---
	lda #<font                               ; Load font data address low byte
	sta ptr_src                              ; Store in source pointer low
	lda #>font                               ; Load font data address high byte
	sta ptr_src+1                            ; Store in source pointer high
	
	; --- Setup destination pointer to character RAM ---
	lda #$c1                                 ; Destination = $C100 (character RAM start)
	stz ptr_dst                              ; Set destination pointer low = $00
	sta ptr_dst+1                            ; Set destination pointer high = $C1
	
	; --- Initialize loop counters ---
	ldy #$00                                 ; Y = byte offset within page (0-255)
    ldx #$03                                 ; X = page counter (3 pages = 768 bytes)
    
    ; --- Switch to I/O page 1 for character RAM access ---
	lda #$01                                 ; Select I/O page 1 (character/color memory)
	sta MMU_IO_CTRL                          ; Write to MMU control register
	
_sfLoop:
    ; --- Copy one byte from font data to character RAM ---
	lda (ptr_src),y                          ; Read byte from font source data
	sta (ptr_dst),y                          ; Write byte to character RAM destination
	iny                                      ; Increment byte offset (0→255)
	bne _sfLoop                              ; If not wrapped, continue page copy
	
	; --- Advance to next page (both source and destination) ---
	inc ptr_src+1                            ; Increment source address high byte
	inc ptr_dst+1                            ; Increment destination address high byte
	dex                                      ; Decrement page counter
	bne _sfLoop                              ; If more pages remain, continue loop
	
	; --- Restore I/O page 0 (normal operation) ---
	stz MMU_IO_CTRL                          ; Switch back to I/O page 0

; **************************************************************************************************************
; loop_italics - Apply italic slant transformation to loaded font
; Purpose: Modify character bitmaps in-place to create italic effect by shifting pixel rows
;          Creates slanted appearance by shifting top rows left and bottom rows right
; Algorithm:
;   1. Process each character (768 bytes total)
;   2. For each 8-byte character:
;      - Shift rows 0-2 right by 2,1,1 pixels (top of character leans left)
;      - Leave rows 3-4 unchanged (middle stays centered)
;      - Shift rows 5-7 left by 1,1,2 pixels (bottom leans right)
;   3. Advance pointer by 8 bytes to next character
;   4. Repeat until pointer reaches $C400 (end of font region)
; Inputs:
;   Character RAM at $C100-$C3FF contains loaded font data
; Outputs:
;   Character RAM modified with italic slant applied to all characters
; Method:
;   Row shifts: [>>2, >>1, >>1, 0, 0, <<1, <<1, <<2]
;   Creates approximately 15° slant angle
; Clobbers: A, Y, ptr_dst, MMU_IO_CTRL
; **************************************************************************************************************
    ; --- Switch to I/O page 1 for character RAM access ---
    lda #$01                                 ; Select I/O page 1 (character/color memory)
    sta MMU_IO_CTRL                          ; Write to MMU control register
    
    ; --- Setup pointer to start of character RAM ---
    lda #$00                                 ; Start at $C100 (character data region)
    sta ptr_dst                              ; Set pointer low byte = $00
    lda #$c1                                 ; Set pointer high byte = $C1
    sta ptr_dst+1                            ; Pointer now points to $C100
    
loop_italics:
    ldy #$00                                 ; Y = scanline offset within character (0-7)
    
    ; --- Top scanline (row 0): Shift right 2 pixels (lean left) ---
    lda (ptr_dst),y                          ; Read scanline 0 bitmap
    lsr                                      ; Shift right 1 pixel
    lsr                                      ; Shift right 1 pixel (total: 2 pixels)
    sta (ptr_dst),y                          ; Write modified scanline back
    iny                                      ; Advance to scanline 1
    
    ; --- Upper scanline (row 1): Shift right 1 pixel ---
    lda (ptr_dst),y                          ; Read scanline 1 bitmap
    lsr                                      ; Shift right 1 pixel
    sta (ptr_dst),y                          ; Write modified scanline back
    iny                                      ; Advance to scanline 2
    
    ; --- Upper-middle scanline (row 2): Shift right 1 pixel ---
    lda (ptr_dst),y                          ; Read scanline 2 bitmap
    lsr                                      ; Shift right 1 pixel
    sta (ptr_dst),y                          ; Write modified scanline back
    iny                                      ; Advance to scanline 3
    
    ; --- Middle scanlines (rows 3-4): No shift (leave unchanged) ---
    iny                                      ; Skip scanline 3 (Y=3→4)
    iny                                      ; Skip scanline 4 (Y=4→5)
    
    ; --- Lower-middle scanline (row 5): Shift left 1 pixel (lean right) ---
    lda (ptr_dst),y                          ; Read scanline 5 bitmap
    asl                                      ; Shift left 1 pixel
    sta (ptr_dst),y                          ; Write modified scanline back
    iny                                      ; Advance to scanline 6
    
    ; --- Lower scanline (row 6): Shift left 1 pixel ---
    lda (ptr_dst),y                          ; Read scanline 6 bitmap
    asl                                      ; Shift left 1 pixel
    sta (ptr_dst),y                          ; Write modified scanline back
    iny                                      ; Advance to scanline 7
    
    ; --- Bottom scanline (row 7): Shift left 2 pixels (lean right) ---
    lda (ptr_dst),y                          ; Read scanline 7 bitmap
    asl                                      ; Shift left 1 pixel
    asl                                      ; Shift left 1 pixel (total: 2 pixels)
    sta (ptr_dst),y                          ; Write modified scanline back
    
    ; --- Advance to next character (8 bytes per character) ---
    clc                                      ; Clear carry for 16-bit addition
    lda ptr_dst                              ; Load pointer low byte
    adc #$08                                 ; Add 8 (one character size)
    sta ptr_dst                              ; Store updated pointer low
    lda ptr_dst+1                            ; Load pointer high byte
    adc #$00                                 ; Add carry if any
    sta ptr_dst+1                            ; Store updated pointer high
    
    ; --- Check if done (reached $C400 = end of font region) ---
    cmp #$c4                                 ; Compare high byte with $C4
    bcc loop_italics                         ; If less than $C4, continue loop
    
    ; --- Restore I/O page 0 (normal operation) ---
    stz MMU_IO_CTRL                          ; Switch back to I/O page 0

  
; **************************************************************************************************************
; makeClut - Load color lookup table into graphics CLUT
; Purpose: Copy sprite color palette from ROM to hardware CLUT registers for sprite rendering
;          Each color is 4 bytes (Blue, Red, Green, Alpha) in BGRA format
; Algorithm:
;   1. Switch to I/O page 1 (CLUT memory access)
;   2. Setup source pointer to CLUT0 data table in ROM
;   3. Setup destination pointer to VKY_GR_CLUT_0 hardware registers
;   4. Initialize color counter (154 colors total)
;   5. For each color:
;      a. Copy 4 bytes (BGRA components) using indexed loop
;      b. Advance source pointer by 4 bytes to next color
;      c. Advance destination pointer by 4 bytes to next CLUT slot
;   6. Restore I/O page 0 (normal operation)
; Inputs:
;   CLUT0 = Source color table in ROM (154 colors × 4 bytes = 616 bytes)
; Outputs:
;   VKY_GR_CLUT_0 filled with 154 color entries for sprite rendering
; Color Format:
;   Each color entry is 4 bytes in BGRA order:
;   Byte 0: Blue component (0-255)
;   Byte 1: Red component (0-255)
;   Byte 2: Green component (0-255)
;   Byte 3: Alpha component (0=transparent, 255=opaque)
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL, totalColors
; Notes: Must be called during initialization before enabling sprites
; **************************************************************************************************************

    ; --- Switch to I/O page 1 for CLUT register access ---
    lda #$01                                 ; Select I/O page 1 (color/character memory)
    sta MMU_IO_CTRL                          ; Write to MMU control register
    
    ; --- Setup source pointer to color data in ROM ---
    lda #<CLUT0                              ; Load CLUT0 data address low byte
    sta ptr_src                              ; Store in source pointer low
    lda #>CLUT0                              ; Load CLUT0 data address high byte
    sta ptr_src+1                            ; Store in source pointer high

    ; --- Setup destination pointer to hardware CLUT registers ---
    lda #<VKY_GR_CLUT_0                      ; Load graphics CLUT address low byte
    sta ptr_dst                              ; Store in destination pointer low
    lda #>VKY_GR_CLUT_0                      ; Load graphics CLUT address high byte
    sta ptr_dst+1                            ; Store in destination pointer high

    ; --- Initialize loop counters ---
    ldx #$00                                 ; X = current color index (0-153)
    ldy #154                                 ; Y = total color count (154 colors)

makeClut:
    ; --- Store total color count for loop comparison ---
    sty totalColors                          ; Save color count to memory variable

color_loop:
    ; --- Copy 4-byte color entry (BGRA components) ---
    ldy #$00                                 ; Y = byte offset within color (0-3)
    
comp_loop:
    ; --- Copy one color component byte ---
    lda (ptr_src),y                          ; Read byte from source color table
    sta (ptr_dst),y                          ; Write byte to hardware CLUT register
    iny                                      ; Advance to next component (B→R→G→A)
    cpy #$04                                 ; Have we copied all 4 components?
    bne comp_loop                            ; If not, continue component loop

    ; --- Check if all colors copied ---
    inx                                      ; Increment color index
    cpx totalColors                          ; Have we copied all 154 colors?
    beq done_lut                             ; If yes, exit loop

    ; --- Advance source pointer to next color (add 4 bytes) ---
    clc                                      ; Clear carry for 16-bit addition
    lda ptr_src                              ; Load source pointer low byte
    adc #$04                                 ; Add 4 (size of one color entry)
    sta ptr_src                              ; Store updated pointer low
    lda ptr_src+1                            ; Load source pointer high byte
    adc #$00                                 ; Add carry if any
    sta ptr_src+1                            ; Store updated pointer high

    ; --- Advance destination pointer to next CLUT slot (add 4 bytes) ---
    clc                                      ; Clear carry for 16-bit addition
    lda ptr_dst                              ; Load destination pointer low byte
    adc #$04                                 ; Add 4 (size of one CLUT slot)
    sta ptr_dst                              ; Store updated pointer low
    lda ptr_dst+1                            ; Load destination pointer high byte
    adc #$00                                 ; Add carry if any
    sta ptr_dst+1                            ; Store updated pointer high

    jmp color_loop                           ; Loop back to copy next color

done_lut:
    ; --- Restore I/O page 0 (normal operation) ---
    stz MMU_IO_CTRL                          ; Switch back to I/O page 0


; **************************************************************************************************************
; SPRITE INITIALIZATION SYSTEM
; **************************************************************************************************************
; Purpose: Configure all game sprites (cars, helicopter, UI elements) in hardware sprite slots
;          Sets up sprite graphics addresses, screen positions, sizes, and enable flags
; Process:
;   1. Configure player car sprite (slot 20) - blue car at center position
;   2. Initialize 3 AI opponent cars (slots 21-23) at starting grid positions
;   3. Setup speedometer needle sprite (slot 0, highest priority)
;   4. Configure Christmas tree/light structure (slots 15-16)
;   5. Place 10 lamp sprites (slots 3-12) at predefined track positions
;   6. Initialize crowd audio effect (PSG noise channel)
;   7. Setup SID engine sound effects for player car (2 voices)
;   8. Enable random number generator for AI behavior
;   9. Initialize music system and frame timer
; Hardware:
;   Writes to VKY_SP0 sprite registers (8 bytes per slot × 64 slots)
;   Each sprite slot controls: address pointer, X/Y position, control flags
; Memory Map:
;   Sprite graphics data located in bank $01 (above $10000)
;   Sprite register base = VKY_SP0 ($D900), slot N = VKY_SP0 + (8*N)
; Notes:
;   Lower slot numbers have higher display priority (drawn on top)
;   Player car uses index-based position updates (updatePos/aiCarsMove)
;   AI cars copy starting positions from aicar_start_X/Y arrays
; Clobbers: A, X, Y, ptr_src, ptr_dst, various sprite registers
; **************************************************************************************************************

; ============================================================================
; PLAYER CAR SPRITE SETUP (Slot 20)
; ============================================================================
; Configure blue player car sprite at screen center position
; Sprite will be repositioned every frame via updatePos routine
; Size: 16×16 pixels, Priority: Slot 20 (lower than UI, higher than shadows)
; ============================================================================

    ; --- Set sprite control flags ---
    lda #%01010001                      ; Sprite control byte breakdown:
                                        ; Bit 0 (EN): 1 = Enable sprite
                                        ; Bits 1-2 (LU): 0 = No LUT (direct color)
                                        ; Bits 3-4 (LA): 0 = Layer 0
                                        ; Bits 5-6 (SZ): 10 = 16×16 pixel size
                                        ; Bit 7: Reserved (0)
    sta car_sprite_base+SP_CTRL         ; Write to sprite slot 20 control register
    
    ; --- Set sprite graphics address (24-bit pointer to blue car graphics) ---
    lda #<blue_car1                     ; Load graphics address low byte
    sta car_sprite_base+SP_AD_L         ; Write to sprite address register (bits 0-7)
    lda #>blue_car1                     ; Load graphics address mid byte
    sta car_sprite_base+SP_AD_M         ; Write to sprite address register (bits 8-15)
    lda #`blue_car1                     ; Load graphics address high byte (bank 1)
    sta car_sprite_base+SP_AD_H         ; Write to sprite address register (bits 16-23)
    
    ; --- Set sprite initial screen position (center of viewport) ---
    lda #184                            ; Initial X position (184 pixels from left)
    sta car_sprite_base+SP_POS_X_L      ; Write X position low byte
    stz car_sprite_base+SP_POS_X_H      ; Clear X position high byte (0-511 range)
    lda #160                            ; Initial Y position (160 pixels from top)
    sta car_sprite_base+SP_POS_Y_L      ; Write Y position low byte
    stz car_sprite_base+SP_POS_Y_H      ; Clear Y position high byte (0-511 range)
    
    ; --- Update initial tilemap scroll based on player position ---
    jsr updatePos                       ; Calculate tilemap offset from world coordinates
    jsr ai_setup                       ; Initialize AI opponent cars




; ============================================================================
; SPEEDOMETER NEEDLE SPRITE SETUP (Slot 0 - Highest Priority)
; ============================================================================
; Configure speedometer needle sprite for HUD display
; Slot 0 ensures needle appears on top of all other sprites
; Size: 8×8 pixels, Position: Top-left corner of speedometer graphic
; ============================================================================

    ; --- Set sprite control flags ---
    lda #%01101001                      ; Sprite control byte breakdown:
                                        ; Bit 0 (EN): 1 = Enable sprite
                                        ; Bits 1-2 (LU): 0 = No LUT
                                        ; Bits 3-4 (LA): 2 = Layer 2 (UI layer)
                                        ; Bits 5-6 (SZ): 11 = 8×8 pixel size
                                        ; Bit 7: Reserved (0)
    sta Speedo_sprite_base+SP_CTRL      ; Write to sprite slot 0 control register
    
    ; --- Set sprite graphics address (24-bit pointer to needle graphic) ---
    lda #<speed_needle                  ; Load graphics address low byte
    sta Speedo_sprite_base+SP_AD_L      ; Write to sprite address register (bits 0-7)
    lda #>speed_needle                  ; Load graphics address mid byte
    sta Speedo_sprite_base+SP_AD_M      ; Write to sprite address register (bits 8-15)
    lda #`speed_needle                  ; Load graphics address high byte (bank 2)
    sta Speedo_sprite_base+SP_AD_H      ; Write to sprite address register (bits 16-23)
    
    ; --- Set sprite screen position (speedometer location in HUD) ---
    lda #102                            ; X position (102 pixels from left edge)
    sta Speedo_sprite_base+SP_POS_X_L   ; Write X position low byte
    stz Speedo_sprite_base+SP_POS_X_H   ; Clear X position high byte
    lda #3                              ; Y position (3 pixels from top edge)
    sta Speedo_sprite_base+SP_POS_Y_L   ; Write Y position low byte
    lda #1                              ; Y position high byte (256 + 3 = 259 total)
    sta Speedo_sprite_base+SP_POS_Y_H   ; Write Y position high byte


; ============================================================================
; CHRISTMAS TREE STRUCTURE SETUP (Slots 15-16) - Initially Disabled
; ============================================================================
; Configure starting light structure sprites (left and right posts)
; Sprites start disabled and animate down from top during race countdown
; Size: 32×32 pixels each, Position: Controlled by move_tree_in routine
; Note: Control flags commented out - sprites enabled during countdown sequence
; ============================================================================

    ; --- Set sprite graphics addresses (both trees use different graphics) ---
    ; Left tree structure
    lda #<tree_left_sprite              ; Load left tree graphics address low byte
    sta christmas_tree_left+SP_AD_L     ; Write to slot 15 address register (low)
    lda #>tree_left_sprite              ; Load left tree graphics address mid byte
    sta christmas_tree_left+SP_AD_M     ; Write to slot 15 address register (mid)
    lda #`tree_left_sprite              ; Load left tree graphics address high byte (bank)
    sta christmas_tree_left+SP_AD_H     ; Write to slot 15 address register (high)
    
    ; Right tree structure
    lda #<tree_right_sprite             ; Load right tree graphics address low byte
    sta christmas_tree_right+SP_AD_L    ; Write to slot 16 address register (low)
    lda #>tree_right_sprite             ; Load right tree graphics address mid byte
    sta christmas_tree_right+SP_AD_M    ; Write to slot 16 address register (mid)
    lda #`tree_right_sprite             ; Load right tree graphics address high byte (bank)
    sta christmas_tree_right+SP_AD_H    ; Write to slot 16 address register (high)

    ; --- Set sprite initial screen positions (using constants) ---
    ; Left tree X position
    lda <#christmas_tree_left_X         ; Load X position low byte from constant
    sta christmas_tree_left+SP_POS_X_L  ; Write to slot 15 X position (low)
    lda >#christmas_tree_left_X         ; Load X position high byte from constant
    sta christmas_tree_left+SP_POS_X_H  ; Write to slot 15 X position (high)
    
    ; Right tree X position
    lda <#christmas_tree_right_X        ; Load X position low byte from constant
    sta christmas_tree_right+SP_POS_X_L ; Write to slot 16 X position (low)
    lda >#christmas_tree_right_X        ; Load X position high byte from constant
    sta christmas_tree_right+SP_POS_X_H ; Write to slot 16 X position (high)

    ; Y positions (both start at Y=0, off-screen top)
    stz christmas_tree_left+SP_POS_Y_L  ; Clear left tree Y position low byte
    stz christmas_tree_left+SP_POS_Y_H  ; Clear left tree Y position high byte
    stz christmas_tree_right+SP_POS_Y_L ; Clear right tree Y position low byte
    stz christmas_tree_right+SP_POS_Y_H ; Clear right tree Y position high byte

; ============================================================================
; STARTING LIGHT LAMPS SETUP (Slots 3-12) - Initially Disabled
; ============================================================================
; Configure 10 lamp sprites arranged on Christmas tree structure (5 per side)
; Lamps illuminate sequentially during race countdown (handled by countdown_start)
; Size: 8×8 pixels each, Positions: Read from lamp_table_X/Y arrays
; Graphics: All lamps use same red_light graphic initially
; Note: Control flags commented out - lamps enabled during countdown sequence
; ============================================================================

    ; --- Initialize lamp placement loop ---
    ldx #$00                            ; Set loop counter to 0 (first lamp)
    
lamp_loop:
    ; --- Calculate sprite register offset for this lamp ---
    ; Each sprite slot = 8 bytes, so slot N offset = N × 8
    txa                                 ; Transfer lamp index to A
    asl                                 ; Multiply by 2
    asl                                 ; Multiply by 4
    asl                                 ; Multiply by 8 (final offset)
    tay                                 ; Transfer offset to Y for indexed addressing

    ; --- Set lamp graphics address (all lamps use same graphic) ---
    lda #<red_light                     ; Load lamp graphics address low byte
    sta lamps_base+SP_AD_L,y            ; Write to lamp sprite address (low)
    lda #>red_light                     ; Load lamp graphics address mid byte
    sta lamps_base+SP_AD_M,y            ; Write to lamp sprite address (mid)
    lda #`red_light                     ; Load lamp graphics address high byte (bank)
    sta lamps_base+SP_AD_H,y            ; Write to lamp sprite address (high)
    
    ; --- Set lamp screen position (read from position tables) ---
    lda lamp_table_X,x                  ; Read X position from table (indexed by lamp #)
    sta lamps_base+SP_POS_X_L,y         ; Write to lamp sprite X position (low)
    lda #0                              ; X position high byte = 0 (all lamps < 256)
    sta lamps_base+SP_POS_X_H,y         ; Write to lamp sprite X position (high)
    lda lamp_table_Y,x                  ; Read Y position from table (indexed by lamp #)
    sta lamps_base+SP_POS_Y_L,y         ; Write to lamp sprite Y position (low)
    lda #0                              ; Y position high byte = 0 (all lamps < 256)
    sta lamps_base+SP_POS_Y_H,y         ; Write to lamp sprite Y position (high)
    
    ; --- Advance to next lamp ---
    inx                                 ; Increment lamp counter (0→1→2...→9)
    cpx #10                             ; Have we placed all 10 lamps?
    bne lamp_loop                       ; If not, loop back to place next lamp


; ============================================================================
; AUDIO SYSTEM INITIALIZATION
; ============================================================================
; Configure sound effects and music for racing gameplay
; Systems: PSG (crowd noise), SID (engine sounds, music)
; ============================================================================

; --- PSG: Crowd Noise Effect (Noise Channel on PSG_L) ---
; Uses white noise generator for ambient crowd ambience
; Volume controlled by crowd_volume variable (modulated by race position)
    lda #$ff                            ; Load zero volume + noise enable
    sta PSG_L                           ; Write to PSG Left control register
    and #$0f                            ; Mask to volume bits only (0-15)
    sta crowd_volume                    ; Store initial crowd volume level
    lda #$e5                            ; Load noise frequency value (pitch)
    sta PSG_L                           ; Write to PSG Left frequency register

; --- PSG: Helicopter Sound Effect (Tone Channel on PSG_R) ---
; Simple square wave tone for helicopter overhead sound
; Volume controlled by distace to helicopter (modulated in main loop)
    lda #$c0                            ; set low 4 bits to 0 (volume 0), enable tone channel 3
    sta PSG_R                           ; Write to PSG Right register
    lda #$20                            ; set frequency high 6 bits for tone channel 3
    sta PSG_R                           ; Write to PSG Right control register
    lda #$df                            ; set attenuation to zero (no attenuation) for tone channel 3
    sta PSG_R                           ; Write to PSG Right control register


    
; --- SID: Engine Sound Effects (2-Voice Pulse Wave) ---
; Voice 1 and 2 create rich engine rumble effect
; Frequency modulated by player speed in main loop
; Uses pulse waveform with ADSR envelope for realistic engine tone
    
    ; Master volume
    lda #$0f                            ; Load maximum SID volume (15)
    sta SID_R_VOL                       ; Write to SID Right volume register
    
    ; ADSR envelope (Attack/Decay/Sustain/Release) for both voices
    lda #$f8                            ; Load ADSR: Fast attack (F), medium decay (8)
    sta SID_R1_ATDL                     ; Write to Voice 1 Attack/Decay register
    sta SID_R2_ATDL                     ; Write to Voice 2 Attack/Decay register
    lda #$94                            ; Load ADSR: High sustain (9), medium release (4)
    sta SID_R1_STRL                     ; Write to Voice 1 Sustain/Release register
    lda #$54                            ; Load ADSR: Medium sustain (5), medium release (4)
    sta SID_R2_STRL                     ; Write to Voice 2 Sustain/Release register
    
    ; Voice 1 initial frequency (bass component)
    lda #$23                            ; Load frequency low byte (base pitch)
    sta SID_R1_FREQ_L                   ; Write to Voice 1 frequency register (low)
    lda #$02                            ; Load frequency high byte
    sta SID_R1_FREQ_H                   ; Write to Voice 1 frequency register (high)
    
    ; Voice 1 pulse width (timbre control)
    lda #$08                            ; Load pulse width high byte (duty cycle)
    sta SID_R1_PULS_H                   ; Write to Voice 1 pulse width (high)
    stz SID_R1_PULS_L                   ; Clear pulse width low byte
    
    ; Voice 2 initial frequency (harmonic component, ~2x Voice 1)
    lda #$58                            ; Load frequency low byte (higher pitch)
    sta SID_R2_FREQ_L                   ; Write to Voice 2 frequency register (low)
    lda #$05                            ; Load frequency high byte
    sta SID_R2_FREQ_H                   ; Write to Voice 2 frequency register (high)

; --- SID: collision sound effect setup (Voice 3) ---
; Simple noise burst for collision events (triggered in main loop)
    
    ; ADSR envelope for collision sound (quick attack, short decay)
    lda #$0a                            ; Load ADSR: Fast attack (0), short decay (8)
    sta SID_R3_ATDL                     ; Write to Voice 3 Attack/Decay register
    lda #$08                            ; Load ADSR: no sustain (0), short release (8)
    sta SID_R3_STRL                     ; Write to Voice 3 Sustain/Release register
    
    ; Voice 3 initial frequency (noise component)
    lda #$00                            ; Load frequency low byte
    sta SID_R3_FREQ_L                   ; Write to Voice 3 frequency register (low)
    lda #$20                            ; Load frequency high byte
    sta SID_R3_FREQ_H                   ; Write to Voice 3 frequency register (high)

; ============================================================================
; SYSTEM INITIALIZATION
; ============================================================================
; Initialize random number generator and background music system
; Setup kernel frame timer for game loop synchronization
; ============================================================================

; --- Random Number Generator ---
; Enable hardware RNG for AI behavior and crowd animation
    lda #$01                            ; Load RNG enable flag
    sta Random_Reg                      ; Write to random number generator control register
    
; --- Background Music System ---
; Initialize GoatTracker music driver (loaded at $A000)
    jsr init_music                      ; Call music initialization routine

; --- Frame Timer Setup ---
; Configure kernel timer for 60Hz game loop (Start Of Frame events)
    lda #kernel.args.timer.FRAMES       ; Load timer mode: Frame-based timing
    ora #kernel.args.timer.QUERY        ; OR with query flag to read current frame
    sta kernel.args.timer.units         ; Write to timer units parameter
    jsr kernel.Clock.SetTimer           ; Call kernel timer setup routine
    bcs skipSet                         ; If error (carry set), skip frame storage
    sta $d0                             ; Store current frame number to ZP variable
skipSet:
    jsr SetTimer                        ; Schedule first timer event for game loop


; **************************************************************************************************************

; **************************************************************************************************************
; MAIN GAME LOOP
; **************************************************************************************************************
; Purpose: Primary execution loop that continuously processes kernel events and updates game state
; Method: Infinite loop calling event handler, never returns to caller
; Entry: Called from initialization code after all systems are configured
; Exit: Never exits (infinite loop)
; Notes: All game logic is driven by kernel events (timer, joystick, keyboard)
; **************************************************************************************************************

loop:
    jsr handle_events                        ; Process all pending kernel events and dispatch handlers
    bra loop                                 ; Loop infinitely (kernel events drive all game logic)


; ==============================================================================
; handle_events - Kernel event queue processor
; Purpose: Poll kernel event queue and dispatch events to appropriate handlers
; Method: Checks for pending events, retrieves next event, calls dispatcher
; Entry: Called from main loop every iteration
; Exit: Returns when event queue is empty
; Uses: kernel.args.events.pending, kernel.NextEvent API call
; Notes: Processes all pending events in queue before returning
; ==============================================================================
handle_events:
    lda kernel.args.events.pending           ; Check if any events are waiting in kernel queue
    bpl done_handle_events                   ; If bit 7 clear (no events), exit handler
    jsr kernel.NextEvent                     ; Retrieve next event from kernel queue
    bcs done_handle_events                   ; If carry set (error/no event), exit handler
    jsr dispatch                             ; Route event to appropriate handler routine
    jmp handle_events                        ; Loop back to process any remaining events
done_handle_events:
    rts     


; ==============================================================================
; dispatch - Event type router
; Purpose: Examine event type field and branch to appropriate handler routine
; Method: Compare event.type against known event constants, branch on match
; Entry: Event data loaded in event structure by kernel.NextEvent
; Exit: Returns after calling specific event handler (or immediately if unknown)
; Handles:
;   - kernel.event.timer.EXPIRED  -> UpdateScreen (main frame update)
;   - kernel.event.key.PRESSED    -> keypress (keyboard input)
;   - kernel.event.JOYSTICK       -> setJoyStick (joystick state change)
; Uses: event.type from kernel event structure
; ==============================================================================
dispatch:
    lda event.type                           ; Load event type identifier from kernel event structure
    cmp #kernel.event.timer.EXPIRED          ; Is this a timer expiration event (SOF)?
    beq UpdateScreen                         ; Yes - run main frame update routine
    cmp #kernel.event.key.PRESSED            ; Is this a keyboard key press event?
    beq keypress                             ; Yes - handle keyboard input
    cmp #kernel.event.JOYSTICK               ; Is this a joystick state change event?
    beq setJoyStick                          ; Yes - update joystick state variables
    rts                                      ; Unknown event type - ignore and return

; **************************************************************************************************************
; keypress - Keyboard input handler (currently unused)
; **************************************************************************************************************
; Purpose: Process keyboard input events
; Entry: Called from dispatch when kernel.event.key.PRESSED detected
; Exit: Returns immediately (no keyboard handling implemented yet)
; Notes: Placeholder for future keyboard controls
; **************************************************************************************************************
keypress:
    rts

; **************************************************************************************************************
; JOYSTICK INPUT PROCESSING SYSTEM
; **************************************************************************************************************
; Purpose: Decode joystick state from kernel event and convert to normalized directional values
; Method: Test individual direction bits from event.joystick.joy1 and set joyX/joyY accordingly
;         Button press includes debounce logic to prevent multiple triggers from single press
; Entry: Called from dispatch when kernel.event.JOYSTICK event detected
;        event.joystick.joy1 contains current joystick state bitmap
; Exit: Updates joyX ($FF=left, $00=center, $01=right)
;       Updates joyY ($FF=up, $00=center, $01=down)  
;       Updates joyB ($01=button pressed, $00=not pressed)
;       Updates joyBhold (debounce flag to prevent repeat triggers)
; Joystick Bit Map (event.joystick.joy1):
;   Bit 0 ($01): Up direction
;   Bit 1 ($02): Down direction
;   Bit 2 ($04): Left direction
;   Bit 3 ($08): Right direction
;   Bit 4 ($10): Button 0 (fire/action)
; Variables:
;   JoyEvent - Temporary storage for joystick state during processing
;   GO - Game state flag (if non-zero, skips directional input, only checks button)
;   joyBhold - Button debounce flag (prevents multiple triggers per press)
; Notes: Directional inputs are mutually exclusive (vertical and horizontal separately)
;        Button debounce ensures single action per press (requires release before re-trigger)
; Clobbers: A register
; **************************************************************************************************************

; ==============================================================================
; setJoyStick - Main joystick state decoder
; Purpose: Convert kernel joystick event bitmap to normalized direction values
; Entry: event.joystick.joy1 loaded by kernel with current joystick state
; Exit: joyX/joyY/joyB updated with normalized values (-1, 0, +1)
; ==============================================================================
setJoyStick:
	lda event.joystick.joy1              ; Load joystick state bitmap from kernel event structure
	sta JoyEvent                         ; Save to temporary variable for repeated testing
	stz joyX                             ; Clear X axis input (assume no horizontal movement)
	stz joyY                             ; Clear Y axis input (assume no vertical movement)
	stz joyB                             ; Clear button state (assume not pressed)
	lda GO                               ; Check game state flag (race started?)
	bne jButton                          ; If race started (GO≠0), skip directional input, only check button

; ==============================================================================
; Vertical Input Processing (Up/Down)
; Tests bit 0 (up) and bit 1 (down), sets joyY to $FF (up) or $01 (down)
; ==============================================================================
jUp:
	lda JoyEvent                         ; Reload joystick state bitmap
	and #$01                             ; Isolate bit 0 (up direction flag)
	beq jDown                            ; If bit 0 clear (not up), test down direction
    dec joyY                             ; Up detected: set joyY = $FF (-1 in signed byte)
	bra jLeft                            ; Skip down test (up takes priority)

jDown:
	lda JoyEvent                         ; Reload joystick state bitmap
	and #$02                             ; Isolate bit 1 (down direction flag)
	beq jLeft                            ; If bit 1 clear (not down), continue to horizontal input
    inc joyY                             ; Down detected: set joyY = $01 (+1 in signed byte)

; ==============================================================================
; Horizontal Input Processing (Left/Right)
; Tests bit 2 (left) and bit 3 (right), sets joyX to $FF (left) or $01 (right)
; ==============================================================================
jLeft:
	lda JoyEvent                         ; Reload joystick state bitmap
	and #$04                             ; Isolate bit 2 (left direction flag)
    beq jRight                           ; If bit 2 clear (not left), test right direction
    dec joyX                             ; Left detected: set joyX = $FF (-1 in signed byte)
	bra jButton                          ; Skip right test (left takes priority)

jRight:
	lda JoyEvent                         ; Reload joystick state bitmap
	and #$08                             ; Isolate bit 3 (right direction flag)
	beq jButton                          ; If bit 3 clear (not right), continue to button test
    inc joyX                             ; Right detected: set joyX = $01 (+1 in signed byte)

; ==============================================================================
; Button Input Processing with Debounce
; Tests bit 4 (button 0) and implements debounce logic to prevent repeat triggers
; Debounce mechanism: Button state only registered on first press, not held state
; ==============================================================================
jButton:
	lda JoyEvent                         ; Reload joystick state bitmap
	and #$10                             ; Isolate bit 4 (button 0 flag)
	beq jReset                           ; If bit 4 clear (button not pressed), clear debounce flag
	lda joyBhold                         ; Load debounce flag (was button held from last frame?)
	bne bounce                           ; If held (joyBhold≠0), ignore this press (debounce)
	lda #$01                             ; Button newly pressed (not held)
	sta joyB                             ; Set button state flag (signal to game logic)
	sta joyBhold                         ; Set debounce flag (mark button as held)
jDone:
	rts                                  ; Exit joystick handler, return to dispatch

; ==============================================================================
; Button Release Handler - Clear debounce flag when button released
; ==============================================================================
jReset:
	stz joyBhold                         ; Clear debounce flag (button released, ready for next press)
	rts                                  ; Exit joystick handler

; ==============================================================================
; Button Debounce Handler - Ignore held button state
; ==============================================================================
bounce:
	stz joyB                             ; Clear button state (prevent repeated actions while held)
	rts                                  ; Exit joystick handler

; **************************************************************************************************************
; MAIN FRAME UPDATE HANDLER
; **************************************************************************************************************
; UpdateScreen - Main SOF (Start Of Frame) interrupt handler
; Purpose: Called every frame from kernel timer event. Orchestrates all per-frame game logic:
;          - Read player inputs and move car
;          - Run AI pathfinding and opponent movement
;          - Update tilemap scrolling and sprite positions
;          - Manage game state transitions and race progression
; Entry: Called from dispatch when kernel.event.timer.EXPIRED detected
;        race_on flag determines current game state (title/countdown/racing/results)
; Exit: Returns after completing all frame tasks, kernel schedules next SOF event
; Uses: All game subsystems (input, physics, AI, graphics, audio)
; Clobbers: Zero-page temporaries, MULU/DIV/ADD registers, processor flags
; **************************************************************************************************************

UpdateScreen:
    jsr SetTimer                             ; reset the timer for the next frame
    jsr animate_crowd                        ; animate crowd sprites and audio effects

    ; Debug display: Show current race_on state on I/O page 2
    ;lda #$02                                 ; Load I/O page 2 selector
    ;sta MMU_IO_CTRL                          ; Switch to I/O page 2 for debug output
    ;ldx race_on                              ; Load current game state value
    ;lda HexTable,x                           ; Convert state to hex ASCII character
    ;sta $c000                                ; Write to debug display location
    ;stz MMU_IO_CTRL                          ; Switch back to I/O page 0 (standard registers)

    ; Music playback control: Only play during active gameplay states
    lda race_on                              ; Load current game state
    cmp #$08                                 ; Compare with state $08 (race start)
    bcc skip_music                           ; If less than $08, skip music (pre-race states)
    jsr play_music                           ; play the background music

; ==============================================================================
; GAME STATE MACHINE - Main game flow controller
; ==============================================================================
; Purpose: Determine current game state and dispatch to appropriate handler routine
; Method: Test race_on flag and branch to state-specific handler via jump table
;
; race_on State Values:
; $00 = Title Screen - Display main menu, wait for start button
; $01 = Fly title screen up - Animate title upward to reveal message area
; $02 = Display welcome message - Show instructions, wait for player input
; $03 = Choose driver and laps - Character/race selection screen
; $04 = Clear screen - Move title screen off top, prepare for race
; $05 = (Reserved)
; $06 = Move in Christmas trees - Animate starting lights descending
; $07 = Start countdown - Sequential lamp illumination (5-4-3-2-1)
; $08 = Start race - Retract Christmas tree, begin race physics
; $09 = Race active - Main gameplay loop (player + AI movement)
; $0A = Fly in results screen - Animate results display
; $0B = Determine winner - Calculate final positions, display results
; $0C = Wait for button or timeout - Hold results, return to title
; $0D = Fly title back down - Restore title screen, reset game state
; ==============================================================================

skip_music:
    lda race_on                              ; Load current game state flag
    beq jmp_skip_play                        ; State $00: Title screen handler
    cmp #$01                                 ; Check for state $01 (title exit animation)
    beq jmp_move_title_out                   ; Branch to title screen exit handler
    cmp #$02                                 ; Check for state $02 (welcome message)
    beq jmp_open_message                     ; Branch to message display handler
    cmp #$03                                 ; Check for state $03 (driver selection)
    beq jmp_choose_driver                    ; Branch to driver/lap selection handler
    cmp #$04                                 ; Check for state $04 (clear screen)
    beq jmp_clear_title_screen               ; Branch to screen clear handler
    cmp #$06                                 ; Check for state $06 (tree entry animation)
    beq jmp_move_tree_in                     ; Branch to Christmas tree entry handler
    cmp #$07                                 ; Check for state $07 (countdown sequence)
    beq jmp_countdown_start                  ; Branch to countdown handler
    cmp #$08                                 ; Check for state $08 (race start)
    beq jmp_move_tree_out                    ; Branch to tree exit animation handler
    cmp #$09                                 ; Check for state $09 (active racing)
    beq race_active                          ; Branch directly to race active loop (no jump table needed)
    cmp #$0a                                 ; Check for state $0A (results entry animation)
    beq jmp_move_results_screen_in           ; Branch to results screen entry handler
    cmp #$0b                                 ; Check for state $0B (results display)
    beq jmp_results_screen                   ; Branch to results screen handler
    cmp #$0c                                 ; Check for state $0C (wait for input/timeout)
    beq jmp_wait_for_button_or_timeout       ; Branch to input wait handler
    cmp #$0d                                 ; Check for state $0D (return to title)
    beq jmp_bring_title_back_down            ; Branch to title restore handler

    ; Unknown state - return without action
    rts 

; ==============================================================================
; GAME STATE JUMP TABLE
; Purpose: Extended jump targets for race_on state handlers (overcome branch range)
; ==============================================================================
    
jmp_skip_play:
    jmp skip_play
jmp_move_title_out:
    jmp move_title_out
jmp_open_message:
    jmp open_message
jmp_choose_driver:
    jmp choose_driver
jmp_clear_title_screen:
    jmp clear_title_screen
jmp_move_tree_in:
    jmp move_tree_in
jmp_countdown_start:
    jmp countdown_start
jmp_move_tree_out:
    jmp move_tree_out
jmp_move_results_screen_in:
    jmp move_results_screen_in
jmp_results_screen:
    jmp results_screen
jmp_wait_for_button_or_timeout:
    jmp wait_for_button_or_timeout
jmp_bring_title_back_down:
    jmp bring_title_back_down


; **************************************************************************************************************
; RACE ACTIVE STATE - Main gameplay loop
; **************************************************************************************************************
; Purpose: Handle all active race gameplay including player control, AI opponents, and collision
; Method: Process inputs, update physics, run AI pathfinding, check collisions, update display
; Entry: Called from UpdateScreen when race_on = $09
; Exit: Returns to UpdateScreen after updating all game entities
; Notes: This is the core gameplay loop running at 60fps during active racing
; **************************************************************************************************************

race_active:
    jsr readInputs                           ; Read joystick inputs and update joyX/joyY/joyB variables
    
    ; Dynamic engine sound effect - modulate SID frequency based on player speed
    ; Creates realistic engine rumble by mapping speed to audio pitch
    clc                                      ; Clear carry flag for 16-bit addition
    lda playerSpeed_F                        ; Load player speed fractional component
    sta ptr_src                              ; Store in temporary pointer (low byte for freq calculation)
    lda playerSpeed_L                        ; Load player speed integer component (main speed value)
    adc #$05                                 ; Add offset to shift frequency into audible range
    sta ptr_src+1                            ; Store adjusted speed (high byte for freq calculation)
    sta SID_R1_FREQ_H                        ; Set SID voice 1 frequency high byte (bass engine tone)
    lda ptr_src                              ; Reload fractional speed component
    sta SID_R1_FREQ_L                        ; Set SID voice 1 frequency low byte (fine pitch control)
    adc Random_L                             ; Add random noise for engine roughness/variation
    sta SID_R2_FREQ_L                        ; Set SID voice 2 frequency low byte (harmonic variation)
    lda ptr_src+1                            ; Reload adjusted speed high byte
    adc #$03                                 ; Add additional offset for harmonic overtone (~2x pitch)
    sta SID_R2_FREQ_H                        ; Set SID voice 2 frequency high byte (harmonic engine tone)


    jsr moveCar                              ; Process player input and update car velocity/position
    
    ; Tile detection: Copy player position to temp variables for tileFind routine
    lda PlayerPOS_X_L                        ; Load player X position low byte (world coordinates)
    sta TileTempX_L                          ; Store in tile detection temp variable
    lda PlayerPOS_X_H                        ; Load player X position high byte
    sta TileTempX_H                          ; Store in tile detection temp variable
    lda PlayerPOS_Y_L                        ; Load player Y position low byte (world coordinates)
    sta TileTempY_L                          ; Store in tile detection temp variable
    lda PlayerPOS_Y_H                        ; Load player Y position high byte
    sta TileTempY_H                          ; Store in tile detection temp variable
    jsr tileFind                             ; Determine current track tile and check surface type (road/grass)

    ; Track position and waypoint system for player
    lda off_road                             ; Load current surface type (0=road, non-zero=grass)
    sta player_off_road                      ; Store player's off-road status for physics calculations
    lda #$03                                 ; Load player car index (player treated as car #3 in waypoint system)
    sta aicar_current                        ; Set current car index for waypoint check routine
    jsr waypoint_check                       ; Check if player crossed waypoint, update lap counter
    
    ; Dynamic crowd audio based on track position
    ldx player_target                        ; Load player's current target waypoint index
    lda crowd_vol_table,x                    ; Get crowd volume level for this track section
    sta crowd_volume                         ; Store crowd volume variable
    ora #$f0                                 ; Combine with volume control bits (bits 7-4 = volume)
    sta PSG_L                                ; Write to PSG LEFT control register (update crowd noise volume)

heli_move:
    jsr helicopter_Move                      ; Update helicopter position (follows average car position)
    stz aicar_current                        ; Reset AI car index to 0 (start with first AI car)
    inc race_timer                           ; Increment global race timer (used for lap timing)

; ==============================================================================
; AI Loop - Process all 3 AI opponent cars
; Iterates through aicar_current index (0, 1, 2) updating each AI car's:
;   - Timer tracking (lap times, splits)
;   - Pathfinding decisions (target waypoint, steering)
;   - Physics (acceleration, braking, movement)
;   - Waypoint detection (lap counting)
;   - Sprite positions (screen-relative rendering)
; ==============================================================================

ai_loop:
    lda race_on                              ; Load current game state
    cmp #$08                                 ; Check if state is less than $08 (pre-race states)
    bcc skip_ai                              ; If pre-race, skip AI processing (not yet racing)
    jsr timers                               ; Update race timers for current AI car (lap times, splits)
    
    jsr ai                                   ; Run AI pathfinding algorithm (determine target waypoint, steering)

    jsr aimoveCar                            ; Process AI car physics (throttle, brake, velocity, position)
    jsr waypoint_check                       ; Check if AI car crossed waypoint, update lap counter
    
skip_ai:
    jsr aiCarsMove                           ; Update AI car sprite position on screen (render relative to player)
    inc aicar_current                        ; Advance to next AI car (0→1→2)
    lda aicar_current                        ; Load updated car index
    cmp #$03                                 ; Check if all 3 AI cars processed (index 0-2)
    bcc ai_loop                              ; If more AI cars remain, loop back
    
    ; Post-AI processing: collision detection and final sprite updates
    jsr collisionCheck                       ; Check for collisions between all cars, resolve impacts
    jsr updatePos                            ; Update all car sprites and tilemap scroll position
    rts                                      ; Return to UpdateScreen, frame complete

; ==============================================================================
; skip_play - Title screen state handler
; ==============================================================================
; Purpose: Display title screen and wait for player to press start button
; Method: Enable title tilemap, check for button press to begin game sequence
; Entry: Called from UpdateScreen when race_on = $00
; Exit: Advances race_on to $01 when button pressed, enabling title animation
; ==============================================================================

skip_play: 
    lda #%00000001                           ; Enable tilemap: 16x16 tiles, bit 0 = enable
    sta VKY_TM2_CTRL                         ; Activate title screen tilemap
    lda joyB
    beq no_start
    lda #$01
    sta race_on
no_start:
    rts

; ==============================================================================
; move_title_out - Title screen exit animation
; ==============================================================================
; Purpose: Animate title screen moving upward off-screen to prepare for race
; Method: Increment Y position by 2 pixels per frame, gradually reduce crowd volume
; Entry: Called from UpdateScreen when race_on = $01
;        title_y_pos_L contains current tilemap Y position
; Exit: Advances race_on to $02 when Y position reaches 175 (off-screen)
;       Updates VKY_TM2_POS_Y_L and crowd_volume each frame
; Notes: Crowd volume fades from current level to minimum ($03) during animation
; Clobbers: A register
; ==============================================================================

move_title_out:
    ; --- Fade crowd volume during title animation ---
    lda crowd_volume                     ; Load current crowd noise volume level
    cmp #$03                             ; Check if already at minimum volume ($03)
    beq skip_crowd_volume                ; If at minimum, skip volume reduction
    
    ; --- Decrement crowd volume by 1 ---
    sec                                  ; Set carry for subtraction
    sbc #$01                             ; Subtract 1 from current volume
    sta crowd_volume                     ; Store updated volume level
    ora #$f0                             ; Combine volume with PSG control bits  |TO|xx|xx|xx|VO|VO|VO|VO|
    sta PSG_L                            ; Write to PSG Left control register    | 1| 1| 1| 1|vo|vo|vo|vo|
    
skip_crowd_volume:
    ; --- Increment title Y position (move up 2 pixels per frame) ---
    inc title_y_pos_L                    ; Increment Y position by 1
    inc title_y_pos_L                    ; Increment Y position by 1 (total: +2 pixels)
    
    ; --- Check if title fully off-screen (Y >= 175) ---
    lda title_y_pos_L                    ; Load current Y position
    cmp #175                             ; Compare to off-screen threshold (175 pixels)
    bcs done_title_move1                 ; If >= 175, animation complete (title off-screen)
    
    ; --- Update tilemap Y position register (still animating) ---
    sta VKY_TM2_POS_Y_L                  ; Write Y position to tilemap 2 position register
    
skip_title_move:
    rts                                  ; Return to UpdateScreen (continue animation next frame)

    
done_title_move1:
    ; --- Title animation complete - advance to next state ---
    inc race_on                          ; Advance to race_on = $02 (welcome message state)
    rts                                  ; Return to UpdateScreen

; ==============================================================================
; disable_title_map - Skip title screen (unused state handler)
; ==============================================================================
; Purpose: Placeholder state handler for race_on = $05 (currently unused)
; Method: Simply advance to next game state
; Entry: Called from UpdateScreen when race_on = $05
; Exit: Advances race_on to $06 (Christmas tree animation)
; Notes: Reserved for future expansion
; ==============================================================================

disable_title_map:
    inc race_on                         ; Advance to race_on = $06
    rts                                 ; Return to UpdateScreen

; **************************************************************************************************************
; move_tree_in - Christmas tree starting light animation (entry sequence)
; **************************************************************************************************************
; Purpose: Animate Christmas tree structure descending from top of screen to race start position
;          Enables tree sprites on first call, then moves them down incrementally each frame
; Method: Moves tree Y position down by 4 pixels per frame until reaching Y=100
;         Transitions to countdown sequence when fully descended
; Entry: Called from UpdateScreen when race_on = $06
;        tree_y_pos contains current Y position (0 on first call)
; Exit: Updates christmas_tree_left/right Y positions, advances to race_on=$07 when complete
; Notes: Also initializes SID voices and clears countdown variables when tree reaches target
; Clobbers: A register
; **************************************************************************************************************

move_tree_in:
    ; --- Check if this is first call (tree_y_pos = 0) ---
    lda tree_y_pos                       ; Load current tree Y position
    bne tree_move_down                   ; If non-zero, skip sprite enable (already enabled)
    
    ; --- Enable Christmas tree sprites (first frame only) ---
    lda #%00010001                       ; Sprite control: enable, 32×32 size    |xx|SZ|SZ|LA|LA|LU|LU|EN|
    sta christmas_tree_left+SP_CTRL      ; Enable left tree sprite (slot 15)     | 0| 0| 0| 1| 0| 0| 0| 1|
    sta christmas_tree_right+SP_CTRL     ; Enable right tree sprite (slot 16)
    
tree_move_down:
    ; --- Increment tree Y position (move down 4 pixels per frame) ---
    clc                                  ; Clear carry for addition
    lda tree_y_pos                       ; Load current Y position
    adc #$04                             ; Add 4 pixels (descent speed)
    sta tree_y_pos                       ; Store updated position
    
    ; --- Check if tree reached target position (Y=100) ---
    cmp #100                             ; Compare position to target (100 pixels from top)
    bcs done_tree_move                   ; If >= 100, tree has reached final position
    
    ; --- Update sprite positions (still descending) ---
    sta christmas_tree_left+SP_POS_Y_L   ; Write Y position to left tree sprite
    sta christmas_tree_right+SP_POS_Y_L  ; Write Y position to right tree sprite
    rts                                  ; Return to UpdateScreen (continue descent next frame)
    
done_tree_move:
    ; --- Tree descent complete - prepare for countdown sequence ---
    inc race_on                          ; Advance to race_on = $07 (countdown state)
    stz start_light_set                  ; Reset countdown stage counter (start at stage 0)
    stz countdown_timer                  ; Reset countdown frame timer
    
    ; --- Initialize SID audio for countdown beeps ---
    lda #$41                             ; SID Voice 1: Gate on, pulse waveform  |GA|SY|RI|SA|TR|PU|SW|NO|
    sta SID_R1_GATE                      ; Configure voice 1 gate register       | 0| 1| 0| 0| 0| 0| 0| 1|
    lda #$21                             ; SID Voice 2: Gate on, pulse waveform  |GA|SY|RI|SA|TR|PU|SW|NO|
    sta SID_R2_GATE                      ; Configure voice 2 gate register       | 0| 0| 1| 0| 0| 0| 0| 1|
    
    jmp heli_move                        ; Jump to helicopter update routine

; **************************************************************************************************************
; countdown_start - Race start countdown sequence controller
; **************************************************************************************************************
; Purpose: Manage 6-stage countdown sequence (5 lights + final start)
;          Illuminate starting lamps sequentially at 1-second intervals
; Method: Increment timer each frame (60 fps), advance light stage every 60 frames
;         Enable lamp sprites in pairs (left/right) for each countdown stage
; Entry: Called from UpdateScreen when race_on = $07
;        countdown_timer tracks frames since last light change
;        start_light_set indicates current countdown stage (0-5)
; Exit: Updates lamp sprite control registers, advances to race_on=$08 when countdown complete
; Notes: Each lamp pair is 8 bytes apart in sprite register space (slots 3-12)
;        Stage 6 triggers race start and PSG audio cue
; Clobbers: A, X, Y registers
; **************************************************************************************************************

countdown_start:
    ; --- Increment frame counter ---
    inc countdown_timer                  ; Increment countdown timer (frames since last light)
    lda countdown_timer                  ; Load current timer value
    cmp #60                              ; Check if 60 frames elapsed (1 second at 60fps)
    bcc skip_countdown                   ; If less than 60, continue waiting this frame
    
    ; --- Advance to next countdown stage ---
    inc start_light_set                  ; Increment countdown stage (0→1→2→3→4→5→6)
    stz countdown_timer                  ; Reset frame timer for next stage
    
    ; --- Check if countdown complete (stage 6 = race start) ---
    lda start_light_set                  ; Load current countdown stage
    cmp #6                               ; Check if reached stage 6 (all lights shown)
    bcs done_countdown                   ; If >= 6, countdown complete, trigger race start
    
    ; --- Calculate lamp sprite indices for this stage ---
    ; Each stage enables 2 lamps (left and right side)
    ; Stage 1 → lamps 0+5, Stage 2 → lamps 1+6, etc.
    lda start_light_set                  ; Load stage number (1-5)
    dec a                                ; Convert to 0-based index (0-4)
    asl                                  ; Multiply by 2
    asl                                  ; Multiply by 4
    asl                                  ; Multiply by 8 (sprite slot size)
    tay                                  ; Y = left lamp offset (0, 8, 16, 24, 32)
    
    ; --- Calculate right lamp offset (40 bytes higher) ---
    clc                                  ; Clear carry for addition
    adc #40                              ; Add 40 (5 sprite slots × 8 bytes)
    tax                                  ; X = right lamp offset (40, 48, 56, 64, 72)
    
    ; --- Enable both lamp sprites for this countdown stage ---
    lda #%01101001                       ; Sprite control: enable, 8×8 size      |xx|SZ|SZ|LA|LA|LU|LU|EN|
    sta lamps_base+SP_CTRL,y             ; Enable left lamp sprite (indexed by Y) | 0| 1| 1| 0| 1| 0| 0| 1|
    sta lamps_base+SP_CTRL,x             ; Enable right lamp sprite (indexed by X)
    
skip_countdown:
    jmp heli_move                        ; Jump to helicopter update routine

; ==============================================================================
; done_countdown - Countdown completion handler
; Purpose: Disable all 10 lamp sprites and transition to tree exit animation
; Method: Loop through all lamp sprites (slots 3-12), clear control registers
;         Configure PSG audio for race start sound effect
; Entry: Called when start_light_set reaches 6 (all countdown stages complete)
; Exit: Advances race_on to $08 (move_tree_out phase), all lamps disabled
; Clobbers: A, X, Y registers
; ==============================================================================

done_countdown:
    ; --- Initialize lamp disable loop ---
    ldx #$00                             ; X = lamp counter (0-9)
    
clear_lamps:
    ; --- Calculate sprite register offset for current lamp ---
    txa                                  ; Transfer lamp index to A
    asl                                  ; Multiply by 2
    asl                                  ; Multiply by 4
    asl                                  ; Multiply by 8 (sprite slot size)
    tay                                  ; Y = sprite offset (0, 8, 16, ... 72)
    
    ; --- Disable lamp sprite ---
    lda #%00000000                       ; Sprite control: disabled (all bits clear)
    sta lamps_base+SP_CTRL,y             ; Write to sprite control register (disable sprite)
    
    ; --- Check if all lamps processed ---
    inx                                  ; Increment lamp counter (0→1→2...→9→10)
    cpx #10                              ; Check if all 10 lamps processed
    bcc clear_lamps                      ; If counter < 10, loop back to disable next lamp
    
    ; --- Advance to tree exit animation state ---
    inc race_on                          ; Advance to race_on = $08 (move_tree_out)
    
    ; --- Configure PSG for race start sound effect (high-pitched beep) ---
    lda #$90                             ; PSG control: Tone 1, volume = 0        |TO|xx|xx|xx|VO|VO|VO|VO|
    sta PSG_L                            ; Write to PSG Left control register     | 1| 0| 0| 1| 0| 0| 0| 0|
    
    lda #$8d                             ; PSG frequency low byte: $058D (1421 Hz approx)
    sta PSG_L                            ; Write frequency bits 0-7
    
    lda #$05                             ; PSG frequency high byte
    sta PSG_L                            ; Write frequency bits 8-9

    jmp heli_move                        ; Jump to helicopter update routine

; **************************************************************************************************************
; move_tree_out - Christmas tree exit animation (race start sequence)
; **************************************************************************************************************
; Purpose: Animate Christmas tree structure ascending off-screen after countdown completes
;          Moves tree up by 4 pixels per frame until fully retracted
; Method: Decrement tree_y_pos each frame, disable sprites when Y underflows to negative
;         Transition to active race state when tree fully retracted
; Entry: Called from UpdateScreen when race_on = $08
;        tree_y_pos contains current Y position
; Exit: Updates christmas_tree sprites, advances to race_on=$09 (race active) when complete
;       Disables PSG crowd noise effect and enables race physics
; Notes: Tree retraction signals official race start
; Clobbers: A register
; **************************************************************************************************************

move_tree_out:
    ; --- Reset countdown state variables ---
    stz start_light_set                  ; Clear countdown stage counter (cleanup)
    
    ; --- Decrement tree Y position (move up 4 pixels per frame) ---
    sec                                  ; Set carry for subtraction
    lda tree_y_pos                       ; Load current Y position
    sbc #$04                             ; Subtract 4 pixels (ascent speed)
    sta tree_y_pos                       ; Store updated position
    
    ; --- Check if tree fully retracted (Y < 0, underflow) ---
    bcs tree_still_moving                ; If carry set, no underflow (Y >= 0, still visible)
    
    ; --- Tree retraction complete - disable sprites and start race ---
    lda #%00000000                       ; Sprite control: disabled (all bits clear)
    sta christmas_tree_left+SP_CTRL      ; Disable left tree sprite (slot 15)
    sta christmas_tree_right+SP_CTRL     ; Disable right tree sprite (slot 16)
    
    stz tree_y_pos                       ; Reset tree position to 0 for next race
    
    ; --- Disable PSG race start tone ---
    lda #$9f                             ; PSG control: Tone 1, volume = 15 (off) |TO|xx|xx|xx|VO|VO|VO|VO|
    sta PSG_L                            ; Write to PSG Left control register     | 1| 0| 0| 1| 1| 1| 1| 1|
    
    ; --- Activate race state ---
    inc race_on                          ; Advance to race_on = $09 (race active)
    jmp race_active                      ; Jump to main race loop
    
tree_still_moving:
    ; --- Update sprite positions (tree still ascending) ---
    sta christmas_tree_left+SP_POS_Y_L   ; Write Y position to left tree sprite
    sta christmas_tree_right+SP_POS_Y_L  ; Write Y position to right tree sprite
    jmp race_active                      ; Continue to race processing (allows car movement during exit)

; ==============================================================================
; brake - Player car emergency braking subroutine
; Purpose: Rapidly reduce player car speed by subtracting large value from velocity
; Method: 24-bit fixed-point subtraction (speed -= $10.00.00 in F.L.H format)
;         Braking force is 16x stronger than normal deceleration
; Entry: Called from moveCar when joyY = $01 (down/brake input detected)
;        PlayerSpeed_F/L/H contains current velocity
; Exit: Branches to stopped if speed becomes negative, else continues to coast
;       PlayerSpeed_F/L/H updated with reduced velocity
; Clobbers: A register
; ==============================================================================

brake:
    ; --- Apply Heavy Braking Force (24-bit fixed-point subtraction) ---
    ; Subtract $10.00.00 from PlayerSpeed (16x stronger than normal deceleration)
    sec                                  ; Set carry for 24-bit subtraction
    lda PlayerSpeed_F                    ; Load speed fractional byte
    sbc #$10                             ; Subtract braking force (16 units from fraction)
    sta PlayerSpeed_F                    ; Store updated fractional speed
    lda PlayerSpeed_L                    ; Load speed low byte (integer)
    sbc #$00                             ; Subtract borrow propagation only
    sta PlayerSpeed_L                    ; Store updated low byte
    lda PlayerSpeed_H                    ; Load speed high byte (overflow)
    sbc #$00                             ; Subtract borrow propagation only
    sta PlayerSpeed_H                    ; Store updated high byte
    bmi stopped                          ; If negative (N flag set) → clamp to zero
    bra coast                            ; Otherwise continue to movement calculation
    
backup:
    rts                                  ; Return (unused backup function)

; ==============================================================================
; decelerate - Player car natural deceleration (coast slowdown)
; Purpose: Gradually reduce player car speed when no throttle input applied
; Method: 24-bit fixed-point subtraction (speed -= $01.00.00 in F.L.H format)
;         Provides gentle slowdown for realistic coasting behavior
; Entry: Called from moveCar when joyY = $00 (no vertical input)
;        PlayerSpeed_F/L/H contains current velocity
; Exit: Branches to stopped if speed becomes negative, else continues to coast
;       PlayerSpeed_F/L/H updated with reduced velocity
; Clobbers: A register
; ==============================================================================

decelerate:
    ; --- Apply Gentle Deceleration (24-bit fixed-point subtraction) ---
    ; Subtract $01.00.00 from PlayerSpeed (natural slowdown when coasting)
    sec                                  ; Set carry for 24-bit subtraction
    lda PlayerSpeed_F                    ; Load speed fractional byte
    sbc #$01                             ; Subtract deceleration force (1 unit from fraction)
    sta PlayerSpeed_F                    ; Store updated fractional speed
    lda PlayerSpeed_L                    ; Load speed low byte (integer)
    sbc #$00                             ; Subtract borrow propagation only
    sta PlayerSpeed_L                    ; Store updated low byte
    lda PlayerSpeed_H                    ; Load speed high byte (overflow)
    sbc #$00                             ; Subtract borrow propagation only
    sta PlayerSpeed_H                    ; Store updated high byte
    bmi stopped                          ; If negative (N flag set) → clamp to zero
    bra coast                            ; Otherwise continue to movement calculation

; ==============================================================================
; stopped - Speed clamp handler (prevents negative player velocity)
; Purpose: Reset player car speed to zero when deceleration causes negative value
; Entry: Called from brake/decelerate when speed subtraction results in negative (N flag set)
; Exit: PlayerSpeed_F/L/H all zeroed, continues to coast for position update
; ==============================================================================

stopped:
    ; --- Clamp Speed to Zero (prevent negative velocity) ---
    stz PlayerSpeed_F                    ; Clear speed fractional byte (zero)
    stz PlayerSpeed_L                    ; Clear speed low byte (zero)
    stz PlayerSpeed_H                    ; Clear speed high byte (zero)
    bra coast                            ; Continue to movement calculation (stationary)

; **************************************************************************************************************
; moveCar - Player car physics controller (acceleration, braking, movement)
; **************************************************************************************************************
; Purpose: Process player joystick input and update car velocity and world position
;          Handle throttle, braking, off-road penalties, and race finish detection
; Method: Read joyY input ($FF=accel, $00=coast, $01=brake), modify 24-bit fixed-point speed
;         Apply off-road speed clamp if not on track surface
;         Check lap count and force braking if race finished
; Entry: Called from race_active section of UpdateScreen
;        joyY contains vertical joystick input (-1/0/+1)
;        player_off_road flag indicates track surface status
; Exit: Updates PlayerSpeed_F/L/H and PlayerPOS_X/Y_F/L/H with new velocity and position
;       Branches to brake/decelerate/accelerate based on input
; Notes: Falls through to coast routine for velocity-to-position conversion
; Clobbers: A, X registers, MULU hardware registers
; **************************************************************************************************************

moveCar:
    ; --- Check if player is off-road (grass/dirt surface) ---
    lda player_off_road                  ; Load off-road flag (0=on track, non-zero=off track)
    cmp #$00                             ; Check if on track surface
    beq finish_race_check                ; If on track, skip speed penalty

    ; --- Off-Road Speed Penalty ---
    ; Clamp speed to maximum $20 when driving on non-track surface
    ; This prevents excessive speed on grass and creates realistic handling
    stz playerSpeed_H                    ; Clear speed high byte (force speed < 256)
    stz playerSpeed_L                    ; Clear speed low byte (integer part = 0)
    lda playerSpeed_F                    ; Load speed fractional byte
    cmp #$20                             ; Check if speed exceeds off-road limit ($20 = 32)
    bcc finish_race_check                ; If already below limit, skip clamping
    lda #$20                             ; Load off-road speed limit
    sta playerSpeed_F                    ; Clamp speed to maximum off-road velocity

; ==============================================================================
; Race Finish Detection
; If player has completed final lap, force braking to prevent further driving
; ==============================================================================

finish_race_check:
    lda lap_count+3                      ; Load player's lap count (player is index 3)
    cmp last_lap                         ; Compare to final lap threshold (race distance)
    bcc normal_drive                     ; If not finished (lap < last_lap), continue normal driving
    lda #$01                             ; Load brake command ($01 = brake input)
    sta joyY                             ; Override joystick Y to force braking (stop player)

normal_drive:
    ; --- Dispatch to appropriate speed handler based on joystick input ---
    lda joyY                             ; Load vertical joystick input
    beq decelerate                       ; If joyY = $00 (center) → coast/decelerate
    cmp #$01                             ; Check if joyY = $01 (down/brake)
    beq brake                            ; If brake input → apply heavy braking
    ; Fall through to acceleration if joyY = $FF (up/throttle)

; ==============================================================================
; Acceleration Handler
; Purpose: Increase player velocity by incrementing 24-bit fixed-point speed
; Method: Add $08 to fractional byte, carry propagates to integer bytes
; Notes: PlayerSpeed uses 24-bit fixed-point format (F=fraction, L=low, H=high)
;        Fractional increment (#$08) controls acceleration rate
; ==============================================================================

    ; --- Apply Acceleration (24-bit fixed-point addition) ---
    ; Add $08.00.00 to PlayerSpeed (smooth acceleration rate)
    clc                                  ; Clear carry for 24-bit addition
    lda PlayerSpeed_F                    ; Load speed fractional byte
    adc #$08                             ; Add acceleration force (8 units to fraction)
    sta PlayerSpeed_F                    ; Store updated fractional speed
    lda PlayerSpeed_L                    ; Load speed low byte (integer)
    adc #$00                             ; Add carry propagation from fraction → low
    sta PlayerSpeed_L                    ; Store updated low byte
    lda PlayerSpeed_H                    ; Load speed high byte (overflow)
    adc #$00                             ; Add carry propagation from low → high
    sta PlayerSpeed_H                    ; Store updated high byte
    ; Fall through to coast for velocity-to-position conversion

; ==============================================================================
; coast - Player velocity-to-position conversion (movement application)
; ==============================================================================
; Purpose: Convert current velocity and heading to world position displacement
; Method: Uses hardware MULU to compute: displacement = velocity × direction_vector
; Process:
;   1. Load direction vector from VectorX/Y tables based on PlayerRotation
;   2. Multiply vector by player speed using MULU coprocessor
;   3. Check vector sign flag to determine add/subtract operation
;   4. Apply signed displacement to 24-bit world position (X axis, then Y axis)
; Hardware MULU Operation:
;   MULU_A = Direction vector component (VectorX/Y_F/L indexed by rotation)
;   MULU_B = Player speed (PlayerSpeed_F/L as 16-bit value)
;   Product = 32-bit result (MULU_LL, MULU_LH, MULU_HL, MULU_HH)
;   Mid-bytes (MULU_LH, MULU_HL, MULU_HH) contain scaled displacement
; Notes: VectorX/Y tables are pre-computed unit vectors for 32 rotation angles (11.25° each)
;        VectorX/Y_S tables contain sign flags (0=positive, non-zero=negative)
; ==============================================================================

coast:
    ; --- Load player rotation angle for vector table lookups ---
    ldx PlayerRotation                   ; X = rotation index (0-31, each = 11.25°)

    ; --- X-Axis Movement Calculation ---
    ; Load X direction vector and player speed into MULU hardware
    lda VectorX_F,x                      ; Load X vector fractional component (indexed by rotation)
    sta MULU_A_L                         ; Store in MULU A register low byte
    lda VectorX_L,x                      ; Load X vector integer component (indexed by rotation)
    sta MULU_A_H                         ; Store in MULU A register high byte
    lda playerSpeed_F                    ; Load player speed fractional component
    sta MULU_B_L                         ; Store in MULU B register low byte
    lda playerSpeed_L                    ; Load player speed integer component
    sta MULU_B_H                         ; Store in MULU B register high byte
    ; MULU hardware now computes: product = VectorX × playerSpeed (32-bit result)

    ; --- Check vector sign to determine add or subtract operation ---
    lda VectorX_S,x                      ; Load X vector sign flag (indexed by rotation)
    bne NegX                             ; If non-zero (negative) → subtract displacement

    ; --- Positive X: add MULU product into PlayerPOS_X (24-bit fixed-point) ---
    ; Product layout: MULU_LH (frac), MULU_HL (mid), MULU_HH (high)
    ; Ignore MULU_LL (too small for game precision)
    clc                                  ; Clear carry for 24-bit addition
    lda PlayerPOS_X_F                    ; Load player X position fractional byte
    adc MULU_LH                          ; Add MULU product mid-low byte (fractional result)
    sta PlayerPOS_X_F                    ; Store updated X fractional position
    lda PlayerPOS_X_L                    ; Load player X position low byte
    adc MULU_HL                          ; Add MULU product mid-high byte + carry
    sta PlayerPOS_X_L                    ; Store updated X low position
    lda PlayerPOS_X_H                    ; Load player X position high byte
    adc MULU_HH                          ; Add MULU product high byte + carry
    sta PlayerPOS_X_H                    ; Store updated X high position
    bra solveY                           ; Continue to Y-axis calculation

; ==============================================================================
; NegX - Handle negative X-axis displacement
; Subtract MULU product from PlayerPOS_X using 24-bit fixed-point subtraction
; ==============================================================================

NegX:
    ; --- Negative X: subtract MULU product from PlayerPOS_X (24-bit fixed-point) ---
    ; Used when direction vector is negative (moving left or backward in X)
    sec                                  ; Set carry for 24-bit subtraction
    lda PlayerPOS_X_F                    ; Load player X position fractional byte
    sbc MULU_LH                          ; Subtract MULU product mid-low byte
    sta PlayerPOS_X_F                    ; Store updated X fractional position
    lda PlayerPOS_X_L                    ; Load player X position low byte
    sbc MULU_HL                          ; Subtract MULU product mid-high byte with borrow
    sta PlayerPOS_X_L                    ; Store updated X low position
    lda PlayerPOS_X_H                    ; Load player X position high byte
    sbc MULU_HH                          ; Subtract MULU product high byte with borrow
    sta PlayerPOS_X_H                    ; Store updated X high position
    ; Fall through to solveY for Y-axis calculation

; ==============================================================================
; solveY - Y-Axis Movement Calculation
; Purpose: Compute and apply Y displacement using same method as X-axis
; Notes: MULU_B registers already contain player speed from X calculation
; ==============================================================================

solveY:
    ; --- Load player rotation angle for Y vector table lookups ---
    ldx PlayerRotation                   ; X = rotation index (0-31, each = 11.25°)

    ; --- Y-Axis Movement Calculation ---
    ; Load Y direction vector into MULU (player speed already in MULU_B from X calc)
    lda VectorY_F,x                      ; Load Y vector fractional component (indexed by rotation)
    sta MULU_A_L                         ; Store in MULU A register low byte
    lda VectorY_L,x                      ; Load Y vector integer component (indexed by rotation)
    sta MULU_A_H                         ; Store in MULU A register high byte
    ; MULU hardware now computes: product = VectorY × playerSpeed (32-bit result)

    ; --- Check vector sign to determine add or subtract operation ---
    lda VectorY_S,x                      ; Load Y vector sign flag (indexed by rotation)
    bne NegY                             ; If non-zero (negative) → subtract displacement

    ; --- Positive Y: add MULU product into PlayerPOS_Y (24-bit fixed-point) ---
    clc                                  ; Clear carry for 24-bit addition
    lda PlayerPOS_Y_F                    ; Load player Y position fractional byte
    adc MULU_LH                          ; Add MULU product mid-low byte (fractional result)
    sta PlayerPOS_Y_F                    ; Store updated Y fractional position
    lda PlayerPOS_Y_L                    ; Load player Y position low byte
    adc MULU_HL                          ; Add MULU product mid-high byte + carry
    sta PlayerPOS_Y_L                    ; Store updated Y low position
    lda PlayerPOS_Y_H                    ; Load player Y position high byte
    adc MULU_HH                          ; Add MULU product high byte + carry
    sta PlayerPOS_Y_H                    ; Store updated Y high position
    bra end_move                         ; Movement calculation complete

; ==============================================================================
; NegY - Handle negative Y-axis displacement
; Subtract MULU product from PlayerPOS_Y using 24-bit fixed-point subtraction
; ==============================================================================

NegY:
    ; --- Negative Y: subtract MULU product from PlayerPOS_Y (24-bit fixed-point) ---
    ; Used when direction vector is negative (moving up or backward in Y)
    sec                                  ; Set carry for 24-bit subtraction
    lda PlayerPOS_Y_F                    ; Load player Y position fractional byte
    sbc MULU_LH                          ; Subtract MULU product mid-low byte
    sta PlayerPOS_Y_F                    ; Store updated Y fractional position
    lda PlayerPOS_Y_L                    ; Load player Y position low byte
    sbc MULU_HL                          ; Subtract MULU product mid-high byte with borrow
    sta PlayerPOS_Y_L                    ; Store updated Y low position
    lda PlayerPOS_Y_H                    ; Load player Y position high byte
    sbc MULU_HH                          ; Subtract MULU product high byte with borrow
    sta PlayerPOS_Y_H                    ; Store updated Y high position
    ; Fall through to end_move
    
end_move:
    rts                                  ; Return to caller (race_active loop)

; ***************************************************************************************************************
; AI CAR MOVEMENT PHYSICS SYSTEM
; ***************************************************************************************************************
; This section implements the movement physics for AI-controlled cars, mirroring the player
; car physics but using indexed addressing (Y register) to operate on per-car data arrays.
; The AI cars share the same acceleration, braking, and velocity calculation logic as the
; player, ensuring consistent handling characteristics across all vehicles.
;
; Data Structure:
;   All AI car data is stored in parallel arrays indexed by car number (0-2):
;   - aicar_Speed_F/L/H[Y] - 24-bit fixed-point velocity (F=fraction, L=low, H=high)
;   - aicar_posX/Y_F/L/H[Y] - 24-bit fixed-point world position (X and Y coordinates)
;   - aicar_Rotation[Y] - Current heading angle (0-31, 11.25° per step)
;   - aicar_JoyY[Y] - Virtual throttle input: $FF=accelerate, $00=coast, $01=brake
;
; Entry Points:
;   aibrake - Emergency braking (subtracts $10 from fractional speed byte)
;   aidecelerate - Gentle slowdown (subtracts $00, currently disabled for AI)
;   aistopped - Speed clamp handler (sets speed to zero if negative)
;   aimoveCar - Main entry point (processes throttle input and updates position)
;   ai_accelerate - Acceleration handler (adds $08 to fractional speed byte)
;   aicoast - Velocity-to-position conversion using hardware MULU
;
; Fixed-Point Math:
;   Speed and position use 24-bit fixed-point representation (8.16 format):
;     Bits 0-7:   Fractional component (sub-pixel precision)
;     Bits 8-15:  Integer low byte (primary position/speed value)
;     Bits 16-23: Integer high byte (overflow/large values)
;   This allows smooth acceleration/movement with sub-pixel accuracy.
;
; Hardware Multiplication:
;   Uses Foenix F256 MULU coprocessor for fixed-point velocity calculations:
;     MULU_A = Direction vector component (VectorX/Y_F, VectorX/Y_L)
;     MULU_B = AI car speed (aicar_Speed_F, aicar_Speed_L)
;     Product = 32-bit result (MULU_LL, MULU_LH, MULU_HL, MULU_HH)
;   The mid-bytes (MULU_LH, MULU_HL, MULU_HH) contain the scaled displacement.
;
; Vector Tables:
;   VectorX_F/L[rotation] - X-axis direction vectors (fractional and integer parts)
;   VectorY_F/L[rotation] - Y-axis direction vectors (fractional and integer parts)
;   VectorX_S[rotation] - X-axis sign flags (0=positive, non-zero=negative)
;   VectorY_S[rotation] - Y-axis sign flags (0=positive, non-zero=negative)
;   These pre-computed tables map rotation angles (0-31) to unit vectors.
;
; Notes:
;   - Y register MUST contain aicar_current index throughout this section
;   - Off-road penalty code is currently disabled (commented out)
;   - Deceleration is currently set to $00 (no slowdown when coasting)
;   - Falls through to updatePos after completing movement calculations
; ***************************************************************************************************************

moveai: 

; ==============================================================================
; aibrake - AI car emergency braking subroutine
; Purpose: Rapidly reduce AI car speed by subtracting large value from velocity
; Method: 24-bit fixed-point subtraction (speed -= $10.00.00 in F.L.H format)
; Entry: Y register contains AI car index (0-2)
; Exit: Branches to aistopped if speed becomes negative, else jumps to aicoast
; ==============================================================================
aibrake:
    ; --- Apply Heavy Braking Force ---
    ; Subtract $10 from fractional byte to create rapid deceleration
    ; This is 16x stronger than normal deceleration ($01)
    sec                          ; Set carry for 24-bit subtraction
    lda aicar_speed_F,y          ; Load AI car speed fractional byte
    sbc #$10                     ; Subtract braking force (16 units)
    sta aicar_speed_F,y          ; Store updated fractional speed
    lda aicar_Speed_L,y          ; Load speed low byte (integer)
    sbc #$00                     ; Subtract borrow propagation only
    sta aicar_Speed_L,y          ; Store updated low byte
    lda aicar_Speed_H,y          ; Load speed high byte (overflow)
    sbc #$00                     ; Subtract borrow propagation only
    sta aicar_Speed_H,y          ; Store updated high byte
    bmi aistopped                ; If negative (N flag set) → clamp to zero
    jmp aicoast                  ; Otherwise continue to movement calculation

; ==============================================================================
; aibackup - Placeholder for reverse movement (currently unused)
; ==============================================================================
aibackup:
    rts                          ; Return immediately (no reverse logic implemented)

; ==============================================================================
; aidecelerate - AI car gentle deceleration (currently disabled)
; Purpose: Slow down AI car when no throttle input (coast mode)
; Method: Currently subtracts $00 (no effect) - disabled for AI racing behavior
; Entry: Y register contains AI car index (0-2)
; Exit: Branches to aistopped if speed becomes negative, else continues to aicoast
; Note: Set to $00 to prevent AI cars from slowing down during race
; ==============================================================================
aidecelerate:
    ; --- Apply Minimal Deceleration (Currently Disabled) ---
    ; Subtract $00 from fractional byte (no actual deceleration)
    ; Change to $01 or higher to enable coast slowdown for AI cars
    sec                          ; Set carry for 24-bit subtraction
    lda aicar_Speed_F,y          ; Load AI car speed fractional byte
    sbc #$00                     ; Subtract deceleration force (ZERO = disabled)
    sta aicar_Speed_F,y          ; Store updated fractional speed
    lda aicar_Speed_L,y          ; Load speed low byte
    sbc #$00                     ; Subtract borrow propagation only
    sta aicar_Speed_L,y          ; Store updated low byte
    lda aicar_Speed_H,y          ; Load speed high byte
    sbc #$00                     ; Subtract borrow propagation only
    sta aicar_Speed_H,y          ; Store updated high byte
    bmi aistopped                ; If negative → clamp to zero
    bra aicoast                  ; Continue to movement calculation

; ==============================================================================
; aistopped - Speed clamp handler (prevents negative velocity)
; Purpose: Reset AI car speed to zero when it goes negative
; Entry: Called when speed subtraction results in negative value (N flag set)
; Exit: Continues to aicoast with speed = 0
; ==============================================================================
aistopped:
    ; --- Clamp Speed to Zero ---
    ; If braking/deceleration caused negative speed, reset to stopped state
    lda #$00                     ; Load zero value
    sta aicar_speed_F,y          ; Clear fractional speed byte
    sta aicar_speed_L,y          ; Clear low speed byte
    sta aicar_speed_H,y          ; Clear high speed byte
    bra aicoast                  ; Continue to movement (will stay in place)

; ==============================================================================
; aimoveCar - AI car main movement logic coordinator
; Purpose: Main entry point for AI car physics - reads virtual joystick input
;          and dispatches to acceleration/braking/coast handlers
; Entry: aicar_current contains car index (0-2)
; Exit: Updates aicar_posX/Y with new world position, branches to updatePos
; Uses: Y register as car index for all indexed array accesses
; ==============================================================================
aimoveCar:
    ; --- Load AI Car Index ---
    ; Transfer current car index (0-2) to Y register for indexed addressing
    ; Y will remain set throughout all subroutines in this section
    ldy aicar_current            ; Y = AI car index (0, 1, or 2)

    ; --- Commented Out: Off-Road Terrain Penalty ---
    ; This section would check if AI car is on road surface and apply speed penalty
    ; Currently disabled - all AI cars maintain full speed regardless of terrain
    ;lda aicar_posX_L,y          ; load current position into temp vars for tileFind
    ;sta TileTempX_L
    ;lda aicar_posX_H,y
    ;sta TileTempX_H
    ;lda aicar_posY_L,y
    ;sta TileTempY_L
    ;lda aicar_posY_H,y
    ;sta TileTempY_H
    ;jsr tileFind                ; find the tile we are on
    ;jsr RoadCheck              ; check if we are on the road

    ; --- Off-Road Speed Cap (Disabled) ---
    ;lda off_road
    ;cmp #$00
    ;beq ai_normal_drive
    ;; Off-road penalty: decelerate more quickly
    ;lda #$00
    ;sta aicar_speed_H,y
    ;sta aicar_speed_L,y
    ;lda aicar_speed_F,y
    ;cmp #$20
    ;bcc ai_normal_drive
    ;lda #$20                    ; Cap off-road speed at $20 (slow)
    ;sta aicar_speed_F,y

    ; stop car if completed final lap
    lda lap_count,Y
    cmp last_lap
    bne ai_normal_drive
    lda #$01
    sta aicar_JoyY,y        ; set to brake input to stop car
    lda #$00
    sta aicar_JoyX,y        ; no steering input

ai_normal_drive:
    ; --- Process Virtual Throttle Input ---
    ; aicar_JoyY contains AI pathfinder's throttle decision:
    ;   $FF (-1) = Accelerate (gas pedal)
    ;   $00 (0)  = Coast (no input, let momentum carry)
    ;   $01 (+1) = Brake (slow down for corners)
    lda aicar_JoyY,y             ; Load AI virtual throttle input
    beq aidecelerate             ; If zero → coast mode (decelerate gently)
    cmp #$01                     ; Compare with brake command value
    bne ai_accelerate            ; If not $01 → must be $FF (accelerate)
    jmp aibrake                  ; If $01 → apply brakes (heavy deceleration)

; ==============================================================================
; ai_accelerate - AI car acceleration handler
; Purpose: Increase AI car velocity by incrementing 24-bit fixed-point speed
; Method: Add $08 to fractional byte, carry propagates to integer bytes
; Entry: Y register contains AI car index (0-2)
; Exit: Falls through to aicoast for position update
; ==============================================================================
ai_accelerate:
    ; --- Increment Speed with Fixed-Point Addition ---
    ; Add $08 to fractional byte (acceleration rate)
    ; Carry propagation through 24-bit value creates smooth speed increase
    clc                          ; Clear carry for 24-bit addition
    lda aicar_Speed_F,y          ; Load speed fractional byte
    adc #$08                     ; Add acceleration force (8 units)
    sta aicar_Speed_F,y          ; Store updated fractional speed
    lda aicar_Speed_L,y          ; Load speed low byte
    adc #$00                     ; Add carry propagation from fraction
    sta aicar_Speed_L,y          ; Store updated low byte
    lda aicar_Speed_H,y          ; Load speed high byte
    adc #$00                     ; Add carry propagation from low byte
    sta aicar_Speed_H,y          ; Store updated high byte (max speed overflow)

; ==============================================================================
; aicoast - AI car velocity-to-position conversion (movement application)
; Purpose: Convert current velocity and heading to world position displacement
; Method: Uses hardware MULU to compute: displacement = velocity × direction_vector
; Process:
;   1. Load direction vector from VectorX/Y tables based on rotation
;   2. Multiply vector by AI car speed using MULU coprocessor
;   3. Check vector sign flag to determine add/subtract operation
;   4. Apply signed displacement to 24-bit world position (X, then Y)
; Entry: Y register contains AI car index, X loaded with rotation for lookups
; Exit: Updates aicar_posX/Y_F/L/H with new world coordinates, branches to updatePos
; ==============================================================================
aicoast:
    ; ==============================================================================
    ; SECTION: X-Axis Movement Calculation
    ; Purpose: Compute horizontal displacement based on heading and speed
    ; Formula: posX += (VectorX[rotation] × speed) [signed]
    ; ==============================================================================

    ; --- Load Direction Vector for X-Axis ---
    ldx aicar_Rotation,y         ; X = AI car heading angle (0-31) for table lookup
    lda VectorX_F,x              ; Load X vector fractional component (sub-unit precision)
    sta MULU_A_L                 ; Store in MULU multiplicand low byte
    lda VectorX_L,x              ; Load X vector integer component (primary direction)
    sta MULU_A_H                 ; Store in MULU multiplicand high byte

    ; --- Load Speed as Multiplier ---
    lda aicar_Speed_F,y          ; Load AI speed fractional byte
    sta MULU_B_L                 ; Store in MULU multiplier low byte
    lda aicar_Speed_L,y          ; Load AI speed integer low byte
    sta MULU_B_H                 ; Store in MULU multiplier high byte
    ; Hardware multiply executes: MULU result = (VectorX × speed) → 32-bit product

    ; --- Check Vector Sign and Apply Displacement ---
    lda VectorX_S,x              ; Load X vector sign flag (0=positive, !0=negative)
    bne aiNegX                   ; If non-zero → subtract (westward movement)

    ; --- Positive X: Add Eastward Displacement ---
    ; Apply rightward/eastward movement (add product to position)
    clc                          ; Clear carry for 24-bit addition
    lda aicar_posX_F,y           ; Load position fractional byte
    adc MULU_LH                  ; Add product low-mid byte (fractional contribution)
    sta aicar_posX_F,y           ; Store updated fractional position
    lda aicar_posX_L,y           ; Load position low byte
    adc MULU_HL                  ; Add product mid-high byte (integer contribution)
    sta aicar_posX_L,y           ; Store updated low byte
    lda aicar_posX_H,y           ; Load position high byte
    adc MULU_HH                  ; Add product high byte (carry/overflow)
    sta aicar_posX_H,y           ; Store updated high byte
    bra aisolveY                 ; Skip negative handler, proceed to Y-axis

aiNegX:
    ; --- Negative X: Subtract Westward Displacement ---
    ; Apply leftward/westward movement (subtract product from position)
    sec                          ; Set carry for 24-bit subtraction
    lda aicar_posX_F,y           ; Load position fractional byte
    sbc MULU_LH                  ; Subtract product low-mid byte
    sta aicar_posX_F,y           ; Store updated fractional position
    lda aicar_posX_L,y           ; Load position low byte
    sbc MULU_HL                  ; Subtract product mid-high byte with borrow
    sta aicar_posX_L,y           ; Store updated low byte
    lda aicar_posX_H,y           ; Load position high byte
    sbc MULU_HH                  ; Subtract product high byte with borrow
    sta aicar_posX_H,y           ; Store updated high byte

aisolveY:
    ; ==============================================================================
    ; SECTION: Y-Axis Movement Calculation
    ; Purpose: Compute vertical displacement based on heading and speed
    ; Formula: posY += (VectorY[rotation] × speed) [signed]
    ; Note: MULU_B still contains speed from previous X calculation (reused)
    ; ==============================================================================

    ; --- Load Direction Vector for Y-Axis ---
    ldx aicar_Rotation,y         ; X = AI car heading angle (reload for Y lookup)
    lda VectorY_F,x              ; Load Y vector fractional component
    sta MULU_A_L                 ; Store in MULU multiplicand low byte
    lda VectorY_L,x              ; Load Y vector integer component
    sta MULU_A_H                 ; Store in MULU multiplicand high byte
    ; MULU_B unchanged (still contains speed), hardware executes: VectorY × speed

    ; --- Check Vector Sign and Apply Displacement ---
    lda VectorY_S,x              ; Load Y vector sign flag (0=positive, !0=negative)
    bne aiNegY                   ; If non-zero → subtract (northward movement)

    ; --- Positive Y: Add Southward Displacement ---
    ; Apply downward/southward movement (add product to position)
    clc                          ; Clear carry for 24-bit addition
    lda aicar_posY_F,y           ; Load position fractional byte
    adc MULU_LH                  ; Add product low-mid byte (fractional contribution)
    sta aicar_posY_F,y           ; Store updated fractional position
    lda aicar_posY_L,y           ; Load position low byte
    adc MULU_HL                  ; Add product mid-high byte (integer contribution)
    sta aicar_posY_L,y           ; Store updated low byte
    lda aicar_posY_H,y           ; Load position high byte
    adc MULU_HH                  ; Add product high byte (carry/overflow)
    sta aicar_posY_H,y           ; Store updated high byte
    bra updatePos                ; Movement complete → update screen projection

aiNegY:
    ; --- Negative Y: Subtract Northward Displacement ---
    ; Apply upward/northward movement (subtract product from position)
    sec                          ; Set carry for 24-bit subtraction
    lda aicar_posY_F,y           ; Load position fractional byte
    sbc MULU_LH                  ; Subtract product low-mid byte
    sta aicar_posY_F,y           ; Store updated fractional position
    lda aicar_posY_L,y           ; Load position low byte
    sbc MULU_HL                  ; Subtract product mid-high byte with borrow
    sta aicar_posY_L,y           ; Store updated low byte
    lda aicar_posY_H,y           ; Load position high byte
    sbc MULU_HH                  ; Subtract product high byte with borrow
    sta aicar_posY_H,y           ; Store updated high byte

end_aimove:
    rts                          ; Return from AI movement routine

; ***************************************************************************************************************
; updatePos - Tilemap scroll and speedometer UI update system
;
; Purpose:
;   Updates hardware tilemap scroll registers to center player on screen and refreshes
;   speedometer needle sprite position based on current player velocity. This routine
;   is the final step in the movement pipeline, converting world coordinates to viewport
;   coordinates and updating UI elements.
;
; Algorithm:
;   1. Calculate tilemap scroll position (player world pos - screen center offset)
;   2. Write scroll position to VKY_TM0 hardware registers (X and Y)
;   3. Save scroll position to variables (used by AI sprite projection)
;   4. Calculate speedometer needle position (speed × scale factor)
;   5. Apply centering offset to speedometer position
;   6. Update speedometer sprite hardware registers
;
; Inputs:
;   PlayerPOS_X_L/H - Player world X position (16-bit integer, fractional byte ignored)
;   PlayerPOS_Y_L/H - Player world Y position (16-bit integer, fractional byte ignored)
;   playerSpeed_F/L - Player velocity (16-bit fixed-point, F=fraction, L=integer)
;   tile_x_offset - Screen center X offset constant (160 pixels)
;   tile_y_offset - Screen center Y offset constant (136 pixels)
;   speedo_scale - Speedometer scaling factor constant ($20 = 32)
;
; Outputs:
;   VKY_TM0_POS_X_L/H - Tilemap 0 X scroll position (hardware register)
;   VKY_TM0_POS_Y_L/H - Tilemap 0 Y scroll position (hardware register)
;   tilePOSX_L/H - Cached tilemap X position (used by aiCarsMove for screen projection)
;   tilePOSY_L/H - Cached tilemap Y position (used by aiCarsMove for screen projection)
;   Speedo_sprite_base+SP_POS_X_L/H - Speedometer needle sprite X position (hardware register)
;
; Uses:
;   MULU_A_L/H - Hardware multiplier input A (player speed)
;   MULU_B_L/H - Hardware multiplier input B (scale factor)
;   MULU_LH/HL - Hardware multiplier output (scaled speed result)
;   speedo_X_L/H - Temporary speedometer X position (16-bit)
;
; Hardware Interaction:
;   TinyVicky Tilemap Registers:
;     VKY_TM0_POS_X_L/H - Tilemap horizontal scroll (pixels)
;     VKY_TM0_POS_Y_L/H - Tilemap vertical scroll (pixels)
;   TinyVicky Sprite Registers:
;     Speedo_sprite_base+SP_POS_X_L/H - Sprite X position (screen-relative pixels)
;
; Notes:
;   - Tilemap scroll creates parallax effect (world moves opposite to player)
;   - Screen center offsets (160, 136) keep player car centered on display
;   - Speedometer uses slot 0 (highest priority, always visible on top)
;   - Speed scaling converts velocity to pixel displacement for needle animation
;   - Centering offset ($66 = 102 pixels) positions needle on speedometer gauge
;   - Y position of speedometer is static (set during initialization)
; ***************************************************************************************************************
updatePos:

; ==============================================================================
; SECTION: Tilemap Scroll Position Update (Player-Centered Camera)
; Purpose: Calculate and write viewport scroll position to center player on screen
; Method: scroll_pos = player_world_pos - screen_center_offset
; Result: Tilemap shifts opposite to player movement, creating camera follow effect
; ==============================================================================

    ; --- Calculate Tilemap X Scroll Position ---
    ; Player is at world position PlayerPOS_X, we want them centered at pixel 160
    ; Tilemap scroll formula: scroll_X = player_world_X - 160
    ; This shifts the map left when player moves right, right when player moves left
    sec                          ; Set carry for 16-bit subtraction
    lda PlayerPOS_X_L            ; Load player world X position low byte
    sbc #tile_x_offset           ; Subtract screen center X offset (160 pixels)
    sta VKY_TM0_POS_X_L          ; Write to tilemap X scroll hardware register
    sta tilePOSX_L               ; Cache for AI sprite screen projection calculations
    lda PlayerPOS_X_H            ; Load player world X position high byte
    sbc #0                       ; Subtract borrow propagation only (high byte offset is 0)
    sta VKY_TM0_POS_X_H          ; Write to tilemap X scroll high byte register
    sta tilePOSX_H               ; Cache high byte for AI calculations

    ; --- Calculate Tilemap Y Scroll Position ---
    ; Player is at world position PlayerPOS_Y, we want them centered at pixel 136
    ; Tilemap scroll formula: scroll_Y = player_world_Y - 136
    ; This shifts the map up when player moves down, down when player moves up
    sec                          ; Set carry for 16-bit subtraction
    lda PlayerPOS_Y_L            ; Load player world Y position low byte
    sbc #tile_y_offset           ; Subtract screen center Y offset (136 pixels)
    sta VKY_TM0_POS_Y_L          ; Write to tilemap Y scroll hardware register
    sta tilePOSY_L               ; Cache for AI sprite screen projection calculations
    lda PlayerPOS_Y_H            ; Load player world Y position high byte
    sbc #0                       ; Subtract borrow propagation only (high byte offset is 0)
    sta VKY_TM0_POS_Y_H          ; Write to tilemap Y scroll high byte register
    sta tilePOSY_H               ; Cache high byte for AI calculations

; ==============================================================================
; SECTION: Speedometer Needle Position Calculation
; Purpose: Convert player velocity to speedometer needle sprite X position
; Method: needle_pos = (player_speed × scale_factor) + centering_offset
; Hardware: Uses MULU coprocessor for fixed-point multiplication
; ==============================================================================

    ; --- Load Speed into Hardware Multiplier ---
    ; Player speed is 24-bit fixed-point (F.L.H), we use fractional and low bytes (16-bit)
    ; This gives us sub-pixel precision for smooth needle animation
    lda playerSpeed_F            ; Load player speed fractional byte (sub-unit precision)
    sta MULU_A_L                 ; Store in MULU multiplicand low byte
    lda playerSpeed_L            ; Load player speed integer low byte (primary value)
    sta MULU_A_H                 ; Store in MULU multiplicand high byte

    ; --- Load Scale Factor into Hardware Multiplier ---
    ; Scale factor converts speed units to pixel displacement on speedometer gauge
    ; speedo_scale = $20 (32 decimal) provides appropriate needle travel range
    lda #speedo_scale            ; Load speedometer scaling constant ($20 = 32)
    sta MULU_B_L                 ; Store in MULU multiplier low byte
    stz MULU_B_H                 ; Clear multiplier high byte (scale factor < 256)
    ; Hardware multiply executes: MULU result = (player_speed × $20) → 32-bit product

    ; --- Extract Scaled Result from Multiplier Output ---
    ; MULU produces 32-bit result (LL, LH, HL, HH), we extract middle bytes (LH, HL)
    ; This gives us the properly scaled 16-bit pixel position for the needle
    lda MULU_LH                  ; Load product low-mid byte (scaled position low)
    sta speedo_X_L               ; Store in speedometer X low byte
    lda MULU_HL                  ; Load product mid-high byte (scaled position high)
    sta speedo_X_H               ; Store in speedometer X high byte

    ; --- Apply Centering Offset to Needle Position ---
    ; Add $66 (102 pixels) to position needle at rest position on speedometer dial
    ; This offset places zero-speed at leftmost position of gauge arc
    clc                          ; Clear carry for 16-bit addition
    lda speedo_X_L               ; Load scaled speed low byte
    adc #$66                     ; Add centering offset (102 pixels)
    sta speedo_X_L               ; Store centered position low byte
    lda speedo_X_H               ; Load scaled speed high byte
    adc #0                       ; Add carry propagation only
    sta speedo_X_H               ; Store centered position high byte

; ==============================================================================
; SECTION: Speedometer Sprite Hardware Register Update
; Purpose: Write calculated needle position to sprite system registers
; Method: Direct write to sprite position registers (X only, Y is static)
; Note: Speedometer uses sprite slot 0 (highest priority, always visible)
; ==============================================================================

    ; --- Write Needle Position to Sprite Registers ---
    ; Speedo_sprite_base points to slot 0 sprite registers (8 bytes starting at VKY_SP0)
    ; SP_POS_X_L/H are offset +4/+5 from sprite base address
    lda speedo_X_L               ; Load final speedometer X position low byte
    sta Speedo_sprite_base+SP_POS_X_L  ; Write to sprite X position low register
    lda speedo_X_H               ; Load final speedometer X position high byte
    sta Speedo_sprite_base+SP_POS_X_H  ; Write to sprite X position high register
    ; Note: Y position (SP_POS_Y_L/H) remains static, set during initialization

    rts                          ; Return from position update routine


; **************************************************************************************************************
; readInputs - Player and AI car sprite rotation update system
;
; Purpose:
;   Processes joystick input to update player car rotation/heading and refreshes sprite graphics
;   for both player and AI cars. Uses frame-based throttling to control rotation speed and 
;   dynamically calculates sprite addresses based on rotation angle for smooth animated turning.
;
; Algorithm:
;   1. Frame Throttling: Only updates rotation every 4 frames (15 Hz at 60 FPS)
;   2. Player Rotation: Adds horizontal joystick delta (-1/0/+1) to 5-bit rotation (0-31)
;   3. Player Sprite: Calculates sprite address by adding rotation to base address
;   4. AI Car Loop: Iterates through 3 AI cars, updating rotation and sprite addresses
;   5. Sprite Registers: Updates SP_AD_L/M/H registers for hardware sprite system
;
; Inputs:
;   joyX - Player horizontal input: $FF=left, $00=straight, $01=right
;   PlayerRotation - Current player heading angle (0-31, where 0=north, 8=east, etc.)
;   aicar_Rotation[0-2] - Current AI car heading angles (0-31 range)
;   aicar_JoyX[0-2] - AI virtual horizontal inputs (set by AI pathfinder)
;   aicar_sprite_L/M[0-2] - Base sprite address components for AI car graphics
;
; Outputs:
;   PlayerRotation - Updated player heading (wrapped to 0-31 range)
;   aicar_Rotation[0-2] - Updated AI car headings (wrapped to 0-31 range)
;   car_sprite_base+SP_AD_L/M/H - Player sprite address registers (3-byte pointer)
;   car_sprite_base+SP_AD_L/M/H,Y - AI car sprite address registers (indexed by Y)
;
; Uses:
;   carDelay - Frame counter for rotation update throttling (0-3)
;   X register - Player rotation / AI car loop index (0-2)
;   Y register - AI sprite register offset calculation (8, 16, 24)
;
; Sprite Address Calculation:
;   Each rotation angle (0-31) maps to a different sprite frame for smooth turning animation.
;   The sprite system expects a 24-bit address split across three registers:
;     SP_AD_L = Low byte (constant, base address of sprite set)
;     SP_AD_M = Mid byte (varies with rotation: base_mid + rotation_angle)
;     SP_AD_H = High byte (bank number, typically $01)
;   Example: blue_car1 base = $01:$2000, rotation 5 → $01:$2005
;
; Sprite Register Offsets:
;   Player car uses slot 20 (car_sprite_base = VKY_SP0 + 8*20)
;   AI cars use slots 21-23 (offset = 8 * (car_index + 1) = 8, 16, 24)
;   Each sprite slot is 8 consecutive bytes in sprite register area
;
; Frame Throttling:
;   carDelay cycles 0→1→2→3→0 every frame
;   Rotation only updates when carDelay wraps from 3→0
;   This reduces turn rate from 60 Hz to 15 Hz for smoother gameplay
;
; Notes:
;   - Rotation wraps using AND #$1f (32 angles = 360° / 11.25° per step)
;   - Sprite graphics must be pre-rendered for all 32 rotation angles
;   - AI cars use same rotation system as player for consistent turning
; **************************************************************************************************************
readInputs:
    ; ==============================================================================
    ; SECTION: Frame Throttling for Rotation Updates
    ; Purpose: Slow down rotation rate from 60 Hz to 15 Hz for better control
    ; Method: Increment counter (0-3), only update when wrapping to 0
    ; ==============================================================================
    inc carDelay                 ; Increment frame counter (0→1→2→3→0)
    lda carDelay                 ; Load current count
    cmp #$04                     ; Check if reached throttle limit (4 frames)
    bne CMskip                   ; Not time yet → skip all rotation updates
    stz carDelay                 ; Reset counter for next 4-frame cycle

    ; ==============================================================================
    ; SECTION: Player Car Rotation Update
    ; Purpose: Apply joystick steering input to player heading angle
    ; Method: Add joyX delta (-1/0/+1) to rotation, wrap to 5-bit range (0-31)
    ; ==============================================================================
    clc                          ; Clear carry for 8-bit addition
    lda PlayerRotation           ; Load current heading (0-31)
    adc joyX                     ; Add horizontal input (-1=left, 0=straight, +1=right)
    and #$1f                     ; Wrap to 5-bit range (0-31) using bitmask
    sta PlayerRotation           ; Store updated heading

    ; ==============================================================================
    ; SECTION: Player Car Sprite Address Update
    ; Purpose: Calculate hardware sprite pointer based on rotation angle
    ; Method: Base address + rotation = frame-specific sprite graphic
    ; Sprite Format: 24-bit address split as [bank:high:low] → [SP_AD_H:SP_AD_M:SP_AD_L]
    ; ==============================================================================
    tax                          ; Transfer rotation to X for indexing (not used here)
    lda #<blue_car1              ; Load low byte of base sprite address (constant)
    sta car_sprite_base+SP_AD_L  ; Write to sprite address low register
    lda #>blue_car1              ; Load mid byte of base sprite address
    clc                          ; Clear carry for rotation offset addition
    adc PlayerRotation           ; Add rotation angle to mid byte (selects frame)
    sta car_sprite_base+SP_AD_M  ; Write to sprite address mid register
    lda #$01                     ; Load high byte (bank number in memory map)
    sta car_sprite_base+SP_AD_H  ; Write to sprite address high register

    ; ==============================================================================
    ; SECTION: AI Car Rotation and Sprite Update Loop
    ; Purpose: Process all 3 AI cars (indices 0, 1, 2) using same rotation logic
    ; Method: Indexed loop through parallel arrays for rotation, input, and sprites
    ; ==============================================================================
    ldx #$00                     ; Initialize loop counter (AI car index 0)

loopAI:
    ; --- Update AI Car Rotation ---
    ; Apply AI virtual joystick input (aicar_JoyX) to AI car heading
    clc                          ; Clear carry for 8-bit addition
    lda aicar_Rotation,x         ; Load AI car current heading (0-31)
    adc aicar_JoyX,x             ; Add AI steering input (from pathfinder AI)
    and #$1f                     ; Wrap to 5-bit range (0-31) using bitmask
    sta aicar_Rotation,X         ; Store updated AI car heading

    ; --- Calculate Sprite Register Offset ---
    ; Convert AI car index (0-2) to sprite register offset (8, 16, 24)
    ; Formula: Y = 8 * (X + 1) = sprite slot offset from car_sprite_base
    ; X=0 → Y=8 (slot 21), X=1 → Y=16 (slot 22), X=2 → Y=24 (slot 23)
    txa                          ; Transfer car index to A
    asl                          ; Multiply by 2 (X * 2)
    asl                          ; Multiply by 2 again (X * 4)
    asl                          ; Multiply by 2 again (X * 8)
    clc                          ; Clear carry for offset addition
    adc #$08                     ; Add 8 to get sprite register offset (8, 16, 24)
    tay                          ; Transfer result to Y for indexed addressing

    ; --- Update AI Car Sprite Address Registers ---
    ; Write 24-bit sprite address into hardware sprite registers using Y offset
    lda aicar_sprite_L,X         ; Load AI sprite base address low byte
    sta car_sprite_base+SP_AD_L,y ; Write to sprite address low register
    lda aicar_sprite_M,X         ; Load AI sprite base address mid byte
    clc                          ; Clear carry for rotation offset
    adc aicar_Rotation,x         ; Add rotation to mid byte (select frame)
    sta car_sprite_base+SP_AD_M,y ; Write to sprite address mid register
    lda #$01                     ; Load bank number (constant for all cars)
    sta car_sprite_base+SP_AD_H,y ; Write to sprite address high register

    ; --- Loop Control ---
    inx                          ; Increment AI car index (0→1→2→3)
    cpx #$03                     ; Check if processed all 3 AI cars
    bne loopAI                   ; Not done → loop back for next AI car

CMskip:
    rts                          ; Return from input processing routine
; ***************************************************************************************************************

; ***************************************************************************************************************
    ; ai - AI car decision-making coordinator
    ;
    ; Purpose:
;   Per-frame entry point for AI car intelligence system. Orchestrates pathfinding and
;   speed control decisions, then translates results into virtual joystick inputs that
;   drive the AI car movement physics (via aimoveCar routine).
;
; Algorithm:
;   1. Clear previous frame's virtual input state (turn/gas/button)
;   2. Call ai_Pathfinder to compute steering and throttle decisions
;   3. Read pathfinder results from TURN_FLAG and GAS_FLAG globals
;   4. Store results into AI car's virtual joystick arrays
;   5. Return control to caller (UpdateScreen game loop)
;
; Inputs:
;   aicar_current - Index of current AI car being processed (0, 1, or 2)
;   aicar_Rotation[X] - Current AI car heading (0-31, used by pathfinder)
;   aicar_posX/Y_L/H[X] - Current AI car world position (used by pathfinder)
;   aicar_target[X] - Current waypoint index this AI car is targeting
;   aicar_TgtSpd_F/L[X] - Target speed for current waypoint (used for throttle decisions)
;   aicar_speed_F/L/H[X] - Current AI car speed (used for throttle decisions)
;
; Outputs:
;   aicar_JoyX[X] - Virtual horizontal input: $FF=left, $00=straight, $01=right
;   aicar_JoyY[X] - Virtual vertical input: $FF=accelerate, $00=coast, $01=brake
;   aicar_JoyB[X] - Virtual button input: $00=not pressed (unused by AI currently)
;
; Side Effects:
;   Modifies TURN_FLAG and GAS_FLAG globals (via ai_Pathfinder call)
;   Clobbers A, X registers
;   Preserves Y register
;
; Called By:
;   UpdateScreen game loop (once per frame, per AI car in ai_loop)
;
; Calls:
;   ai_Pathfinder - Computes steering and speed decisions using outrigger pathfinding
;
; Notes:
;   - Virtual joystick arrays (aicar_Joy*) mirror player input structure for code reuse
;   - aimoveCar routine reads these arrays to apply physics (acceleration, turning, etc.)
;   - AI decision frequency is per-frame (60 Hz), no throttling at this level
;   - Pathfinder uses same outrigger algorithm as helicopter for consistency
;   - Future enhancements could add collision avoidance or overtaking logic here
; ***************************************************************************************************************
ai:    
    ; --- STEP 1: Clear previous frame's virtual joystick state ---
    ; Reset all three virtual input channels to neutral/zero state before computing
    ; new decisions. This ensures clean state if pathfinder skips updating a channel.
    ldx aicar_current               ; X = AI car index (0, 1, or 2)
    lda #$00                        ; A = neutral input value (no turn, no throttle change)
    sta aicar_JoyX,x                ; Clear horizontal input (turn left/right/straight)
    sta aicar_JoyY,x                ; Clear vertical input (accelerate/brake/coast)
    sta aicar_JoyB,x                ; Clear button input (unused by AI, reserved for future)

    ; --- STEP 2: Compute AI decisions via pathfinding system ---
    ; ai_Pathfinder analyzes current position, target waypoint, rotation, and speed
    ; to determine optimal steering (TURN_FLAG) and throttle (GAS_FLAG) commands.
    ; Results are written to global flag variables for retrieval below.
    jsr ai_Pathfinder               ; Call pathfinding: sets TURN_FLAG and GAS_FLAG

    ; --- STEP 3: Load AI car index again (X may be clobbered by pathfinder) ---
    ; ai_Pathfinder may use X register internally, so reload car index to ensure
    ; correct indexing when storing results back to per-car arrays.
    ldx aicar_current               ; X = AI car index (restore after subroutine call)

    ; --- STEP 4: Store steering decision into virtual joystick ---
    ; TURN_FLAG values: $FF=turn left (-1), $00=go straight (0), $01=turn right (+1)
    ; These map directly to joystick horizontal axis semantics used by readInputs/aimoveCar
    lda TURN_FLAG                   ; Load steering decision from pathfinder result
    sta aicar_JoyX,x                ; Store into AI car's virtual horizontal input

    ; --- STEP 5: Store throttle decision into virtual joystick ---
    ; GAS_FLAG values: $FF=accelerate (-1), $00=coast (0), $01=brake (+1)
    ; These map to joystick vertical axis semantics used by aimoveCar physics
    lda GAS_FLAG                    ; Load throttle decision from pathfinder result
    sta aicar_JoyY,x                ; Store into AI car's virtual vertical input

    ; --- STEP 6: Return to game loop ---
    ; Control returns to UpdateScreen's ai_loop, which will call aimoveCar to apply
    ; these virtual inputs as physics forces (rotation change, acceleration/braking).
    rts                             ; Return from AI decision routine



; **************************************************************************************************************
; aiCarsMove - AI car sprite screen projection and visibility culling
;
; Purpose:
;   Convert AI car world position to screen-relative coordinates and update sprite registers.
;   Enable sprite rendering when car is visible on screen, disable when off-screen to save
;   rendering cycles and prevent visual artifacts.
;
; Algorithm:
;   1. Calculate viewport offset (tilemap scroll position - screen margin)
;   2. Compute AI car screen delta (car world position - viewport offset)
;   3. Calculate sprite register offset based on car index
;   4. Perform visibility range tests on signed 16-bit screen deltas
;   5. If visible: enable sprite and update position registers
;   6. If off-screen: disable sprite rendering
;
; Inputs:
;   aicar_current - Index of current AI car (0-2)
;   aicar_posX/Y_L/H[X] - AI car world position (16-bit signed)
;   tilePOSX/Y_L/H - Current tilemap scroll position (viewport top-left corner)
;   ai_x_offset - Screen margin X offset (24 pixels)
;   ai_y_offset - Screen margin Y offset (24 pixels)
;
; Outputs:
;   car_sprite_base+SP_CTRL,Y - Sprite control register (enable/disable)
;   car_sprite_base+SP_POS_X_L/H,Y - Sprite X position (signed 16-bit screen delta)
;   car_sprite_base+SP_POS_Y_L/H,Y - Sprite Y position (signed 16-bit screen delta)
;
; Uses:
;   tmpx/tmpx+1 - Temporary signed 16-bit screen-relative X coordinate
;   tmpy/tmpy+1 - Temporary signed 16-bit screen-relative Y coordinate
;   X register - AI car index (aicar_current)
;   Y register - Sprite register offset (8 * (car_index + 1))
;
; Notes:
;   - Sprites use screen-relative coordinates (not world coordinates)
;   - Sprite slot allocation: Player=slot 20, AI cars=slots 21-23
;   - Negative screen deltas indicate off-screen left/top
;   - Visibility bounds: X: -1 to 351, Y: -1 to 271 pixels
; **************************************************************************************************************
aiCarsMove:

; ==============================================================================
; SECTION: Screen Projection (World → Screen Coordinate Conversion)
; Purpose: Convert tilemap scroll position to viewport offset
; Method: viewport_offset = tilemap_scroll - screen_margin
; Result: tmpx/tmpy contain viewport top-left corner in world space
; ==============================================================================

    ; --- Calculate viewport left edge: tmpx = tilePOSX - ai_x_offset ---
    ; tilePOSX represents the current tilemap scroll position (player-centered)
    ; Subtract screen margin (24 pixels) to find viewport left edge in world space
    sec                             ; Set carry for 16-bit subtraction
    lda tilePOSX_L                  ; Load tilemap X position low byte
    sbc #ai_x_offset                ; Subtract X margin ($18 = 24 pixels)
    sta tmpx                        ; Store viewport left edge low byte
    lda tilePOSX_H                  ; Load tilemap X position high byte
    sbc #0                          ; Subtract borrow propagation only
    sta tmpx+1                      ; Store viewport left edge high byte

    ; --- Calculate viewport top edge: tmpy = tilePOSY - ai_y_offset ---
    ; Same process for Y axis - compute viewport top edge in world space
    sec                             ; Set carry for 16-bit subtraction
    lda tilePOSY_L                  ; Load tilemap Y position low byte
    sbc #ai_y_offset                ; Subtract Y margin ($18 = 24 pixels)
    sta tmpy                        ; Store viewport top edge low byte
    lda tilePOSY_H                  ; Load tilemap Y position high byte
    sbc #0                          ; Subtract borrow propagation only
    sta tmpy+1                      ; Store viewport top edge high byte

; ==============================================================================
; SECTION: AI Car Screen Delta Calculation
; Purpose: Compute screen-relative position for current AI car
; Method: screen_delta = car_world_position - viewport_offset
; Result: tmpx/tmpy contain signed 16-bit screen coordinates (can be negative)
; ==============================================================================

    ; --- Load current AI car index ---
    ldx aicar_current               ; X = AI car index (0, 1, or 2)

    ; --- Calculate screen-relative X: tmpx = aicar_posX - tmpx ---
    ; Subtract viewport left edge from car world X to get screen delta
    ; Result is signed: negative if car is left of screen, positive if on/right
    sec                             ; Set carry for 16-bit subtraction
    lda aicar_posX_L,x              ; Load AI car world X position low byte
    sbc tmpx                        ; Subtract viewport left edge low byte
    sta tmpx                        ; Store screen-relative X delta low byte
    lda aicar_posX_H,x              ; Load AI car world X position high byte
    sbc tmpx+1                      ; Subtract viewport left edge high (with borrow)
    sta tmpx+1                      ; Store screen-relative X delta high byte (sign in bit 7)

    ; --- Calculate screen-relative Y: tmpy = aicar_posY - tmpy ---
    ; Subtract viewport top edge from car world Y to get screen delta
    ; Result is signed: negative if car is above screen, positive if on/below
    sec                             ; Set carry for 16-bit subtraction
    lda aicar_posY_L,x              ; Load AI car world Y position low byte
    sbc tmpy                        ; Subtract viewport top edge low byte
    sta tmpy                        ; Store screen-relative Y delta low byte
    lda aicar_posY_H,x              ; Load AI car world Y position high byte
    sbc tmpy+1                      ; Subtract viewport top edge high (with borrow)
    sta tmpy+1                      ; Store screen-relative Y delta high byte (sign in bit 7)

; ==============================================================================
; SECTION: Calculate Sprite Register Offset
; Purpose: Compute Y register offset for accessing sprite registers
; Method: Y = 8 * (car_index + 1) = sprite slot offset from car_sprite_base
; Sprite allocation: Player=slot 20, AI car 0=slot 21, AI car 1=slot 22, AI car 2=slot 23
; Each sprite slot is 8 bytes, so offset = 8 * (aicar_current + 1)
; ==============================================================================

    ; --- Calculate sprite register offset: Y = X * 8 + 8 ---
    ; TXA + ASL*3 + ADC implements: Y = (car_index * 8) + 8
    ; This gives Y = 8, 16, or 24 for AI cars 0, 1, 2 respectively
    txa                             ; Transfer car index to A (0, 1, or 2)
    asl                             ; car_index * 2
    asl                             ; car_index * 4
    asl                             ; car_index * 8
    clc                             ; Clear carry for addition
    adc #$08                        ; Add 8 to skip player sprite slot
    tay                             ; Y = sprite register offset (8, 16, or 24)

; ==============================================================================
; SECTION: Visibility Range Testing
; Purpose: Determine if AI car sprite is within visible screen bounds
; Method: Test signed 16-bit screen deltas using high byte (sign) and low byte (magnitude)
; Strategy:
;   - High byte negative (BMI): off-screen left/top → disable
;   - High byte == 0: small positive range (0-255) → fine-grain check
;   - High byte == 1: medium range (256-511) → fine-grain check
;   - High byte >= 2: large range (512+) → off-screen right/bottom → disable
; Visibility bounds: X: 0 to ~350 pixels, Y: 0 to ~270 pixels
; ==============================================================================

    ; --- X-axis visibility check ---
    lda tmpx+1                      ; Load screen-relative X high byte (sign byte)
    bmi disableSprite               ; If negative (bit 7 set), off-screen left → disable
    beq checkY                      ; If zero (0-255 range), within bounds → check Y axis
    cmp #$02                        ; Compare high byte to 2 (checking if X >= 512)
    bcs disableSprite               ; If >= 2 (X >= 512 pixels), off-screen right → disable
    
    ; High byte is 1 (X in 256-511 range), perform fine-grain low byte check
    lda tmpx                        ; Load screen-relative X low byte
    cmp #$60                        ; Compare to $60 (96 decimal)
    bcs disableSprite               ; If >= 96, total X >= 352 pixels → too far right → disable

checkY:
    ; --- Y-axis visibility check (mirrors X-axis logic) ---
    lda tmpy+1                      ; Load screen-relative Y high byte (sign byte)
    bmi disableSprite               ; If negative (bit 7 set), off-screen top → disable
    beq enableSprite                ; If zero (0-255 range), within bounds → enable sprite
    cmp #$02                        ; Compare high byte to 2 (checking if Y >= 512)
    bcs disableSprite               ; If >= 2 (Y >= 512 pixels), off-screen bottom → disable
    
    ; High byte is 1 (Y in 256-511 range), perform fine-grain low byte check
    lda tmpy                        ; Load screen-relative Y low byte
    cmp #$10                        ; Compare to $10 (16 decimal)
    bcs disableSprite               ; If >= 16, total Y >= 272 pixels → too far down → disable

; ==============================================================================
; SECTION: Enable Sprite and Update Position Registers (Car Visible)
; Purpose: Set sprite control register to enable rendering and update screen position
; SP_CTRL format: |xx|SZ|SZ|LA|LA|LU|LU|EN|
; Bits: SZ=size (01=16x16), LA=layer (01=layer 1), LU=LUT (0), EN=enable (1=on)
; ==============================================================================

enableSprite:
    ; --- Enable AI car sprite ---
    lda #%01010001                  ; Size 16x16, layer 1, LUT 0, enable=1
    sta car_sprite_base+SP_CTRL,y   ; Set sprite control register (Y = slot offset)
    
    ; --- Update sprite X position registers ---
    ; Write signed 16-bit screen delta to sprite position registers
    lda tmpx                        ; Load screen-relative X delta low byte
    sta car_sprite_base+SP_POS_X_L,y ; Set sprite X position low byte
    lda tmpx+1                      ; Load screen-relative X delta high byte (sign)
    sta car_sprite_base+SP_POS_X_H,y ; Set sprite X position high byte
    
    ; --- Update sprite Y position registers ---
    lda tmpy                        ; Load screen-relative Y delta low byte
    sta car_sprite_base+SP_POS_Y_L,y ; Set sprite Y position low byte
    lda tmpy+1                      ; Load screen-relative Y delta high byte (sign)
    sta car_sprite_base+SP_POS_Y_H,y ; Set sprite Y position high byte
    rts                             ; Return from aiCarsMove routine

; ==============================================================================
; disableSprite - Disable AI car sprite when off-screen
; Purpose: Turn off sprite rendering to save cycles and prevent visual glitches
; Method: Clear enable bit (bit 0) in SP_CTRL register
; Note: Size and layer bits remain set for faster re-enable next frame
; ==============================================================================

disableSprite:
    ; Disable AI car sprite by clearing enable bit in control register
    lda #%01010000                  ; Size 16x16, layer 1, LUT 0, enable=0
    sta car_sprite_base+SP_CTRL,y   ; Set sprite control register (Y = slot offset)
    rts                             ; Return from aiCarsMove routine

; **************************************************************************************************************
; helicopter_Move - Helicopter sprite AI and rendering system
;
; Purpose: 
;   Manages the helicopter sprite that follows the race action. Each frame, the helicopter
;   autonomously steers toward the average position of all cars (player + AI cars), adjusts
;   its velocity based on heading, applies velocity limits, updates world position, converts
;   to screen coordinates, animates rotor blades, and renders the helicopter body, rotor, and
;   shadows when on-screen.
;
; Algorithm Overview:
;   1. Turn Rate Throttling: Only recalculates steering every 'turn_rate' frames
;   2. Target Calculation: Computes average X/Y position of all 4 cars using ADD/DIV coprocessors
;   3. Pathfinding: Uses outrigger distance comparison (via finder_math) to determine turn direction
;   4. Velocity Adjustment: Modifies X/Y velocity based on current heading (rotation 0-31)
;   5. Velocity Limiting: Clamps velocity to +/- top_plus_vel to prevent excessive speed
;   6. Position Update: Applies velocity to world position (24-bit fixed-point X/Y)
;   7. Screen Projection: Converts world position to screen-relative coordinates
;   8. Shadow Positioning: Offsets shadow sprites (+16 X, +32 Y from main sprite)
;   9. Visibility Testing: Range checks to enable/disable sprites when off-screen
;   10. Blade Animation: Cycles through 8 rotor frames, alternates shadow visibility
;   11. Sprite Rendering: Updates sprite registers for body, rotor, and shadows
;
; Inputs:
;   helicopter_turn_rate - Frame counter for turn throttling
;   helicopter_ROT - Current heading (0-31, where 0=up, 8=right, 16=down, 24=left)
;   helicopter_POSX/Y_F/L/H - World position (24-bit fixed-point)
;   helicopter_X/Y_VEL_F/L/H - Velocity vectors (24-bit signed fixed-point)
;   PlayerPOS_X/Y_L/H - Player car world position
;   aicar_posX/Y_L[0..2] - AI car world positions
;   tilePOSX/Y_L/H - Current tilemap scroll position (for screen projection)
;   blade_angle - Rotor animation frame counter (0-7)
;   shadow_disp - Shadow flicker toggle for depth effect
;
; Outputs:
;   helicopter_POSX/Y_* - Updated world position
;   helicopter_X/Y_VEL_* - Updated velocity
;   helicopter_ROT - Updated heading
;   helicopter_base+SP_* - Main helicopter sprite registers (address, position, control)
;   helicopter_blade+SP_* - Rotor sprite registers
;   helicopter_shadow+SP_* - Body shadow sprite registers  
;   helicopter_S_blade+SP_* - Rotor shadow sprite registers
;   average_X/Y_L/H - Computed target position (centroid of all cars)
;
; Uses:
;   ADD_* coprocessor registers for 32-bit accumulation
;   DEVU_* coprocessor registers for division by 4
;   MULU_* coprocessor registers (via finder_math for distance calculations)
;   OR_Right*/OR_Left* outrigger tables indexed by rotation
;   tmpx/tmpy zero-page temporaries for screen coordinate conversion
;
; Constants:
;   top_plus_vel = $e0 - Maximum positive velocity
;   top_minus_vel = -$e0 - Maximum negative velocity (two's complement)
;   h_acceleration = $04 - Velocity change per adjustment
;   turn_rate = $10 - Frames between steering recalculations (16 frames)
;   heli_x_offset - Screen edge offset for X projection
;   heli_y_offset - Screen edge offset for Y projection
;
; Notes:
;   - Helicopter uses same pathfinding algorithm as AI cars (outrigger distance comparison)
;   - Velocity is signed 24-bit fixed-point (F=fractional, L=low byte, H=high byte w/ sign)
;   - Rotation values: 0=$00=North, 8=$08=East, 16=$10=South, 24=$18=West
;   - Shadow sprites flicker (alternate frames) to create pseudo-transparency depth effect
;   - Sprite visibility uses signed 16-bit screen deltas with range tolerance checks
; **************************************************************************************************************
helicopter_Move:
    ; --- Local constants for helicopter physics ---
    top_plus_vel = $e0              ; Maximum positive velocity ($e0 = 224)
    top_minus_vel = -top_plus_vel   ; Maximum negative velocity (-224 in two's complement)
    h_acceleration = $04            ; Velocity increment per frame ($04 = 4 units)
    turn_rate = $10                 ; Steering update interval ($10 = 16 frames)

    ; --- Turn rate throttling: only recalculate steering every 16 frames ---
    ; This reduces CPU overhead and creates smoother, more deliberate helicopter movement
    inc helicopter_turn_rate        ; Increment frame counter
    lda helicopter_turn_rate
    cmp #turn_rate                  ; Check if 16 frames have elapsed
    beq take_helicopter_turn        ; If yes, recalculate steering
    jmp skip_helicopter_turn        ; Otherwise, skip to velocity adjustment

; ==============================================================================
; SECTION: Helicopter Steering Calculation (runs every 16 frames)
; Purpose: Determine which direction helicopter should turn to follow the race
; Method: Compute centroid of all cars, use outrigger pathfinding to steer toward it
; ==============================================================================
take_helicopter_turn:
    stz helicopter_turn_rate        ; Reset frame counter for next interval
    stz TURN_FLAG                   ; Initialize turn decision (0 = straight)
    ldy helicopter_ROT              ; Y = current helicopter rotation (0-31) for table lookups

    ; --- STEP 1: Compute average X position of all 4 cars (player + 3 AI) ---
    ; Strategy: Use hardware ADD coprocessor for 32-bit accumulation, then divide by 4
    ; The ADD coprocessor has: ADD_A (operand A), ADD_B (operand B), ADD_R (result)
    ; Each is 32-bit: ..._LL (bits 0-7), ..._LH (8-15), ..._HL (16-23), ..._HH (24-31)
    
    ; Clear accumulator operand A (will hold running sum)
    stz ADD_A_LL
    stz ADD_A_LH
    stz ADD_A_HL
    stz ADD_A_HH
    
    ; Load player X position into operand B (extend 16-bit to 32-bit)
    lda PlayerPOS_X_L               ; Player X low byte
    sta ADD_B_LL
    lda PlayerPOS_X_H               ; Player X high byte
    sta ADD_B_LH
    stz ADD_B_HL                    ; Zero-extend to 32-bit
    stz ADD_B_HH
    ; Note: Writing to ADD_B triggers the add operation, result appears in ADD_R
    
    ; Initialize loop counter to accumulate 3 AI car positions
    ldx #$00                        ; X = AI car index (0, 1, 2)
    
; ==============================================================================
; ai_loop2: Accumulate AI car X positions into running sum
; Purpose: Add each AI car's X coordinate to the accumulator (player already added)
; Loop: 3 iterations (AI cars 0, 1, 2)
; Pattern: Load ADD_R → store to operand A → load AI car X → store to operand B → repeat
; Result: ADD_R contains sum of player X + 3 AI car X positions
; ==============================================================================
ai_loop2:
    ; --- STEP 1: Preserve previous ADD result via temporary buffer ---
    ; The ADD coprocessor overwrites ADD_R on each operation, so we must
    ; copy the current sum to m_result_* before loading operand A.
    ; This 4-byte copy preserves the 32-bit accumulated value.
    lda ADD_R_LL                    ; Load sum byte 0 (bits 0-7)
    sta m_result_LL                 ; Store to temp buffer
    lda ADD_R_LH                    ; Load sum byte 1 (bits 8-15)
    sta m_result_LH
    lda ADD_R_HL                    ; Load sum byte 2 (bits 16-23)
    sta m_result_HL
    lda ADD_R_HH                    ; Load sum byte 3 (bits 24-31)
    sta m_result_HH

    ; --- STEP 2: Load accumulated sum into ADD operand A ---
    ; Transfer the preserved 32-bit sum from m_result_* to ADD_A_*.
    ; This becomes the left-hand operand for the next addition.
    lda m_result_LL
    sta ADD_A_LL                    ; Sum byte 0 → ADD operand A (low-low)
    lda m_result_LH
    sta ADD_A_LH                    ; Sum byte 1 → ADD operand A (low-high)
    lda m_result_HL
    sta ADD_A_HL                    ; Sum byte 2 → ADD operand A (high-low)
    lda m_result_HH
    sta ADD_A_HH                    ; Sum byte 3 → ADD operand A (high-high)
    
    ; --- STEP 3: Load current AI car X position into ADD operand B ---
    ; aicar_posX is a 16-bit signed coordinate indexed by X (AI car number).
    ; Extend to 32-bit by zero-filling upper bytes (treats as positive offset).
    lda aicar_posX_L,x              ; AI car X low byte (bits 0-7)
    sta ADD_B_LL                    ; → ADD operand B (low-low)
    lda aicar_posX_H,x              ; AI car X high byte (bits 8-15, includes sign)
    sta ADD_B_LH                    ; → ADD operand B (low-high)
    stz ADD_B_HL                    ; Zero upper word (bits 16-23)
    stz ADD_B_HH                    ; Zero upper word (bits 24-31)
                                    ; Writing ADD_B_HH triggers: ADD_R ← ADD_A + ADD_B
    
    ; --- STEP 4: Advance to next AI car and loop ---
    inx                             ; X = X + 1 (next AI car index)
    cpx #$03                        ; Processed all 3 AI cars?
    bne ai_loop2                    ; If not, loop back to accumulate next car

; ==============================================================================
; SECTION: Divide accumulated X sum by 4 to compute average
; Hardware: DEVU (division unit)
; Operation: average_X ← (player_X + AI0_X + AI1_X + AI2_X) / 4
; Result: 16-bit average X coordinate stored in average_X_L/H
; ==============================================================================
    ; Load 32-bit sum into DEVU numerator (only need low 16 bits for coordinate average)
    lda ADD_R_LL                    ; Sum byte 0
    sta DEVU_NUM_L                  ; → Numerator low byte
    lda ADD_R_LH                    ; Sum byte 1
    sta DEVU_NUM_H                  ; → Numerator high byte
    
    ; Set divisor = 4 (to compute average of 4 cars)
    lda #$04                        ; Divisor = 4
    sta DEVU_DEN_L                  ; → Denominator low byte
    stz DEVU_DEN_H                  ; → Denominator high byte (zero)
                                    ; Writing DEVU_DEN_H triggers division operation
    
    ; Read quotient (result) from QUOU registers
    lda QUOU_LL                     ; Quotient byte 0 (bits 0-7)
    sta average_X_L                 ; → Average X low byte
    lda QUOU_LH                     ; Quotient byte 1 (bits 8-15)
    sta average_X_H                 ; → Average X high byte
                                    ; average_X now holds centroid X coordinate

; ==============================================================================
; SECTION: Compute average Y position of all 4 cars
; Purpose: Mirror the X-axis averaging process for Y coordinates
; Method: Player Y + AI0_Y + AI1_Y + AI2_Y, then divide by 4
; Hardware: ADD coprocessor for accumulation, DEVU for division
; Result: average_Y_L/H contains centroid Y coordinate
; ==============================================================================

    ; --- Initialize ADD coprocessor for Y accumulation ---
    stz ADD_A_LL                    ; Clear accumulator operand A
    stz ADD_A_LH
    stz ADD_A_HL
    stz ADD_A_HH
    
    ; --- Load player Y position into operand B (first addend) ---
    lda PlayerPOS_Y_L               ; Player Y low byte
    sta ADD_B_LL                    ; → ADD operand B
    lda PlayerPOS_Y_H               ; Player Y high byte (includes sign bit)
    sta ADD_B_LH
    stz ADD_B_HL                    ; Zero-extend to 32-bit
    stz ADD_B_HH                    ; Writing ADD_B_HH triggers: ADD_R ← 0 + player_Y
    
    ldx #$00                        ; Reset loop counter for 3 AI cars

; ==============================================================================
; ai_loop3: Accumulate AI car Y positions (mirrors ai_loop2 for Y-axis)
; Loop: 3 iterations (AI cars 0, 1, 2)
; Result: ADD_R contains sum of player Y + 3 AI car Y positions
; ==============================================================================
ai_loop3:
    ; --- STEP 1: Preserve previous ADD result ---
    lda ADD_R_LL                    ; Copy 32-bit sum from ADD_R
    sta m_result_LL                 ; to temporary buffer m_result_*
    lda ADD_R_LH
    sta m_result_LH
    lda ADD_R_HL
    sta m_result_HL
    lda ADD_R_HH
    sta m_result_HH

    ; --- STEP 2: Load accumulated Y sum into ADD operand A ---
    lda m_result_LL
    sta ADD_A_LL                    ; Transfer preserved sum to operand A
    lda m_result_LH
    sta ADD_A_LH
    lda m_result_HL
    sta ADD_A_HL
    lda m_result_HH
    sta ADD_A_HH
    
    ; --- STEP 3: Load current AI car Y position into operand B ---
    lda aicar_posY_L,x              ; AI car Y low byte (indexed by X)
    sta ADD_B_LL                    ; → ADD operand B
    lda aicar_posY_H,x              ; AI car Y high byte
    sta ADD_B_LH
    stz ADD_B_HL                    ; Zero-extend to 32-bit
    stz ADD_B_HH                    ; Writing ADD_B_HH triggers addition
    
    ; --- STEP 4: Advance and loop ---
    inx                             ; Next AI car index
    cpx #$03                        ; Processed all 3?
    bne ai_loop3                    ; Loop back if more cars remain

; ==============================================================================
; SECTION: Divide accumulated Y sum by 4 to compute average
; Operation: average_Y ← (player_Y + AI0_Y + AI1_Y + AI2_Y) / 4
; Result: 16-bit average Y coordinate in average_Y_L/H
; ==============================================================================
    lda ADD_R_LL                    ; Load 32-bit sum (low 16 bits sufficient)
    sta DEVU_NUM_L                  ; → DEVU numerator low
    lda ADD_R_LH
    sta DEVU_NUM_H                  ; → DEVU numerator high
    
    lda #$04                        ; Divisor = 4
    sta DEVU_DEN_L
    stz DEVU_DEN_H                  ; Trigger division by writing denominator high
    
    lda QUOU_LL                     ; Read quotient
    sta average_Y_L                 ; → Average Y low byte
    lda QUOU_LH
    sta average_Y_H                 ; → Average Y high byte
                                    ; average_Y now holds centroid Y coordinate

; ==============================================================================
; SECTION: Outrigger Pathfinding Setup
; Purpose: Compute two probe points (left/right outriggers) offset from helicopter
;          to determine which direction steers closer to target (average car position)
; Method: Add rotation-indexed offset vectors to helicopter position
; Tables: OR_Right*/OR_Left* contain signed 16-bit offsets for each rotation (0-31)
; Note: Y register holds helicopter_ROT for table indexing
; ==============================================================================

    ; Compute right-outrigger world position = helicopter_pos + OR_Right@rotation
    ; Note: Y holds the rotation index. OR_RightXL/OR_RightXH and OR_RightYL/
    ; OR_RightYH are signed 16-bit offset tables indexed by rotation (Y).
    ; We add low then high with carry to form 16-bit world coordinates and
    ; store the results into temporary zero-page RRXL/RRXH/RRYL/RRYH.
    
    ; --- Right outrigger X calculation: RRXL/H ← helicopter_POSX + OR_RightX[Y] ---
    clc                             ; Clear carry for 16-bit addition
    lda helicopter_POSX_L           ; Load helicopter X position low byte
    adc OR_RightXL,Y                ; Add right offset X low (indexed by rotation Y)
    sta RRXL                        ; Store result: right outrigger X low byte
    lda helicopter_POSX_H           ; Load helicopter X position high byte
    adc OR_RightXH,Y                ; Add right offset X high with carry propagation
    sta RRXH                        ; Store result: right outrigger X high byte
    
    ; --- Right outrigger Y calculation: RRYL/H ← helicopter_POSY + OR_RightY[Y] ---
    clc                             ; Clear carry for next 16-bit addition
    lda helicopter_POSY_L           ; Load helicopter Y position low byte
    adc OR_RightYL,Y                ; Add right offset Y low (indexed by rotation Y)
    sta RRYL                        ; Store result: right outrigger Y low byte
    lda helicopter_POSY_H           ; Load helicopter Y position high byte
    adc OR_RightYH,Y                ; Add right offset Y high with carry propagation
    sta RRYH                        ; Store result: right outrigger Y high byte
                                    ; Right probe point now positioned in world space

    ; Compute left-outrigger world position = helicopter_pos + OR_Left@rotation
    ; Mirrors the right-outrigger computation but using the OR_Left tables.
    ; This creates a second probe point to the left of the helicopter's heading.
    
    ; --- Left outrigger X calculation: LRXL/H ← helicopter_POSX + OR_LeftX[Y] ---
    clc                             ; Clear carry for 16-bit addition
    lda helicopter_POSX_L           ; Load helicopter X position low byte
    adc OR_LeftXL,Y                 ; Add left offset X low (indexed by rotation Y)
    sta LRXL                        ; Store result: left outrigger X low byte
    lda helicopter_POSX_H           ; Load helicopter X position high byte
    adc OR_LeftXH,Y                 ; Add left offset X high with carry propagation
    sta LRXH                        ; Store result: left outrigger X high byte
    
    ; --- Left outrigger Y calculation: LRYL/H ← helicopter_POSY + OR_LeftY[Y] ---
    clc                             ; Clear carry for next 16-bit addition
    lda helicopter_POSY_L           ; Load helicopter Y position low byte
    adc OR_LeftYL,Y                 ; Add left offset Y low (indexed by rotation Y)
    sta LRYL                        ; Store result: left outrigger Y low byte
    lda helicopter_POSY_H           ; Load helicopter Y position high byte
    adc OR_LeftYH,Y                 ; Add left offset Y high with carry propagation
    sta LRYH                        ; Store result: left outrigger Y high byte
                                    ; Left probe point now positioned in world space
                                    ; Both outriggers ready for distance comparison

; ==============================================================================
; SECTION: Distance Vector Calculation
; Purpose: Compute signed displacement vectors from each outrigger to target
; Method: delta = target - outrigger (signed 16-bit subtraction)
; Outputs: RDX*/RDY* (right deltas), LDX*/LDY* (left deltas)
; Note: These vectors will be squared and summed to compute distances^2
; ==============================================================================

    ; Calculate distances from each outrigger to the average car position (target)
    ; We compute: diff = target - outrigger (signed), storing into RDX*/RDY* and LDX*/LDY*.
    ; These displacement vectors represent the direction from each probe point to the goal.
    
    ; --- Right outrigger X delta: RDXL/H ← average_X - RRXL/H ---
    ; Compute signed 16-bit subtraction: target_X - right_outrigger_X
    sec                             ; Set carry for SBC (subtraction with borrow)
    lda average_X_L                 ; Load target X low byte (centroid of all cars)
    sbc RRXL                        ; Subtract right outrigger X low
    sta RDXL                        ; Store result: right delta X low byte
    lda average_X_H                 ; Load target X high byte
    sbc RRXH                        ; Subtract right outrigger X high (with borrow)
    sta RDXH                        ; Store result: right delta X high byte (signed)
    
    ; --- Right outrigger Y delta: RDYL/H ← average_Y - RRYL/H ---
    sec                             ; Set carry for next 16-bit subtraction
    lda average_Y_L                 ; Load target Y low byte
    sbc RRYL                        ; Subtract right outrigger Y low
    sta RDYL                        ; Store result: right delta Y low byte
    lda average_Y_H                 ; Load target Y high byte
    sbc RRYH                        ; Subtract right outrigger Y high (with borrow)
    sta RDYH                        ; Store result: right delta Y high byte (signed)
                                    ; Right displacement vector (RDXL/H, RDYL/H) now computed

    ; --- Left outrigger X delta: LDXL/H ← average_X - LRXL/H ---
    ; Compute signed 16-bit subtraction: target_X - left_outrigger_X
    sec                             ; Set carry for SBC
    lda average_X_L                 ; Load target X low byte
    sbc LRXL                        ; Subtract left outrigger X low
    sta LDXL                        ; Store result: left delta X low byte
    lda average_X_H                 ; Load target X high byte
    sbc LRXH                        ; Subtract left outrigger X high (with borrow)
    sta LDXH                        ; Store result: left delta X high byte (signed)
    
    ; --- Left outrigger Y delta: LDYL/H ← average_Y - LRYL/H ---
    sec                             ; Set carry for next 16-bit subtraction
    lda average_Y_L                 ; Load target Y low byte
    sbc LRYL                        ; Subtract left outrigger Y low
    sta LDYL                        ; Store result: left delta Y low byte
    lda average_Y_H                 ; Load target Y high byte
    sbc LRYH                        ; Subtract left outrigger Y high (with borrow)
    sta LDYH                        ; Store result: left delta Y high byte (signed)
                                    ; Left displacement vector (LDXL/H, LDYL/H) now computed
                                    ; Both vectors represent direction from probe points to target

; ==============================================================================
; SECTION: Distance Squared Calculation and Steering Decision
; Purpose: Compute distance^2 for each outrigger and compare to determine turn
; Method: Call finder_math which squares deltas, sums them, and sets TURN_FLAG
; Formula: dist^2 = dx*dx + dy*dy (Pythagorean distance without sqrt)
; Hardware: Uses MULU coprocessor for 16x16→32 bit multiplications
; Result: TURN_FLAG = $FF (left), $00 (straight), $01 (right)
; ==============================================================================

    ; Now compute squared distances: dist^2 = dx*dx + dy*dy
    ; finder_math will square each delta component (X and Y) for both outriggers,
    ; sum them to get distance^2, compare the results, and set TURN_FLAG to
    ; indicate which outrigger is closer to the target (smaller distance).
    jsr finder_math                 ; Compute distances and set steering decision

; ==============================================================================
; SECTION: Apply Steering Decision to Helicopter Rotation
; Purpose: Update helicopter heading based on pathfinding result
; Method: Add TURN_FLAG to current rotation and wrap to 0-31 range
; TURN_FLAG values: $FF=turn left (-1), $00=straight (0), $01=turn right (+1)
; ==============================================================================
    
    ; --- Update helicopter rotation based on TURN_FLAG ---
    ; TURN_FLAG is set by finder_math: $FF (left), $00 (straight), $01 (right)
    clc                             ; Clear carry for addition
    lda helicopter_ROT              ; Load current rotation (0-31)
    adc TURN_FLAG                   ; Add turn delta ($FF, $00, or $01)
    and #$1f                        ; Wrap to 0-31 range (5-bit mask)
    sta helicopter_ROT              ; Store updated rotation

; ==============================================================================
; SECTION: Update Helicopter Sprite Addresses Based on Rotation
; Purpose: Point sprite registers to correct animation frame for current heading
; Method: Calculate sprite address offset = rotation * 4 (each frame is 4 bytes apart)
; Sprite format: 32 frames (rotations 0-31), each at base_address + (rotation * 4)
; ==============================================================================

    ; --- Calculate helicopter body sprite address ---
    ; Formula: sprite_address = helicopter1 + (rotation * 4)
    ; ASL twice multiplies rotation by 4 (shift left 2 bits)
    asl                             ; rotation * 2
    asl                             ; rotation * 4
    clc                             ; Clear carry for addition
    adc #>helicopter1               ; Add to sprite bank mid-byte (page offset)
    sta helicopter_base+SP_AD_M     ; Store sprite address mid-byte
    lda #<helicopter1               ; Load sprite base address low byte
    sta helicopter_base+SP_AD_L     ; Store sprite address low byte
    lda #`helicopter1               ; Load sprite base address high byte (bank)
    sta helicopter_base+SP_AD_H     ; Store sprite address high byte (bank)
                                    ; Helicopter body sprite now points to correct rotation frame

    ; --- Calculate helicopter shadow sprite address ---
    ; Shadow sprite has separate animation frames matching body rotation
    lda helicopter_ROT              ; Reload rotation (A was modified by calculations)
    asl                             ; rotation * 2
    asl                             ; rotation * 4
    clc                             ; Clear carry for addition
    adc #>h_shadow1                 ; Add to shadow sprite bank mid-byte
    sta helicopter_shadow+SP_AD_M   ; Store shadow sprite address mid-byte
    lda #<h_shadow1                 ; Load shadow sprite base address low byte
    sta helicopter_shadow+SP_AD_L   ; Store shadow sprite address low byte
    lda #`h_shadow1                 ; Load shadow sprite base address high byte (bank)
    sta helicopter_shadow+SP_AD_H   ; Store shadow sprite address high byte (bank)
                                    ; Shadow sprite now points to correct rotation frame

; ==============================================================================
; SECTION: Velocity Adjustment Based on Heading (runs every frame)
; Purpose: Modify X/Y velocity to create physics-based movement toward target
; Method: Check rotation ranges and adjust velocity components accordingly
; Rotation map: 0=North, 8=East, 16=South, 24=West (clockwise)
; X-axis: East(+) rotation 0-15, West(-) rotation 17-31, None at 0/16
; Y-axis: South(+) rotation 9-23, North(-) rotation 0-7 or 25-31, None at 8/24
; ==============================================================================

skip_helicopter_turn:

; --- X Velocity Adjustment ---
; Determine if helicopter should accelerate left, right, or maintain X velocity
; Based on which half of rotation circle the helicopter is facing

    lda helicopter_ROT              ; Load current rotation (0-31)
    cmp #$10                        ; Compare to 16 (facing straight down/up)
    beq no_adjust_x                 ; If exactly 16, no X component (straight vertical)
    bcc add_helicopter_X_velocity   ; If < 16 (rotations 0-15), facing right half → add X velocity
    bra sub_helicopter_X_velocity   ; If > 16 (rotations 17-31), facing left half → subtract X velocity

no_adjust_x:
    ; Rotation is exactly 16 (straight down) - skip X adjustment
    bra Y_velocity                  ; Move to Y velocity adjustment

add_helicopter_X_velocity:
    ; --- Increase X velocity (move right/east) ---
    ; Helicopter is facing right half of compass (rotations 0-15)
    ; Add h_acceleration to 24-bit signed velocity (F=fractional, L=low, H=high)
    clc                             ; Clear carry for addition
    lda helicopter_X_VEL_F          ; Load X velocity fractional byte
    adc #h_acceleration             ; Add acceleration constant ($04)
    sta helicopter_X_VEL_F          ; Store updated fractional byte
    lda helicopter_X_VEL_L          ; Load X velocity low byte
    adc #$00                        ; Add carry propagation only
    sta helicopter_X_VEL_L          ; Store updated low byte
    lda helicopter_X_VEL_H          ; Load X velocity high byte (sign byte)
    adc #$00                        ; Add carry propagation only
    sta helicopter_X_VEL_H          ; Store updated high byte
    bra Y_velocity                  ; Continue to Y velocity adjustment

sub_helicopter_X_velocity:
    ; --- Decrease X velocity (move left/west) ---
    ; Helicopter is facing left half of compass (rotations 17-31)
    ; Subtract h_acceleration from 24-bit signed velocity
    sec                             ; Set carry for subtraction (SBC)
    lda helicopter_X_VEL_F          ; Load X velocity fractional byte
    sbc #h_acceleration             ; Subtract acceleration constant ($04)
    sta helicopter_X_VEL_F          ; Store updated fractional byte
    lda helicopter_X_VEL_L          ; Load X velocity low byte
    sbc #$00                        ; Subtract borrow propagation only
    sta helicopter_X_VEL_L          ; Store updated low byte
    lda helicopter_X_VEL_H          ; Load X velocity high byte (sign byte)
    sbc #$00                        ; Subtract borrow propagation only
    sta helicopter_X_VEL_H          ; Store updated high byte

; --- Y Velocity Adjustment ---
; Determine if helicopter should accelerate up, down, or maintain Y velocity
; Y-axis logic is more complex due to wrap-around at North (rotation 0/31)

Y_velocity:
    lda helicopter_ROT              ; Load current rotation (0-31)
    cmp #$08                        ; Compare to 8 (facing straight right/east)
    beq no_adjust_y                 ; If exactly 8, no Y component (straight horizontal)
    bcc sub_helicopter_Y_velocity   ; If < 8 (rotations 0-7), facing upper-right → subtract Y (move up/north)
    cmp #$18                        ; Compare to 24 (facing straight left/west)
    beq no_adjust_y                 ; If exactly 24, no Y component (straight horizontal)
    bcs sub_helicopter_Y_velocity   ; If >= 24 (rotations 24-31), facing upper-left → subtract Y (move up/north)
    bra add_helicopter_Y_velocity   ; Else (rotations 9-23), facing lower half → add Y (move down/south)

no_adjust_y:
    ; Rotation is exactly 8 or 24 (straight horizontal) - skip Y adjustment
    bra velocity_limits             ; Move to velocity clamping

add_helicopter_Y_velocity:
    ; --- Increase Y velocity (move down/south) ---
    ; Helicopter is facing lower half of compass (rotations 9-23)
    ; Add h_acceleration to 24-bit signed Y velocity
    clc                             ; Clear carry for addition
    lda helicopter_Y_VEL_F          ; Load Y velocity fractional byte
    adc #h_acceleration             ; Add acceleration constant ($04)
    sta helicopter_Y_VEL_F          ; Store updated fractional byte
    lda helicopter_Y_VEL_L          ; Load Y velocity low byte
    adc #$00                        ; Add carry propagation only
    sta helicopter_Y_VEL_L          ; Store updated low byte
    lda helicopter_Y_VEL_H          ; Load Y velocity high byte (sign byte)
    adc #$00                        ; Add carry propagation only
    sta helicopter_Y_VEL_H          ; Store updated high byte
    bra velocity_limits             ; Continue to velocity clamping

sub_helicopter_Y_velocity:
    ; --- Decrease Y velocity (move up/north) ---
    ; Helicopter is facing upper half of compass (rotations 0-7 or 24-31)
    ; Subtract h_acceleration from 24-bit signed Y velocity
    sec                             ; Set carry for subtraction
    lda helicopter_Y_VEL_F          ; Load Y velocity fractional byte
    sbc #h_acceleration             ; Subtract acceleration constant ($04)
    sta helicopter_Y_VEL_F          ; Store updated fractional byte
    lda helicopter_Y_VEL_L          ; Load Y velocity low byte
    sbc #$00                        ; Subtract borrow propagation only
    sta helicopter_Y_VEL_L          ; Store updated low byte
    lda helicopter_Y_VEL_H          ; Load Y velocity high byte (sign byte)
    sbc #$00                        ; Subtract borrow propagation only
    sta helicopter_Y_VEL_H          ; Store updated high byte

; ==============================================================================
; SECTION: Velocity Limiting (Clamp to Max Speed)
; Purpose: Prevent helicopter from exceeding maximum velocity in either direction
; Method: Check sign (positive/negative) then compare magnitude against limits
; Limits: +top_plus_vel ($e0 = 224) and -top_minus_vel (-$e0 = -224)
; Note: Velocity is 24-bit signed: H=high/sign byte, L=low byte, F=fractional
; ==============================================================================

velocity_limits:
    ; --- Check X velocity positive limit (moving right/east) ---
    ; Strategy: Check sign byte first, then compare magnitude if positive
    lda helicopter_X_VEL_H          ; Load X velocity high byte (sign byte)
    bmi check_helicopter_x_minus    ; If negative (bit 7 set), check negative limit
    
    ; X velocity is positive - check if exceeds +top_plus_vel
    lda helicopter_X_VEL_F          ; Load fractional byte (magnitude)
    cmp #top_plus_vel               ; Compare with max positive velocity ($e0 = 224)
    bcc check_helicopter_Y_velocity ; If below limit, velocity OK - check Y velocity
    
    ; X velocity exceeds positive limit - clamp to maximum
    lda #top_plus_vel               ; Load max positive velocity
    sta helicopter_X_VEL_F          ; Clamp fractional byte to limit
    stz helicopter_X_VEL_L          ; Zero low byte (no integer component at limit)
    stz helicopter_X_VEL_H          ; Zero high byte (positive = 0 sign byte)
    bra check_helicopter_Y_velocity ; Continue to Y velocity check

check_helicopter_x_minus:
    ; --- Check X velocity negative limit (moving left/west) ---
    ; X velocity is negative - check if exceeds -top_minus_vel
    lda helicopter_X_VEL_F          ; Load fractional byte (magnitude in two's complement)
    cmp #top_minus_vel              ; Compare with max negative velocity (-$e0 = -224)
    bcs check_helicopter_Y_velocity ; If above limit (less negative), velocity OK - check Y
    
    ; X velocity exceeds negative limit - clamp to maximum negative
    lda #top_minus_vel              ; Load max negative velocity (-224 in two's complement)
    sta helicopter_X_VEL_F          ; Clamp fractional byte to negative limit
    lda #$FF                        ; Load $FF for negative sign extension
    sta helicopter_X_VEL_L          ; Set low byte to $FF (two's complement negative)
    sta helicopter_X_VEL_H          ; Set high byte to $FF (negative sign byte)

check_helicopter_Y_velocity:
    ; --- Check Y velocity positive limit (moving down/south) ---
    ; Same logic as X velocity but for Y axis
    lda helicopter_Y_VEL_H          ; Load Y velocity high byte (sign byte)
    bmi check_helicopter_y_minus    ; If negative (bit 7 set), check negative limit
    
    ; Y velocity is positive - check if exceeds +top_plus_vel
    lda helicopter_Y_VEL_F          ; Load fractional byte (magnitude)
    cmp #top_plus_vel               ; Compare with max positive velocity ($e0 = 224)
    bcc compute_helicopter_position ; If below limit, velocity OK - proceed to position update
    
    ; Y velocity exceeds positive limit - clamp to maximum
    lda #top_plus_vel               ; Load max positive velocity
    sta helicopter_Y_VEL_F          ; Clamp fractional byte to limit
    stz helicopter_Y_VEL_L          ; Zero low byte (no integer component at limit)
    stz helicopter_Y_VEL_H          ; Zero high byte (positive = 0 sign byte)
    bra compute_helicopter_position ; Continue to position update

check_helicopter_y_minus:
    ; --- Check Y velocity negative limit (moving up/north) ---
    ; Y velocity is negative - check if exceeds -top_minus_vel
    lda helicopter_Y_VEL_F          ; Load fractional byte (magnitude in two's complement)
    cmp #top_minus_vel              ; Compare with max negative velocity (-$e0 = -224)
    bcs compute_helicopter_position ; If above limit (less negative), velocity OK - proceed
    
    ; Y velocity exceeds negative limit - clamp to maximum negative
    lda #top_minus_vel              ; Load max negative velocity (-224 in two's complement)
    sta helicopter_Y_VEL_F          ; Clamp fractional byte to negative limit
    lda #$FF                        ; Load $FF for negative sign extension
    sta helicopter_Y_VEL_L          ; Set low byte to $FF (two's complement negative)
    sta helicopter_Y_VEL_H          ; Set high byte to $FF (negative sign byte)

; ==============================================================================
; SECTION: Position Update (Apply Velocity to World Position)
; Purpose: Integrate velocity into position using 24-bit fixed-point arithmetic
; Method: pos = pos + vel (with carry propagation through F→L→H bytes)
; Boundary: Clamp position to 0 if negative (world edge collision)
; Note: Position uses same 24-bit format as velocity (F=frac, L=low, H=high/sign)
; ==============================================================================

compute_helicopter_position:

    ; --- Update X position: helicopter_POSX += helicopter_X_VEL ---
    ; 24-bit addition with carry propagation from fractional → low → high bytes
    clc                             ; Clear carry for addition
    lda helicopter_POSX_F           ; Load current X position fractional byte
    adc helicopter_X_VEL_F          ; Add X velocity fractional byte
    sta helicopter_POSX_F           ; Store updated X position fractional byte
    lda helicopter_POSX_L           ; Load current X position low byte
    adc helicopter_X_VEL_L          ; Add X velocity low byte (with carry from fractional)
    sta helicopter_POSX_L           ; Store updated X position low byte
    lda helicopter_POSX_H           ; Load current X position high byte (sign byte)
    adc helicopter_X_VEL_H          ; Add X velocity high byte (with carry from low)
    sta helicopter_POSX_H           ; Store updated X position high byte

    ; --- Check for negative X position (off left edge of world) ---
    bpl y_pos                       ; If positive (bit 7 clear), position valid - continue to Y
    
    ; X position went negative - clamp to zero (left world boundary)
    stz helicopter_POSX_F           ; Zero fractional byte
    stz helicopter_POSX_L           ; Zero low byte
    stz helicopter_POSX_H           ; Zero high byte (position = 0)

y_pos:
    ; --- Update Y position: helicopter_POSY += helicopter_Y_VEL ---
    ; Same 24-bit addition process as X position
    clc                             ; Clear carry for addition
    lda helicopter_POSY_F           ; Load current Y position fractional byte
    adc helicopter_Y_VEL_F          ; Add Y velocity fractional byte
    sta helicopter_POSY_F           ; Store updated Y position fractional byte
    lda helicopter_POSY_L           ; Load current Y position low byte
    adc helicopter_Y_VEL_L          ; Add Y velocity low byte (with carry from fractional)
    sta helicopter_POSY_L           ; Store updated Y position low byte
    lda helicopter_POSY_H           ; Load current Y position high byte (sign byte)
    adc helicopter_Y_VEL_H          ; Add Y velocity high byte (with carry from low)
    sta helicopter_POSY_H           ; Store updated Y position high byte
    
    ; --- Check for negative Y position (off top edge of world) ---
    bpl done_helicopter_pos         ; If positive (bit 7 clear), position valid - continue
    
    ; Y position went negative - clamp to zero (top world boundary)
    stz helicopter_POSY_F           ; Zero fractional byte
    stz helicopter_POSY_L           ; Zero low byte
    stz helicopter_POSY_H           ; Zero high byte (position = 0)

done_helicopter_pos:

; ==============================================================================
; SECTION: Rotor Blade Sound Effect (Distance-Based Volume Attenuation)
; Purpose: Generate helicopter rotor sound with volume based on distance to player
; Method: Calculate distance, scale to attenuation range, apply envelope, write to PSG
; Algorithm:
;   1. Compute signed 16-bit distance (helicopter X - player X)
;   2. Convert to absolute value via two's complement negation if negative
;   3. Scale distance by dividing by 32 (5 right shifts) for attenuation index
;   4. Load envelope value from 8-entry table indexed by animation counter
;   5. Add distance-based attenuation to envelope (farther = quieter)
;   6. Clamp to maximum attenuation ($0B) to prevent silence
;   7. Write to PSG tone 3 volume register with latch bit
;   8. Cycle animation counter 0-7 for envelope wave effect
; Envelope: 8-frame cycle creates pulsing rotor sound (bladeEnv table)
; Attenuation: $00=loudest (0dB), $0F=quietest (-28dB), PSG scale
; ==============================================================================

    ; --- Calculate Distance from Helicopter to Player (X-axis only) ---
    ; Formula: distance = helicopter_X - player_X (signed 16-bit subtraction)
    sec                             ; Set carry for 16-bit subtraction (SBC)
    lda helicopter_POSX_L           ; Load helicopter world X position low byte
    sbc PlayerPOS_X_L               ; Subtract player X position low byte
    sta rotorDist_L                 ; Store signed distance X low byte
    lda helicopter_POSX_H           ; Load helicopter world X position high byte
    sbc PlayerPOS_X_H               ; Subtract player X position high byte (with borrow)
    sta rotorDist_H                 ; Store signed distance X high byte (bit 7 = sign)

    ; --- Convert to Absolute Value (Make Distance Positive) ---
    ; Check sign bit (bit 7 of high byte): if negative, negate via two's complement
    lda rotorDist_H                 ; Load distance high byte to test sign
    bpl rotor_dist_abs_done         ; If positive (bit 7 clear), skip negation
    
    ; Distance is negative - perform two's complement negation: -dist = ~dist + 1
    lda rotorDist_L                 ; Load distance low byte
    eor #$ff                        ; Flip all bits (one's complement)
    clc                             ; Clear carry for addition
    adc #$01                        ; Add 1 to complete two's complement
    sta rotorDist_L                 ; Store absolute value low byte
    lda rotorDist_H                 ; Load distance high byte
    eor #$ff                        ; Flip all bits (one's complement)
    adc #$00                        ; Add carry propagation only
    sta rotorDist_H                 ; Store absolute value high byte (now positive)

rotor_dist_abs_done:

    ; --- Scale Distance for Attenuation Index ---
    ; Divide distance by 32 (÷2^5) via 5 right shifts to map world distance to attenuation
    ; Each shift divides by 2: distance ÷ 2 ÷ 2 ÷ 2 ÷ 2 ÷ 2 = distance ÷ 32
    ; Result: 0-255+ distance range maps to 0-7+ attenuation range
    lsr rotorDist_H                 ; Shift high byte right (÷2), LSB → carry
    ror rotorDist_L                 ; Rotate low byte right through carry
    lsr rotorDist_H                 ; Shift high byte right (÷4), LSB → carry
    ror rotorDist_L                 ; Rotate low byte right through carry
    lsr rotorDist_H                 ; Shift high byte right (÷8), LSB → carry
    ror rotorDist_L                 ; Rotate low byte right through carry
    lsr rotorDist_H                 ; Shift high byte right (÷16), LSB → carry
    ror rotorDist_L                 ; Rotate low byte right through carry
    lsr rotorDist_H                 ; Shift high byte right (÷32), LSB → carry
    ror rotorDist_L                 ; Rotate low byte right through carry (final scaled distance)

    ; --- Load Envelope Value from Animation Table ---
    ; bladeEnv is 8-byte table with pulsing wave pattern
    ; rotorIdx cycles 0-7 to animate through envelope for rotor sound effect
    ldy rotorIdx                    ; Load current rotor animation frame counter (0-7)
    lda bladeEnv,Y                  ; Load base envelope attenuation value from table

    ; --- Apply Distance-Based Attenuation Modifier ---
    ; Combine base envelope with scaled distance: farther helicopter = higher attenuation = quieter
    clc                             ; Clear carry for 8-bit addition
    adc rotorDist_L                 ; Add distance-based attenuation (0-255 scaled)
    cmp #$0b                        ; Compare to maximum allowed attenuation ($0B = -22dB)
    bcc vol_ok                      ; If below max (C clear), attenuation valid - proceed
    lda #$0b                        ; Clamp to maximum attenuation to prevent complete silence

vol_ok:
    ; --- Write Attenuation to PSG Tone 3 Volume Register ---
    ; PSG volume format: |1|LCH|VVVV| - bit 7=latch, bits 6-5=channel (11=tone3), bits 3-0=attenuation
    ora #$d0                        ; Set latch bit + tone 3 channel select ($D0 = %11010000)
    sta PSG_R                       ; Write to PSG right channel (tone 3 volume control)

    ; --- Cycle Rotor Animation Counter (8-Frame Loop) ---
    ; Counter advances each frame to animate envelope wave, wraps 0→1→2...→7→0
    inc rotorIdx                    ; Increment rotor animation frame counter
    lda rotorIdx                    ; Load updated counter value
    cmp #$08                        ; Have we completed 8-frame cycle?
    bne skip_rotor_reset            ; If not at 8, continue without reset
    
    ; Counter reached 8 - reset to 0 for next envelope cycle
    stz rotorIdx                    ; Zero rotor animation counter (wrap to frame 0)
skip_rotor_reset:



; ==============================================================================
; SECTION: Screen Projection (World → Screen Coordinate Conversion)
; Purpose: Convert helicopter's world position to screen-relative coordinates
; Method: screen_delta = world_position - tilemap_scroll_position
; Why: Sprites use screen-relative coordinates, not world coordinates
; Result: tmpx/tmpy contain signed 16-bit screen deltas (can be negative if off-screen)
; ==============================================================================

    ; --- Calculate tilemap scroll offset (convert tilemap position to pixel space) ---
    ; tilePOSX/Y represent the current tilemap scroll position (top-left corner of viewport)
    ; We subtract offsets to account for screen edge margins and create screen-relative coords
    
    ; tmpx = tilePOSX - heli_x_offset (compute viewport left edge in world space)
    sec                             ; Set carry for 16-bit subtraction
    lda tilePOSX_L                  ; Load tilemap X position low byte
    sbc #heli_x_offset              ; Subtract X offset constant (viewport left margin)
    sta tmpx                        ; Store adjusted viewport X low byte
    lda tilePOSX_H                  ; Load tilemap X position high byte
    sbc #0                          ; Subtract borrow propagation only
    sta tmpx+1                      ; Store adjusted viewport X high byte
    
    ; tmpy = tilePOSY - heli_y_offset (compute viewport top edge in world space)
    sec                             ; Set carry for 16-bit subtraction
    lda tilePOSY_L                  ; Load tilemap Y position low byte
    sbc #heli_y_offset              ; Subtract Y offset constant (viewport top margin)
    sta tmpy                        ; Store adjusted viewport Y low byte
    lda tilePOSY_H                  ; Load tilemap Y position high byte
    sbc #0                          ; Subtract borrow propagation only
    sta tmpy+1                      ; Store adjusted viewport Y high byte

    ; --- Calculate screen-relative X position ---
    ; tmpx = helicopter_POSX - tmpx (helicopter world X - viewport left edge)
    ; Result is signed: negative if helicopter is left of screen, positive if on/right of screen
    ; Note: SEC still set from previous subtraction, so this continues the borrow chain
    lda helicopter_POSX_L           ; Load helicopter world X position low byte
    sbc tmpx                        ; Subtract viewport left edge low byte
    sta tmpx                        ; Store screen-relative X delta low byte
    lda helicopter_POSX_H           ; Load helicopter world X position high byte
    sbc tmpx+1                      ; Subtract viewport left edge high byte (with borrow)
    sta tmpx+1                      ; Store screen-relative X delta high byte (sign in bit 7)

    ; --- Calculate screen-relative Y position ---
    ; tmpy = helicopter_POSY - tmpy (helicopter world Y - viewport top edge)
    ; Result is signed: negative if helicopter is above screen, positive if on/below screen
    sec                             ; Set carry for 16-bit subtraction
    lda helicopter_POSY_L           ; Load helicopter world Y position low byte
    sbc tmpy                        ; Subtract viewport top edge low byte
    sta tmpy                        ; Store screen-relative Y delta low byte
    lda helicopter_POSY_H           ; Load helicopter world Y position high byte
    sbc tmpy+1                      ; Subtract viewport top edge high byte (with borrow)
    sta tmpy+1                      ; Store screen-relative Y delta high byte (sign in bit 7)

; ==============================================================================
; SECTION: Shadow Sprite Positioning
; Purpose: Calculate shadow sprite positions offset from main helicopter sprites
; Method: shadow_pos = main_pos + offset (+16 X, +32 Y)
; Why: Creates depth effect by placing shadows down and to the right
; Note: Both body shadow and blade shadow use same offset relative to their mains
; ==============================================================================

    ; --- Calculate shadow X position: shadow_X = tmpx + 16 ---
    ; Offset shadows 16 pixels right to simulate light source from upper-left
    clc                             ; Clear carry for 16-bit addition
    lda tmpx                        ; Load main sprite screen X low byte
    adc #$10                        ; Add 16 pixels offset ($10 = 16 decimal)
    sta helicopter_shadow+SP_POS_X_L    ; Store shadow body X position low byte
    sta helicopter_S_blade+SP_POS_X_L   ; Store shadow blade X position low byte
    lda tmpx+1                      ; Load main sprite screen X high byte
    adc #$00                        ; Add carry propagation only
    sta helicopter_shadow+SP_POS_X_H    ; Store shadow body X position high byte
    sta helicopter_S_blade+SP_POS_X_H   ; Store shadow blade X position high byte

    ; --- Calculate shadow Y position: shadow_Y = tmpy + 32 ---
    ; Offset shadows 32 pixels down to simulate ground plane below helicopter
    clc                             ; Clear carry for 16-bit addition
    lda tmpy                        ; Load main sprite screen Y low byte
    adc #$20                        ; Add 32 pixels offset ($20 = 32 decimal)
    sta helicopter_shadow+SP_POS_Y_L    ; Store shadow body Y position low byte
    sta helicopter_S_blade+SP_POS_Y_L   ; Store shadow blade Y position low byte
    lda tmpy+1                      ; Load main sprite screen Y high byte
    adc #$00                        ; Add carry propagation only
    sta helicopter_shadow+SP_POS_Y_H    ; Store shadow body Y position high byte
    sta helicopter_S_blade+SP_POS_Y_H   ; Store shadow blade Y position high byte

; ==============================================================================
; SECTION: Visibility Range Testing
; Purpose: Determine if helicopter is within visible screen bounds
; Method: Check signed 16-bit screen deltas (tmpx+1/tmpy+1 = high bytes with sign)
; Strategy:
;   - If high byte negative (BMI), sprite is off-screen to left/top → disable
;   - If high byte == 0, sprite is in small positive range → fine-grain check with low byte
;   - If high byte >= 2, sprite is too far right/bottom → disable
;   - Low byte checks provide fine tolerance within valid range bands
; Why: Sprites outside viewport waste rendering cycles and can cause visual glitches
; ==============================================================================

    ; --- X-axis visibility check ---
    lda tmpx+1                      ; Load screen-relative X high byte (sign byte)
    bmi dhs                         ; If negative (bit 7 set), off-screen left → disable
    beq checkHY                     ; If zero (0-255 pixel range), check fine bounds then Y
    cmp #$02                        ; Compare high byte to 2 (checking if X >= 512)
    bcs dhs                         ; If >= 2 (X >= 512 pixels), off-screen right → disable
    
    ; High byte is 1 (X in 256-511 range), perform fine-grain low byte check
    lda tmpx                        ; Load screen-relative X low byte
    cmp #$60                        ; Compare to $60 (96 decimal)
    bcs dhs                         ; If >= 96, total X >= 352 pixels → disable (too far right)
    bra checkHY                     ; Low byte OK, proceed to Y check

dhs:
    ; Helicopter is off-screen, jump to disable sprite routine
    jmp disableHSprite

checkHY:
    ; --- Y-axis visibility check (mirrors X-axis logic) ---
    lda tmpy+1                      ; Load screen-relative Y high byte (sign byte)
    bmi dhs                         ; If negative (bit 7 set), off-screen top → disable
    beq enableHSprite               ; If zero (0-255 pixel range), visible → enable sprites
    cmp #$02                        ; Compare high byte to 2 (checking if Y >= 512)
    bcs dhs                         ; If >= 2 (Y >= 512 pixels), off-screen bottom → disable
    
    ; High byte is 1 (Y in 256-511 range), perform fine-grain low byte check
    lda tmpy                        ; Load screen-relative Y low byte
    cmp #$10                        ; Compare to $10 (16 decimal)
    bcs dhs                         ; If >= 16, total Y >= 272 pixels → disable (too far down)
    
; ==============================================================================
; SECTION: Blade Animation and Sprite Rendering (Helicopter Visible)
; Purpose: Animate rotor blades and update all sprite registers for visible helicopter
; Animation: 8-frame rotor cycle (blade_angle 0-7), each frame 4 bytes apart in sprite data
; Shadow: Alternates on/off each frame for flicker effect (creates pseudo-transparency)
; Sprites: 4 total (base body, blade rotor, body shadow, blade shadow)
; ==============================================================================

enableHSprite:
    ; --- Update blade animation frame counter ---
    inc blade_angle                 ; Increment blade animation counter (0→1→2...→7→8)
    lda blade_angle                 ; Load current blade angle
    and #$07                        ; Wrap to 0-7 range (8-frame cycle)
    sta blade_angle                 ; Store wrapped angle
    
    ; --- Calculate blade sprite address offset ---
    ; Formula: sprite_offset = blade_angle * 4 (each frame is 4 bytes apart)
    ; Method: ASL twice (shift left 2 bits) multiplies by 4
    asl                             ; blade_angle * 2
    asl                             ; blade_angle * 4
    tay                             ; Transfer offset to Y for later shadow calculation
    
    ; --- Set main rotor blade sprite address ---
    ; Address = blade1 + (blade_angle * 4)
    clc                             ; Clear carry for addition
    adc #>blade1                    ; Add sprite data bank mid-byte (page offset)
    sta helicopter_blade+SP_AD_M    ; Store blade sprite address mid-byte
    lda #<blade1                    ; Load blade sprite base address low byte
    sta helicopter_blade+SP_AD_L    ; Store blade sprite address low byte
    lda #`blade1                    ; Load blade sprite bank number (high byte)
    sta helicopter_blade+SP_AD_H    ; Store blade sprite address high byte
    
    ; --- Set shadow rotor blade sprite address ---
    ; Address = blade_shadow1 + (blade_angle * 4)
    ; Y register still holds blade_angle * 4 offset
    tya                             ; Transfer offset back to A
    clc                             ; Clear carry for addition
    adc #>blade_shadow1             ; Add shadow sprite data bank mid-byte
    sta helicopter_S_blade+SP_AD_M  ; Store shadow blade sprite address mid-byte
    lda #<blade_shadow1             ; Load shadow blade sprite base address low byte
    sta helicopter_S_blade+SP_AD_L  ; Store shadow blade sprite address low byte
    lda #`blade_shadow1             ; Load shadow blade sprite bank number (high byte)
    sta helicopter_S_blade+SP_AD_H  ; Store shadow blade sprite address high byte

    ; --- Enable main helicopter sprites (body and rotor) ---
    ; SP_CTRL format: |xx|SZ|SZ|LA|LA|LU|LU|EN|
    ; Bits: SZ=size (01=16x16), LA=layer, LU=LUT, EN=enable (1=on)
    lda #%00010001                  ; Size 16x16, layer 0, LUT 0, enable=1
    sta helicopter_base+SP_CTRL     ; Enable helicopter body sprite
    sta helicopter_blade+SP_CTRL    ; Enable helicopter blade sprite
    
    ; --- Shadow flicker toggle (alternates every frame) ---
    ; Creates pseudo-transparency effect by showing shadows on alternate frames only
    inc shadow_disp                 ; Increment shadow display counter
    lda shadow_disp                 ; Load counter value
    and #$01                        ; Mask to bit 0 (alternates 0/1 each frame)
    beq noShadow                    ; If bit 0 clear (even frames), disable shadows
    
    ; Odd frame - enable shadow sprites
    lda #%00010001                  ; Size 16x16, enable=1
    sta helicopter_shadow+SP_CTRL   ; Enable helicopter body shadow
    sta helicopter_S_blade+SP_CTRL  ; Enable helicopter blade shadow
    bra skip_noShadow               ; Skip disable section

noShadow:
    ; Even frame - disable shadow sprites (flicker effect)
    lda #%00010000                  ; Size 16x16, enable=0 (sprite disabled)
    sta helicopter_S_blade+SP_CTRL  ; Disable helicopter blade shadow
    sta helicopter_shadow+SP_CTRL   ; Disable helicopter body shadow

skip_noShadow:
    ; --- Update main sprite screen positions ---
    ; Set helicopter body and blade sprites to calculated screen-relative coordinates
    ; Sprites use signed 16-bit positions (can be negative for off-screen clipping)
    
    ; X position updates
    lda tmpx                        ; Load screen-relative X delta low byte
    sta helicopter_base+SP_POS_X_L  ; Set body sprite X position low
    sta helicopter_blade+SP_POS_X_L ; Set blade sprite X position low
    lda tmpx+1                      ; Load screen-relative X delta high byte (sign)
    sta helicopter_base+SP_POS_X_H  ; Set body sprite X position high
    sta helicopter_blade+SP_POS_X_H ; Set blade sprite X position high
    
    ; Y position updates
    lda tmpy                        ; Load screen-relative Y delta low byte
    sta helicopter_base+SP_POS_Y_L  ; Set body sprite Y position low
    sta helicopter_blade+SP_POS_Y_L ; Set blade sprite Y position low
    lda tmpy+1                      ; Load screen-relative Y delta high byte (sign)
    sta helicopter_base+SP_POS_Y_H  ; Set body sprite Y position high
    sta helicopter_blade+SP_POS_Y_H ; Set blade sprite Y position high
    rts                             ; Return from helicopter_Move routine

; ==============================================================================
; disableHSprite - Disable all helicopter sprites when off-screen
; Purpose: Turn off sprite rendering to save cycles and prevent visual glitches
; Method: Clear enable bit (bit 0) in SP_CTRL register for all 4 helicopter sprites
; Sprites: base body, blade rotor, body shadow, blade shadow
; ==============================================================================

disableHSprite:
    ; Disable all helicopter sprites by clearing enable bit in control register
    ; SP_CTRL format: |xx|SZ|SZ|LA|LA|LU|LU|EN| where EN=0 disables sprite
    lda #%00010000                  ; Size 16x16 preserved, enable=0 (sprite off)
    sta helicopter_base+SP_CTRL     ; Disable helicopter body sprite
    sta helicopter_blade+SP_CTRL    ; Disable helicopter blade sprite
    sta helicopter_shadow+SP_CTRL   ; Disable helicopter body shadow sprite
    sta helicopter_S_blade+SP_CTRL  ; Disable helicopter blade shadow sprite
    rts                             ; Return from helicopter_Move routine



; **************************************************************************************************************
; ai_Pathfinder - AI car steering decision algorithm
; Purpose: Calculate optimal steering direction for AI car to reach its current waypoint target
; Algorithm:
;   1. Compute two "outrigger" points (left and right) relative to car's current position and rotation
;   2. Calculate squared distances from each outrigger to the target waypoint
;   3. Compare distances to determine which side is closer to waypoint
;   4. Set TURN_FLAG based on comparison (turn toward closer outrigger)
;   5. Set GAS_FLAG based on speed comparison to target speed
; Inputs:
;   aicar_current = Index of AI car (0-2)
;   aicar_Rotation[X] = Car's current rotation (0-31)
;   aicar_posX/Y[X] = Car's world position (24-bit fixed point)
;   aicar_target[X] = Current waypoint index car is targeting
;   aicar_speed[X] = Car's current speed (24-bit fixed point)
;   aicar_TgtSpd[X] = Car's target speed for current waypoint (16-bit)
;   aiLineX/Y[Y] = Waypoint coordinates (16-bit)
;   OR_Right*/OR_Left* = Rotation-indexed outrigger offset tables
; Outputs:
;   TURN_FLAG = Steering decision: $00=straight, $01=turn right, $FF=turn left
;   GAS_FLAG = Throttle decision: $00=no change, $FF=accelerate, $01=brake
; Uses: MULU and ADD hardware coprocessors for distance calculations
; **************************************************************************************************************


ai_Pathfinder:
    ; **************************************************************************************************************
    ; SECTION 1: Initialize flags and load car data
    ; Purpose: Clear decision flags and set up indexing registers
    ; **************************************************************************************************************

    ; Clear turn decision as default (go straight)
    stz TURN_FLAG
    stz GAS_FLAG

    ; Setup indexing: X = aicar_current (which car), Y = its rotation index
    ; The outriggers (OR_Right*/OR_Left*/OR_Front*) are tables indexed by
    ; rotation (Y), providing signed 16-bit offsets around the car.
    ldx aicar_current           ; X = AI car index (0-2)
    ldy aicar_Rotation,x        ; Y = rotation index for table lookups (0-31)

    ; **************************************************************************************************************
    ; SECTION 2: Speed control decision (gas/brake)
    ; Purpose: Compare current speed with target speed and set GAS_FLAG accordingly
    ; Speed comparison uses 16-bit fixed-point: high byte (integer) checked first, then fractional
    ; **************************************************************************************************************

    ; --- Compare integer parts of speed ---
    lda aicar_speed_L,x         ; Load current speed low byte (integer part)
    cmp aicar_TgtSpd_L,x        ; Compare with target speed low byte
    beq check_fraction          ; If equal, check fractional part for fine comparison
    bcc more_gas                ; If current < target, need to accelerate
    bcs more_brake              ; If current > target, need to brake

check_fraction:
    ; --- Compare fractional parts when integer parts match ---
    lda aicar_speed_F,x         ; Load current speed fractional byte
    cmp aicar_TgtSpd_F,x        ; Compare with target speed fractional byte
    beq no_gas                  ; If exact match, maintain current throttle
    bcc more_gas                ; If current < target, accelerate
    
more_brake:
    ; --- Set brake flag (speed too high) ---
    lda #$01                    ; GAS_FLAG = $01 means brake
    sta GAS_FLAG
    bra compute_turn            ; Skip to steering computation

no_gas:
    ; --- Speed matches target, no throttle change needed ---
    lda #$00                    ; GAS_FLAG = $00 means maintain speed
    sta GAS_FLAG
    bra compute_turn            ; Skip to steering computation

more_gas:
    ; --- Set accelerate flag (speed too low) ---
    lda #$ff                    ; GAS_FLAG = $FF means accelerate
    sta GAS_FLAG


compute_turn:
    ; **************************************************************************************************************
    ; SECTION 3: Compute outrigger world positions
    ; Purpose: Calculate two "sensor" points on left and right sides of car
    ; Why: By comparing distances from these points to waypoint, we can determine turn direction
    ; Outriggers are rotation-dependent offsets that move with car's heading
    ; **************************************************************************************************************

    ; --- Calculate right-outrigger position (right side of car) ---
    ; Formula: right_outrigger = car_position + rotation_offset
    ; OR_Right* tables contain signed 16-bit offsets indexed by rotation (0-31)
    clc                         ; Clear carry for 16-bit addition
    lda aicar_posX_L,x          ; Load car X position low byte
    adc OR_RightXL,Y            ; Add right-outrigger X offset for current rotation
    sta RRXL                    ; Store right-outrigger X low byte
    lda aicar_posX_H,x          ; Load car X position high byte
    adc OR_RightXH,Y            ; Add right-outrigger X offset high with carry
    sta RRXH                    ; Store right-outrigger X high byte

    clc                         ; Clear carry for Y coordinate addition
    lda aicar_posY_L,x          ; Load car Y position low byte
    adc OR_RightYL,Y            ; Add right-outrigger Y offset for current rotation
    sta RRYL                    ; Store right-outrigger Y low byte
    lda aicar_posY_H,x          ; Load car Y position high byte
    adc OR_RightYH,Y            ; Add right-outrigger Y offset high with carry
    sta RRYH                    ; Store right-outrigger Y high byte

    ; --- Calculate left-outrigger position (left side of car) ---
    ; Same process as right-outrigger but using OR_Left* tables
    clc                         ; Clear carry for 16-bit addition
    lda aicar_posX_L,x          ; Load car X position low byte
    adc OR_LeftXL,Y             ; Add left-outrigger X offset for current rotation
    sta LRXL                    ; Store left-outrigger X low byte
    lda aicar_posX_H,x          ; Load car X position high byte
    adc OR_LeftXH,Y             ; Add left-outrigger X offset high with carry
    sta LRXH                    ; Store left-outrigger X high byte

    clc                         ; Clear carry for Y coordinate addition
    lda aicar_posY_L,x          ; Load car Y position low byte
    adc OR_LeftYL,Y             ; Add left-outrigger Y offset for current rotation
    sta LRYL                    ; Store left-outrigger Y low byte
    lda aicar_posY_H,x          ; Load car Y position high byte
    adc OR_LeftYH,Y             ; Add left-outrigger Y offset high with carry
    sta LRYH                    ; Store left-outrigger Y high byte

    ; **************************************************************************************************************
    ; SECTION 4: Calculate distance vectors from outriggers to waypoint
    ; Purpose: Compute signed 16-bit displacement vectors (dx, dy) for each outrigger
    ; Formula: distance_vector = waypoint_position - outrigger_position
    ; Results will be positive/negative depending on relative positions
    ; **************************************************************************************************************

    ; --- Load target waypoint coordinates ---
    ldy aicar_target,x          ; Y = waypoint index this car is targeting

    ; --- Calculate right-outrigger distance vector ---
    ; RDX = waypoint_X - right_outrigger_X (signed 16-bit)
    sec                         ; Set carry for 16-bit subtraction
    lda aiLineX_L,y             ; Load waypoint X low byte
    sbc RRXL                    ; Subtract right-outrigger X low
    sta RDXL                    ; Store X displacement low byte
    lda aiLineX_H,y             ; Load waypoint X high byte
    sbc RRXH                    ; Subtract right-outrigger X high with borrow
    sta RDXH                    ; Store X displacement high byte (sign in bit 7)

    ; RDY = waypoint_Y - right_outrigger_Y (signed 16-bit)
    sec                         ; Set carry for 16-bit subtraction
    lda aiLineY_L,y             ; Load waypoint Y low byte
    sbc RRYL                    ; Subtract right-outrigger Y low
    sta RDYL                    ; Store Y displacement low byte
    lda aiLineY_H,y             ; Load waypoint Y high byte
    sbc RRYH                    ; Subtract right-outrigger Y high with borrow
    sta RDYH                    ; Store Y displacement high byte (sign in bit 7)

    ; --- Calculate left-outrigger distance vector ---
    ; LDX = waypoint_X - left_outrigger_X (signed 16-bit)
    sec                         ; Set carry for 16-bit subtraction
    lda aiLineX_L,y             ; Load waypoint X low byte
    sbc LRXL                    ; Subtract left-outrigger X low
    sta LDXL                    ; Store X displacement low byte
    lda aiLineX_H,y             ; Load waypoint X high byte
    sbc LRXH                    ; Subtract left-outrigger X high with borrow
    sta LDXH                    ; Store X displacement high byte (sign in bit 7)

    ; LDY = waypoint_Y - left_outrigger_Y (signed 16-bit)
    sec                         ; Set carry for 16-bit subtraction
    lda aiLineY_L,y             ; Load waypoint Y low byte
    sbc LRYL                    ; Subtract left-outrigger Y low
    sta LDYL                    ; Store Y displacement low byte
    lda aiLineY_H,y             ; Load waypoint Y high byte
    sbc LRYH                    ; Subtract left-outrigger Y high with borrow
    sta LDYH                    ; Store Y displacement high byte (sign in bit 7)

finder_math:
    ; **************************************************************************************************************
    ; finder_math - Distance calculation and turn decision subroutine
    ; Purpose: Calculate squared distances from outriggers to waypoint and determine turn direction
    ; Algorithm:
    ;   1. Convert signed distance vectors to absolute values (handle negative coordinates)
    ;   2. Square each component: RDX², RDY², LDX², LDY² using hardware multiplier
    ;   3. Sum components: right_dist² = RDX² + RDY², left_dist² = LDX² + LDY²
    ;   4. Compare squared distances: diff = right_dist² - left_dist²
    ;   5. Set TURN_FLAG based on sign and magnitude of diff
    ; Why squared distances: Avoids expensive square root, preserves relative ordering
    ; Inputs:
    ;   RDXL/H, RDYL/H = Right-outrigger distance vector components (signed 16-bit)
    ;   LDXL/H, LDYL/H = Left-outrigger distance vector components (signed 16-bit)
    ; Outputs:
    ;   TURN_FLAG = $FF (turn left), $00 (straight), $01 (turn right)
    ; Uses: MULU coprocessor for 16x16->32 multiplication, ADD coprocessor for 32-bit addition
    ; **************************************************************************************************************

    ; **************************************************************************************************************
    ; SECTION 5: Convert signed vectors to absolute values
    ; Purpose: Make all distance components positive for squaring operation
    ; Method: Check high byte sign bit; if negative, apply two's complement (flip bits + 1)
    ; **************************************************************************************************************

    ; Convert signed differences to absolute values (16-bit two's complement)
    ; Note: After making differences positive, this routine uses the MULU
    ; hardware to compute 16x16->32 products for each component. The
    ; product bytes (MULU_LL..MULU_HH) must be read immediately and are
    ; stored into temporary zero-page slots (RDXS*, RDYS*, etc.) before
    ; being accumulated via the ADD coprocessor.
    ; For each hi byte negative, negate the 16-bit value to make it positive.
    ; --- Convert RDXL/H to absolute value ---
    lda RDXH                    ; Load high byte (contains sign bit)
    bpl skipRDXH                ; If positive (bit 7 = 0), skip negation
    ; Negate using two's complement: ~value + 1
    lda RDXL                    ; Load low byte
    eor #$ff                    ; Flip all bits (one's complement)
    clc                         ; Clear carry for addition
    adc #$01                    ; Add 1 to complete two's complement
    sta RDXL                    ; Store negated low byte
    lda RDXH                    ; Load high byte
    eor #$ff                    ; Flip all bits
    adc #$00                    ; Add carry from low byte
    sta RDXH                    ; Store negated high byte (now positive)
skipRDXH:

    ; --- Convert RDYL/H to absolute value ---
    lda RDYH                    ; Load high byte (contains sign bit)
    bpl skipRDYH                ; If positive, skip negation
    lda RDYL                    ; Load low byte
    eor #$ff                    ; Flip all bits
    clc                         ; Clear carry
    adc #$01                    ; Add 1 (two's complement)
    sta RDYL                    ; Store negated low byte
    lda RDYH                    ; Load high byte
    eor #$ff                    ; Flip all bits
    adc #$00                    ; Add carry
    sta RDYH                    ; Store negated high byte
skipRDYH:

    ; --- Convert LDXL/H to absolute value ---
    lda LDXH                    ; Load high byte (contains sign bit)
    bpl skipLDXH                ; If positive, skip negation
    lda LDXL                    ; Load low byte
    eor #$ff                    ; Flip all bits
    clc                         ; Clear carry
    adc #$01                    ; Add 1 (two's complement)
    sta LDXL                    ; Store negated low byte
    lda LDXH                    ; Load high byte
    eor #$ff                    ; Flip all bits
    adc #$00                    ; Add carry
    sta LDXH                    ; Store negated high byte
skipLDXH:

    ; --- Convert LDYL/H to absolute value ---
    lda LDYH                    ; Load high byte (contains sign bit)
    bpl skipLDYH                ; If positive, skip negation
    lda LDYL                    ; Load low byte
    eor #$ff                    ; Flip all bits
    clc                         ; Clear carry
    adc #$01                    ; Add 1 (two's complement)
    sta LDYL                    ; Store negated low byte
    lda LDYH                    ; Load high byte
    eor #$ff                    ; Flip all bits
    adc #$00                    ; Add carry
    sta LDYH                    ; Store negated high byte
skipLDYH:

    ; **************************************************************************************************************
    ; SECTION 6: Square each distance component using hardware multiplier
    ; Purpose: Calculate RDX², RDY², LDX², LDY² to prepare for distance² formula
    ; Hardware: MULU performs 16x16 -> 32-bit unsigned multiply
    ; Process: Write operands to MULU_A and MULU_B, read 32-bit result from MULU_LL/LH/HL/HH
    ; Note: Results must be read immediately after write (hardware limitation)
    ; **************************************************************************************************************

    ; Square distances using hardware MULU. We compute RX^2 + RY^2 and
    ; LX^2 + LY^2 separately, read 32-bit products (we use low 16 bits)
    ; and accumulate into temporary registers (RDXS*, RDYS*, LDXS*, LDYS*).

    ; --- Calculate RDX² (right-outrigger X displacement squared) ---
    lda RDXL                    ; Load X distance component low byte
    sta MULU_A_L                ; Set multiplier operand A low
    sta MULU_B_L                ; Set multiplier operand B low (A * A)
    lda RDXH                    ; Load X distance component high byte
    sta MULU_A_H                ; Set multiplier operand A high
    sta MULU_B_H                ; Set multiplier operand B high
    ; Read 32-bit product immediately (RDX * RDX)
    lda MULU_LL                 ; Read product byte 0 (least significant)
    sta RDXSLL                  ; Store RDX² low-low byte
    lda MULU_LH                 ; Read product byte 1
    sta RDXSLH                  ; Store RDX² low-high byte
    lda MULU_HL                 ; Read product byte 2
    sta RDXSHL                  ; Store RDX² high-low byte
    lda MULU_HH                 ; Read product byte 3 (most significant)
    sta RDXSHH                  ; Store RDX² high-high byte

    ; --- Calculate RDY² (right-outrigger Y displacement squared) ---
    lda RDYL                    ; Load Y distance component low byte
    sta MULU_A_L                ; Set multiplier operand A low
    sta MULU_B_L                ; Set multiplier operand B low
    lda RDYH                    ; Load Y distance component high byte
    sta MULU_A_H                ; Set multiplier operand A high
    sta MULU_B_H                ; Set multiplier operand B high
    ; Read 32-bit product (RDY * RDY)
    lda MULU_LL                 ; Read product byte 0
    sta RDYSLL                  ; Store RDY² low-low byte
    lda MULU_LH                 ; Read product byte 1
    sta RDYSLH                  ; Store RDY² low-high byte
    lda MULU_HL                 ; Read product byte 2
    sta RDYSHL                  ; Store RDY² high-low byte
    lda MULU_HH                 ; Read product byte 3
    sta RDYSHH                  ; Store RDY² high-high byte

    ; --- Calculate LDX² (left-outrigger X displacement squared) ---
    lda LDXL                    ; Load X distance component low byte
    sta MULU_A_L                ; Set multiplier operand A low
    sta MULU_B_L                ; Set multiplier operand B low
    lda LDXH                    ; Load X distance component high byte
    sta MULU_A_H                ; Set multiplier operand A high
    sta MULU_B_H                ; Set multiplier operand B high
    ; Read 32-bit product (LDX * LDX)
    lda MULU_LL                 ; Read product byte 0
    sta LDXSLL                  ; Store LDX² low-low byte
    lda MULU_LH                 ; Read product byte 1
    sta LDXSLH                  ; Store LDX² low-high byte
    lda MULU_HL                 ; Read product byte 2
    sta LDXSHL                  ; Store LDX² high-low byte
    lda MULU_HH                 ; Read product byte 3
    sta LDXSHH                  ; Store LDX² high-high byte

    ; --- Calculate LDY² (left-outrigger Y displacement squared) ---
    lda LDYL                    ; Load Y distance component low byte
    sta MULU_A_L                ; Set multiplier operand A low
    sta MULU_B_L                ; Set multiplier operand B low
    lda LDYH                    ; Load Y distance component high byte
    sta MULU_A_H                ; Set multiplier operand A high
    sta MULU_B_H                ; Set multiplier operand B high
    ; Read 32-bit product (LDY * LDY)
    lda MULU_LL                 ; Read product byte 0
    sta LDYSLL                  ; Store LDY² low-low byte
    lda MULU_LH                 ; Read product byte 1
    sta LDYSLH                  ; Store LDY² low-high byte
    lda MULU_HL                 ; Read product byte 2
    sta LDYSHL                  ; Store LDY² high-low byte
    lda MULU_HH                 ; Read product byte 3
    sta LDYSHH                  ; Store LDY² high-high byte

    ; **************************************************************************************************************
    ; SECTION 7: Sum squared components to get total squared distances
    ; Purpose: Calculate right_distance² = RDX² + RDY² and left_distance² = LDX² + LDY²
    ; Hardware: ADD coprocessor performs 32-bit addition
    ; Process: Write operands to ADD_A and ADD_B, read 32-bit result from ADD_R
    ; Formula: distance² = dx² + dy² (Pythagorean theorem without square root)
    ; **************************************************************************************************************

    ; Sum RX^2 + RY^2 using the ADD coprocessor: put RDXS into ADD_A and
    ; RDYS into ADD_B, then read the result ADD_R_* into RDIST*.

    ; --- Calculate right_distance² = RDX² + RDY² ---
    lda RDXSLL                  ; Load RDX² byte 0
    sta ADD_A_LL                ; Set ADD operand A byte 0
    lda RDXSLH                  ; Load RDX² byte 1
    sta ADD_A_LH                ; Set ADD operand A byte 1
    lda RDXSHL                  ; Load RDX² byte 2
    sta ADD_A_HL                ; Set ADD operand A byte 2
    lda RDXSHH                  ; Load RDX² byte 3
    sta ADD_A_HH                ; Set ADD operand A byte 3
    lda RDYSLL                  ; Load RDY² byte 0
    sta ADD_B_LL                ; Set ADD operand B byte 0
    lda RDYSLH                  ; Load RDY² byte 1
    sta ADD_B_LH                ; Set ADD operand B byte 1
    lda RDYSHL                  ; Load RDY² byte 2
    sta ADD_B_HL                ; Set ADD operand B byte 2
    lda RDYSHH                  ; Load RDY² byte 3
    sta ADD_B_HH                ; Set ADD operand B byte 3
    ; Read 32-bit sum (right-outrigger squared distance to waypoint)
    lda ADD_R_LL                ; Read result byte 0
    sta RDISTLL                 ; Store right_distance² byte 0
    lda ADD_R_LH                ; Read result byte 1
    sta RDISTLH                 ; Store right_distance² byte 1
    lda ADD_R_HL                ; Read result byte 2
    sta RDISTHL                 ; Store right_distance² byte 2
    lda ADD_R_HH                ; Read result byte 3
    sta RDISTHH                 ; Store right_distance² byte 3

    ; --- Calculate left_distance² = LDX² + LDY² ---
    lda LDXSLL                  ; Load LDX² byte 0
    sta ADD_A_LL                ; Set ADD operand A byte 0
    lda LDXSLH                  ; Load LDX² byte 1
    sta ADD_A_LH                ; Set ADD operand A byte 1
    lda LDXSHL                  ; Load LDX² byte 2
    sta ADD_A_HL                ; Set ADD operand A byte 2
    lda LDXSHH                  ; Load LDX² byte 3
    sta ADD_A_HH                ; Set ADD operand A byte 3
    lda LDYSLL                  ; Load LDY² byte 0
    sta ADD_B_LL                ; Set ADD operand B byte 0
    lda LDYSLH                  ; Load LDY² byte 1
    sta ADD_B_LH                ; Set ADD operand B byte 1
    lda LDYSHL                  ; Load LDY² byte 2
    sta ADD_B_HL                ; Set ADD operand B byte 2
    lda LDYSHH                  ; Load LDY² byte 3
    sta ADD_B_HH                ; Set ADD operand B byte 3
    ; Read 32-bit sum (left-outrigger squared distance to waypoint)
    lda ADD_R_LL                ; Read result byte 0
    sta LDISTLL                 ; Store left_distance² byte 0
    lda ADD_R_LH                ; Read result byte 1
    sta LDISTLH                 ; Store left_distance² byte 1
    lda ADD_R_HL                ; Read result byte 2
    sta LDISTHL                 ; Store left_distance² byte 2
    lda ADD_R_HH                ; Read result byte 3
    sta LDISTHH                 ; Store left_distance² byte 3

    ; **************************************************************************************************************
    ; SECTION 8: Compare distances and determine turn direction
    ; Purpose: Decide whether to turn left, right, or go straight based on which outrigger is closer
    ; Algorithm:
    ;   1. Compute difference: DIFF = right_distance² - left_distance²
    ;   2. If DIFF < 0: right side closer to waypoint → turn right
    ;   3. If DIFF > 0: left side closer to waypoint → turn left
    ;   4. Apply threshold to avoid jitter from tiny differences
    ; Threshold strategy: Small differences (<threshold) don't trigger turns (avoids oscillation)
    ; **************************************************************************************************************

    ; --- Calculate difference between squared distances (32-bit subtraction) ---
    ; DIFF = RDIST - LDIST (positive means left closer, negative means right closer)
    sec                         ; Set carry for 32-bit subtraction
    lda RDISTLL                 ; Load right_distance² byte 0
    sbc LDISTLL                 ; Subtract left_distance² byte 0
    sta DIFFLL                  ; Store difference byte 0
    lda RDISTLH                 ; Load right_distance² byte 1
    sbc LDISTLH                 ; Subtract left_distance² byte 1 with borrow
    sta DIFFLH                  ; Store difference byte 1
    lda RDISTHL                 ; Load right_distance² byte 2
    sbc LDISTHL                 ; Subtract left_distance² byte 2 with borrow
    sta DIFFHL                  ; Store difference byte 2
    lda RDISTHH                 ; Load right_distance² byte 3
    sbc LDISTHH                 ; Subtract left_distance² byte 3 with borrow
    sta DIFFHH                  ; Store difference byte 3 (sign in bit 7)

    ; --- Analyze difference to make turn decision ---
    ; Decide turn direction based on sign and a small low-byte threshold
    ; Strategy: use the high byte (DIFFHH) to determine rough sign/which side
    ; is closer. Then apply a small low-byte threshold to prevent jitter from
    ; tiny differences (noise). Thresholds chosen empirically: 0x10 and 0xF0
    ; correspond to a few pixels of squared-distance difference before a turn
    ; decision is emitted.
    lda DIFFHH                  ; Load difference high byte (contains sign)
    bmi turnRight               ; If negative (bit 7 set), right side closer → turn right

    ; Left is closer if DIFF positive and above threshold
turnLeft:
    ; DIFF > 0 means left side is closer to waypoint
    lda DIFFLL                  ; Load difference low byte
    cmp #$10                    ; Compare with threshold (avoid jitter)
    ;bcc goStraight             ; If difference too small, go straight (commented out)
    lda #$ff                    ; TURN_FLAG = $FF means turn left
    sta TURN_FLAG               ; Set turn decision
    rts                         ; Return to caller

turnRight:
    ; DIFF < 0 means right side is closer to waypoint
    lda DIFFLL                  ; Load difference low byte
    cmp #$f0                    ; Compare with negative threshold
    ;bcs goStraight             ; If difference too small, go straight (commented out)
    lda #$01                    ; TURN_FLAG = $01 means turn right
    sta TURN_FLAG               ; Set turn decision
    rts                         ; Return to caller

goStraight:
    ; Difference too small - maintain current heading to avoid oscillation
    lda #$00                    ; TURN_FLAG = $00 means go straight
    sta TURN_FLAG               ; Set turn decision
    rts                         ; Return to caller

; **************************************************************************************************************
; waypoint_check - AI waypoint detection and lap management system
; Purpose: Determine if an AI car has reached its current waypoint target and handle lap completion
; Algorithm:
;   1. Compute car's front-outrigger position (point ahead of car in direction of travel)
;   2. Compare front-outrigger position against waypoint trigger line
;   3. Trigger is directional (up/down/left/right edge) to ensure one-way detection
;   4. On waypoint hit: advance target, check for lap completion
;   5. On lap completion: update leaderboard, display lap time, reset target to waypoint 0
; Inputs:
;   aicar_current = Index of AI car being checked (0-2)
;   aicar_Rotation[X] = Car's current rotation (0-31, for front-outrigger calculation)
;   aicar_target[X] = Current waypoint index this car is targeting
;   aiLineX/Y[Y] = Waypoint coordinates (16-bit X,Y position)
;   waypoint_Dir[Y] = Trigger direction (1=up, 2=right, 3=down, 4=left)
;   aiLineIndex = Total number of waypoints in track (lap complete when target wraps to 0)
; Outputs:
;   aicar_target[X] = Updated to next waypoint (or 0 if lap completed)
;   lap_count[X] = Incremented on lap completion
;   current_lap = Highest lap number reached by any car
;   first_place_flag = Leaderboard position (0-3) for lap time display
;   Lap time displayed on screen with car color
; Data Structures:
;   OR_Front* tables = Rotation-indexed offsets for front of car (32 entries, 16-bit signed)
;   HexTable = ASCII digit lookup table for BCD display
;   lap_template = "Lap X: " string template
;   lt_template = "MM:SS.TT" time display template
;   text_color_table = Car color palette indices for lap time text
; **************************************************************************************************************



waypoint_check:
    ; **************************************************************************************************************
    ; SECTION 1: Compute front-outrigger position
    ; Purpose: Calculate a point ahead of the car in its direction of travel
    ; Why: Ensures waypoint detection happens at front of car, not center (more intuitive trigger)
    ; **************************************************************************************************************

    ; --- Load AI car data ---
    ldx aicar_current           ; X = current AI car index (0-2)
    ldy aicar_Rotation,X        ; Y = car's rotation index (0-31)

    ; --- Calculate front-outrigger X coordinate ---
    ; Formula: X1 = aicar_posX + OR_FrontX[rotation]
    ; OR_FrontX is a rotation-indexed table of signed 16-bit offsets
    clc                         ; Clear carry for addition
    lda aicar_posX_L,x          ; Load car X position low byte
    adc OR_FrontXL,Y            ; Add front offset X low (rotation-dependent)
    sta X1L                     ; Store front-outrigger X low
    lda aicar_posX_H,X          ; Load car X position high byte
    adc OR_FrontXH,Y            ; Add front offset X high with carry
    sta X1H                     ; Store front-outrigger X high
    
    ; --- Calculate front-outrigger Y coordinate ---
    ; Formula: Y1 = aicar_posY + OR_FrontY[rotation]
    clc                         ; Clear carry for addition
    lda aicar_posY_L,x          ; Load car Y position low byte
    adc OR_FrontYL,Y            ; Add front offset Y low (rotation-dependent)
    sta Y1L                     ; Store front-outrigger Y low
    lda aicar_posY_H,x          ; Load car Y position high byte
    adc OR_FrontYH,Y            ; Add front offset Y high with carry
    sta Y1H                     ; Store front-outrigger Y high

    ; **************************************************************************************************************
    ; SECTION 2: Load waypoint target coordinates
    ; Purpose: Get the position of the waypoint this car is currently targeting
    ; **************************************************************************************************************

    ; --- Load waypoint coordinates ---
    lda aicar_target,X          ; Load this car's current waypoint index (0..aiLineIndex-1)
    tay                         ; Transfer to Y for array indexing
    lda aiLineX_L,Y             ; Load waypoint X coordinate low
    sta X2L                     ; Store as target X low
    lda aiLineX_H,Y             ; Load waypoint X coordinate high
    sta X2H                     ; Store as target X high
    lda aiLineY_L,Y             ; Load waypoint Y coordinate low
    sta Y2L                     ; Store as target Y low
    lda aiLineY_H,Y             ; Load waypoint Y coordinate high
    sta Y2H                     ; Store as target Y high

    ; **************************************************************************************************************
    ; SECTION 3: Directional waypoint trigger test
    ; Purpose: Check if car's front-outrigger has crossed the waypoint trigger line
    ; Strategy: Each waypoint has a direction code (1-4) indicating which edge triggers
    ;   - Direction 1 (up): Trigger when Y1 < Y2 (car moved above waypoint)
    ;   - Direction 2 (right): Trigger when X1 > X2 (car moved right of waypoint)
    ;   - Direction 3 (down): Trigger when Y1 > Y2 (car moved below waypoint)
    ;   - Direction 4 (left): Trigger when X1 < X2 (car moved left of waypoint)
    ; This directional approach ensures one-way detection (no false triggers from reverse)
    ; **************************************************************************************************************

    lda waypoint_Dir,Y          ; Load waypoint trigger direction (1-4)
    cmp #$01                    ; Is it direction 1 (up)?
    beq w_up                    ; If yes, jump to up-direction handler
    cmp #$02                    ; Is it direction 2 (right)?
    beq w_right                 ; If yes, jump to right-direction handler
    cmp #$03                    ; Is it direction 3 (down)?
    beq w_down                  ; If yes, jump to down-direction handler
    cmp #$04                    ; Is it direction 4 (left)?
    beq w_left                  ; If yes, jump to left-direction handler
    rts                         ; Invalid direction, exit without change

; **************************************************************************************************************
; w_left - Check if car crossed left edge of waypoint
; Trigger condition: X1 < X2 (car's front is left of waypoint X coordinate)
; **************************************************************************************************************
w_left:
    ; --- Compare high bytes first (coarse check) ---
    lda X1H                     ; Load front-outrigger X high byte
    cmp X2H                     ; Compare with waypoint X high byte
    bne NAW                     ; If not equal, no match (too far away)
    
    ; --- Compare low bytes (fine check) ---
    lda X1L                     ; Load front-outrigger X low byte
    cmp X2L                     ; Compare with waypoint X low byte
    bcs NAW                     ; If X1 >= X2, not crossed yet (carry set means >=)
    bra next_waypoint           ; X1 < X2, waypoint reached!

; NAW label for "Not At Waypoint" - provides long jump capability
naw:
    jmp not_at_waypoint         ; Jump to not-at-waypoint handler (out of branch range)

; **************************************************************************************************************
; w_up - Check if car crossed top edge of waypoint
; Trigger condition: Y1 < Y2 (car's front is above waypoint Y coordinate)
; **************************************************************************************************************
w_up:
    ; --- Compare high bytes first (coarse check) ---
    lda Y1H                     ; Load front-outrigger Y high byte
    cmp Y2H                     ; Compare with waypoint Y high byte
    bne NAW                     ; If not equal, no match (too far away)
    
    ; --- Compare low bytes (fine check) ---
    lda Y1L                     ; Load front-outrigger Y low byte
    cmp Y2L                     ; Compare with waypoint Y low byte
    bcs NAW                     ; If Y1 >= Y2, not crossed yet
    bra next_waypoint           ; Y1 < Y2, waypoint reached!

; **************************************************************************************************************
; w_right - Check if car crossed right edge of waypoint
; Trigger condition: X1 > X2 (car's front is right of waypoint X coordinate)
; **************************************************************************************************************
w_right:
    ; --- Compare high bytes first (coarse check) ---
    lda X1H                     ; Load front-outrigger X high byte
    cmp X2H                     ; Compare with waypoint X high byte
    bne NAW                     ; If not equal, no match (too far away)
    
    ; --- Compare low bytes (fine check) ---
    lda X1L                     ; Load front-outrigger X low byte
    cmp X2L                     ; Compare with waypoint X low byte
    bcc NAW                     ; If X1 < X2, not crossed yet (carry clear means <)
    bra next_waypoint           ; X1 >= X2, waypoint reached!

; **************************************************************************************************************
; w_down - Check if car crossed bottom edge of waypoint
; Trigger condition: Y1 > Y2 (car's front is below waypoint Y coordinate)
; **************************************************************************************************************
w_down:
    ; --- Compare high bytes first (coarse check) ---
    lda Y1H                     ; Load front-outrigger Y high byte
    cmp Y2H                     ; Compare with waypoint Y high byte
    bne NAW                     ; If not equal, no match (too far away)
    
    ; --- Compare low bytes (fine check) ---
    lda Y1L                     ; Load front-outrigger Y low byte
    cmp Y2L                     ; Compare with waypoint Y low byte
    bcc NAW                     ; If Y1 < Y2, not crossed yet
    ; Fall through to next_waypoint (Y1 >= Y2, waypoint reached!)

; **************************************************************************************************************
; SECTION 4: Waypoint reached - advance to next target
; Purpose: Increment car's target waypoint index and check for lap completion
; **************************************************************************************************************
next_waypoint:
    ; --- Advance to next waypoint ---
    ldx aicar_current           ; Reload car index (X may have been modified)
    lda aicar_target,x          ; Load current waypoint index
    clc                         ; Clear carry for addition
    adc #1                      ; Increment to next waypoint
    sta aicar_target,x          ; Store new target index
    
    ; --- Check for lap completion ---
    ; If new target index >= aiLineIndex, we've completed a lap
    ; aiLineIndex holds the total number of waypoints (e.g., 20 waypoints = indices 0-19)
    cmp aiLineIndex             ; Compare with total waypoint count
    beq DWP                     ; If equal, still within lap (index now equals max)
    bcc DWP                     ; If less than, still within lap
    bra reset_lap               ; If greater, lap complete! Reset to waypoint 0

DWP:
    jmp doneWaypoint            ; Jump to speed update (out of branch range)

; **************************************************************************************************************
; SECTION 5: Lap completion handler
; Purpose: Record lap completion, update leaderboard position, display lap time on screen
; Algorithm:
;   1. Increment lap counter for this car
;   2. Update current_lap (highest lap reached by any car)
;   3. Determine leaderboard position (first_place_flag)
;   4. Format lap time (MM:SS.TT) from BCD timer values
;   5. Display lap time on screen at position based on leaderboard rank
; **************************************************************************************************************
reset_lap:
    ; --- Update lap counters and leaderboard ---
    inc first_place_flag        ; Increment place counter (0=1st, 1=2nd, etc.)
    inc lap_count,x             ; Increment this car's lap counter
    lda lap_count,x             ; Load new lap count
    cmp current_lap             ; Compare with current highest lap
    beq skip_first_place        ; If equal, not in lead
    bcc skip_first_place        ; If less than, not in lead
    sta current_lap             ; If greater, this car is now leading!
    stz first_place_flag        ; Reset to first place (position 0)
    
skip_first_place:
    ; --- mark the lap completion for this car
    ; --- Prepare to display lap time ---
    ; --- Store final lap time if this is the first time on this lap ---
    lda lap_count,x             ; Load this car's lap count
    cmp last_lap                ; Compare with last_lap value (final lap)
    bne not_last_lap            ; If not equal, skip final time storage
    lda minutes,x               ; Load this car's minutes time
    sta fminutes,x              ; Store as final minutes
    lda seconds,x               ; Load this car's seconds time
    sta fseconds,x              ; Store as final seconds
    lda tenths,x                ; Load this car's tenths time
    sta ftenths,x               ; Store as final tenths
    lda fplace_index            ; Load current final place index
    sta fplace,X                ; Store car index for final
    inc fplace_index            ; Increment final place counter

    lda fplace_index            ; Reload final place index
    cmp #$04                    ; Check if all 3 cars have finished (cars +1)
    bne not_last_lap            ; If not all finished, skip final results display
    ; --- All cars have finished the race, set race_on flag to race over ---
    inc race_on


not_last_lap:

    ; --- Reset waypoint target to beginning of track ---
    lda #$00                    ; Start from waypoint 0
    sta aicar_target,x          ; Reset this car's target

    ; **************************************************************************************************************
    ; SECTION 6: Format lap time for display
    ; Purpose: Convert BCD timer values to ASCII digits in lap time template
    ; Format: "Lap X: MM:SS.TT" (X = lap number, MM = minutes, SS = seconds, TT = tenths)
    ; **************************************************************************************************************

    ; --- Extract lap number digit ---
    lda lap_count,X             ; Load lap count 
    and #$0f                    ; Mask low nibble (ones digit of lap count)
    tay                         ; Use as index into HexTable
    lda HexTable,Y              ; Convert BCD digit to ASCII character
    sta lap_template+4          ; Store in "Lap X:" template (position 4)
    
    ; --- Extract minutes tens digit ---
    lda minutes,X               ; Load minutes (BCD format: $00-$99)
    sta fminutes,X              ; Store as final minutes for record
    lsr                         ; Shift right 4 times to get high nibble
    lsr                         ; (divide by 16 = tens digit)
    lsr
    lsr
    tay                         ; Use as index into HexTable
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template             ; Store as first character of time (position 0)
    
    ; --- Extract minutes ones digit ---
    lda minutes,X               ; Load minutes again
    and #$0f                    ; Mask low nibble (ones digit)
    tay                         ; Use as index
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template+1           ; Store as second character (position 1)
    
    ; --- Extract seconds tens digit ---
    lda seconds,X               ; Load seconds (BCD format: $00-$59)
    sta fseconds,X              ; Store as final seconds for record
    lsr                         ; Shift right to get high nibble
    lsr
    lsr
    lsr
    tay                         ; Use as index
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template+3           ; Store after colon (position 3, skipping ':' at 2)
    
    ; --- Extract seconds ones digit ---
    lda seconds,X               ; Load seconds again
    and #$0f                    ; Mask low nibble
    tay                         ; Use as index
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template+4           ; Store as fourth digit (position 4)
    
    ; --- Extract tenths tens digit ---
    lda tenths,X                ; Load tenths (BCD format: $00-$99)
    sta ftenths,X               ; Store as final tenths for record
    lsr                         ; Shift right to get high nibble
    lsr
    lsr
    lsr
    tay                         ; Use as index
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template+6           ; Store after decimal (position 6, skipping '.' at 5)
    
    ; --- Extract tenths ones digit ---
    lda tenths,X                ; Load tenths again
    and #$0f                    ; Mask low nibble
    tay                         ; Use as index
    lda HexTable,Y              ; Convert to ASCII
    sta lt_template+7           ; Store as final digit (position 7)

    ; --- Optional: Reset timer for this car (currently commented out) ---
    ;lda #$00                   ; Could reset timer to measure per-lap times
    ;sta minutes,X              ; Reset minutes
    ;sta seconds,X              ; Reset seconds
    ;sta tenths,X               ; Reset tenths

    ; **************************************************************************************************************
    ; SECTION 7: Calculate screen position for lap time display
    ; Purpose: Position lap time text on screen based on leaderboard rank
    ; Layout: First place at top, subsequent places stacked vertically below
    ; Each position is $50 bytes lower in screen memory (one row = 80 chars = $50 bytes)
    ; **************************************************************************************************************

    ; --- Initialize base screen address ---
    lda #$32                    ; Screen memory base address low ($C232)
    sta ptr_dst                 ; Store as destination pointer low
    lda #$c2                    ; Screen memory base address high
    sta ptr_dst+1               ; Store as destination pointer high

    ; --- Adjust pointer based on leaderboard position ---
    ldy #$00                    ; Initialize position counter
txt_placement_loop:
    cpy first_place_flag        ; Have we reached this car's position?
    beq skip_txt_loop           ; If yes, done adjusting pointer
    
    ; Move pointer down one row ($50 bytes per row)
    clc                         ; Clear carry for addition
    lda ptr_dst                 ; Load pointer low byte
    adc #$50                    ; Add one row offset (80 characters = $50 hex)
    sta ptr_dst                 ; Store updated pointer low
    lda ptr_dst+1               ; Load pointer high byte
    adc #$00                    ; Add carry
    sta ptr_dst+1               ; Store updated pointer high
    iny                         ; Increment position counter
    bra txt_placement_loop      ; Continue until reaching target position
    
skip_txt_loop:
    ; --- Setup color and attribute pointer ---
    lda text_color_table,X      ; Load car's display color from table
    sta textColor               ; Store for use in print loop
    
    ldy #$00                    ; Initialize character index
    clc                         ; Clear carry for addition
    lda ptr_dst                 ; Load character pointer low
    adc #$50                    ; Add one row to get attribute memory offset
    sta ptr_src                 ; Store as source pointer (for attributes)
    lda ptr_dst+1               ; Load character pointer high
    adc #$00                    ; Add carry
    sta ptr_src+1               ; Store source pointer high

    ; **************************************************************************************************************
    ; SECTION 8: Write lap time to screen
    ; Purpose: Display formatted lap time string with car-specific color
    ; Memory layout: Character data in one bank, attribute data in adjacent bank
    ; **************************************************************************************************************

print_lap_loop:
    ; --- Write character data ---
    lda #$02                    ; Select character data bank (MMU page 2)
    sta MMU_IO_CTRL             ; Switch to character bank
    lda lap_template,Y          ; Load character from template
    sta (ptr_dst),y             ; Write to screen character memory
    
    ; --- Write background/spacing ---
    lda #$20                    ; Space character (ASCII $20)
    sta (ptr_src),y             ; Write to next row (spacing/background)
    
    ; --- Write attribute data ---
    inc MMU_IO_CTRL             ; Switch to attribute bank (MMU page 3)
    lda textColor               ; Load car's color attribute
    sta (ptr_dst),y             ; Write color to attribute memory
    
    ; --- Move to next character ---
    iny                         ; Increment character index
    cpy #$0f                    ; Have we written all 15 characters?
    bcc print_lap_loop          ; If not, continue loop

    ; --- Restore memory bank ---
    stz MMU_IO_CTRL             ; Switch back to default bank (page 0)

 
    ;bra doneWaypoint           ; Optional: could jump directly to done

; **************************************************************************************************************
; SECTION 9: Waypoint check complete
; Purpose: Final cleanup and speed adjustment for waypoint
; **************************************************************************************************************

not_at_waypoint:
    ; Car has not reached waypoint yet, no action needed
    ; Fall through to doneWaypoint

doneWaypoint:
    ; --- Update car's target speed for current waypoint ---
    ; Each waypoint has an associated speed fraction (0.0-1.0 in 8-bit fixed point)
    ; This allows slowing cars for tight corners, speeding up for straights
    ; Formula: target_speed = waypoint_speed_fraction * car_top_speed
    
    lda aicar_target,x          ; Load current waypoint index
    tay                         ; Transfer to Y for array indexing
    lda waypoint_Spd,Y          ; Load waypoint speed fraction (0-255)
    sta MULU_A_L                ; Set as MULU operand A low
    stz MULU_A_H                ; Clear operand A high (8-bit value)
    
    lda aicar_TopSpd_F,x        ; Load car's top speed fractional byte
    sta MULU_B_L                ; Set as MULU operand B low
    lda aicar_TopSpd_L,x        ; Load car's top speed low byte
    sta MULU_B_H                ; Set as MULU operand B high
    
    ; MULU result = speed_fraction * top_speed (16-bit result in MULU_LL..MULU_HH)
    lda MULU_LH                 ; Read result mid-low byte
    sta aicar_TgtSpd_F,x        ; Store as target speed fractional
    lda MULU_HL                 ; Read result mid-high byte
    sta aicar_TgtSpd_L,x        ; Store as target speed low
    rts                         ; Return to caller

; **************************************************************************************************************
; collisionCheck - Main collision detection entry point
; Purpose: Check all car-to-car collisions using a double-loop approach
; Strategy: Uses nested loops to check each unique car pair exactly once
;   Outer loop (Y): iterates through cars 0-2 as "primary" car
;   Inner loop (X): checks primary car against all cars with higher index
; This avoids duplicate checks (e.g., car 0 vs car 1 AND car 1 vs car 0)
; **************************************************************************************************************

collisionCheck:
; ---------------------------------------------------------------
; CHECK_COLLISION - simple overlap test.
; Purpose: determine whether two squares (center1,R1) and (center2,R2) overlap.
; Inputs: X1L/X1H, Y1L/Y1H, X2L/X2H, Y2L/Y2H, R1, R2.
; DIST2/RAD2 temporaries, A/X/Y registers.
; Notes: uses quick-reject on per-axis ranges then exact squared-distance test.
; ---------------------------------------------------------------

CHECK_COLLISION:
    ldy #$00        ; Set y register for primary car index
                    ; start outer loop over all cars
objext_Y_loop:
    ; --- Setup inner loop pointer ---
    ; Transfer Y to X, then increment X so we only check cars with higher index
    ; Example: when Y=0, X starts at 1 (checks car 0 vs cars 1,2,3)
    ;          when Y=1, X starts at 2 (checks car 1 vs cars 2,3)
    tyx       ; transfer y to x for indexing
    inx        ; this sets the x to point to the car afer the primary car
                ; so we don't check self-collision and double checks
object_loop:
    ; --- Load car Y (primary car) position into collision registers ---
    ; set up circle parameters for collision_math
    ;ldy aicar_current
    lda aicar_posX_L,y          ; Load primary car X position (low byte)
    sta X1L
    lda aicar_posX_H,y          ; Load primary car X position (high byte)
    sta X1H
    lda aicar_posY_L,y          ; Load primary car Y position (low byte)
    sta Y1L
    lda aicar_posY_H,y          ; Load primary car Y position (high byte)
    sta Y1H
    lda #$08                    ; Set collision radius (8 pixels = half car width)
    sta R1
    
    ; --- Load car X (comparison car) position into collision registers ---
    ; load second object parameters of the other car
    lda aicar_posX_L,x          ; Load comparison car X position (low byte)
    sta X2L
    lda aicar_posX_H,x          ; Load comparison car X position (high byte)
    sta X2H
    lda aicar_posY_L,x          ; Load comparison car Y position (low byte)
    sta Y2L
    lda aicar_posY_H,x          ; Load comparison car Y position (high byte)
    sta Y2H
    
    ; --- Perform collision test and handle response ---
    jsr collision_math          ; Test for collision between cars Y and X, do response if detected

    inx                         ; Move to next comparison car
    cpx #$04                    ; Have we checked all 4 cars (0-3)?
    bcc object_loop             ; If not, continue inner loop
    
    ; --- Advance to next car in outer loop ---
    iny                         ; Move to next primary car
    cpy #$03                    ; Have we checked cars 0-2 as primary?
    bcc objext_Y_loop           ; If not, continue outer loop
exitLoop:
    rts                         ; All car pairs checked, return

; **************************************************************************************************************
; collision2 - Handle collision spinout effects (UNUSED)
; Purpose: Mark colliding cars for spinout animation
; Inputs: Y = car index 1, X = car index 2 (the two cars that collided)
; Outputs: Sets CollideFlag and CollideRot for both cars using random values
; Notes: Currently not called from main collision detection routine
; **************************************************************************************************************
collision2:
    ; mark the two cars involved in the collision


; --------------------------------------------------------------------------
    lda #$02           ; DEBUG: Visual indicator - increment screen memory
    sta MMU_IO_CTRL    ; Switch to memory page 2
    inc $c002          ; Increment memory location (shows collision occurred)
    stz MMU_IO_CTRL    ; Restore memory page 0
; --------------------------------------------------------------------------

    ; --- Set spinout parameters for primary car (Y) ---
    ldy aicar_current           ; Load current car index
    lda Random_L                ; Get random value for spinout duration
    and #$1f                    ; Mask to 0-31 frames
    sta aicar_CollideFlag,y     ; Set spinout counter for this car
    lda aicar_Rotation,y        ; Save current rotation
    sta aicar_CollideRot,y      ; Store as collision rotation for restoration
    
    ; --- Set spinout parameters for comparison car (X) ---
    lda Random_L                ; Get another random value
    and #$1f                    ; Mask to 0-31 frames
    sta aicar_CollideFlag,x     ; Set spinout counter for other car
    rts


; **************************************************************************************************************
; collision_math - Axis-Aligned Bounding Box (AABB) collision detection with response
; Purpose: Detect collision between two cars using rectangle overlap test,
;          then compute physical response (position separation and momentum transfer)
; Inputs:
;   X1L/X1H, Y1L/Y1H = Car 1 position (16-bit world coordinates)
;   X2L/X2H, Y2L/Y2H = Car 2 position (16-bit world coordinates)
;   R1 = Collision radius (8 pixels for 16x16 car sprites)
;   Y = Car 1 index, X = Car 2 index (preserved for response calculations)
; Outputs:
;   Carry flag: SET if collision detected, CLEAR if no collision
;   If collision: Both car positions adjusted to separate them
;                 Speed/momentum transferred between cars
; Algorithm:
;   1. Quick-reject test on X axis: compute distance, check against 2*radius
;   2. Quick-reject test on Y axis: compute distance, check against 2*radius
;   3. If both pass: collision detected, proceed to response
;   4. Response: Separate cars along major axis of overlap
;                Transfer momentum from faster car to slower car
; **************************************************************************************************************
collision_math:
; simple rectangle collision detection
    ; --- Setup collision threshold ---
    ; double radius sum
    lda R1                      ; Load collision radius (8 pixels)
    asl                         ; Multiply by 2 (collision threshold = 16 pixels)
    sta R2                      ; Store doubled radius for comparison
    
    ; --- X-axis collision test ---
    ; Quick reject on X axis
    ; Compute signed distance: RAW_DISTX = X1 - X2
    sec                         ; Set carry for subtraction
    lda X1L                     ; Load car 1 X position (low byte)
    sbc X2L                     ; Subtract car 2 X position (low byte)
    sta RAW_DISTX_L             ; Store raw X distance (signed)
    lda X1H                     ; Load car 1 X position (high byte)
    sbc X2H                     ; Subtract car 2 X position (high byte) with borrow
    sta RAW_DISTX_H             ; Store raw X distance high byte (sign)
    
    ; Convert signed distance to unsigned for comparison
    ; Add offset for radius sum (makes negative values wrap to high positive)
    clc                         ; Clear carry for addition
    lda RAW_DISTX_L             ; Load raw distance low
    adc R1                      ; Add radius (shifts range: -8..+8 -> 0..16)
    sta DISTX_L                 ; Store adjusted distance
    lda RAW_DISTX_H             ; Load raw distance high (sign byte)
    adc #$00                    ; Add carry propagation
    sta DISTX_H                 ; Store adjusted distance high byte
    
    ; Check if X distance exceeds collision threshold
    lda DISTX_H                 ; Load high byte of adjusted distance
    bne no_collision            ; If non-zero, distance > 255, no collision
    lda DISTX_L                 ; Load low byte of adjusted distance
    cmp R2                      ; Compare with 2*radius (16 pixels)
    bcs no_collision            ; If distance >= 16, no X overlap, exit
    
    ; --- Y-axis collision test ---
    ; Quick reject on Y axis
    ; Compute signed distance: RAW_DISTY = Y1 - Y2
    sec                         ; Set carry for subtraction
    lda Y1L                     ; Load car 1 Y position (low byte)
    sbc Y2L                     ; Subtract car 2 Y position (low byte)
    sta RAW_DISTY_L             ; Store raw Y distance (signed)
    lda Y1H                     ; Load car 1 Y position (high byte)
    sbc Y2H                     ; Subtract car 2 Y position (high byte) with borrow
    sta RAW_DISTY_H             ; Store raw Y distance high byte (sign)
    
    ; Convert signed distance to unsigned for comparison
    clc                         ; Clear carry for addition
    lda RAW_DISTY_L             ; Load raw distance low
    adc R1                      ; Add radius (shifts range)
    sta DISTY_L                 ; Store adjusted distance
    lda RAW_DISTY_H             ; Load raw distance high (sign byte)
    adc #$00                    ; Add carry propagation
    sta DISTY_H                 ; Store adjusted distance high byte
    
    ; Check if Y distance exceeds collision threshold
    lda DISTY_H                 ; Load high byte of adjusted distance
    bne no_collision            ; If non-zero, distance > 255, no collision
    lda DISTY_L                 ; Load low byte of adjusted distance
    cmp R2                      ; Compare with 2*radius (16 pixels)
    bcs no_collision            ; If distance >= 16, no Y overlap, exit
    
    ; --- Collision confirmed: proceed to response ---
    bra collision_react         ; Both X and Y overlap, handle collision

no_collision:
    ; set no-collision flag
    clc                         ; Clear carry to signal no collision
    rts                         ; Return to caller
    
; **************************************************************************************************************
; collision_react - Physical collision response system
; Purpose: After collision detection, separate cars and transfer momentum
; Strategy:
;   1. Compute absolute values of X and Y separation distances
;   2. Determine major axis (X or Y) with largest overlap
;   3. Separate cars along major axis (push apart by half the overlap)
;   4. Transfer momentum from faster car to slower car (simulates impact)
; Inputs:
;   RAW_DISTX_L/H = Signed X distance between cars
;   RAW_DISTY_L/H = Signed Y distance between cars
;   Y = Car 1 index, X = Car 2 index
; Outputs:
;   Both car positions modified to separate them
;   Both car speeds modified to transfer momentum
;   Carry flag SET to indicate collision occurred
; **************************************************************************************************************
collision_react:
    ; set collision flag
    sec                         ; Set carry to indicate collision
    cpx #$03                    ; Check if car X is the player car (index 3)
    bne skip_collision_sound   ; If not, skip sound effect
    lda #$80                    ; close sound gate trigger
    sta SID_R3_GATE             ; Trigger collision sound effect
    lda #$81                    ; open sound gate trigger
    sta SID_R3_GATE           ; Trigger collision sound effect
skip_collision_sound:

; --------------------------------------------------------------------------
;    lda #$02                    ; DEBUG: Visual indicator - increment screen memory
;    sta MMU_IO_CTRL             ; Switch to memory page 2
;    inc $c000                   ; Increment memory location (shows collision occurred)
;    stz MMU_IO_CTRL             ; Restore memory page 0
; --------------------------------------------------------------------------

    ; --- Convert signed distances to absolute values ---
    ; We need absolute values to determine which axis has greater overlap
    ; XSIGN/YSIGN track the original signs for directional separation
    
    stz XSIGN                   ; Clear X sign flag (assume positive)
    stz YSIGN                   ; Clear Y sign flag (assume positive)
    
    ; --- Absolute value of X distance ---
    lda RAW_DISTX_H             ; Check sign of X distance
    bpl skipAbsX                ; If positive (bit 7 clear), skip negation
    
    ; X distance is negative, negate it using two's complement
    dec XSIGN                   ; Set sign flag to $FF (negative)
    lda RAW_DISTX_L             ; Load low byte
    eor #$ff                    ; Invert all bits (one's complement)
    clc                         ; Clear carry for addition
    adc #$01                    ; Add 1 (two's complement negation)
    sta RAW_DISTX_L             ; Store absolute value low byte
    lda RAW_DISTX_H             ; Load high byte
    eor #$ff                    ; Invert all bits
    adc #$00                    ; Add carry propagation
    sta RAW_DISTX_H             ; Store absolute value high byte
skipAbsX:

    ; --- Absolute value of Y distance ---
    lda RAW_DISTY_H             ; Check sign of Y distance
    bpl skipAbsY                ; If positive (bit 7 clear), skip negation
    
    ; Y distance is negative, negate it
    dec YSIGN                   ; Set sign flag to $FF (negative)
    lda RAW_DISTY_L             ; Load low byte
    eor #$ff                    ; Invert all bits (one's complement)
    clc                         ; Clear carry for addition
    adc #$01                    ; Add 1 (two's complement negation)
    sta RAW_DISTY_L             ; Store absolute value low byte
    lda RAW_DISTY_H             ; Load high byte
    eor #$ff                    ; Invert all bits
    adc #$00                    ; Add carry propagation
    sta RAW_DISTY_H             ; Store absolute value high byte
skipAbsY:

    ; --- Determine major axis of collision ---
    ; Compare absolute X and Y distances to find which axis has more overlap
    ; We'll separate cars along the major axis (the direction of greatest penetration)
    lda RAW_DISTX_L             ; Load absolute X distance (low byte only suffices)
    cmp RAW_DISTY_L             ; Compare with absolute Y distance
    bcc Y_major                 ; If X < Y, Y is major axis

; **************************************************************************************************************
; X_major - Collision response along X axis
; Cars overlap more in X direction, so separate them horizontally
; Use XSIGN to determine which direction to push each car
; **************************************************************************************************************
X_major:
    ; --- Halve the separation distance ---
    ; We divide by 2 so each car moves half the distance (equal separation)
    lsr RAW_DISTX_L             ; Divide X distance by 2 (shift right)
    
    ; --- Check sign and apply separation ---
    lda XSIGN                   ; Load X sign flag
    bne X_positive              ; If non-zero ($FF), distance was negative, jump to positive handler

; --- X_negative: Car 1 is to the LEFT of Car 2 ---
; Push Car 1 further left (add distance), Car 2 further right (subtract distance)
X_negative:
    clc                         ; Clear carry for addition
    lda aicar_posX_L,y          ; Load car 1 X position low
    adc RAW_DISTX_L             ; Add half separation (push left)
    sta aicar_posX_L,y          ; Store new position
    lda aicar_posX_H,y          ; Load car 1 X position high
    adc #$00                    ; Add carry propagation
    sta aicar_posX_H,y          ; Store new position high
    
    sec                         ; Set carry for subtraction
    lda aicar_posX_L,x          ; Load car 2 X position low
    sbc RAW_DISTX_L             ; Subtract half separation (push right)
    sta aicar_posX_L,x          ; Store new position
    lda aicar_posX_H,x          ; Load car 2 X position high
    sbc #$00                    ; Subtract borrow
    sta aicar_posX_H,x          ; Store new position high
    
    bra Transfer_energy         ; Skip to momentum transfer

; --- X_positive: Car 1 is to the RIGHT of Car 2 ---
; Push Car 1 further right (subtract distance), Car 2 further left (add distance)
X_positive:
    sec                         ; Set carry for subtraction
    lda aicar_posX_L,y          ; Load car 1 X position low
    sbc RAW_DISTX_L             ; Subtract half separation (push right)
    sta aicar_posX_L,y          ; Store new position
    lda aicar_posX_H,y          ; Load car 1 X position high
    sbc #$00                    ; Subtract borrow
    sta aicar_posX_H,y          ; Store new position high
    
    clc                         ; Clear carry for addition
    lda aicar_posX_L,x          ; Load car 2 X position low
    adc RAW_DISTX_L             ; Add half separation (push left)
    sta aicar_posX_L,x          ; Store new position
    lda aicar_posX_H,x          ; Load car 2 X position high
    adc #$00                    ; Add carry propagation
    sta aicar_posX_H,x          ; Store new position high

    bra Transfer_energy         ; Skip to momentum transfer

; **************************************************************************************************************
; Y_major - Collision response along Y axis
; Cars overlap more in Y direction, so separate them vertically
; Use YSIGN to determine which direction to push each car
; **************************************************************************************************************
Y_major:
    ; --- Halve the separation distance ---
    lsr RAW_DISTY_L             ; Divide Y distance by 2 (shift right)
    
    ; --- Check sign and apply separation ---
    lda YSIGN                   ; Load Y sign flag
    bne Y_positive              ; If non-zero ($FF), distance was negative, jump to positive handler

; --- Y_negative: Car 1 is ABOVE Car 2 (lower Y value) ---
; Push Car 1 further up (add distance), Car 2 further down (subtract distance)
Y_negative:
    clc                         ; Clear carry for addition
    lda aicar_posY_L,y          ; Load car 1 Y position low
    adc RAW_DISTY_L             ; Add half separation (push up)
    sta aicar_posY_L,y          ; Store new position
    lda aicar_posY_H,y          ; Load car 1 Y position high
    adc #$00                    ; Add carry propagation
    sta aicar_posY_H,y          ; Store new position high
    
    sec                         ; Set carry for subtraction
    lda aicar_posY_L,x          ; Load car 2 Y position low
    sbc RAW_DISTY_L             ; Subtract half separation (push down)
    sta aicar_posY_L,x          ; Store new position
    lda aicar_posY_H,x          ; Load car 2 Y position high
    sbc #$00                    ; Subtract borrow
    sta aicar_posY_H,x          ; Store new position high
    
    bra Transfer_energy         ; Skip to momentum transfer

; --- Y_positive: Car 1 is BELOW Car 2 (higher Y value) ---
; Push Car 1 further down (subtract distance), Car 2 further up (add distance)
Y_positive:
    sec                         ; Set carry for subtraction
    lda aicar_posY_L,y          ; Load car 1 Y position low
    sbc RAW_DISTY_L             ; Subtract half separation (push down)
    sta aicar_posY_L,y          ; Store new position
    lda aicar_posY_H,y          ; Load car 1 Y position high
    sbc #$00                    ; Subtract borrow
    sta aicar_posY_H,y          ; Store new position high
    
    clc                         ; Clear carry for addition
    lda aicar_posY_L,x          ; Load car 2 Y position low
    adc RAW_DISTY_L             ; Add half separation (push up)
    sta aicar_posY_L,x          ; Store new position
    lda aicar_posY_H,x          ; Load car 2 Y position high
    adc #$00                    ; Add carry propagation
    sta aicar_posY_H,x          ; Store new position high


; **************************************************************************************************************
; Transfer_energy - Momentum transfer system
; Purpose: Simulate elastic collision by transferring speed from faster car to slower car
; Strategy:
;   1. Compare 24-bit speeds of both cars (high byte first for efficiency)
;   2. Compute speed difference between faster and slower car
;   3. Transfer half the difference from faster car to slower car
;   4. This conserves total momentum while making collision feel realistic
; Inputs:
;   Y = Car 1 index, X = Car 2 index
;   aicar_speed_F/L/H[Y] = Car 1 speed (24-bit: fractional, low, high)
;   aicar_speed_F/L/H[X] = Car 2 speed (24-bit: fractional, low, high)
; Outputs:
;   Both car speeds modified to reflect momentum transfer
; **************************************************************************************************************
Transfer_energy:

    ; --- Determine which car is faster (24-bit comparison) ---
    ; Compare high bytes first for efficiency (most significant difference)
    lda aicar_speed_H,y         ; Load car 1 speed high byte
    cmp aicar_speed_H,x         ; Compare with car 2 speed high byte
    bcc transfer_to_y           ; If car 1 < car 2, transfer to car 1
    beq compare_L               ; If equal, check next byte
    bra transfer_to_x           ; If car 1 > car 2, transfer to car 2
    
compare_L:
    ; High bytes equal, compare middle bytes
    lda aicar_speed_L,y         ; Load car 1 speed low byte
    cmp aicar_speed_L,x         ; Compare with car 2 speed low byte
    bcc transfer_to_y           ; If car 1 < car 2, transfer to car 1
    beq compare_F               ; If equal, check fractional byte
    bra transfer_to_x           ; If car 1 > car 2, transfer to car 2
    
compare_F:
    ; Middle bytes equal, compare fractional bytes
    lda aicar_speed_F,y         ; Load car 1 speed fractional byte
    cmp aicar_speed_F,x         ; Compare with car 2 speed fractional byte
    bcc transfer_to_y           ; If car 1 < car 2, transfer to car 1
    ; If car 1 >= car 2, fall through to transfer_to_x

; **************************************************************************************************************
; transfer_to_x - Transfer momentum from Car 1 (faster) to Car 2 (slower)
; Car 1 (Y) has more speed, so it loses some and Car 2 (X) gains some
; **************************************************************************************************************
transfer_to_x:
    ; --- Compute speed difference (24-bit subtraction) ---
    sec                         ; Set carry for subtraction
    lda aicar_speed_F,y         ; Load car 1 fractional speed
    sbc aicar_speed_F,x         ; Subtract car 2 fractional speed
    sta speed_transfer_F        ; Store difference (fractional)
    lda aicar_speed_L,y         ; Load car 1 low speed
    sbc aicar_speed_L,x         ; Subtract car 2 low speed with borrow
    sta speed_transfer_L        ; Store difference (low)
    lda aicar_speed_H,y         ; Load car 1 high speed
    sbc aicar_speed_H,x         ; Subtract car 2 high speed with borrow
    sta speed_transfer_H        ; Store difference (high)
    
    ; --- Halve the transfer amount ---
    ; Divide by 2 so momentum is shared equally (elastic collision)
    lsr speed_transfer_H        ; Shift high byte right (divide by 2)
    ror speed_transfer_L        ; Rotate low byte right (carry from high)
    ror speed_transfer_F        ; Rotate fractional byte right (carry from low)

    ; --- Add half difference to slower car (X) ---
    clc                         ; Clear carry for addition
    lda aicar_speed_F,x         ; Load car 2 fractional speed
    adc speed_transfer_F        ; Add half the transfer amount
    sta aicar_speed_F,x         ; Store new speed (fractional)
    lda aicar_speed_L,x         ; Load car 2 low speed
    adc speed_transfer_L        ; Add with carry
    sta aicar_speed_L,x         ; Store new speed (low)
    lda aicar_speed_H,x         ; Load car 2 high speed
    adc speed_transfer_H        ; Add with carry
    sta aicar_speed_H,x         ; Store new speed (high)
    
    ; --- Subtract half difference from faster car (Y) ---
    sec                         ; Set carry for subtraction
    lda aicar_speed_F,y         ; Load car 1 fractional speed
    sbc speed_transfer_F        ; Subtract half the transfer amount
    sta aicar_speed_F,y         ; Store new speed (fractional)
    lda aicar_speed_L,y         ; Load car 1 low speed
    sbc speed_transfer_L        ; Subtract with borrow
    sta aicar_speed_L,y         ; Store new speed (low)
    lda aicar_speed_H,y         ; Load car 1 high speed
    sbc speed_transfer_H        ; Subtract with borrow
    sta aicar_speed_H,y         ; Store new speed (high)
    rts                         ; Return to collision check loop

; **************************************************************************************************************
; transfer_to_y - Transfer momentum from Car 2 (faster) to Car 1 (slower)
; Car 2 (X) has more speed, so it loses some and Car 1 (Y) gains some
; **************************************************************************************************************
transfer_to_y
    ; --- Compute speed difference (24-bit subtraction) ---
    sec                         ; Set carry for subtraction
    lda aicar_speed_F,x         ; Load car 2 fractional speed
    sbc aicar_speed_F,y         ; Subtract car 1 fractional speed
    sta speed_transfer_F        ; Store difference (fractional)
    lda aicar_speed_L,x         ; Load car 2 low speed
    sbc aicar_speed_L,y         ; Subtract car 1 low speed with borrow
    sta speed_transfer_L        ; Store difference (low)
    lda aicar_speed_H,x         ; Load car 2 high speed
    sbc aicar_speed_H,y         ; Subtract car 1 high speed with borrow
    sta speed_transfer_H        ; Store difference (high)

    ; --- Halve the transfer amount ---
    lsr speed_transfer_H        ; Shift high byte right (divide by 2)
    ror speed_transfer_L        ; Rotate low byte right (carry from high)
    ror speed_transfer_F        ; Rotate fractional byte right (carry from low)

    ; --- Add half difference to slower car (Y) ---
    clc                         ; Clear carry for addition
    lda aicar_speed_F,y         ; Load car 1 fractional speed
    adc speed_transfer_F        ; Add half the transfer amount
    sta aicar_speed_F,y         ; Store new speed (fractional)
    lda aicar_speed_L,y         ; Load car 1 low speed
    adc speed_transfer_L        ; Add with carry
    sta aicar_speed_L,y         ; Store new speed (low)
    lda aicar_speed_H,y         ; Load car 1 high speed
    adc speed_transfer_H        ; Add with carry
    sta aicar_speed_H,y         ; Store new speed (high)
    
    ; --- Subtract half difference from faster car (X) ---
    sec                         ; Set carry for subtraction
    lda aicar_speed_F,x         ; Load car 2 fractional speed
    sbc speed_transfer_F        ; Subtract half the transfer amount
    sta aicar_speed_F,x         ; Store new speed (fractional)
    lda aicar_speed_L,x         ; Load car 2 low speed
    sbc speed_transfer_L        ; Subtract with borrow
    sta aicar_speed_L,x         ; Store new speed (low)
    lda aicar_speed_H,x         ; Load car 2 high speed
    sbc speed_transfer_H        ; Subtract with borrow
    sta aicar_speed_H,x         ; Store new speed (high)
    rts                         ; Return to collision check loop

; **************************************************************************************************************
; tileFind - World-to-tile coordinate converter with road detection
; Purpose: Convert player's world coordinates to tile grid indices and check if on/off road
; Algorithm:
;   1. Divide world pixel coordinates by 16 (tile size) to get tile X,Y indices
;   2. Keep remainder as pixel offset within tile (for road checking)
;   3. Compute linear tilemap index: 2 * (50*tileY + tileX) (50 tiles wide, 2 bytes/tile)
;   4. Read tile ID from tilemap at computed offset
;   5. For certain tile types, copy tile pixel data and check if player is on road surface
; Inputs:
;   TileTempX_L/H = Player world X coordinate (pixel position)
;   TileTempY_L/H = Player world Y coordinate (pixel position)
;   tilemap = Base address of 50-tile-wide tilemap (2 bytes per entry)
; Outputs:
;   currentTile = Tile ID at player position
;   TilePointX_L/H = Pixel X offset within tile (0-15)
;   TilePointY_L/H = Pixel Y offset within tile (0-15)
;   off_road flag = Set if player is not on road surface
; Hardware Used:
;   DEVU coprocessor for division (world coords / 16)
;   MULU coprocessor for multiplication (tileY * 50)
; **************************************************************************************************************
tileFind:

    ; --- Apply screen offset to get world pixel coordinates ---
    ; (This appears to be done by caller before calling tileFind)



    ; --- Convert world X coordinate to tile X index and pixel offset ---
    ; Divide X pixel coord by 16 (tile width) -> quotient = tile X, remainder = pixel X
    lda TileTempX_L             ; Load world X coordinate low byte
    sta DEVU_NUM_L              ; Set as numerator low for division
    lda TileTempX_H             ; Load world X coordinate high byte
    sta DEVU_NUM_H              ; Set as numerator high for division
    lda #16                     ; Tile size = 16 pixels
    sta DEVU_DEN_L              ; Set denominator low (16)
    stz DEVU_DEN_H              ; Set denominator high (0)
    
    lda QUOU_LL                 ; Read quotient low (tile X index)
    sta TileTempX_L             ; Store tile X coordinate low
    lda QUOU_LH                 ; Read quotient high (tile X index)
    sta TileTempX_H             ; Store tile X coordinate high
    lda REMU_LL                 ; Read remainder low (pixel offset within tile)
    sta TilePointX_L            ; Store pixel X offset (0-15)
    lda REMU_LH                 ; Read remainder high (should be 0)
    sta TilePointX_H            ; Store pixel X offset high
                                    ; TilePointX now holds the exact pixel offset within the tile

    ; --- Convert world Y coordinate to tile Y index and pixel offset ---
    lda TileTempY_L             ; Load world Y coordinate low byte
    sta DEVU_NUM_L              ; Set as numerator low for division
    lda TileTempY_H             ; Load world Y coordinate high byte
    sta DEVU_NUM_H              ; Set as numerator high for division
    lda #16                     ; Tile size = 16 pixels
    sta DEVU_DEN_L              ; Set denominator low (16)
    stz DEVU_DEN_H              ; Set denominator high (0)
    
    lda QUOU_LL                 ; Read quotient low (tile Y index)
    sta TileTempY_L             ; Store tile Y coordinate low
    lda QUOU_LH                 ; Read quotient high (tile Y index)
    sta TileTempY_H             ; Store tile Y coordinate high
    lda REMU_LL                 ; Read remainder low (pixel offset within tile)
    sta TilePointY_L            ; Store pixel Y offset (0-15)
    lda REMU_LH                 ; Read remainder high (should be 0)
    sta TilePointY_H            ; Store pixel Y offset high
                                ; TilePointY now holds the exact pixel offset within the tile

    ; --- Compute linear tilemap index ---
    ; Formula: index = 2 * (50*tileY + tileX)
    ; The factor of 2 accounts for 2-byte tile entries
    ; The factor of 50 is the tilemap width in tiles
    
    ; Step 1: Multiply tileY by 50 using MULU hardware
    lda TileTempY_L             ; Load tile Y coordinate low
    sta MULU_A_L                ; Set MULU operand A low
    lda TileTempY_H             ; Load tile Y coordinate high
    sta MULU_A_H                ; Set MULU operand A high
    lda #50                     ; Tilemap width in tiles
    sta MULU_B_L                ; Set MULU operand B low (50)
    stz MULU_B_H                ; Set MULU operand B high (0)
    
    ; Step 2: Add tileX to the product (50*tileY + tileX)
    clc                         ; Clear carry for addition
    lda MULU_LL                 ; Read product low byte
    adc TileTempX_L             ; Add tile X coordinate low
    sta tilemem_L               ; Store linear index low
    lda MULU_LH                 ; Read product high byte
    adc TileTempX_H             ; Add tile X coordinate high with carry
    sta tilemem_H               ; Store linear index high

    ; Step 3: Multiply by 2 (tile entries are 2 bytes each)
    asl tilemem_L               ; Shift left low byte (x2)
    rol tilemem_H               ; Rotate left high byte (propagate carry)

    ; --- Read tile ID from tilemap ---
    clc                         ; Clear carry for address addition
    lda #<tilemap               ; Load tilemap base address low
    adc tilemem_L               ; Add tile offset low
    sta ptr_dst                 ; Store final pointer low
    lda #>tilemap               ; Load tilemap base address high
    adc tilemem_H               ; Add tile offset high with carry
    sta ptr_dst+1               ; Store final pointer high

    lda (ptr_dst)               ; Read tile ID from tilemap (first byte of 2-byte entry)
    sta currentTile             ; Store for road checking
    
    ; --- Determine if road checking is needed ---
    ; Tile IDs $02-$06 are road tiles that don't need pixel-level checking
    ; Other tiles require pixel-level inspection to determine road surface
    cmp #$07                    ; Is tile ID >= $07?
    bcs checkTile               ; If yes, need to check pixels
    cmp #$02                    ; Is tile ID < $02?
    bcc checkTile               ; If yes, need to check pixels
    
    ; Tile is in range $02-$06 (road tile), no pixel check needed
    stz off_road                ; Clear off-road penalty flag (player is on road)
    rts                         ; Done

checkTile:
    ; Tile requires pixel-level road checking
    jsr copyTile                ; Copy tile graphics to buffer for inspection
    jsr RoadCheck               ; Check specific pixel at player position
    rts                         ; Done
; ***************************************************************************************************************
; RoadCheck - Pixel-level road surface detection
; Purpose: Sample the local roadCheckMem buffer (copied from tileset) at player's exact
;          position within the tile to determine if car is on road or off-road
; Algorithm:
;   1. Convert TilePointX/Y (0-15) to linear index in 16x16 tile buffer
;   2. Read pixel color value at that index
;   3. Compare color against known road color palette values
;   4. Set off_road flag if not a road color
; Inputs:
;   roadCheckMem = 256-byte buffer containing current tile's pixel data
;   TilePointX_L = Pixel X offset within tile (0-15)
;   TilePointY_L = Pixel Y offset within tile (0-15)
; Outputs:
;   off_road = $00 if on road, $01 if off-road
; Road Colors: $00 (black), $04-$91 (various road grays), $92, $98+ (light grays)
; Non-Road: $01-$03, $93-$97 (grass, barriers, etc.)
; Clobbers: X, A, flags
; ***************************************************************************************************************
RoadCheck:
    stz off_road                ; Clear off-road penalty flag (assume on road)
    
    ; --- Convert 2D tile coordinates to linear buffer index ---
    ; Formula: index = Y*16 + X (16 pixels per row in 16x16 tile)
    lda TilePointY_L            ; Load pixel Y offset (0-15)
    asl                         ; Multiply by 2
    asl                         ; Multiply by 4
    asl                         ; Multiply by 8
    asl                         ; Multiply by 16 (Y*16 = row start offset)
    clc                         ; Clear carry for addition
    adc TilePointX_L            ; Add pixel X offset (0-15)
    tax                         ; Transfer to X register for indexed addressing
    
    ; --- Read pixel color at player position ---
    lda roadCheckMem,x          ; Read color value from tile buffer
    
    ; --- Check if pixel color matches road palette ---
    beq foundRoad               ; If $00 (black), it's road
    cmp #$92                    ; Check for dark gray road color
    beq foundRoad               ; If $92, it's road
    cmp #$04                    ; Check if color < $04
    bcc foundRoad               ; If $01-$03, treat as road (was backwards logic, but kept for compatibility)
    cmp #$98                    ; Check for light gray road color
    bcs foundRoad               ; If >= $98, it's road
    
    ; --- Off-road detected ---
    ; If we reach here, pixel color is in non-road range ($04-$91, $93-$97)
    ; Apply speed penalty (Current slows to a crawl)

    lda #$01                    ; Set off-road penalty flag
    sta off_road                ; Movement code will apply deceleration
    rts                         ; Return with penalty active

foundRoad:
    ; --- On-road confirmed ---
    stz off_road                ; Ensure off-road penalty is clear
    rts                         ; Return with no penalty
; **************************************************************************************************************
; copyTile - DMA tile data transfer for road checking
; Purpose: Copy a 256-byte tile from the tileset graphics data to local buffer using DMA
;          This enables fast pixel-level inspection without repeated tileset accesses
; Algorithm:
;   1. Use ADD coprocessor to compute source address: tileset_base + (currentTile * 256)
;   2. Configure DMA source = computed tileset address
;   3. Configure DMA destination = roadCheckMem buffer
;   4. Set DMA count = 256 bytes
;   5. Start DMA transfer and wait for completion
; Inputs:
;   tileset = Base address of tile graphics data (each tile = 256 bytes = 16x16 pixels)
;   currentTile = Tile index to copy (0-255)
; Outputs:
;   roadCheckMem = 256-byte buffer containing tile's pixel data
; Hardware Used:
;   ADD coprocessor for address calculation
;   DMA engine for high-speed memory transfer
; Clobbers: ADD_A/B/R_*, DMA_SRC/DST/CNT_*, DMA_CTRL/STATUS registers
; Notes: Each tile is 256 bytes (16x16 pixels, 1 byte per pixel for color index)
; **************************************************************************************************************
copyTile:
    ; --- Compute source address: tileset + (currentTile * 256) ---
    ; Use ADD coprocessor: ADD_A = tileset base, ADD_B = currentTile << 8
    ; Result in ADD_R will be source address for DMA
    
    ; Setup ADD_A = tileset base address (24-bit)
    lda #<tileset               ; Load tileset base address low byte
    sta ADD_A_LL                ; Set ADD operand A (bits 0-7)
    lda #>tileset               ; Load tileset base address high byte
    sta ADD_A_LH                ; Set ADD operand A (bits 8-15)
    lda #`tileset               ; Load tileset bank byte
    sta ADD_A_HL                ; Set ADD operand A (bits 16-23)
    stz ADD_A_HH                ; Clear high byte (bits 24-31)
    
    ; Setup ADD_B = currentTile * 256 (shift tile index left 8 bits)
    stz ADD_B_LL                ; Bits 0-7 = 0 (multiply by 256)
    lda currentTile             ; Load tile index (0-255)
    sta ADD_B_LH                ; Bits 8-15 = tile index (tile * 256)
    stz ADD_B_HL                ; Clear bits 16-23
    stz ADD_B_HH                ; Clear bits 24-31

    ; --- Enable DMA engine and read computed address ---
    lda #%00000001              ; Enable bit set, but don't start transfer yet
    sta DMA_CTRL                ; Enable DMA engine (allows ADD_R read)

    ; Read computed address from ADD coprocessor result (ADD_R = ADD_A + ADD_B)
    lda ADD_R_LL                ; Read computed address low byte
    sta DMA_SRC_L               ; Set DMA source address low
    lda ADD_R_LH                ; Read computed address mid byte
    sta DMA_SRC_M               ; Set DMA source address mid
    lda ADD_R_HL                ; Read computed address high byte
    sta DMA_SRC_H               ; Set DMA source address high

    ; --- Configure DMA destination (roadCheckMem buffer) ---
    lda #<roadCheckMem          ; Load buffer address low
    sta DMA_DST_L               ; Set DMA destination address low
    lda #>roadCheckMem          ; Load buffer address high
    sta DMA_DST_M               ; Set DMA destination address mid
    stz DMA_DST_H               ; Clear destination high byte (zero page)
    
    ; --- Configure DMA transfer size ---
    lda #$ff                    ; Transfer 256 bytes (one complete tile)
    sta DMA_CNT_L               ; Set DMA count low ($FF = 255, but DMA counts 0-255 = 256)
    stz DMA_CNT_M               ; Clear count mid byte
    stz DMA_CNT_H               ; Clear count high byte

    ; --- Start DMA transfer ---
    lda #%10000001              ; Set START bit (7) + ENABLE bit (0)
    sta DMA_CTRL                ; Begin DMA transfer

waitDMA:
    ; --- Wait for DMA completion ---
    lda DMA_STATUS              ; Read DMA status register
    and #%10000000              ; Mask busy flag (bit 7)
    cmp #%10000000              ; Is busy flag still set?
    beq waitDMA                 ; If yes, keep waiting

    ; --- Cleanup: Disable DMA engine ---
    stz DMA_CTRL                ; Clear control register (disable DMA)
    rts                         ; Return with tile data in roadCheckMem

; **************************************************************************************************************
; timers - Race timer system with BCD time tracking
; Purpose: Update race timers for all cars (player + 3 AI) and master timer
;          Maintains time in BCD (Binary Coded Decimal) format for easy display
; Algorithm:
;   1. Check if race_timer counter reached threshold (3 frames = 0.05 seconds at 60Hz)
;   2. If yes, increment all car timers by 0.05 seconds (5 tenths)
;   3. Handle carries: tenths -> seconds (at 100), seconds -> minutes (at 60)
;   4. Update timer display on screen
; Timing:
;   - Called every frame (60Hz)
;   - race_timer counts 0,1,2,0,1,2,... (resets at 3)
;   - Every 3 frames = 0.05 seconds, increment tenths by 5
; Data Format:
;   - BCD (Binary Coded Decimal): $59 = 59 decimal, not 89 decimal
;   - Enables direct display without conversion
; Timer Arrays (5 entries each):
;   tenths[0-2] = AI car 1-3 tenths, tenths[3] = player, tenths[4] = master
;   seconds[0-2] = AI car 1-3 seconds, seconds[3] = player, seconds[4] = master
;   minutes[0-2] = AI car 1-3 minutes, minutes[3] = player, minutes[4] = master
; **************************************************************************************************************
timers:
; **************************************************************************************************************
; updateTimer - increment master timer (tenths, seconds, minutes)

    ; --- Check if timer update is needed ---
    lda race_timer              ; Load frame counter (0-2)
    cmp #$03                    ; Has it reached 3? (3 frames = 0.05 sec at 60Hz)
    bcc skip_timer              ; If less than 3, skip timer update
    stz race_timer              ; Reset frame counter to 0
    
    ; --- Update all timers using BCD arithmetic ---
    sed                         ; Set Decimal mode (BCD arithmetic)
    ldx #$00                    ; Initialize car index (0 = AI car 1)
    
timer_loop:
    ; --- Increment tenths by 5 (0.05 seconds) ---
    clc                         ; Clear carry for addition
    lda tenths,x                ; Load current tenths value (BCD)
    adc #$05                    ; Add 5 tenths (0.05 seconds)
    sta tenths,x                ; Store new tenths value
    
    ; --- Handle carry to seconds ---
    lda seconds,x               ; Load current seconds (with carry from tenths)
    adc #$00                    ; Add carry (if tenths rolled over 100)
    sta seconds,x               ; Store new seconds value
    
    ; --- Check if seconds reached 60 (need to increment minutes) ---
    cmp #$60                    ; Has seconds reached 60? (BCD)
    bcc skip_minute             ; If less than 60, skip minute increment
    
    ; --- Increment minutes and reset seconds ---
    stz seconds,x               ; Reset seconds to 00 (BCD)
    lda minutes,x               ; Load current minutes
    clc                         ; Clear carry
    adc #$01                    ; Add 1 minute (BCD)
    sta minutes,x               ; Store new minutes value
    
skip_minute:
    ; --- Move to next timer ---
    inx                         ; Increment car index
    cpx #$05                    ; Have we updated all 5 timers? (3 AI + player + master)
    bcc timer_loop              ; If not, continue loop
    
    cld                         ; Clear Decimal mode (return to binary arithmetic)
    jsr print_timer             ; Update timer display on screen
    
skip_timer:
    rts                         ; Return to caller


; **************************************************************************************************************
; print_timer - Update on-screen timer display from master timer values
; Purpose: Convert BCD-formatted master timer (minutes, seconds, tenths) into digit tiles
;          and render them to the speedometer tilemap for display
; Algorithm:
;   1. Split each BCD byte into two nibbles (high and low) to get individual digits
;   2. Store each digit (0-9) in timer_template array (8 digits total: MM:SS.TT)
;   3. Convert each digit to tile index by adding $09 (tile offset for number graphics)
;   4. Write tile indices to speedo_tilemap at offset +12 (2 bytes per tile entry)
; Inputs:
;   master_minutes = BCD minutes (0-99, e.g., $23 = 23 minutes)
;   master_seconds = BCD seconds (0-59, e.g., $45 = 45 seconds)
;   master_tenths = BCD tenths (0-99, e.g., $67 = 67 hundredths)
; Outputs:
;   speedo_tilemap updated with timer digits at positions 12-27 (8 digits × 2 bytes)
; Timer Format: MM:SS.TT (e.g., "02:34.56")
;   timer_template[0] = tens of minutes
;   timer_template[1] = ones of minutes
;   timer_template[2] = colon (not modified here, static in template)
;   timer_template[3] = tens of seconds
;   timer_template[4] = ones of seconds
;   timer_template[5] = decimal point (not modified here, static in template)
;   timer_template[6] = tens of hundredths
;   timer_template[7] = ones of hundredths
; Clobbers: A, X, Y, timer_template array
; **************************************************************************************************************
print_timer:
    ; --- Extract minutes digits from BCD value ---
    lda master_minutes              ; Load BCD minutes (e.g., $23 = 23 minutes)
    lsr                             ; Shift right 4 times to get high nibble
    lsr                             ; (tens digit)
    lsr
    lsr
    sta timer_template              ; Store tens of minutes (e.g., 2 from $23)
    lda master_minutes              ; Load BCD minutes again
    and #$0f                        ; Mask to get low nibble (ones digit)
    sta timer_template+1            ; Store ones of minutes (e.g., 3 from $23)
    
    ; --- Extract seconds digits from BCD value ---
    lda master_seconds              ; Load BCD seconds (e.g., $45 = 45 seconds)
    lsr                             ; Shift right 4 times to get high nibble
    lsr                             ; (tens digit)
    lsr
    lsr
    sta timer_template+3            ; Store tens of seconds (e.g., 4 from $45)
    lda master_seconds              ; Load BCD seconds again
    and #$0f                        ; Mask to get low nibble (ones digit)
    sta timer_template+4            ; Store ones of seconds (e.g., 5 from $45)
    
    ; --- Extract tenths/hundredths digits from BCD value ---
    lda master_tenths               ; Load BCD tenths (e.g., $67 = 67 hundredths)
    lsr                             ; Shift right 4 times to get high nibble
    lsr                             ; (tens digit)
    lsr
    lsr
    sta timer_template+6            ; Store tens of hundredths (e.g., 6 from $67)
    lda master_tenths               ; Load BCD tenths again
    and #$0f                        ; Mask to get low nibble (ones digit)
    sta timer_template+7            ; Store ones of hundredths (e.g., 7 from $67)

    ; --- Write digit tiles to speedometer tilemap ---
    ldx #$00                        ; Initialize digit index (0-7)
pt_loop:
    txa                             ; Transfer digit index to A
    asl                             ; Multiply by 2 (each tile entry = 2 bytes)
    tay                             ; Transfer to Y for tilemap indexing
    lda timer_template,x            ; Load digit value (0-9)
    clc                             ; Clear carry for addition
    adc #$09                        ; Add tile offset (digit 0 starts at tile $09)
    sta speedo_tilemap+12,Y         ; Write tile index to tilemap (byte 0 = tile ID)
    lda #$03                        ; Load palette index 3 for timer digits
    sta speedo_tilemap+13,Y         ; Write palette to tilemap (byte 1 = attributes)
    inx                             ; Move to next digit
    cpx #$08                        ; Have we written all 8 digits?
    bne pt_loop                     ; If not, continue loop
    rts                             ; Return to caller


; ****************************************************************************************************************
; animate_crowd - Animated crowd sprites in the stands
; Purpose: Create visual variety by cycling crowd sprites through different animation frames
;          Uses a frame counter to alternate between horizontal and vertical crowd sections
; Algorithm:
;   1. Increment frame counter (0-3 repeating cycle)
;   2. On frame 2: Animate vertical crowd sprites (10 positions)
;   3. On frame 4: Animate horizontal crowd sprites (8 positions), reset counter
;   4. For each position, randomly select an animation frame (0-3) and write to tilemap
; Animation Cycle:
;   Frame 0,1: No action (skip)
;   Frame 2: Update vertical crowds (crowds along top/bottom edges)
;   Frame 3: No action (skip)
;   Frame 4: Update horizontal crowds (crowds along left/right edges), reset to 0
; Tile Ranges:
;   Horizontal crowd tiles: $01-$04 (base tile + random 0-3)
;   Vertical crowd tiles: $05-$08 (base tile + random 0-3)
; Inputs:
;   crowds_hori = Array of 8 tilemap offsets for horizontal crowd positions
;   crowds_vert = Array of 10 tilemap offsets for vertical crowd positions
;   Random_L = Random number generator for animation variety
; Outputs:
;   Tilemap updated with new crowd sprite tiles at specified positions
; Clobbers: A, X, Y, ptr_dst, crowd_counter
; **************************************************************************************************************
animate_crowd:
    inc crowd_counter               ; Increment animation frame counter
    lda crowd_counter               ; Load current frame count
    cmp #$02                        ; Is it frame 2?
    beq acv                         ; If yes, animate vertical crowds
    cmp #$04                        ; Is it frame 4?
    bne skip_ach                    ; If not, skip all animation this frame
    stz crowd_counter               ; Reset counter to 0 (start new cycle)
    
    ; --- Animate horizontal crowd sprites (8 positions) ---
    ldx #$00                        ; Initialize crowd position index
ach_loop:
    txa                             ; Transfer position index to A
    asl                             ; Multiply by 2 (crowd array stores 16-bit addresses)
    tay                             ; Transfer to Y for array indexing
    
    ; --- Compute tilemap address for this crowd position ---
    clc                             ; Clear carry for addition
    lda crowds_hori,y               ; Load tilemap offset low byte
    adc #<tilemap                   ; Add tilemap base address low
    sta ptr_dst                     ; Store in destination pointer
    iny                             ; Move to high byte of offset
    lda crowds_hori,y               ; Load tilemap offset high byte
    adc #>tilemap                   ; Add tilemap base address high with carry
    sta ptr_dst+1                   ; Store in destination pointer high
    
    ; --- Write random crowd animation frame to tilemap ---
    ldy #$00                        ; Reset Y for indirect indexing
    lda Random_L                    ; Read random number generator
    and #$03                        ; Mask to 0-3 (4 animation frames)
    clc                             ; Clear carry for addition
    adc #$01                        ; Add base tile index (horizontal crowds start at $01)
    sta (ptr_dst),y                 ; Write tile ID to tilemap
    iny                             ; Move to tile attribute byte
    lda #$03                        ; Load palette index 3
    sta (ptr_dst),y                 ; Write palette to tilemap
    inx                             ; Move to next crowd position
    cpx #$08                        ; Have we animated all 8 horizontal crowds?
    bcc ach_loop                    ; If not, continue loop
skip_ach:
    rts                             ; Return to caller
    
acv:
    ; --- Animate vertical crowd sprites (10 positions) ---
    ldx #$00                        ; Initialize crowd position index
acv_loop:
    txa                             ; Transfer position index to A
    asl                             ; Multiply by 2 (crowd array stores 16-bit addresses)
    tay                             ; Transfer to Y for array indexing
    
    ; --- Compute tilemap address for this crowd position ---
    clc                             ; Clear carry for addition
    lda crowds_vert,y               ; Load tilemap offset low byte
    adc #<tilemap                   ; Add tilemap base address low
    sta ptr_dst                     ; Store in destination pointer
    iny                             ; Move to high byte of offset
    lda crowds_vert,y               ; Load tilemap offset high byte
    adc #>tilemap                   ; Add tilemap base address high with carry
    sta ptr_dst+1                   ; Store in destination pointer high
    
    ; --- Write random crowd animation frame to tilemap ---
    ldy #$00                        ; Reset Y for indirect indexing
    lda Random_L                    ; Read random number generator
    and #$03                        ; Mask to 0-3 (4 animation frames)
    clc                             ; Clear carry for addition
    adc #$05                        ; Add base tile index (vertical crowds start at $05)
    sta (ptr_dst),y                 ; Write tile ID to tilemap
    iny                             ; Move to tile attribute byte
    lda #$03                        ; Load palette index 3
    sta (ptr_dst),y                 ; Write palette to tilemap
    inx                             ; Move to next crowd position
    cpx #$0a                        ; Have we animated all 10 vertical crowds?
    bcc acv_loop                    ; If not, continue loop
    rts                             ; Return to caller


; ***************************************************************************************************************
; open_message - Display opening/start message on title screen
; Purpose: Show "Press Button to Start" or similar message on first call, wait for button press
; Algorithm:
;   1. Check if message already displayed (one-time initialization)
;   2. If not displayed: Copy start_message text to screen at $C2D0
;   3. Wait for button press (joyB) to advance to next game state
; Inputs:
;   start_message = Null-terminated ($FF) message text
;   joyB = Joystick button state (nonzero = pressed)
; Outputs:
;   Message rendered to screen at $C2D0
;   race_on incremented when button pressed
;   open_message_displayed flag set
; Memory Layout:
;   Character data written to $C2D0+ (text matrix at MMU_IO_CTRL = $02)
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL
; ***************************************************************************************************************
open_message:
    ; --- Check if message already displayed ---
    lda open_message_displayed      ; Has message been shown?
    beq display_open_message        ; If no, display it
    cmp #$01                        ; is message currently displayed?
    beq om_check_button             ; If yes, keep waiting for button press
    bra bypass_open_message         ; skip displaying altogether


    display_open_message:
    inc open_message_displayed      ; Mark message as displayed (one-time flag)
    
    ; --- Setup source and destination pointers ---
    lda #<start_message             ; Load message address low byte
    sta ptr_src                     ; Store in source pointer
    lda #>start_message             ; Load message address high byte
    sta ptr_src+1                   ; Store in source pointer high
    lda #$d0                        ; Screen destination address low ($C2D0)
    sta ptr_dst                     ; Store in destination pointer
    lda #$c2                        ; Screen destination address high
    sta ptr_dst+1                   ; Store in destination pointer high
    
    ; --- Copy message to screen character matrix ---
    ldy #$00                        ; Initialize byte offset
    lda #$02                        ; Select character matrix
    sta MMU_IO_CTRL                 ; Switch to text character memory
    
om_loop:
    ; --- Copy message text byte by byte ---
    lda (ptr_src),y                 ; Read character from message
    cmp #$ff                        ; Is it terminator byte ($FF)?
    beq om_done                     ; If yes, message copy complete
    sta (ptr_dst),y                 ; Write character to screen
    inx                             ; Increment character count (debug/unused?)
    iny                             ; Move to next character
    bne om_loop                     ; If Y didn't wrap, continue same page
    inc ptr_dst+1                   ; Move destination to next page (cross $FF boundary)
    inc ptr_src+1                   ; Move source to next page
    bra om_loop                     ; Continue copying
    
om_done:
    stz MMU_IO_CTRL                 ; Restore memory map to normal
om_check_button:    
    ; --- Check for button press to advance game state ---
    lda joyB                        ; Read button state
    beq still_display               ; If not pressed, keep displaying message
    inc open_message_displayed
bypass_open_message:
    inc race_on                     ; Button pressed: advance to next game state
still_display:
    rts                             ; Return to caller

; ***************************************************************************************************************
; choose_driver - Driver selection and race configuration screen
; Purpose: Display driver selection screen, allow player to choose their driver and set lap count
;          Randomly assign remaining drivers to AI opponents, display all profiles
; Inputs: 
;   joyX = Joystick X axis (-1 = left, 0 = none, 1 = right) for driver selection
;   joyY = Joystick Y axis (-1 = up, 0 = none, 1 = down) for lap count adjustment
;   joyB = Button press (nonzero = confirm and start race)
; Outputs:
;   player_racer = Selected player driver index (0-15)
;   aicar_racer[0-2] = AI opponent driver indices (randomly assigned, no duplicates)
;   last_lap = Number of laps for race (3-9)
;   race_on flag incremented when ready to start
; Algorithm:
;   1. First call: Display message, clear screen, randomly select AI drivers
;   2. Setup sprite portraits for all 4 drivers (3 AI + player)
;   3. Handle joystick input: left/right cycles player driver, up/down adjusts lap count
;   4. Ensure no duplicate driver selections (player can't pick same as AI)
;   5. Button press confirms selection and advances to race
; ***************************************************************************************************************
choose_driver:
    
    ; --- Check if this is first call (initialization needed) ---
    lda choose_driver_displayed         ; Has driver select screen been displayed?
    bne jmp_cd_done                     ; If yes, skip initialization and go to input handling
    inc choose_driver_displayed         ; Mark screen as displayed (only initialize once)
    jsr clrScreen                       ; Clear the screen for driver selection UI
    stz joyB                            ; Clear button state (prevent instant selection)
    
    ; --- Display driver selection message to screen ---
    lda #<driver_select_message         ; Load message address low byte
    sta ptr_src                         ; Store in source pointer
    lda #>driver_select_message         ; Load message address high byte
    sta ptr_src+1                       ; Store in source pointer high
    lda #$80                            ; Screen destination address low ($C280)
    sta ptr_dst                         ; Store in destination pointer
    lda #$c2                            ; Screen destination address high
    sta ptr_dst+1                       ; Store in destination pointer high
    ldy #$00                            ; Initialize byte offset
    lda #$02                            ; Select character matrix
    sta MMU_IO_CTRL                     ; Switch to text character memory
    
cd_loop:
    ; --- Copy message text to screen character by character ---
    lda (ptr_src),y                     ; Read character from message
    cmp #$ff                            ; Is it terminator byte?
    beq cdm_done                        ; If yes, message copy complete
    sta (ptr_dst),y                     ; Write character to screen
    inx                                 ; Increment character count (unused?)
    iny                                 ; Move to next character
    bne cd_loop                         ; If Y didn't wrap, continue same page
    inc ptr_dst+1                       ; Move destination to next page
    inc ptr_src+1                       ; Move source to next page
    bra cd_loop                         ; Continue copying
    
jmp_cd_done:
    jmp cd_done                         ; Long jump to main input section
    
cdm_done:
    jsr display_last_lap                 ; Display initial lap count on screen
    stz MMU_IO_CTRL                     ; Restore memory map to normal
    
    ; --- Randomly select 3 unique AI drivers (no duplicates, can't match player) ---
    lda #$ff                            ; Initialize with invalid driver index
    sta aicar_racer                     ; Mark AI car 0 as unassigned
    sta aicar_racer+1                   ; Mark AI car 1 as unassigned
    sta aicar_racer+2                   ; Mark AI car 2 as unassigned
    ldx #$00                            ; Initialize AI car index (0-2)
    
ai_driver_select_loop:
    ; --- Generate random driver index and check for conflicts ---
    lda Random_L                        ; Read random number generator
    and #$0F                            ; Mask to 0-15 (16 available drivers)
    cmp player_racer                    ; Does it match player's driver?
    beq ai_driver_select_loop           ; If yes, try again
    cmp aicar_racer+0                   ; Does it match AI car 0?
    beq ai_driver_select_loop           ; If yes, try again
    cmp aicar_racer+1                   ; Does it match AI car 1?
    beq ai_driver_select_loop           ; If yes, try again
    cmp aicar_racer+2                   ; Does it match AI car 2?
    beq ai_driver_select_loop           ; If yes, try again
    sta aicar_racer,X                   ; Store unique driver index for this AI car
    inx                                 ; Move to next AI car
    cpx #$03                            ; Have we assigned all 3 AI drivers?
    bcc ai_driver_select_loop           ; If not, continue loop

    ; --- Setup AI driver 0 portrait sprite ---
    ; Load driver's portrait graphic address and position on screen
    ldx aicar_racer+0                   ; Get AI car 0 driver index
    lda racer_face_L,X                  ; Load portrait graphic address low byte
    sta ai_car_0_face+SP_AD_L           ; Store in sprite address low
    lda racer_face_M,X                  ; Load portrait graphic address mid byte
    sta ai_car_0_face+SP_AD_M           ; Store in sprite address mid
    lda racer_face_H,X                  ; Load portrait graphic address high byte
    sta ai_car_0_face+SP_AD_H           ; Store in sprite address high
    
    lda #$20                            ; X position = 32 pixels from left
    sta ai_car_0_face+SP_POS_X_L        ; Store sprite X position low
    lda #$00                            ; X position high byte
    sta ai_car_0_face+SP_POS_X_H        ; Store sprite X position high
    lda #$b0                            ; Y position = 176 pixels from top
    sta ai_car_0_face+SP_POS_Y_L        ; Store sprite Y position low
    lda #$00                            ; Y position high byte
    sta ai_car_0_face+SP_POS_Y_H        ; Store sprite Y position high
    lda #%00000001                      ; Enable sprite (bit 0 = enable)
    sta ai_car_0_face+SP_CTRL           ; Store sprite control flags

    lda #$c0                            ; Text color for AI driver 0
    sta tmp_color                       ; Store in temp color variable
    ldy #$c5                            ; Text screen address high byte ($C5xx)
    lda #$a8                            ; Text screen address low byte
    jsr driver_text                     ; Display AI driver 0 name/stats


    ; --- Setup AI driver 1 portrait sprite ---
    ldx aicar_racer+1                   ; Get AI car 1 driver index
    lda racer_face_L,X                  ; Load portrait graphic address low byte
    sta ai_car_1_face+SP_AD_L           ; Store in sprite address low
    lda racer_face_M,X                  ; Load portrait graphic address mid byte
    sta ai_car_1_face+SP_AD_M           ; Store in sprite address mid
    lda racer_face_H,X                  ; Load portrait graphic address high byte
    sta ai_car_1_face+SP_AD_H           ; Store in sprite address high
    
    lda #$20                            ; X position = 32 pixels from left
    sta ai_car_1_face+SP_POS_X_L        ; Store sprite X position low
    lda #$00                            ; X position high byte
    sta ai_car_1_face+SP_POS_X_H        ; Store sprite X position high
    lda #$d0                            ; Y position = 208 pixels from top
    sta ai_car_1_face+SP_POS_Y_L        ; Store sprite Y position low
    lda #$00                            ; Y position high byte
    sta ai_car_1_face+SP_POS_Y_H        ; Store sprite Y position high
    lda #%00000001                      ; Enable sprite (bit 0 = enable)
    sta ai_car_1_face+SP_CTRL           ; Store sprite control flags

    lda #$b0                            ; Text color for AI driver 1
    sta tmp_color                       ; Store in temp color variable
    ldy #$c6                            ; Text screen address high byte ($C6xx)
    lda #$e8                            ; Text screen address low byte
    jsr driver_text                     ; Display AI driver 1 name/stats
    
    ; --- Setup AI driver 2 portrait sprite ---
    ldx aicar_racer+2                   ; Get AI car 2 driver index
    lda racer_face_L,X                  ; Load portrait graphic address low byte
    sta ai_car_2_face+SP_AD_L           ; Store in sprite address low
    lda racer_face_M,X                  ; Load portrait graphic address mid byte
    sta ai_car_2_face+SP_AD_M           ; Store in sprite address mid
    lda racer_face_H,X                  ; Load portrait graphic address high byte
    sta ai_car_2_face+SP_AD_H           ; Store in sprite address high
    
    lda #$20                            ; X position = 32 pixels from left
    sta ai_car_2_face+SP_POS_X_L        ; Store sprite X position low
    lda #$00                            ; X position high byte
    sta ai_car_2_face+SP_POS_X_H        ; Store sprite X position high
    lda #$f0                            ; Y position = 240 pixels from top
    sta ai_car_2_face+SP_POS_Y_L        ; Store sprite Y position low
    lda #$00                            ; Y position high byte
    sta ai_car_2_face+SP_POS_Y_H        ; Store sprite Y position high
    lda #%00000001                      ; Enable sprite (bit 0 = enable)
    sta ai_car_2_face+SP_CTRL           ; Store sprite control flags

    lda #$d0                            ; Text color for AI driver 2
    sta tmp_color                       ; Store in temp color variable
    ldy #$c8                            ; Text screen address high byte ($C8xx)
    lda #$28                            ; Text screen address low byte
    jsr driver_text                     ; Display AI driver 2 name/stats
    
cd_done:
    ; --- Setup player driver profile (ensuring no conflicts with AI) ---
    lda player_racer                    ; Load current player driver selection
    cmp #$ff                            ; Is it uninitialized ($FF)?
    bne keep_player_driver              ; If valid, continue with it
    lda #$00                            ; Default to driver 0
    sta player_racer                    ; Initialize player driver
    
keep_player_driver:
    ; --- Check if player's choice conflicts with any AI driver ---
    lda player_racer                    ; Load player's driver selection
    cmp aicar_racer+0                   ; Does it match AI car 0?
    beq ps_adjust                       ; If yes, adjust to next driver
    cmp aicar_racer+1                   ; Does it match AI car 1?
    beq ps_adjust                       ; If yes, adjust to next driver
    cmp aicar_racer+2                   ; Does it match AI car 2?
    beq ps_adjust                       ; If yes, adjust to next driver
    bra ps_done                         ; No conflicts, proceed with this driver
    
skip_driver_select:
    ; --- Handle input delay (debounce joystick movements) ---
    dec driver_select_delay             ; Decrement delay counter
    rts                                 ; Return (waiting for delay to expire)
    
ps_adjust:
    ; --- Player selection conflicts, try next driver ---
    inc player_racer                    ; Move to next driver in roster
    bra keep_player_driver              ; Check again for conflicts
    
ps_done:
    ; --- Display player's selected driver portrait ---
    ldx player_racer                    ; Get player's driver index
    lda racer_face_L,X                  ; Load portrait graphic address low byte
    sta player_face+SP_AD_L             ; Store in sprite address low
    lda racer_face_M,X                  ; Load portrait graphic address mid byte
    sta player_face+SP_AD_M             ; Store in sprite address mid
    lda racer_face_H,X                  ; Load portrait graphic address high byte
    sta player_face+SP_AD_H             ; Store in sprite address high
    lda #$20                            ; X position = 32 pixels from left
    sta player_face+SP_POS_X_L          ; Store sprite X position low
    lda #$00                            ; X position high byte
    sta player_face+SP_POS_X_H          ; Store sprite X position high
    lda #$88                            ; Y position = 136 pixels from top
    sta player_face+SP_POS_Y_L          ; Store sprite Y position low
    lda #$00                            ; Y position high byte
    sta player_face+SP_POS_Y_H          ; Store sprite Y position high
    lda #%00000001                      ; Enable sprite (bit 0 = enable)
    sta player_face+SP_CTRL             ; Store sprite control flags

    lda #$20                            ; Text color for player driver
    sta tmp_color                       ; Store in temp color variable
    ldy #$c4                            ; Text screen address high byte ($C4xx)
    lda #$18                            ; Text screen address low byte
    jsr driver_text                     ; Display player driver name/stats
    
 choose_driver_input:
    ; --- Handle joystick input for driver/lap selection ---
    lda driver_select_delay             ; Check input delay timer
    bne skip_driver_select              ; If still counting down, ignore input
    
    ; --- Check for button press (confirm selection and start race) ---
    lda joyB                            ; Read button state
    beq next_joy_check                  ; If not pressed, check other inputs
    inc race_on                         ; Increment race flag (advance to next state)
    rts                                 ; Return (start race)

next_joy_check:
    ; --- Check horizontal joystick input (driver selection) ---
    lda joyX                            ; Read joystick X axis
    beq check_y                         ; If neutral, check Y axis instead
    lda #$10                            ; Set input delay (16 frames between inputs)
    sta driver_select_delay             ; Store delay to prevent rapid changes
    
joy_check:
    ; --- Determine joystick direction and adjust driver selection ---
    lda joyX                            ; Read joystick X axis
    bmi cd_left                         ; If negative (left), go to left handler
    
    ; --- Right: cycle to next driver ---
    inc player_racer                    ; Move to next driver
    lda player_racer                    ; Load new selection
    and #$0f                            ; Wrap to 0-15 range (16 drivers)
    sta player_racer                    ; Store wrapped value
    bra check_driver_choice             ; Check for conflicts with AI
    
cd_left:    
    ; --- Left: cycle to previous driver ---
    dec player_racer                    ; Move to previous driver
    lda player_racer                    ; Load new selection
    and #$0f                            ; Wrap to 0-15 range (16 drivers)
    sta player_racer                    ; Store wrapped value
    bra check_driver_choice             ; Check for conflicts with AI
    
check_driver_choice:
    ; --- Ensure player didn't select same driver as any AI ---
    cmp aicar_racer+0                   ; Does it match AI car 0?
    beq joy_check                       ; If yes, keep cycling
    cmp aicar_racer+1                   ; Does it match AI car 1?
    beq joy_check                       ; If yes, keep cycling
    cmp aicar_racer+2                   ; Does it match AI car 2?
    beq joy_check                       ; If yes, keep cycling
    bra good_choice                     ; No conflicts, accept this driver
    
check_y:
    ; --- Check vertical joystick input (lap count adjustment) ---
    lda joyY                            ; Read joystick Y axis
    beq good_choice                     ; If neutral, no lap adjustment needed
    lda #$10                            ; Set input delay (16 frames)
    sta driver_select_delay             ; Store delay to prevent rapid changes
    
    lda joyY                            ; Read joystick Y axis again
    bpl cd_up                           ; If positive (down), go to up handler
    
    ; --- Down: increase lap count ---
    inc last_lap                        ; Increment lap count
    lda last_lap                        ; Load new lap count
    cmp #$0a                            ; Has it reached 10?
    bcs loop_down                       ; If yes, wrap back to minimum
    bra display_last_lap                ; Display updated lap count

loop_down:
    ; --- Wrap lap count from 10 back to minimum (3) ---
    lda #$03                            ; Minimum lap count = 3
    sta last_lap                        ; Store wrapped value
    bra display_last_lap                ; Display updated lap count
    
cd_up:    
    ; --- Up: decrease lap count ---
    dec last_lap                        ; Decrement lap count
    lda last_lap                        ; Load new lap count
    cmp #$03                            ; Has it gone below 3?
    bcc loop_up                         ; If yes, wrap to maximum
    bra display_last_lap                ; Display updated lap count
 
loop_up:
    ; --- Wrap lap count from 2 up to maximum (9) ---
    lda #$09                            ; Maximum lap count = 9
    sta last_lap                        ; Store wrapped value
    bra display_last_lap                ; Display updated lap count

    jsr display_last_lap
    

good_choice:
    rts                                 ; Return to caller

    display_last_lap:
    ; --- Update lap count display on screen ---
    lda #$02                            ; Select character matrix
    sta MMU_IO_CTRL                     ; Switch to text character memory
    lda last_lap                        ; Load current lap count
    and #$0f                            ; Mask to low nibble (0-9)
    tax                                 ; Transfer to X for table lookup
    lda HexTable,X                      ; Convert to ASCII digit
    sta $c32f                           ; Write to screen at fixed location
    stz MMU_IO_CTRL                     ; Restore memory map
    rts                                 ; Return to caller

; ***************************************************************************************************************
; driver_text - Display driver name and stats at specified screen location
; Purpose: Render driver's name and statistics text to the screen with color
; Inputs:
;   X = Driver index (0-15) to look up in racer tables
;   A = Screen destination address low byte
;   Y = Screen destination address high byte
;   tmp_color = Text color to use for display
; Outputs:
;   Text rendered to screen at specified location
; Algorithm:
;   1. Setup source pointer from racer_table using driver index
;   2. Clear the text area with spaces
;   3. Copy text character by character to screen
;   4. Handle line breaks ($0D or $0F) by advancing to next line (+$50 bytes)
;   5. Apply color to each character in color matrix
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL
; ***************************************************************************************************************
driver_text:
    sta ptr_dst                         ; Store screen destination low byte
    sty ptr_dst+1                       ; Store screen destination high byte
    lda racer_table_L,X                 ; Load driver text table address low
    sta ptr_src                         ; Store in source pointer
    lda racer_table_H,X                 ; Load driver text table address high
    sta ptr_src+1                       ; Store in source pointer high

    ldy #$00                            ; Initialize offset counter
    
clear_text_loop:
    ; --- Clear text area with spaces (256 characters) ---
    lda #$02                            ; Select character matrix
    sta MMU_IO_CTRL                     ; Switch to text character memory
    lda #$20                            ; ASCII space character
    sta (ptr_dst),Y                     ; Write space to screen
    iny                                 ; Move to next character
    bne clear_text_loop                 ; Loop until Y wraps (256 iterations)

    ldx #$00                            ; Initialize source text offset
    
driver_text_loop:
    ; --- Copy driver text to screen ---
    lda #$02                            ; Select character matrix
    sta MMU_IO_CTRL                     ; Switch to text character memory
    phy                                 ; Save Y (destination offset)
    txy                                 ; Transfer source offset to Y
    lda (ptr_src),Y                     ; Read character from driver text
    ply                                 ; Restore Y (destination offset)
    
    cmp #$00                            ; Is it null terminator?
    beq driver_text_done                ; If yes, text rendering complete
    cmp #$0f                            ; Is it line feed?
    beq driver_text_nextline            ; If yes, advance to next line
    cmp #$0d                            ; Is it carriage return?
    beq driver_text_nextline            ; If yes, advance to next line

    ; --- Write character and apply color ---
    sta (ptr_dst),Y                     ; Write character to screen
    lda #$03                            ; Select color matrix
    sta MMU_IO_CTRL                     ; Switch to color memory
    lda tmp_color                       ; Load text color
    sta (ptr_dst),Y                     ; Apply color to this character
    iny                                 ; Move to next destination position
    inx                                 ; Move to next source character
    bra driver_text_loop                ; Continue copying

driver_text_nextline:
    ; --- Advance to next line on screen (80 characters = $50 bytes) ---
    clc                                 ; Clear carry for addition
    lda ptr_dst                         ; Load destination address low
    adc #$50                            ; Add 80 bytes (one screen line)
    sta ptr_dst                         ; Store new address low
    lda ptr_dst+1                       ; Load destination address high
    adc #$00                            ; Add carry if present
    sta ptr_dst+1                       ; Store new address high
    inx                                 ; Skip over line break in source
    ldy #$00                            ; Reset destination offset to line start
    bra driver_text_loop                ; Continue copying

driver_text_done:
    stz MMU_IO_CTRL                     ; Restore memory map to normal
    rts                                 ; Return to caller

; ***************************************************************************************************************
; clear_title_screen - Clear title screen elements before race start
; Purpose: Remove title screen graphics and initialize race state
;          Hides all portrait sprites and resets player/AI car positions
; Algorithm:
;   1. Clear screen buffer to remove title screen text
;   2. Disable all driver portrait sprites (3 AI + 1 player)
;   3. Reset player rotation to 0 (facing forward)
;   4. Reset all 3 AI car sprite addresses and speeds
;   5. Randomly assign starting positions to all 4 cars (no duplicates)
;   6. Update position displays and AI car positions
;   7. Increment race_on flag twice to advance to race state
; Inputs: None (uses global state: car positions, sprites, rotation)
; Outputs:
;   All portrait sprites disabled (SP_CTRL = 0)
;   PlayerRotation = 0
;   car_pos[0-3] = Random unique starting positions (0-3)
;   AI car sprite addresses and positions initialized
;   race_on incremented by 2
; Clobbers: A, X, Y, various AI and player position registers
; ***************************************************************************************************************
clear_title_screen:
    jsr clrScreen               ; Clear the screen buffer
    stz ai_car_0_face+SP_CTRL   ; Disable AI car 0 portrait sprite (hide from display)
    stz ai_car_1_face+SP_CTRL   ; Disable AI car 1 portrait sprite (hide from display)
    stz ai_car_2_face+SP_CTRL   ; Disable AI car 2 portrait sprite (hide from display)
    stz player_face+SP_CTRL     ; Disable player portrait sprite (hide from display)
    stz PlayerRotation          ; Reset player rotation to 0
    ldx #$00 
reset_ai_cars:
    ; --- Calculate Sprite Register Offset ---
    ; Convert AI car index (0-2) to sprite register offset (8, 16, 24)
    ; Formula: Y = 8 * (X + 1) = sprite slot offset from car_sprite_base
    ; X=0 → Y=8 (slot 21), X=1 → Y=16 (slot 22), X=2 → Y=24 (slot 23)
    txa                          ; Transfer car index to A
    asl                          ; Multiply by 2 (X * 2)
    asl                          ; Multiply by 2 again (X * 4)
    asl                          ; Multiply by 2 again (X * 8)
    clc                          ; Clear carry for offset addition
    adc #$08                     ; Add 8 to get sprite register offset (8, 16, 24)
    tay                          ; Transfer result to Y for indexed addressing

    ; --- Reset AI Car Sprite Address Registers ---
    ; Write 24-bit sprite address into hardware sprite registers using Y offset
    lda aicar_sprite_L,X         ; Load AI sprite base address low byte
    sta car_sprite_base+SP_AD_L,y ; Write to sprite address low register
    lda aicar_sprite_M,X         ; Load AI sprite base address mid byte
    clc                          ; Clear carry for rotation offset
    adc aicar_Rotation,x         ; Add rotation to mid byte (select frame)
    sta car_sprite_base+SP_AD_M,y ; Write to sprite address mid register
    lda #$01                     ; Load bank number (constant for all cars)
    sta car_sprite_base+SP_AD_H,y ; Write to sprite address high register
    lda #$ff                     ; Mark starting position as unassigned (placeholder)
    sta car_pos,X                ; Store in AI car starting position slot
    inx                          ; Move to next AI car
    cpx #$03                     ; Have we reset all 3 AI cars?
    bcc reset_ai_cars            ; If not, continue loop

    sta car_pos+3                ; Mark player starting position as unassigned too

    ; --- Randomly Assign Starting Grid Positions ---
    ; Algorithm: Generate random position (0-3) for each car, ensure no duplicates
    ; car_pos array maps: car index → starting position slot (0-3)
    ; Loops until all 4 cars have unique starting positions
    ldx #$00                     ; Initialize car index (0 = first car to assign)
choose_drver_pos:
    lda Random_L                 ; Read random number generator
    and #$03                     ; Mask to 0-3 (4 starting positions available)

    ; --- Check if this position is already taken by another car ---
    cmp car_pos+0                ; Does AI car 0 already have this position?
    beq choose_drver_pos         ; If yes, try again with new random number
    cmp car_pos+1                ; Does AI car 1 already have this position?
    beq choose_drver_pos         ; If yes, try again
    cmp car_pos+2                ; Does AI car 2 already have this position?
    beq choose_drver_pos         ; If yes, try again
    cmp car_pos+3                ; Does player already have this position?
    beq choose_drver_pos         ; If yes, try again

    ; --- Position is unique, assign it to current car ---
    sta car_pos,X                ; Store position assignment (car X gets position A)
    tay                          ; Transfer position index to Y for table lookup
    
    ; --- Copy starting position coordinates to car's active position registers ---
    ; Read from aicar_start_*[position] tables, write to aicar_pos*[car] arrays
    lda aicar_start_X_F,y        ; Load start position X fraction byte
    sta aicar_posX_F,X           ; Store in car's active X fraction
    lda aicar_start_X_L,y        ; Load start position X low byte
    sta aicar_posX_L,X           ; Store in car's active X low
    lda aicar_start_X_H,y        ; Load start position X high byte
    sta aicar_posX_H,X           ; Store in car's active X high
    lda aicar_start_Y_F,y        ; Load start position Y fraction byte
    sta aicar_posY_F,X           ; Store in car's active Y fraction
    lda aicar_start_Y_L,y        ; Load start position Y low byte
    sta aicar_posY_L,X           ; Store in car's active Y low
    lda aicar_start_Y_H,y        ; Load start position Y high byte
    sta aicar_posY_H,X           ; Store in car's active Y high
    
    inx                          ; Move to next car
    cpx #$04                     ; Have we assigned all 4 cars (3 AI + player)?
    bcc choose_drver_pos         ; If not, continue loop

    ; --- Update Display Positions ---
    jsr updatePOS                ; Refresh player sprite position on screen

    ; --- Initialize AI Car Movement State ---
    ; Call aiCarsMove for each AI car to set initial sprite frames and orientation
    ldx #$00                     ; Initialize AI car index
set_initial_car_pos:
    stx aicar_current            ; Set current AI car index for processing
    jsr aiCarsMove               ; Update AI car sprite and movement state
    inx                          ; Move to next AI car
    cpx #$03                     ; Have we initialized all 3 AI cars?
    bcc set_initial_car_pos      ; If not, continue loop

    ; --- Advance Game State to Racing Mode ---
    inc race_on                  ; Increment race_on (from 1 to 2)
    inc race_on                  ; Increment race_on again (from 2 to 3 = racing state)
    stz VKY_TM2_CTRL             ; Disable title screen tilemap (race mode)
    lda #$a0                     ; title screen TM2 position offscreen (y = decimal 416)
    sta title_y_pos_L
    sta VKY_TM2_POS_Y_L          ; Position TM2 offscreen
    lda #$01    
    sta title_y_pos_H
    sta VKY_TM2_POS_Y_H          ; Position TM2 offscreen
    rts                          ; Return to caller


; **************************************************************************************************************
; move_results_screen_in - Animate results screen scrolling into view
; Purpose: Slide results screen tilemap (TM2) from off-screen position to visible area
;          Creates a smooth transition from race end to final results display
; Algorithm:
;   1. Enable TM2 (results screen tilemap)
;   2. Decrement Y position by 1 pixel per frame (scroll downward)
;   3. Check if target position reached ($00AF)
;   4. When complete: clear screen, disable helicopter sprites, advance race state
; Inputs:
;   title_y_pos_L/H = Current Y position of TM2 (starts at $01A0 = 416, offscreen)
; Outputs:
;   VKY_TM2_CTRL = TM2 enabled ($01)
;   VKY_TM2_POS_Y = Updated Y position
;   race_on incremented when animation complete
;   Helicopter sprites disabled
; Target Position: $00AF (175 decimal) - results screen visible center
; Clobbers: A, flags
; **************************************************************************************************************
move_results_screen_in:
    ; --- Enable results screen tilemap ---
    lda #$00000001                  ; TM2 enable flag
    sta VKY_TM2_CTRL                ; Enable TM2 for results screen display
    
    ; --- Scroll screen upward by 1 pixel ---
    sec                             ; Set carry for 16-bit subtraction
    lda title_y_pos_L               ; Load current Y position low byte
    sbc #$01                        ; Subtract 1 (move up)
    sta title_y_pos_L               ; Store updated Y position
    sta VKY_TM2_POS_Y_L             ; Update TM2 hardware register
    lda title_y_pos_H               ; Load current Y position high byte
    sbc #$00                        ; Subtract with borrow
    sta title_y_pos_H               ; Store updated Y position high
    sta VKY_TM2_POS_Y_H             ; Update TM2 hardware register
    
    ; --- Check if target position reached ---
    lda title_y_pos_H               ; Load Y position high byte
    bne still_moving                ; If non-zero, still scrolling
    lda title_y_pos_L               ; Load Y position low byte
    cmp #$af                        ; Compare with target ($AF = 175)
    bne still_moving                ; If not at target, continue scrolling
    
    ; --- Animation complete - finalize results screen ---
    inc race_on                     ; Advance race state to results display
    jsr clrScreen                   ; Clear screen text for results overlay

    ; --- Disable all helicopter sprites ---
    ; SP_CTRL format: |xx|SZ|SZ|LA|LA|LU|LU|EN| where EN=0 disables sprite
    lda #%00000000                  ; Disable all helicopter sprites
    sta helicopter_base+SP_CTRL     ; Disable helicopter body sprite
    sta helicopter_blade+SP_CTRL    ; Disable helicopter blade sprite
    sta helicopter_shadow+SP_CTRL   ; Disable helicopter body shadow sprite
    sta helicopter_S_blade+SP_CTRL  ; Disable helicopter blade shadow sprite

    ; --- Disable all AI car sprites ---
    ldx #$01                        ; disable ai car sprites as well
disable_ai_cars:
    ; --- Calculate Sprite Register Offset ---
    ; Formula: Y = X * 8 (each sprite uses 8 registers)
    txa                             ; Transfer car index to A
    asl                             ; Multiply by 2
    asl                             ; Multiply by 2 again (now X * 4)
    asl                             ; Multiply by 2 again (now X * 8)
    tay                             ; Transfer offset to Y
    lda #%00010000                  ; Size 16x16 preserved, enable=0 (sprite off)
    sta car_sprite_base+SP_CTRL,y   ; Disable AI car sprite (hide from display)
    inx                             ; Move to next AI car
    cpx #$03                        ; Have we disabled all 3 AI cars?
    bcc disable_ai_cars             ; If not, continue loop
    
still_moving:
    jmp race_active                 ; Continue to main game loop

jmp_results_done:
    jmp results_done                ; Long jump to results done handler

; **************************************************************************************************************
; results_screen - Display race results and final standings
; Purpose: Show final race results with driver portraits, names, and finishing times
;          One-time display that presents all finishers in order with formatted times
; Algorithm:
;   1. Check if results already displayed (one-time flag)
;   2. Display "Race Results" message header
;   3. Position driver portraits in finishing order (1st-4th)
;   4. Print driver names next to portraits with color coding
;   5. Format and display finishing times (MM:SS.TT format)
;   6. Convert BCD time values to ASCII for display
; Inputs:
;   fplace[0-3] = Finishing positions for each car (0=1st, 1=2nd, etc.)
;   fminutes/fseconds/ftenths[0-3] = Final times in BCD format
;   aicar_racer[0-3] = Driver indices for name/portrait lookup
;   results_displayed = Flag to prevent duplicate display
; Outputs:
;   Screen updated with results message, portraits, names, and times
;   Driver face sprites positioned and enabled
;   results_displayed flag set
; Memory Layout:
;   Message starts at $C280
;   Portrait sprites at positions from fpos_L/H tables
;   Text at positions from ftext_pos_L/H tables
; Data Format:
;   Times displayed as "MM:SS.TT" (minutes:seconds.hundredths)
;   BCD values converted to ASCII via HexTable lookup
; Clobbers: A, X, Y, ptr_src, ptr_dst, MMU_IO_CTRL, tmp registers
; **************************************************************************************************************
results_screen:
    ; --- Check if results already displayed (one-time initialization) ---
    lda results_displayed           ; Load display flag
    bne jmp_results_done            ; If already shown, skip to done
    inc results_displayed           ; Set flag (prevent duplicate display)
    stz joyB                        ; Clear button state

    ; **************************************************************************************************************
    ; SECTION 1: Display results message header
    ; Purpose: Copy "Race Results" message to screen at fixed position
    ; Message Format: Null-terminated ($FF) text string
    ; Screen Position: $C280 (row 5, centered)
    ; **************************************************************************************************************

    ; --- Setup source and destination pointers ---
    lda #<results_message           ; Load message address low byte
    sta ptr_src                     ; Store in source pointer
    lda #>results_message           ; Load message address high byte
    sta ptr_src+1                   ; Store in source pointer high
    lda #$80                        ; Screen destination address low ($C280)
    sta ptr_dst                     ; Store in destination pointer
    lda #$c2                        ; Screen destination address high ($C2xx)
    sta ptr_dst+1                   ; Store in destination pointer high
    
    ; --- Copy message text to screen ---
    ldy #$00                        ; Initialize byte offset
    lda #$02                        ; Select character matrix
    sta MMU_IO_CTRL                 ; Switch to text character memory
    
rs_loop:
    lda (ptr_src),y                 ; Read character from message
    cmp #$ff                        ; Is it terminator byte ($FF)?
    beq rs_done                     ; If yes, message copy complete
    sta (ptr_dst),y                 ; Write character to screen
    iny                             ; Move to next character
    bne rs_loop                     ; If Y didn't wrap, continue same page
    
    ; --- Handle page boundary crossing ---
    inc ptr_dst+1                   ; Move destination to next page (256 bytes)
    inc ptr_src+1                   ; Move source to next page
    bra rs_loop                     ; Continue copying
    
rs_done:
    stz MMU_IO_CTRL                 ; Restore memory map to normal

    ; **************************************************************************************************************
    ; SECTION 2: Display driver portrait sprites
    ; Purpose: Position and enable driver face sprites in finishing order
    ; Layout: Vertical list from top (1st place) to bottom (4th place)
    ; Sprite Order: Determined by fplace array (finishing positions)
    ; **************************************************************************************************************

    ; --- Initialize driver portrait loop ---
    ldx #$00                        ; Initialize car index (0-3)
    
display_results_faces:
    ; --- Calculate sprite register offset ---
    ; Formula: Y = X * 8 (each sprite uses 8 registers)
    phx                             ; Save car index on stack
    txa                             ; Transfer car index to A
    asl                             ; Multiply by 2
    asl                             ; Multiply by 2 again (now X * 4)
    asl                             ; Multiply by 2 again (now X * 8)
    tay                             ; Transfer offset to Y
    
    ; --- Get finishing position and lookup Y coordinate ---
    lda fplace,x                    ; Load finishing position for this car
    tax                             ; Transfer to X for table lookup
    lda fpos_L,X                    ; Load Y position low byte from table
    sta ai_car_0_face+SP_POS_Y_L,y  ; Store in sprite Y position low
    lda fpos_H,X                    ; Load Y position high byte from table
    sta ai_car_0_face+SP_POS_Y_H,y  ; Store in sprite Y position high
    
    ; --- Set X position (horizontal alignment) ---
    lda #$82                        ; X position = 130 pixels from left
    sta ai_car_0_face+SP_POS_X_L,y  ; Store in sprite X position low
    lda #$00                        ; X position high byte = 0
    sta ai_car_0_face+SP_POS_X_H,y  ; Store in sprite X position high
    
    ; --- Enable sprite ---
    lda #%00000001                  ; Sprite enable (bit 0 = 1)
    sta ai_car_0_face+SP_CTRL,y     ; Write to sprite control register
    
    ; --- Advance to next car ---
    plx                             ; Restore car index from stack
    inx                             ; Move to next car
    cpx #$04                        ; Have we processed all 4 cars?
    bcc display_results_faces       ; If not, continue loop

    ; **************************************************************************************************************
    ; SECTION 3: Display driver names and finishing times
    ; Purpose: Print each driver's name and final race time next to their portrait
    ; Text Layout: Name on left, time on right (offset by $17 bytes)
    ; Color: Uses text_color_table for car-specific colors
    ; Time Format: MM:SS.TT (converted from BCD to ASCII)
    ; **************************************************************************************************************

    ; --- Initialize name printing loop ---
    ldx #$00                        ; Initialize car index (0-3)
    
print_results_names:
    ; --- Setup pointers for driver name and screen position ---
    phx                             ; Save car index on stack
    lda fplace,x                    ; Load finishing position for this car
    tay                             ; Transfer to Y for position lookup
    lda aicar_racer,x               ; Load driver index for this car
    tax                             ; Transfer to X for name lookup
    
    ; --- Load driver name string address ---
    lda racer_table_L,x             ; Load driver name table address low
    sta ptr_src                     ; Store in source pointer
    lda racer_table_H,x             ; Load driver name table address high
    sta ptr_src+1                   ; Store in source pointer high
    
    ; --- Load screen destination address ---
    lda ftext_pos_L,Y               ; Load text position low (based on finish position)
    sta ptr_dst                     ; Store in destination pointer
    lda ftext_pos_H,Y               ; Load text position high
    sta ptr_dst+1                   ; Store in destination pointer high
    
    ldy #$00                        ; Initialize character offset
    plx                             ; Restore car index from stack
    
print_results_name_loop:
    ; --- Write character to screen ---
    lda #$02                        ; Select character matrix
    sta MMU_IO_CTRL                 ; Switch to character memory
    lda (ptr_src),Y                 ; Read character from driver name
    cmp #$0f                        ; Is it line feed/terminator?
    beq print_results_name_done     ; If yes, name complete
    sta (ptr_dst),Y                 ; Write character to screen
    
    ; --- Apply color to character ---
    lda #$03                        ; Select color matrix
    sta MMU_IO_CTRL                 ; Switch to color memory
    lda text_color_table,x          ; Load car-specific color
    sta (ptr_dst),Y                 ; Apply color to this character
    
    iny                             ; Move to next character
    bra print_results_name_loop     ; Continue copying name

print_results_name_done:

    ; --- Position pointer for time display ---
    ; Offset $17 bytes to the right for time column
    clc                             ; Clear carry for addition
    lda ptr_dst                     ; Load destination pointer low
    adc #$17                        ; Add $17 (23 decimal) for time offset
    sta ptr_dst                     ; Store updated pointer low
    lda ptr_dst+1                   ; Load destination pointer high
    adc #$00                        ; Add carry if present
    sta ptr_dst+1                   ; Store updated pointer high
    
    ; --- Format and display finishing time ---
    ldy #$00                        ; Initialize character offset
    
print_results_time_loop:
    ; --- Convert BCD time to ASCII and display as MM:SS.TT ---
    ; Format: Two digits minutes, colon, two digits seconds, period, two digits hundredths
    ; BCD Extraction: High nibble = tens digit, low nibble = ones digit
    
    lda #$02                        ; Select character matrix
    sta MMU_IO_CTRL                 ; Switch to character memory
    
    ; --- Minutes tens digit (M_) ---
    lda fminutes,X                  ; Load minutes (BCD format)
    phx                             ; Save car index
    lsr                             ; Shift right 4 times
    lsr                             ; to extract high nibble
    lsr                             ; (tens digit)
    lsr
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    sta (ptr_dst),Y                 ; Write tens digit to screen
    plx                             ; Restore car index
    
    ; --- Minutes ones digit (_M) ---
    lda fminutes,X                  ; Load minutes again
    and #$0f                        ; Mask low nibble (ones digit)
    phx                             ; Save car index
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    iny                             ; Move to next screen position
    sta (ptr_dst),Y                 ; Write ones digit to screen
    plx                             ; Restore car index
    
    ; --- Colon separator (:) ---
    lda #$3a                        ; ASCII colon character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write colon to screen
    
    ; --- Seconds tens digit (S_) ---
    lda fseconds,X                  ; Load seconds (BCD format)
    phx                             ; Save car index
    lsr                             ; Shift right 4 times
    lsr                             ; to extract high nibble
    lsr                             ; (tens digit)
    lsr
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write tens digit to screen
    plx                             ; Restore car index
    
    ; --- Seconds ones digit (_S) ---
    lda fseconds,X                  ; Load seconds again
    and #$0f                        ; Mask low nibble (ones digit)
    phx                             ; Save car index
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write ones digit to screen
    plx                             ; Restore car index
    
    ; --- Period separator (.) ---
    lda #$2e                        ; ASCII period character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write period to screen
    
    ; --- Hundredths tens digit (T_) ---
    lda ftenths,X                   ; Load hundredths (BCD format)
    phx                             ; Save car index
    lsr                             ; Shift right 4 times
    lsr                             ; to extract high nibble
    lsr                             ; (tens digit)
    lsr
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write tens digit to screen
    plx                             ; Restore car index
    
    ; --- Hundredths ones digit (_T) ---
    lda ftenths,X                   ; Load hundredths again
    and #$0f                        ; Mask low nibble (ones digit)
    phx                             ; Save car index
    tax                             ; Use as index into HexTable
    lda HexTable,X                  ; Convert to ASCII character
    iny                             ; Move to next position
    sta (ptr_dst),Y                 ; Write ones digit to screen
    plx                             ; Restore car index

    ; --- Finalize display for this driver ---
    stz MMU_IO_CTRL                 ; Restore memory map to normal
    
    ; --- Move to next driver ---
    inx                             ; Increment car index
    cpx #$04                        ; Have we printed all 4 drivers?
    bcc jmp_print_results_names     ; If not, continue loop

    lda #$df                        ; Load muted volume level (turn off helicopter sound)
    sta PSG_R                       ; Write to PSG Right control register
    inc race_on                     ; Advance race state after results display to wait for input/timeout
    lda #30                        ; Set delay timer for results screen
    sta tmpx                       ; Store in temporary variable
    lda #60                        ; Set another delay timer
    sta tmpy                       ; Store in temporary variable

results_done:

    rts                             ; Return to caller

jmp_print_results_names:
    jmp print_results_names

; **************************************************************************************************************
; wait_for_button_or_timeout - Wait for user button press or timeout expiration
; Purpose: Display results screen for configured duration, allowing early exit via button press
;          Used after race completion to show final standings before returning to title
; Algorithm:
;   1. Decrement frame counter (tmpy) every frame (60 frames = 1 second)
;   2. When tmpy reaches zero, decrement seconds counter (tmpx) and reset tmpy to 60
;   3. Check for button press (joyB) every frame for early exit
;   4. When either timeout expires or button pressed, advance race state to title screen
; Inputs:
;   tmpy = Frame counter (0-60, counts down to 0 each second)
;   tmpx = Seconds counter (initialized to 30 for 30-second timeout)
;   joyB = Button state ($00 = not pressed, non-zero = pressed)
; Outputs:
;   tmpy = Decremented frame counter, reset to 60 when reaching 0
;   tmpx = Decremented seconds counter when frame counter expires
;   race_on = Incremented when timeout or button press occurs
; Timing: Called every frame (60Hz), decrements tmpx every 60 frames
; Clobbers: A
; **************************************************************************************************************
wait_for_button_or_timeout:
    dec tmpy                        ; Decrement frame counter (60 frames per second)
    lda tmpy                        ; Check if frame counter reached zero
    bne skip_second_drop            ; If not zero, skip second decrement
    lda #60                         ; Reset frame counter to 60 (one second)
    sta tmpy                        ; Store reset value
    dec tmpx                        ; Decrement seconds counter by 1
    lda tmpx                        ; Check if seconds counter reached zero
    beq wait_done_next              ; If zero, timeout expired - exit wait
skip_second_drop:
    lda joyB                        ; Read button state
    beq wait_not_done               ; If not pressed, continue waiting
wait_done_next:
    inc race_on                     ; Advance race state to bring in title screen
    stz ai_car_0_face+SP_CTRL       ; Disable AI car 0 portrait sprite
    stz ai_car_1_face+SP_CTRL       ; Disable AI car 1 portrait sprite
    stz ai_car_2_face+SP_CTRL       ; Disable AI car 2 portrait sprite
    stz player_face+SP_CTRL         ; Disable player portrait sprite
    jsr clrScreen                   ; Clear screen before title screen
    lda #$0F                        ; Load minimum volume level
    sta crowd_volume                ; Reset crowd sound volume to full (15)
    sta PSG_L                       ; Write to PSG Left control register
wait_not_done
    rts                             ; Return to caller


; **************************************************************************************************************
; bring_title_back_down - Animate title screen return and reset all game state
; Purpose: Scroll title screen back into view from results screen and completely reset all
;          race parameters to prepare for a new game session
; Algorithm:
;   1. Decrement title screen Y position by 1 pixel per frame (scroll upward into view)
;   2. Check if target position reached ($0000)
;   3. When complete: Reset all race state variables to initial values
;   4. Clear all timer and position data for next race
;   5. Reinitialize AI cars and player to starting state
; Inputs:
;   title_y_pos_L/H = Current Y position of TM2 (starts at $00AF = 175, moves to $0000)
; Outputs:
;   VKY_TM2_POS_Y = Updated Y position (scrolls from $00AF to $0000)
;   All race state variables reset to defaults
;   All timers cleared (minutes, seconds, tenths)
;   All position and speed data reset
;   Player and AI cars repositioned to starting grid
; Target Position: $0000 (top of screen) - title screen fully visible
; Clobbers: A, X, Y, numerous state variables
; **************************************************************************************************************
bring_title_back_down:
    ; --- Scroll title screen upward by 1 pixel per frame ---
    sec                             ; Set carry for 16-bit subtraction
    lda title_y_pos_L               ; Load current Y position low byte
    sbc #$01                        ; Subtract 1 pixel (move upward toward 0)
    sta title_y_pos_L               ; Store updated Y position
    sta VKY_TM2_POS_Y_L             ; Update TM2 hardware register
    lda title_y_pos_H               ; Load current Y position high byte
    sbc #$00                        ; Subtract with borrow (propagate carry)
    sta title_y_pos_H               ; Store updated Y position high
    sta VKY_TM2_POS_Y_H             ; Update TM2 hardware register

    lda title_y_pos_L               ; Load Y position low byte
    lsr                             ; divide by 2
    lsr                             ; divide by 4
    lsr                             ; divide by 8
    cmp #$0f                        ; max volume level
    bcs skip_sid_volume_adjust      ; if more than max, skip
    sta SID_L_VOL                   ; Adjust SID left volume for effect
    sta SID_R_VOL                   ; Adjust SID right volume for effect
skip_sid_volume_adjust:

    ; --- Check if target position reached (title fully visible) ---
    lda title_y_pos_H               ; Load Y position high byte
    bne jmp_still_moving2           ; If non-zero, still scrolling upward
    lda title_y_pos_L               ; Load Y position low byte
    bne jmp_still_moving2           ; If not at target (0), continue scrolling

    bra reset_parameters            ; Target reached: begin state reset
jmp_still_moving2:
    jmp still_moving2               ; Continue scrolling (return to main loop)

reset_parameters:
    ; **************************************************************************************************************
    ; SECTION 1: Reset Core Race State Variables
    ; Purpose: Clear all race progress and state flags to prepare for new game
    ; **************************************************************************************************************
    
    stz race_on                     ; Reset race state to 0 (title screen mode)
    stz race_lap                    ; Clear current lap counter
    stz countdown_timer             ; Reset pre-race countdown timer
    stz start_light_set             ; Clear starting light sequence state
    stz tree_y_pos                  ; Reset animated tree Y position
    
    ; --- Clear UI Display Flags ---
    stz results_displayed           ; Reset results screen flag (allow new display)
    stz choose_driver_displayed     ; Reset driver selection flag (allow new display)
    
    ; --- Reset Race Progress Tracking ---
    stz current_lap                 ; Clear current lap being timed
    stz first_place_flag            ; Clear first place status indicator
    
    ; --- Reset Master Race Timer (BCD Format) ---
    stz master_minutes              ; Clear master timer minutes
    stz master_seconds              ; Clear master timer seconds
    stz master_tenths               ; Clear master timer hundredths
    stz race_timer                  ; Reset frame counter for timer updates
    stz fplace_index                ; Clear finishing position index
    
    ; --- Reset Starting Countdown ---
    lda #$05                        ; Initialize countdown to 5 (5, 4, 3, 2, 1, GO)
    sta start_counter               ; Store starting countdown value

    ; **************************************************************************************************************
    ; SECTION 2: Reset Player Car State
    ; Purpose: Clear all player vehicle data to starting state
    ; **************************************************************************************************************
    
    stz PlayerRotation              ; Reset player rotation to 0 (facing north)
    stz playerSpeed_F               ; Clear player speed fraction byte (sub-pixel velocity)
    stz playerSpeed_L               ; Clear player speed low byte (primary velocity)
    stz playerSpeed_H               ; Clear player speed high byte (high velocity)
    stz player_target               ; Reset player waypoint target to 0 (start position)
    stz Player_collideFlag          ; Clear player collision active flag
    stz Player_CollideRot           ; Clear player collision rotation adjustment
    
    ; --- Reset Control Input State ---
    stz CUR_DIR                     ; Reset current direction to 0 (straight ahead)
    stz TURN_FLAG                   ; Clear turn flag (0 = no turn, straight)
    stz GAS_FLAG                    ; Clear gas flag (0 = coast, no acceleration)
    
    ; **************************************************************************************************************
    ; SECTION 3: Reset Best Lap Records
    ; Purpose: Clear lap time records for new racing session
    ; **************************************************************************************************************
    
    stz top_speed_min               ; Clear best lap time minutes (BCD)
    stz top_speed_sec               ; Clear best lap time seconds (BCD)
    stz top_speed_ten               ; Clear best lap time hundredths (BCD)
    
    ; **************************************************************************************************************
    ; SECTION 4: Reset Animation and Audio State
    ; Purpose: Reinitialize visual and sound effects for new race
    ; **************************************************************************************************************
    
    stz crowd_counter               ; Reset crowd animation frame counter (0-3 cycle)
    lda #$0F                        ; Load maximum volume level
    sta crowd_volume                ; Reset crowd sound volume to full (15)
    sta PSG_L                       ; Write to PSG Left control register
    lda #$df                        ; Load muted volume level
    sta PSG_R                       ; Write to PSG Right control register
    
    stz SID_L_VOL                   ; Reset SID sound volume to 0 (muted)
    jsr stop_music                  ; Stop any currently playing music tracks
    jsr init_music                  ; reinitialize music system
    lda #$20
    sta SID_R1_GATE                 ; Disable engine sound effect
    sta SID_R2_GATE                 ; Disable skid sound effect
    lda #$0f                        ; Load maximum volume level
    sta SID_R_VOL                   ; Reset SID right volume to maximum
    
    ; **************************************************************************************************************
    ; SECTION 5: Reset Joystick Input State
    ; Purpose: Clear all user input buffers and debounce states
    ; **************************************************************************************************************
    
    stz joyX                        ; Clear joystick X axis ($00 = centered)
    stz joyY                        ; Clear joystick Y axis ($00 = centered)
    stz joyB                        ; Clear button state ($00 = not pressed)
    stz joyBhold                    ; Clear button hold/debounce state

    ; **************************************************************************************************************
    ; SECTION 6: Reset Driver Assignment
    ; Purpose: Mark all AI driver slots as unassigned for new selection
    ; **************************************************************************************************************
    
    lda #$ff                        ; Load unassigned marker ($FF = no driver)
    sta aicar_racer                 ; Clear AI car 0 driver assignment
    sta aicar_racer+1               ; Clear AI car 1 driver assignment
    sta aicar_racer+2               ; Clear AI car 2 driver assignment

    ; **************************************************************************************************************
    ; SECTION 7: Reset Per-Car Race Data (Loop for 4 Cars)
    ; Purpose: Clear timing, position, and state data for all cars (3 AI + player)
    ; Algorithm: Loop through car index 0-3, reset all per-car arrays
    ; **************************************************************************************************************
    
    ldx #$00                        ; Initialize car index to 0
reset_parameters_loop:
    lda #$00                        ; Load clear value (0)
    
    ; --- Clear Lap and Timer Data ---
    sta lap_count,X                 ; Clear lap counter for this car
    sta minutes,X                   ; Clear race minutes (BCD) for this car
    sta seconds,X                   ; Clear race seconds (BCD) for this car
    sta tenths,X                    ; Clear race hundredths (BCD) for this car
    
    ; --- Clear Final Time Records ---
    sta fminutes,X                  ; Clear final time minutes for this car
    sta fseconds,X                  ; Clear final time seconds for this car
    sta ftenths,X                   ; Clear final time hundredths for this car
    
    ; --- Clear Speed Data (24-bit) ---
    sta aicar_speed_F,X             ; Clear speed fraction byte
    sta aicar_speed_L,X             ; Clear speed low byte
    sta aicar_speed_H,X             ; Clear speed high byte
    
    ; --- Clear Navigation and Orientation ---
    sta aicar_Rotation,X            ; Clear rotation angle (0 = facing north)
    sta aicar_target,X              ; Clear waypoint target index
    
    ; --- Clear Collision State ---
    sta aicar_CollideFlag,X         ; Clear collision active flag
    sta aicar_CollideRot,X          ; Clear collision rotation adjustment
    
    ; --- Clear AI Input Simulation ---
    sta aicar_JoyX,X                ; Clear AI joystick X simulation
    sta aicar_JoyY,X                ; Clear AI joystick Y simulation
    sta aicar_JoyB,X                ; Clear AI button simulation
    
    ; --- Reset Finishing and Starting Positions ---
    lda #$ff                        ; Load unfinished marker ($FF = not finished)
    sta fplace,X                    ; Mark car as not yet finished
    sta car_pos,X                   ; Mark starting position as unassigned
    
    ; --- Advance to Next Car ---
    inx                             ; Increment car index (0→1→2→3)
    cpx #$04                        ; Have we reset all 4 cars?
    bne reset_parameters_loop       ; If not, continue loop

    ; **************************************************************************************************************
    ; SECTION 8: Initialize Player Sprite Graphics
    ; Purpose: Set player car sprite to default blue car graphics
    ; **************************************************************************************************************
    
    lda #<blue_car1                 ; Load blue car graphics address low byte
    sta car_sprite_base+SP_AD_L     ; Write to sprite address register (bits 0-7)
    lda #>blue_car1                 ; Load blue car graphics address mid byte
    sta car_sprite_base+SP_AD_M     ; Write to sprite address register (bits 8-15)
    lda #`blue_car1                 ; Load blue car graphics address high byte (bank)
    sta car_sprite_base+SP_AD_H     ; Write to sprite address register (bits 16-23)
    
    ; **************************************************************************************************************
    ; SECTION 9: Initialize AI Car Positions
    ; Purpose: Call AI setup routine to position all opponent cars at starting grid
    ; **************************************************************************************************************
    
    jsr ai_setup                    ; Initialize AI car starting positions and sprites

still_moving2
    rts                             ; Return to caller (continue title screen animation)




; **************************************************************************************************************
; ai_setup - Initialize AI opponent car positions for new race
; Purpose: Copy starting grid positions from template arrays to active position arrays
;          Prepares all 3 AI-controlled cars (slots 21-23) for race start
; Algorithm:
;   1. Loop through all 3 AI cars (index 0-2)
;   2. For each car: Copy all 6 position bytes (X_F/L/H and Y_F/L/H)
;   3. Copy from aicar_start_* arrays to aicar_pos* arrays
;   4. Exit when all 3 cars initialized
; Inputs:
;   aicar_start_X_F/L/H[0-2] = Starting X positions for 3 AI cars (24-bit)
;   aicar_start_Y_F/L/H[0-2] = Starting Y positions for 3 AI cars (24-bit)
; Outputs:
;   aicar_posX_F/L/H[0-2] = Current X positions set to starting values
;   aicar_posY_F/L/H[0-2] = Current Y positions set to starting values
;   aicar_current = Set to 0, then incremented to 3
; Position Format:
;   24-bit fixed-point: *_F = fraction (1/256 pixel), *_L = low byte, *_H = high byte
; Clobbers: A, X, aicar_current
; Notes: Called during race reset to position AI cars at starting grid
; **************************************************************************************************************
ai_setup:
    ; --- Initialize AI car loop counter ---
    stz aicar_current               ; Set current car index to 0 (first AI car)
    
place_ai_cars:
    ; --- Check if all AI cars have been initialized ---
    lda aicar_current               ; Load current AI car index (0-2)
    cmp #$03                        ; Have we processed all 3 AI cars?
    beq done_ai_cars                ; If yes, exit initialization loop
    
    ; --- Transfer car index to X for array indexing ---
    tax                             ; X = car index (0, 1, or 2)
    
    ; --- Copy X coordinate (24-bit: Fraction, Low, High) ---
    lda aicar_start_X_F,x           ; Load starting X position fraction byte
    sta aicar_posX_F,x              ; Copy to active X position fraction
    lda aicar_start_X_L,x           ; Load starting X position low byte
    sta aicar_posX_L,x              ; Copy to active X position low
    lda aicar_start_X_H,x           ; Load starting X position high byte
    sta aicar_posX_H,x              ; Copy to active X position high
    
    ; --- Copy Y coordinate (24-bit: Fraction, Low, High) ---
    lda aicar_start_Y_F,x           ; Load starting Y position fraction byte
    sta aicar_posY_F,x              ; Copy to active Y position fraction
    lda aicar_start_Y_L,x           ; Load starting Y position low byte
    sta aicar_posY_L,x              ; Copy to active Y position low
    lda aicar_start_Y_H,x           ; Load starting Y position high byte
    sta aicar_posY_H,x              ; Copy to active Y position high
    
    ; --- Advance to next AI car ---
    inc aicar_current               ; Increment car index (0→1, 1→2, 2→3)
    bra place_ai_cars               ; Loop back to process next car
    
done_ai_cars:
    ; --- All AI cars positioned at starting grid ---
    rts                             ; Return to caller





; **************************************************************************************************************
; SetTimer - Update kernel timer with current frame value
; Purpose: Increment frame counter and schedule kernel timer event for next frame
;          Used to synchronize game loop with system timer for consistent timing
; Algorithm:
;   1. Increment frame counter at $D0
;   2. Store frame count in kernel.args.timer.absolute
;   3. Store same value in kernel.args.timer.cookie (for timer identification)
;   4. Set timer units to FRAMES mode
;   5. Call kernel Clock.SetTimer to schedule next timer event
; Inputs:
;   $D0 = Current frame counter value
; Outputs:
;   kernel.args.timer.absolute = Updated frame count
;   kernel.args.timer.cookie = Frame count (used as timer identifier)
;   kernel.args.timer.units = FRAMES mode
;   Kernel timer scheduled for next frame interrupt
; Clobbers: A, $D0
; Notes: Frame counter wraps at 256, creating a repeating timer cycle
; **************************************************************************************************************
SetTimer:    
    inc $d0
    lda $d0
    sta kernel.args.timer.absolute           ; store in timer.absolute parameter
    sta kernel.args.timer.cookie             ; saved as a cookie to the kernel (same as frame number)
    lda #kernel.args.timer.FRAMES            ; set the Timer to Frames
    sta kernel.args.timer.units              ; store in units parameter
    jsr kernel.Clock.SetTimer                ; jsr to Kernel routine to set timer
    rts


; **************************************************************************************************************
; clrScreen - Clear text and color matrices on display
; Purpose: Fill entire screen with blank spaces (character $20) and white color ($F0)
;          Used to prepare screen for new content or reset display state
; Algorithm:
;   1. Setup pointer to start of screen memory at $C000
;   2. Iterate through 19 pages (256 bytes each) = 4864 total characters
;   3. For each character position:
;      - Switch to character matrix (MMU_IO_CTRL = $02)
;      - Write blank space ($20)
;      - Switch to color matrix (MMU_IO_CTRL = $03)
;      - Write white color ($F0)
;   4. Restore MMU_IO_CTRL to normal operation
; Memory Layout:
;   Screen starts at $C000 and extends for 19 pages (4864 bytes)
;   Character matrix accessed via MMU_IO_CTRL = $02
;   Color matrix accessed via MMU_IO_CTRL = $03
; Inputs: None
; Outputs:
;   Screen character matrix cleared with spaces ($20)
;   Color matrix set to white ($F0) for all positions
; Clobbers: ptr_dst, A, X, Y, MMU_IO_CTRL
; Notes: Assumes MMU_IO_CTRL = $00 on entry and restores it on exit
; **************************************************************************************************************
clrScreen:
    ; --- Initialize screen pointer to $C000 (start of screen memory) ---
    lda #$00                                 ; Set pointer low byte to $00
    sta ptr_dst                              ; Store in destination pointer low
    lda #$c0                                 ; Set pointer high byte to $C0 ($C000)
    sta ptr_dst+1                            ; Store in destination pointer high
    
    ; --- Setup loop counters ---
    ldy #$00                                 ; Y counts 0-255 within each page
    ldx #$13                                 ; X counts 19 pages down to 0 (19 × 256 = 4864 chars)
    
csLoop:
    ; --- Write blank character to current position ---
    lda #$02                                 ; Select character matrix
    sta MMU_IO_CTRL                          ; Switch memory mapping to character data
    lda #$20                                 ; Load blank space character ($20 = space)
    sta (ptr_dst),y                          ; Write space to current screen position
    
    ; --- Write white color to current position ---
    lda #$03                                 ; Select color matrix
    sta MMU_IO_CTRL                          ; Switch memory mapping to color data
    lda #$f0                                 ; Load white color ($F0 = white on black)
    sta (ptr_dst),y                          ; Write color to current screen position
    
    ; --- Advance to next character position ---
    iny                                      ; Increment Y (move to next char in page)
    bne csLoop                               ; If Y ≠ 0, continue within page
    
    ; --- Move to next page ---
    inc ptr_dst+1                            ; Increment page (move to next 256-byte block)
    dex                                      ; Decrement page counter
    bne csLoop                               ; If more pages remain, continue loop

    ; --- Restore memory mapping and return ---
    stz MMU_IO_CTRL                          ; Restore MMU_IO_CTRL to normal ($00)
    rts                                      ; Return to caller

; **************************************************************************************************************
; Working Memory - Game state variables and race data storage
; **************************************************************************************************************

; --- Screen and UI State Flags ---
thanks_screen: .byte $00                    ; Flag: Thanks/credits screen displayed ($00 = no, $01 = yes)
open_message_displayed: .byte $00           ; Flag: Opening message displayed ($00 = no, $01 = yes)
choose_driver_displayed: .byte $00          ; Flag: Driver selection screen shown ($00 = no, $01 = yes)
results_displayed: .byte $00                ; Flag: Results screen displayed ($00 = no, $01 = yes)

; --- Race State Variables ---
race_on:         .byte $00                  ; Race state: $00 = title, $01 = driver select, $02+ = racing
race_lap:        .byte $00                  ; Current lap number (0-indexed)
last_lap:        .byte $03                  ; Total laps to complete (default 3, adjustable 3-9)
start_counter:   .byte $05                  ; Countdown timer for race start (5, 4, 3, 2, 1, GO)

; --- Title Screen Animation State ---
title_y_pos_L:   .byte $00                  ; Y position for animated title screen elements
title_y_pos_H:   .byte $00                  ; High byte for Y position

t_d_counter:     .byte $00                  ; Title/demo counter for timing animations
tree_y_pos:      .byte $00                  ; Y position for animated trees on title screen
countdown_timer: .byte $00                  ; Frame counter for countdown sequence
start_light_set: .byte $00                  ; Starting lights state (0-5 for light sequence)
crowd_counter:   .byte $00                  ; Animation frame counter for crowd sprites (0-3)
crowd_volume:    .byte $0F                  ; Crowd sound volume (0-15, louder when player leads)

; --- BCD Time Tracking System ---
; Time format: Binary Coded Decimal (BCD) for easy display
; Player time is indexed as 3, AI car times are indexed 0-2
current_lap:    .byte $00                   ; Current lap being timed (0-3: AI cars 0-2 or player)
first_place_flag: .byte $00                 ; Flag: $01 if player is in first place, $00 otherwise

lap_count:       .byte $00, $00, $00, $00   ; Lap counters for AI cars 0-2 and player (index 3)
top_speed_min:   .byte $00                  ; Best lap time: minutes (BCD format)
top_speed_sec:   .byte $00                  ; Best lap time: seconds (BCD format)
top_speed_ten:   .byte $00                  ; Best lap time: hundredths (BCD format)

; --- Individual Race Timers (BCD format: $59 = 59 decimal, not 89) ---
minutes:         .byte $00, $00, $00, $00   ; Minutes for AI cars 0-2 and player (index 3)
master_minutes:  .byte $00                  ; Master race timer: minutes
seconds:         .byte $00, $00, $00, $00   ; Seconds for AI cars 0-2 and player (index 3)
master_seconds:  .byte $00                  ; Master race timer: seconds 
tenths:          .byte $00, $00, $00, $00   ; Hundredths for AI cars 0-2 and player (index 3)
master_tenths:   .byte $00                  ; Master race timer: hundredths (0-99 BCD)

; --- Finishing Times (First Place Records) ---
fplace_index:    .byte $00                  ; Index of car that finished first (0-3)
fplace:          .byte $ff, $ff, $ff, $ff   ; Finishing order ($FF = not finished, 0-3 = finish position)
fminutes:        .byte $00, $00, $00, $00   ; Final race time: minutes (BCD) for each car
fseconds:        .byte $00, $00, $00, $00   ; Final race time: seconds (BCD) for each car
ftenths:         .byte $00, $00, $00, $00   ; Final race time: hundredths (BCD) for each car

; --- race results face position table ---
fpos_L:          .byte $80,$a0,$c0,$e0
fpos_H:          .byte $00,$00,$00,$00

; --- race results text position table ---
ftext_pos_L:     .byte $86,$c6,$06,$46
ftext_pos_H:     .byte $c4,$c5,$c7,$c8

; --- Timer Display and UI Templates ---
race_timer:      .byte $00                  ; Frame counter for timer updates (increments every frame)
lap_template:    .text "Lap 0: "            ; Display template for lap number
lt_template:     .text "00:00.00"           ; Display template for lap time (MM:SS.TT)
lead_time_template: .text " +00.00"         ; Display template for time difference from leader
timer_template:  .byte $00,$00, $0a, $00, $00, $0b, $00,$00  ; Timer digits: MM:SS.TT ($0A = colon, $0B = period)

; --- Text Display Color Management ---
text_color_table:   .byte $c0,$b0,$d0,$20   ; Color codes for different text elements
textColor: .byte $00                        ; Current text color for display routines

; --- Debug and Utility Variables ---
debugTMP: .byte $00                         ; Temporary debug variable for testing
HexTable: .text "0123456789ABCDEF"          ; Hex digit lookup table for ASCII conversion

tmpx: .byte $00, $00                        ; Temporary X coordinate storage (16-bit)
tmpy: .byte $00, $00                        ; Temporary Y coordinate storage (16-bit)

; --- Input State Variables ---
carDelay: .byte $00                         ; Delay counter for car control input debouncing
totalColors: .byte $00                      ; Total color count (unused?)
JoyEvent: .byte $00                         ; Joystick event code for input processing
joyX:    .byte $00                          ; Joystick X-axis: $FF = left, $00 = center, $01 = right
joyY:    .byte $00                          ; Joystick Y-axis: $FF = up, $00 = center, $01 = down
joyB:    .byte $00                          ; Joystick button state: $00 = not pressed, $01+ = pressed
joyBhold: .byte $00                         ; Joystick button debounce state (prevents rapid repeats)
GO:      .byte $00                          ; Race start button state (GO signal)

; --- Tile System Working Variables ---
tilePOSX_L: .byte $00                       ; Tile position X coordinate low byte
tilePOSX_H: .byte $00                       ; Tile position X coordinate high byte
tilePOSY_L: .byte $00                       ; Tile position Y coordinate low byte
tilePOSY_H: .byte $00                       ; Tile position Y coordinate high byte

tilemem_L: .byte $00                        ; Tilemap memory pointer low byte
tilemem_H: .byte $00                        ; Tilemap memory pointer high byte
TilePointX_L: .byte $00                     ; Pixel X offset within current tile (0-15) low byte
TilePointX_H: .byte $00                     ; Pixel X offset within current tile high byte

TilePointY_L: .byte $00                     ; Pixel Y offset within current tile (0-15) low byte
TilePointY_H: .byte $00                     ; Pixel Y offset within current tile high byte

; **************************************************************************************************************
; Position Data - 24-bit Fixed-Point Coordinate System
; Layout: Each position value uses three bytes for high precision
;   *_H  = High byte (most significant integer byte)
;   *_L  = Low byte (least significant integer byte)
;   *_F  = Fraction byte (sub-pixel precision, 1/256th of a pixel)
; Movement calculations use fractional arithmetic with carry propagation through ADC/SBC
; Example: Player starts at (194, 340) = (0x00C2, 0x0154) in world coordinates
; **************************************************************************************************************

speedo_X_L: .byte $00                       ; Speedometer display X position low byte
speedo_X_H: .byte $00                       ; Speedometer display X position high byte

; --- Starting Position Management ---
car_pos:           .byte $00, $00, $00, $00 ; Starting grid positions for 4 cars (0-3, assigned randomly)
start_positionsX_F: .byte $00, $00, $00, $00 ; Starting X positions: fraction bytes
start_positionsX_L: .byte $a2, $b2, $02, $e2 ; Starting X positions: low bytes
start_positionsX_H: .byte $00, $00, $01, $00 ; Starting X positions: high bytes
start_positionsY_F: .byte $00, $00, $00, $00 ; Starting Y positions: fraction bytes
start_positionsY_L: .byte $74, $a3, $a3, $6a ; Starting Y positions: low bytes
start_positionsY_H: .byte $01, $01, $01, $01 ; Starting Y positions: high bytes

; **************************************************************************************************************
; AI Car Data Tables (3 AI opponents)
; Each array has 3 entries (one per AI car), player data stored separately
; **************************************************************************************************************

aicar_current:  .byte $00                   ; Current AI car being processed (0-2)

; --- AI Car Sprite Graphics Pointers (24-bit addresses) ---
aicar_sprite_L: .byte <green_car1,<red_car1,<yellow_car1   ; Sprite base address low bytes
aicar_sprite_M: .byte >green_car1,>red_car1,>yellow_car1   ; Sprite base address mid bytes
aicar_sprite_H: .byte `green_car1,`red_car1,`yellow_car1   ; Sprite base address high bytes

; --- AI Car World Positions (24-bit fixed-point) ---
aicar_posX_F:   .byte $00, $00, $00         ; AI car X positions: fraction bytes
PlayerPOS_X_F: .byte $00                    ; Player X position: fraction byte
aicar_posX_L:   .byte $a2, $b2, $02         ; AI car X positions: low bytes
PlayerPOS_X_L: .byte $e2                    ; Player X position: low byte ($E2 = 226 decimal)
aicar_posX_H:   .byte $00, $00, $01         ; AI car X positions: high bytes
PlayerPOS_X_H: .byte $00                    ; Player X position: high byte

aicar_posY_F:   .byte $00, $00, $00         ; AI car Y positions: fraction bytes
PlayerPOS_Y_F: .byte $00                    ; Player Y position: fraction byte
aicar_posY_L:   .byte $74, $a3, $a3         ; AI car Y positions: low bytes
PlayerPOS_Y_L: .byte $6a                    ; Player Y position: low byte ($6A = 106 decimal)
aicar_posY_H:   .byte $01, $01, $01         ; AI car Y positions: high bytes
PlayerPOS_Y_H: .byte $01                    ; Player Y position: high byte (combined: 0x016A = 362 decimal)

; --- Race Start Positions (Initial Grid Positions) ---
aicar_start_X_F:   .byte $00, $00, $00, $00 ; Start position X: fraction bytes (all 4 cars)
aicar_start_X_L:   .byte $d2, $d2, $e2, $e2 ; Start position X: low bytes
aicar_start_X_H:   .byte $00, $00, $00, $00 ; Start position X: high bytes
aicar_start_Y_F:   .byte $00, $00, $00, $00 ; Start position Y: fraction bytes (all 4 cars)
aicar_start_Y_L:   .byte $6f, $83, $7e, $6a ; Start position Y: low bytes
aicar_start_Y_H:   .byte $01, $01, $01, $01 ; Start position Y: high bytes

; --- Speed Data (24-bit fixed-point velocity) ---
aicar_speed_F:  .byte $00, $00, $00         ; AI car speed: fraction bytes
playerSpeed_F: .byte $00                    ; Player speed: fraction byte
aicar_speed_L:  .byte $00, $00, $00         ; AI car speed: low bytes
playerSpeed_L: .byte $00                    ; Player speed: low byte
aicar_speed_H:  .byte $00, $00, $00         ; AI car speed: high bytes
playerSpeed_H: .byte $00                    ; Player speed: high byte

; --- Target Speed Settings (Top Speed Limits) ---
aicar_TgtSpd_F: .byte $fd, $fd, $fd, $00    ; AI target speed: fraction bytes
playerTopSpeed_F: .byte $40                 ; Player top speed: fraction byte (0x000340 = 832 decimal)
aicar_TgtSpd_L: .byte $02, $02, $02, $00    ; AI target speed: low bytes
playerTopSpeed_L: .byte $03                 ; Player top speed: low byte
aicar_TgtSpd_H: .byte $00, $00, $00, $00    ; AI target speed: high bytes

; --- Waypoint Navigation Targets ---
aicar_target:   .byte $00, $00, $00         ; AI car current waypoint index (0-21)
player_target:  .byte $00                   ; Player waypoint target (used for lap counting and crowd reactions)

aicar_TopSpd_F: .byte $40, $40, $40         ; AI maximum speed: fraction bytes
aicar_TopSpd_L: .byte $03, $03, $03         ; AI maximum speed: low bytes

; --- Player Control State Flags ---
CUR_DIR:        .byte $00                   ; Current direction indicator (0-31 for 32 rotation steps)
TURN_FLAG:      .byte $00                   ; Turn state: $00 = straight, $01 = left, $02 = right
GAS_FLAG:       .byte $00                   ; Acceleration state: $00 = coast, $01 = brake, $FF = gas

; --- AI Car Input Simulation (Mimics Joystick Input) ---
aicar_JoyX:     .byte $00, $00, $00         ; AI joystick X-axis simulation (left/right)
aicar_JoyY:     .byte $00, $00, $00         ; AI joystick Y-axis simulation (up/down for gas/brake)
aicar_JoyB:     .byte $00, $00, $00         ; AI button press simulation (unused)

; --- Rotation State (Sprite Facing Direction) ---
aicar_Rotation: .byte $00, $00, $00         ; AI car rotation index (0-31, 11.25° steps)
PlayerRotation: .byte $00                   ; Player rotation index (0-31, 11.25° steps)

; --- Collision State Management ---
aicar_CollideFlag: .byte $00, $00, $00      ; AI collision active: $00 = none, $01 = colliding
Player_collideFlag: .byte $00               ; Player collision active: $00 = none, $01 = colliding
aicar_CollideRot: .byte $00, $00, $00       ; AI rotation adjustment during collision
Player_CollideRot: .byte $00                ; Player rotation adjustment during collision

; **************************************************************************************************************
; Helicopter Animation Data (Overhead Camera Tracking Sprite)
; 24-bit fixed-point position and velocity for smooth cinematic movement
; **************************************************************************************************************

; --- Helicopter Position (World Coordinates) ---
helicopter_POSX_F: .byte $00                ; Helicopter X position: fraction byte
helicopter_POSX_L: .byte $b2                ; Helicopter X position: low byte
helicopter_POSX_H: .byte $01                ; Helicopter X position: high byte (starts at 0x01B2 = 434)
helicopter_POSY_F: .byte $00                ; Helicopter Y position: fraction byte
helicopter_POSY_L: .byte $54                ; Helicopter Y position: low byte
helicopter_POSY_H: .byte $01                ; Helicopter Y position: high byte (starts at 0x0154 = 340)

; --- Helicopter Orientation and Animation ---
helicopter_ROT:   .byte $18                 ; Helicopter rotation angle (0-31, initialized to $18 = 24)

; --- Helicopter Velocity (Movement Speed) ---
helicopter_X_vel_F: .byte $00               ; X velocity: fraction byte
helicopter_X_vel_L: .byte $00               ; X velocity: low byte
helicopter_X_vel_H: .byte $00               ; X velocity: high byte
helicopter_Y_vel_F: .byte $00               ; Y velocity: fraction byte
helicopter_Y_vel_L: .byte $00               ; Y velocity: low byte
helicopter_Y_vel_H: .byte $00               ; Y velocity: high byte

; --- Helicopter Target Velocity (For Smooth Acceleration) ---
helicopter_X_V_Tgt: .byte $00               ; Target X velocity (goal for smooth transitions)
helicopter_Y_V_Tgt: .byte $00               ; Target Y velocity (goal for smooth transitions)

; --- Rotor Blade Animation ---
blade_angle:      .byte $00                 ; Rotor blade rotation angle (cycles 0-255 for spinning effect)
shadow_disp:     .byte $00                  ; Shadow displacement offset (varies with helicopter height)
helicopter_turn_rate: .byte $00             ; Turn rate for banking/turning animations

; --- Helicopter sound effect variables ---
rotorIdx: .byte $00                          ; Rotor sound effect index (cycles through attenuation levels)
rotorDist_L: .byte $00                       ; Distance to player for rotor sound attenuation
rotorDist_H: .byte $00                       ; High byte of distance to player for rotor sound attenuation

; --- Helicopter attenuation table for sound effect ---
bladeEnv: .byte $00,$02,$05,$09,$0e,$09,$05,$02


; **************************************************************************************************************
; Geometry and Math Working Variables
; Used for collision detection, pathfinding, and angle calculations
; **************************************************************************************************************

; --- General Purpose Math Temporaries ---
TMP:        .byte $00                       ; Temporary variable for misc calculations
DX_L:       .byte $00                       ; Delta X low byte (difference in X coordinates)
DX_H:       .byte $00                       ; Delta X high byte
DY_L:       .byte $00                       ; Delta Y low byte (difference in Y coordinates)
DY_H:       .byte $00                       ; Delta Y high byte
SUM_R:      .byte $00                       ; Sum result for addition operations
t1:         .byte $00                       ; Temporary 1 (for swapping, intermediate values)
t2:         .byte $00                       ; Temporary 2 (for swapping, intermediate values)

; --- Distance and Ratio Calculations ---
RATIO_L:    .byte $00                       ; Ratio calculation result low byte
RATIO_H:    .byte $00                       ; Ratio calculation result high byte

DIST2_L:    .byte $00                       ; Distance squared low byte (for magnitude comparisons)
DIST2_H:    .byte $00                       ; Distance squared high byte
RAD2_L:     .byte $00                       ; Radius squared low byte (collision detection threshold)
RAD2_H:     .byte $00                       ; Radius squared high byte
DIR:        .byte $00                       ; Direction result (0-31 angle index)
Quad:       .byte $00                       ; Quadrant indicator (0-3 for four compass quadrants)
base:       .byte $00                       ; Base value for table lookups

; --- Vector Cross Product Variables (Collision Detection) ---
BX_L:       .byte $00                       ; Vector B X component low byte
BX_H:       .byte $00                       ; Vector B X component high byte
BY_L:       .byte $00                       ; Vector B Y component low byte
BY_H:       .byte $00                       ; Vector B Y component high byte
BXS:       .byte $00                        ; Vector B X sign ($00 = positive, $FF = negative)
BYS:       .byte $00                        ; Vector B Y sign
AXS:       .byte $00                        ; Vector A X sign
AYS:       .byte $00                        ; Vector A Y sign
CP_AXBY_S: .byte $00                        ; Cross product sign (determines turn direction)

; --- Trigonometric Lookup Tables ---
; Tangent thresholds ×256 (16-bit little-endian) for angle calculation
; Used to convert DY/DX ratios to rotation angles
TAN_TAB_L:    .byte $33, $6A, $AB, $00, $7F, $6A, $06  ; Tangent table low bytes
TAN_TAB_H:    .byte $00, $00, $00, $01, $01, $02, $05  ; Tangent table high bytes

; **************************************************************************************************************
; Road Surface Detection System
; Tile-based road checking for off-road detection and AI pathfinding
; **************************************************************************************************************

currentTile: .byte $00                      ; Current tile ID at car position (0-255)

; --- Road Check Memory Pointer (24-bit Tileset Address) ---
roadCheck_L: .byte $00                      ; Road check pointer low byte
roadCheck_M: .byte $00                      ; Road check pointer mid byte
roadCheck_H: .byte $00                      ; Road check pointer high byte

; --- Road Check Buffers (256 bytes = 16×16 pixel tile data) ---
roadCheckMem: .fill $100, $00               ; Player car road check buffer (256 bytes)
;ai1RoadCKMem: .fill $100, $00               ; AI car 1 road check buffer (256 bytes)
;ai2RoadCKMem: .fill $100, $00               ; AI car 2 road check buffer (256 bytes)
;ai3RoadCKMem: .fill $100, $00               ; AI car 3 road check buffer (256 bytes)

; --- Starting Light Position Tables (Speedometer Display) ---
lamp_table_X: .byte 153, 166, 179, 192, 205, 153, 166, 179, 192, 205  ; Lamp sprite X positions (10 lamps)
lamp_table_Y: .byte 113, 113, 113, 113, 113, 121, 121, 121, 121, 121  ; Lamp sprite Y positions (2 rows)

; **************************************************************************************************************
; Vector Movement Tables - Direction to Velocity Conversion
; Purpose: Convert rotation angle (0-31) to X/Y velocity components for movement
; Format: Signed 8.8 fixed-point with separate sign byte
;   VectorX/Y_F = Fractional component (0-255)
;   VectorX/Y_L = Integer component (0-1 for magnitude up to 1.999)
;   VectorX/Y_S = Sign byte ($00 = positive, $FF = negative)
; Algorithm: 
;   X component = cos(angle)
;   Y component = sin(angle)
;   Angle range: 0-31 (11.25° per step, full 360° rotation)
; Usage: Index by rotation (0-31), multiply speed by vector to get X/Y movement
; **************************************************************************************************************
VectorX_F: .byte $00,$31,$61,$8e,$b5,$d4,$ec,$fb,$00,$fb,$ec,$d4,$b5,$8e,$61,$31,$00,$31,$61,$8e,$b5,$d4,$ec,$fb,$00,$fb,$ec,$d4,$b5,$8e,$61,$31
VectorX_L: .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00
VectorX_S: .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
VectorY_F: .byte $00,$fb,$ec,$d4,$b5,$8e,$61,$31,$00,$31,$61,$8e,$b5,$d4,$ec,$fb,$00,$fb,$ec,$d4,$b5,$8e,$61,$31,$00,$31,$61,$8e,$b5,$d4,$ec,$fb
VectorY_L: .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
VectorY_S: .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff

; **************************************************************************************************************
; Outrigger Tables - AI Pathfinding Sensor Points
; Purpose: Define virtual sensor points around car for waypoint distance calculations
; Algorithm:
;   - Left and right outriggers extend from car center at current rotation
;   - AI compares distance from left vs right sensor to waypoint
;   - Shorter distance indicates correct turn direction
; Format: 16-bit signed coordinates relative to car center
;   OR_*XL/YL = Low byte of X/Y offset
;   OR_*XH/YH = High byte (sign extension)
; Sensors:
;   Right = Right side sensor for right turn detection
;   Left = Left side sensor for left turn detection  
;   Front = Forward sensor for straight-ahead navigation
; **************************************************************************************************************
OR_RightXL: .byte $15,$14,$13,$12,$10,$08,$05,$02,$00,$fd,$fa,$f7,$f5,$f3,$f2,$f1,$f1,$f1,$f2,$f3,$f5,$f7,$fa,$fd,$ff,$02,$05,$08,$0a,$0c,$0d,$0e
OR_RightXH: .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$00
OR_RightYL: .byte $00,$02,$05,$08,$0a,$0c,$0d,$0e,$0f,$0e,$0d,$0c,$0a,$08,$05,$02,$00,$fd,$fa,$f7,$f5,$f3,$f2,$f1,$f1,$f1,$f2,$f3,$f5,$f7,$fa,$fd
OR_RightYH: .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff

OR_LeftXL:  .byte $f1,$f1,$f2,$f3,$f5,$f7,$fa,$fd,$ff,$02,$05,$08,$0a,$0c,$0d,$0e,$0f,$0e,$0d,$0c,$0a,$08,$05,$02,$00,$fd,$fa,$f7,$f5,$f3,$f2,$f1
OR_LeftXH:  .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff
OR_LeftYL:  .byte $00,$fd,$fa,$f7,$f5,$f3,$f2,$f1,$f1,$f1,$f2,$f3,$f5,$f7,$fa,$fd,$ff,$02,$05,$08,$0a,$0c,$0d,$0e,$0f,$0e,$0d,$0c,$0a,$08,$05,$02
OR_LeftYH:  .byte $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
OR_FrontXL: .byte $02,$05,$08,$0a,$0c,$0d,$0e,$0f,$0e,$0d,$0c,$0a,$08,$05,$02,$00,$fd,$fa,$f7,$f5,$f3,$f2,$f1,$f1,$f1,$f2,$f3,$f5,$f7,$fa,$fd,$ff
OR_FrontXH: .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
OR_FrontYL: .byte $f1,$f2,$f3,$f5,$f7,$fa,$fd,$ff,$02,$05,$08,$0a,$0c,$0d,$0e,$0f,$0e,$0d,$0c,$0a,$08,$05,$02,$00,$fd,$fa,$f7,$f5,$f3,$f2,$f1,$f1
OR_FrontYH: .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff

; **************************************************************************************************************
; AI Waypoint Navigation System
; Purpose: Define racing line waypoints for AI pathfinding around track
; Algorithm:
;   - AI cars navigate from waypoint to waypoint in sequence
;   - Each waypoint has X/Y coordinate, preferred direction, and target speed
;   - When near waypoint, AI advances to next waypoint index (wraps at end)
; **************************************************************************************************************

aiLineIndex: .byte 21                       ; Total number of waypoints (0-21 = 22 waypoints)

; --- Commented Out: Old Waypoint Data (Preserved for Reference) ---
;aiLineX_L:  .byte $d0,$d4,$fd,$30,$72,$87,$c7,$f9,$0a,$38,$76,$7d,$6f,$70,$38,$aa,$7f,$a0,$e1,$06,$ed,$55,$1c,$01,$e3,$af
;aiLineX_H:  .byte $00,$00,$00,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$02,$01,$01,$01,$01,$00,$00
;aiLineY_L:  .byte $e1,$bd,$a2,$9d,$c1,$f1,$14,$fb,$ca,$ae,$c4,$e8,$41,$8f,$de,$df,$af,$90,$a0,$7b,$56,$50,$80,$d2,$de,$ab
;aiLineY_H:  .byte $00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01

; --- Active Waypoint Coordinates (16-bit World Position) ---
aiLineX_L:       .byte $d8,$10,$72,$a9,$e7,$2a,$61,$99,$91,$88,$52,$cc,$9b,$c5,$12,$29,$10,$6d,$38,$27,$d8,$d9  ; X low bytes
aiLineX_H:       .byte $00,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$01,$01,$01,$02,$02,$02,$01,$01,$01,$00,$00  ; X high bytes
                       ; Waypoint indices:
                       ; 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  A,  B,  C,  D,  E,  F, 10, 11, 12, 13, 14, 15
aiLineY_L:  .byte $f0,$c6,$c5,$03,$3a,$fb,$c4,$f9,$4d,$bd,$f6,$02,$cb,$b4,$b4,$96,$74,$74,$bf,$04,$bf,$62  ; Y low bytes
aiLineY_H:  .byte $00,$00,$00,$01,$01,$00,$00,$00,$01,$01,$01,$02,$01,$01,$01,$01,$01,$01,$01,$02,$01,$01  ; Y high bytes
                    ; Waypoint indices:
                    ; 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  A,  B,  C,  D,  E,  F, 10, 11, 12, 13, 14, 15

; --- Waypoint Direction Hints (Preferred Heading at Each Waypoint) ---
; Direction codes: 1 = up, 2 = right, 3 = down, 4 = left
waypoint_Dir: .byte $01,$02,$02,$03,$02,$01,$02,$03,$03,$03,$04,$04,$01,$02,$02,$01,$04,$04,$03,$04,$01,$01

; --- Waypoint Target Speeds (Recommended Speed for Each Section) ---
; Speed values: $FF = full speed, $C0-$D0 = moderate, $80 = slow (corners)
waypoint_Spd: .byte $ff,$c0,$ff,$c0,$c0,$c0,$c0,$c0,$ff,$ff,$d0,$ff,$80,$80,$c0,$80,$80,$ff,$c0,$80,$80,$ff

; **************************************************************************************************************
; Crowd Animation Data
; Purpose: Define tilemap positions for animated crowd sprites in grandstands
; Algorithm: Crowd sprites cycle through 4 animation frames for visual variety
; **************************************************************************************************************

crowds_hori:    .word $03a6, $03a8, $03aa, $03ac, $03ae, $03b0, $03b2, $03b4      ; Horizontal crowd positions (8 sprites)
crowds_vert:    .word $0654, $06b8, $071c, $0780, $07e4, $0848, $08ac, $0910, $0974, $09d8  ; Vertical crowd positions (10 sprites)
crowd_vol_table: .byte $01,$01,$01,$02,$04,$08,$09,$0a,$0a,$0c,$0c,$0e,$0e,$0b,$0a,$0e,$0e,$0d,$09,$06,$03,$02  ; Volume table by position

; **************************************************************************************************************
; Driver/Racer Profile System
; Purpose: Store driver selection data and portrait sprite information for all 16 racers
; Format:
;   - racer_table = Pointer to driver name/bio text (low/high bytes)
;   - racer_face = Pointer to portrait sprite graphics (24-bit address: low/mid/high)
;   - ai_racer_face_pos = Screen positions for AI driver portraits during selection
; Usage:
;   - Player selects from 16 available drivers
;   - AI randomly assigned 3 drivers (no duplicates)
;   - Portrait sprites displayed during driver selection screen
; **************************************************************************************************************

; --- Current Driver Assignments ---
aicar_racer:    .byte $ff, $ff, $ff         ; AI car driver indices (0-15, one per AI car)
player_racer:   .byte $ff                   ; Player driver index ($FF = uninitialized, 0-15 when selected)
tmp_color:      .byte $00                   ; Temporary color for text rendering
driver_select_delay: .byte $00              ; Input delay counter for driver selection (debounce)

; --- AI Portrait Screen Positions (Driver Selection Screen) ---
ai_racer_face_posX_L: .byte $20, $20, $20   ; AI portrait X positions low bytes
ai_racer_face_posX_H: .byte $00, $00, $00   ; AI portrait X positions high bytes
ai_racer_face_posY_L: .byte $b0, $d0, $f0   ; AI portrait Y positions low bytes (176, 208, 240)
ai_racer_face_posY_H: .byte $00, $00, $00   ; AI portrait Y positions high bytes

; --- Driver Name/Bio Text Pointers (16 Drivers) ---
racer_table_L:   .byte <DataFlux,<NeonVector,<CyberLine,<PulseDrive,<GridRunner,<CodeStorm,<HyperByte,<VoltEdge
                 .byte <TurboLogic,<BitCrusher,<PhaseRift,<SynthDrive,<SignalRed,<ByteRacer,<IonRunner,<NightCircuit

racer_table_H:   .byte >DataFlux,>NeonVector,>CyberLine,>PulseDrive,>GridRunner,>CodeStorm,>HyperByte,>VoltEdge
                 .byte >TurboLogic,>BitCrusher,>PhaseRift,>SynthDrive,>SignalRed,>ByteRacer,>IonRunner,>NightCircuit

; --- Driver Portrait Sprite Graphics Pointers (24-bit Addresses) ---
racer_face_L:  .byte <racer1_face,<racer2_face,<racer3_face,<racer4_face,<racer5_face,<racer6_face,<racer7_face,<racer8_face
                 .byte <racer9_face,<racer10_face,<racer11_face,<racer12_face,<racer13_face,<racer14_face,<racer15_face,<racer16_face
racer_face_M:  .byte >racer1_face,>racer2_face,>racer3_face,>racer4_face,>racer5_face,>racer6_face,>racer7_face,>racer8_face
                 .byte >racer9_face,>racer10_face,>racer11_face,>racer12_face,>racer13_face,>racer14_face,>racer15_face,>racer16_face
racer_face_H:  .byte `racer1_face,`racer2_face,`racer3_face,`racer4_face,`racer5_face,`racer6_face,`racer7_face,`racer8_face
                 .byte `racer9_face,`racer10_face,`racer11_face,`racer12_face,`racer13_face,`racer14_face,`racer15_face,`racer16_face

.include "portraits.s"                       ; Include driver profile text data

; **************************************************************************************************************
; Start Message - Opening Credits and Thank You Text
; Purpose: Display game credits and acknowledgments on title screen
; Format: Multi-line text message terminated with $FF byte
; Usage: Displayed by open_message routine on first game start
; Layout: 80 characters per line, positioned at screen address $C2D0
; **************************************************************************************************************
start_message:
;      Column ruler for 80-character screen width:
;      00000000001111111111222222222233333333334444444444555555555566666666667777777777 
;      01234567890123456789012345678901234567890123456789012345678901234567890123456789
.text " Thank you for playing Track Day Racing!                                        "
.text "                                                                                "
.text " This game was created as a labor of love for the Foenix/Wildbits               "
.text " community and as my entry for the October-December 2025 Game Jam.              "
.text "                                                                                "
.text " Whether you're a veteran racer or just starting your first                     "
.text " lap, I hope this brings back fond memories of classic arcade racing            "
.text " while showcasing what the F256 hardware can do.                                "
.text "                                                                                "
.text " Special thanks to the Foenix/Wildbits community for their incredible support,  "
.text " documentation, and enthusiasm. Your passion for retro computing made           "
.text " this project possible.                                                         "
.text "                                                                                "
.text " Stay on the track, watch your speed, and most importantly, have fun!           "
.text "                                                                                "
.text "                                           - Michael Cassera, December 2025     "
.text "                                                                                "
.text "                                                                                "
.text "                                                                                "
.text "                    Press the joystick button to continue...                    "
.byte $ff

; ***************************************************************************************************************
; driver select screen
driver_select_message:
;      00000000001111111111222222222233333333334444444444555555555566666666667777777777
;      01234567890123456789012345678901234567890123456789012345678901234567890123456789
.text "            Select Your Driver (Blue Car) & number of laps to race:             "
.text "                                                                                "
.text " Up/Down    -> 3 Laps.                                                          "
.text " Left/Right -> driver.                                                          "
.text "                                                                                "
.byte $ff

; ***************************************************************************************************************
; Results Screen Text
results_message:
;      00000000001111111111222222222233333333334444444444555555555566666666667777777777
;      01234567890123456789012345678901234567890123456789012345678901234567890123456789
.text "                                  Race Results                                  "
.text "                                  ------------                                  "
.text "                                                                                "
.text "            Position                   Driver               Total Time          "
.text "            --------                   ------               ----------          " 
.text "                                                                                "               
.text "           1st Place:                                                           "
.text "                                                                                "
.text "                                                                                "
.text "                                                                                "
.text "           2nd Place:                                                           "
.text "                                                                                "
.text "                                                                                "
.text "                                                                                "
.text "           3rd Place:                                                           "
.text "                                                                                "
.text "                                                                                "
.text "                                                                                "
.text "           4th Place:                                                           "
.text "                                                                                "
.byte $ff

; ***************************************************************************************************************
; Include graphics data
font:
.binary "atari_letters.bin"                ; 8x8 font graphics (located in CPU addressable range for text rendering)
CLUT0:
.include "race_color.s"                     ; Color lookup table (palette, located in CPU addressable range to set VDC palette)
tilemap:
.binary "tilemap_road.tlm"                  ; Road/track tilemap layout (located in CPU addressable range for lookup)
speedo_tilemap:
.binary "tilemap_speedo.tlm"                ; Speedometer tilemap layout (located in CPU addressable range for showing lap time)

; ***************************************************************************************************************
; Include music data
; music player is a packed binary blob from GoatTracker
; This needs a hard address to load to, and entry points for init, play, stop because it's a binary blob

*=$a000                                     ; Music driver loads at $A000
init_music:                                 ; Entry point: Initialize music
play_music = init_music + 3                 ; Entry point: Play one frame of music (offset +3)
stop_music = init_music + 6                 ; Entry point: Stop music (offset +6)
.binary "hangon.bin"                        ; SID music driver binary blob

; **************************************************************************************************************
; Include sprite and tileset data
; This data is not accessed directly, but is referenced by pointers in the code above.

*=$10000
.include "bluecar.s"                        ; Blue car sprite data
.include "greencar.s"                       ; Green car sprite data
.include "redcar.s"                         ; Red car sprite data
.include "yellowcar.s"                      ; Yellow car sprite data
.include "helicopter_main.s"                ; Helicopter body sprite
.include "helicopter_rotor.s"               ; Helicopter rotor sprite
.include "helicopter_shadow.s"              ; Helicopter body shadow
.include "helicopter_rotor_shadow.s"        ; Helicopter rotor shadow
.include "8x8_sprites.s"                    ; 8x8 sprite graphics (UI elements)
.include "lighting_tree.s"                  ; Christmas tree/light sprites
.include "racers.s"                         ; Racer face sprite data

tileset:
.include "track2a_tileset.s"                ; Road/track tiles
crowd_tileset:
.include "crowds_tileset.s"                 ; Crowd/spectator tiles
speedo_tileset:
.include "speedo_set.s"                     ; Speedometer UI tiles
title_tileset:
.include "title_screen_set.s"               ; Title screen tiles
title_tilemap:
.binary "title_tilemap.tlm"                 ; Title screen tilemap layout
.fill 440, $0201                            ; padding for black selection screen
.fill 600, $0000                            ; padding to for title scrolling
