; setup.asm
; This file contains the register map for the Foenix A256K
; Michael Cassera
;---------------------------------------------------------------------



; Master Memory Unit
MMU_IO_CTRL 	= $01						;MMU I/O Control

; Vicky control
VKY_MSTR_CTRL_0 = $d000						; Vicky Master Control Register 0
VKY_MSTR_CTRL_1 = $d001						; Vicky Master Control Register 1
VKY_BRDR_CTRL   = $d004						; Vicky Border Control Register

; Vicky Background Color
VKY_BKG_COL_B   = $d00d						; Vicky Graphics Background Color Blue
VKY_BKG_COL_G   = $d00e						; Vicky Graphics Background Color Green
VKY_BKG_COL_R   = $d00f						; Vicky Graphics Background Color Red

; Vicky layer control
VKY_LAYER_CTRL_0= $d002
VKY_LAYER_CTRL_1= $d003

; Tile Set 0 Registers
VKY_TS0_AD_L	= $d280						; Vicky Tile 0 Image Start Address LOW BYTE
VKY_TS0_AD_M	= $d281						; Vicky Tile 0 Image Start Address MEDIUM BYTE
VKY_TS0_AD_H	= $d282						; Vicky Tile 0 Image Start Address HIGH BYTE

; Tile Set 1 Registers
VKY_TS1_AD_L	= $d284						; Vicky Tile 1 Image Start Address LOW BYTE
VKY_TS1_AD_M	= $d285						; Vicky Tile 1 Image Start Address MEDIUM BYTE
VKY_TS1_AD_H	= $d286						; Vicky Tile 1 Image Start Address HIGH BYTE

; Tile Set 2 Registers
VKY_TS2_AD_L	= $d288						; Vicky Tile 2 Image Start Address LOW BYTE
VKY_TS2_AD_M	= $d289						; Vicky Tile 2 Image Start Address MEDIUM BYTE
VKY_TS2_AD_H	= $d28a						; Vicky Tile 2 Image Start Address HIGH BYTE

; Tile Set 3 Registers
VKY_TS3_AD_L	= $d28c						; Vicky Tile 3 Image Start Address LOW BYTE
VKY_TS3_AD_M	= $d28d						; Vicky Tile 3 Image Start Address MEDIUM BYTE
VKY_TS3_AD_H	= $d28e						; Vicky Tile 3 Image Start Address HIGH BYTE

; Tile Map 0 Registers
VKY_TM0_CTRL	= $d200						; Tile Map 0 Control
VKY_TM0_AD_L	= $d201						; Tile Map 0 Start Address LOW BYTE
VKY_TM0_AD_M	= $d202						; Tile Map 0 Start Address MEDIUM BYTE
VKY_TM0_AD_H	= $d203						; Tile Map 0 Start Address HIGH BYTE
VKY_TM0_SZ_X	= $d204						; Tile Map 0 Size X
VKY_TM0_SZ_Y	= $d206						; Tile Map 0 Size Y
VKY_TM0_POS_X_L = $d208						; Tile Map 0 X Position & Scroll LOW BYTE
VKY_TM0_POS_X_H = $d209						; Tile Map 0 X Position & Scroll HIGH BYTE
VKY_TM0_POS_Y_L = $d20a						; Tile Map 0 Y Position & Scroll LOW BYTE
VKY_TM0_POS_Y_H = $d20b						; Tile Map 0 Y Position & Scroll HIGH BYTE

; Tile Map 1 Registers
VKY_TM1_CTRL	= $d20c						; Tile Map 1 Control
VKY_TM1_AD_L	= $d20d						; Tile Map 1 Start Address LOW BYTE
VKY_TM1_AD_M	= $d20e						; Tile Map 1 Start Address MEDIUM BYTE
VKY_TM1_AD_H	= $d20f						; Tile Map 1 Start Address HIGH BYTE
VKY_TM1_SZ_X	= $d210						; Tile Map 1 Size X
VKY_TM1_SZ_Y	= $d212						; Tile Map 1 Size Y
VKY_TM1_POS_X_L = $d214						; Tile Map 1 X Position & Scroll LOW BYTE
VKY_TM1_POS_X_H = $d215						; Tile Map 1 X Position & Scroll HIGH BYTE
VKY_TM1_POS_Y_L = $d216						; Tile Map 1 Y Position & Scroll LOW BYTE
VKY_TM1_POS_Y_H = $d217						; Tile Map 1 Y Position & Scroll HIGH BYTE

; Tile Map 2 Registers
VKY_TM2_CTRL	= $d218						; Tile Map 2 Control
VKY_TM2_AD_L	= $d219						; Tile Map 2 Start Address LOW BYTE
VKY_TM2_AD_M	= $d21a						; Tile Map 2 Start Address MEDIUM BYTE
VKY_TM2_AD_H	= $d21b						; Tile Map 2 Start Address HIGH BYTE
VKY_TM2_SZ_X	= $d21c						; Tile Map 2 Size X
VKY_TM2_SZ_Y	= $d21e						; Tile Map 2 Size Y
VKY_TM2_POS_X_L = $d220						; Tile Map 2 X Position & Scroll LOW BYTE
VKY_TM2_POS_X_H = $d221						; Tile Map 2 X Position & Scroll HIGH BYTE
VKY_TM2_POS_Y_L = $d222						; Tile Map 2 Y Position & Scroll LOW BYTE
VKY_TM2_POS_Y_H = $d223						; Tile Map 2 Y Position & Scroll HIGH BYTE

; Sprite registers		                    ; we're starting a $0a for cars in case we want something in front of them (explosions or ???)

VKY_SP0         = $d900                     ; start of sprite register locations / each new aprite is a multiple of 8
SP_CTRL         = $00                       ; control register              7-x, 6/5-size, 4/3-layer, 2/1-lut, 0-enable
SP_AD_L         = $01                       ; image address location
SP_AD_M         = $02
SP_AD_H         = $03
SP_POS_X_L      = $04                       ; x position
SP_POS_X_H      = $05 
SP_POS_Y_L      = $06                       ; y position
SP_POS_Y_H      = $07


; Vicky Color Look Up Table Regsiters
VKY_GR_CLUT_0  	= $d000						; Graphics LUT #0 in I/O page 1
VKY_GR_CLUT_1  	= $d400						; Graphics LUT #1 in I/O page 1

; SID (Sound Interface Device) register map
; The system exposes two sets of SID registers (Left and Right) for
; stereo output or per-channel routing. Each set contains three sound
; channels (1..3) with frequency, pulse width, gate and ADSR controls,
; plus shared filter/resonance/volume registers.
;
; Per-channel register layout:
;  - _FREQ_L/_FREQ_H : 16-bit frequency value (low/high)
;  - _PULS_L/_PULS_H : 16-bit pulse width (low/high) for pulse waveform
;  - _GATE           : gate/control flags (trigger/envelope enable)
;  - _ATDL/_STRL     : attack/decay/ sustain/ release / level bytes (ADSR settings)
;
; Left SID registers (base $d400)
SID_L1_FREQ_L   = $d400                     ; Channel 1 Frequency LOW byte
SID_L1_FREQ_H   = $d401                     ; Channel 1 Frequency HIGH byte
SID_L1_PULS_L   = $d402                     ; Channel 1 Pulse Width LOW byte
SID_L1_PULS_H   = $d403                     ; Channel 1 Pulse Width HIGH byte
SID_L1_GATE     = $d404                     ; Channel 1 Gate/Control
SID_L1_ATDL     = $d405                     ; Channel 1 ADSR Attack/Decay/Level
SID_L1_STRL     = $d406                     ; Channel 1 Sustain/Release Level

SID_L2_FREQ_L   = $d407                     ; Channel 2 Frequency LOW byte
SID_L2_FREQ_H   = $d408                     ; Channel 2 Frequency HIGH byte
SID_L2_PULS_L   = $d409                     ; Channel 2 Pulse Width LOW byte
SID_L2_PULS_H   = $d40a                     ; Channel 2 Pulse Width HIGH byte
SID_L2_GATE     = $d40b                     ; Channel 2 Gate/Control
SID_L2_ATDL     = $d40c                     ; Channel 2 ADSR Attack/Decay/Level
SID_L2_STRL     = $d40d                     ; Channel 2 Sustain/Release Level

SID_L3_FREQ_L   = $d40e                     ; Channel 3 Frequency LOW byte   
SID_L3_FREQ_H   = $d40f                     ; Channel 3 Frequency HIGH byte
SID_L3_PULS_L   = $d410                     ; Channel 3 Pulse Width LOW byte
SID_L3_PULS_H   = $d411                     ; Channel 3 Pulse Width HIGH byte
SID_L3_GATE     = $d412                     ; Channel 3 Gate/Control
SID_L3_ATDL     = $d413                     ; Channel 3 ADSR Attack/Decay/Level
SID_L3_STRL     = $d414                     ; Channel 3 Sustain/Release Level

SID_L_FLT_L     = $d415                     ; Filter cutoff low
SID_L_FLT_H     = $d416                     ; Filter cutoff high
SID_L_RES       = $d417                     ; Filter resonance/control
SID_L_VOL       = $d418                     ; Master volume for left SID

; Right SID registers (base $d500)
SID_R1_FREQ_L   = $d500                     ; Channel 1 Frequency LOW byte
SID_R1_FREQ_H   = $d501                     ; Channel 1 Frequency HIGH byte
SID_R1_PULS_L   = $d502                     ; Channel 1 Pulse Width LOW byte
SID_R1_PULS_H   = $d503                     ; Channel 1 Pulse Width HIGH byte
SID_R1_GATE     = $d504                     ; Channel 1 Gate/Control
SID_R1_ATDL     = $d505                     ; Channel 1 ADSR Attack/Decay/Level
SID_R1_STRL     = $d506                     ; Channel 1 Sustain/Release Level

SID_R2_FREQ_L   = $d507                     ; Channel 2 Frequency LOW byte
SID_R2_FREQ_H   = $d508                     ; Channel 2 Frequency HIGH byte
SID_R2_PULS_L   = $d509                     ; Channel 2 Pulse Width LOW byte
SID_R2_PULS_H   = $d50a                     ; Channel 2 Pulse Width HIGH byte
SID_R2_GATE     = $d50b                     ; Channel 2 Gate/Control
SID_R2_ATDL     = $d50c                     ; Channel 2 ADSR Attack/Decay/Level
SID_R2_STRL     = $d50d                     ; Channel 2 Sustain/Release Level

SID_R3_FREQ_L   = $d50e                     ; Channel 3 Frequency LOW byte
SID_R3_FREQ_H   = $d50f                     ; Channel 3 Frequency HIGH byte
SID_R3_PULS_L   = $d510                     ; Channel 3 Pulse Width LOW byte
SID_R3_PULS_H   = $d511                     ; Channel 3 Pulse Width HIGH byte
SID_R3_GATE     = $d512                     ; Channel 3 Gate/Control
SID_R3_ATDL     = $d513                     ; Channel 3 ADSR Attack/Decay/Level
SID_R3_STRL     = $d514                     ; Channel 3 Sustain/Release Level

SID_R_FLT_L     = $d515                     ; Filter cutoff low
SID_R_FLT_H     = $d516                     ; Filter cutoff high
SID_R_RES       = $d517                     ; Filter resonance/control
SID_R_VOL       = $d518                     ; Master volume for right SID

;PSG Registers
PSG_L           = $d600
PSG_R           = $d610
PSG_LR          = $d608

PSG1_FREQ_LO    = %10000000                 ; OR with low 4 bits
PSG1_FREQ_HI    = %00000000                 ; OR with low 6 bits
PSG1_VOLUME     = %10010000                 ; OR with low 4 bits / default is full  - 0 = full, f = silent

PSG2_FREQ_LO    = %10100000                 ; OR with low 4 bits
PSG2_FREQ_HI    = %00000000                 ; OR with low 6 bits
PSG2_VOLUME     = %10110000                 ; OR with low 4 bits / default is full  - 0 = full, f = silent

PSG3_FREQ_LO    = %11000000                 ; OR with low 4 bits
PSG3_FREQ_HI    = %00000000                 ; OR with low 6 bits
PSG3_VOLUME     = %11010000                 ; OR with low 4 bits / default is full  - 0 = full, f = silent


;Midi
MIDI_COM        = $dda1                     ; midi command

; Interrupt Registers
VIRQ			= $fffe						; Pointer to IRQ routine (LOW Byte)
INT_PEND_0		= $d660						; Pending register for interrupts 0-7
INT_PEND_1		= $d661						; Pending register for interrupts 8-15
INT_MASK_0		= $d66c						; Mask register for interrupts 0-7
INT_MASK_1		= $d66d						; Mask register for interrupts 8-15

; ======================================================================
; Math Coprocessor register map — overview
;
; This system exposes a small hardware math coprocessor accessible via
; memory-mapped registers in the $de00-$de1f range. The coprocessor
; supports multiply (MULU), divide (DEVU), quotient/remainder (QUOU/REMU)
; and multi-byte addition (ADD) operations. Multi-byte values are passed
; and retrieved using four byte lanes named LL, LH, HL, HH (least to
; most-significant). This lets the CPU hand large integers to the
; coprocessor without doing manual byte-wise carry propagation.
;
; Naming / byte order convention:
;  - LL : least-significant byte
;  - LH : next byte
;  - HL : next byte
;  - HH : most-significant byte
;
; Typical usage patterns:
;  - Multiply (unsigned): write A into MULU_A_L/H, write B into MULU_B_L/H,
;    then the product bytes are available at MULU_LL..MULU_HH (A x B).
;  - Divide (unsigned): write denominator into DEVU_DEN_*, numerator into
;    DEVU_NUM_*, result (quotient) appears in QUOU_*, remainder in REMU_*.
;  - Add: write operand A into ADD_A_*, operand B into ADD_B_* and read
;    result from ADD_R_*.
;
; ======================================================================
; Math Coprocessor
MULU_A_L		= $de00					    ; unsigned A LOW byte
MULU_A_H		= $de01					    ; unsigned A HIGH Byte
MULU_B_L		= $de02					    ; unsigned B LOW byte
MULU_B_H		= $de03					    ; unsigned B HIGH byte
MULU_LL			= $de10					    ; A x B byte 0 (product low)
MULU_LH			= $de11					    ; A x B byte 1
MULU_HL			= $de12					    ; A x B byte 2
MULU_HH			= $de13					    ; A x B byte 3 (product high)

DEVU_DEN_L      = $de04					    ; denominator low byte
DEVU_DEN_H      = $de05					    ; denominator high byte
DEVU_NUM_L      = $de06					    ; numerator low byte
DEVU_NUM_H      = $de07					    ; numerator high byte
QUOU_LL         = $de14					    ; quotient byte 0 (low)
QUOU_LH         = $de15					    ; quotient byte 1
REMU_LL         = $de16					    ; remainder byte 0
REMU_LH         = $de17					    ; remainder byte 1

ADD_A_LL		= $de08					    ; operand A low byte
ADD_A_LH		= $de09					    ; operand A byte 1
ADD_A_HL		= $de0a					    ; operand A byte 2
ADD_A_HH		= $de0b					    ; operand A byte 3 (high)
ADD_B_LL		= $de0c					    ; operand B low byte
ADD_B_LH		= $de0d					    ; operand B byte 1
ADD_B_HL		= $de0e					    ; operand B byte 2
ADD_B_HH		= $de0f					    ; operand B byte 3 (high)
ADD_R_LL		= $de18					    ; result low byte
ADD_R_LH		= $de19					    ; result byte 1
ADD_R_HL		= $de1a					    ; result byte 2
ADD_R_HH		= $de1b					    ; result byte 3 (high)

; DMA (Direct Memory Access) registers
;======================================================================
;
; Overview:
; The DMA engine copies data between memory regions or fills memory with a
; constant. Control bits in DMA_CTRL select operation mode and trigger the
; transfer. DMA_STATUS toggles between source/destination when used in
; certain chained operations; DMA_FILL holds the fill value when FL bit is
; set in DMA_CTRL.
;
; DMA_CTRL bits (high->low): ST|xx|xx|xx|TE|FL|2D|EN
;  - EN : enable/trigger the DMA transfer
;  - 2D : 2D mode / stride enable (implementation-specific)
;  - FL : fill mode (use DMA_FILL instead of reading a source)
;  - TE : toggle enable or transfer end handling
;  - ST : start/priority flags
;
; Registers layout:
;  - DMA_SRC_L/M/H : 24-bit source address (ignored when FL=1)
;  - DMA_DST_L/M/H : 24-bit destination address
;  - DMA_CNT_L/M/H : 24-bit transfer count (number of bytes)
;  - DMA_FILL      : byte value to write when FL=1 (fill mode)
;
; Usage example outline:
;  1) Write source address to DMA_SRC_* (unless FL=1)
;  2) Write destination address to DMA_DST_*
;  3) Write transfer count to DMA_CNT_*
;  4) Set DMA_CTRL with EN=1 (and FL=1 for fill) to start transfer
;  5) Poll DMA_STATUS or an interrupt to know when complete
;
; Note: DMA is memory-mapped I/O and may require specific ordering of
; writes on this platform. Consult hardware docs if transfers behave
; unexpectedly (e.g., write ordering or cache effects).
; DMA registers
;======================================================================
DMA_CTRL		= $df00					; DMA control  ST|xx|xx|xx|TE|FL|2D|EN
DMA_STATUS		= $df01					; DMA Source/Destination Toggle (0=src, 1=dst)
DMA_FILL        = $df01					; DMA Fill value for fill mode (FL=1)
DMA_SRC_L		= $df04					; DMA Source Address LOW byte (if FL=0)
DMA_SRC_M		= $df05					; DMA Source Address MEDIUM byte (if FL=0)
DMA_SRC_H		= $df06					; DMA Source Address HIGH byte (if FL=0)
DMA_DST_L		= $df08					; DMA Destination Address LOW byte
DMA_DST_M		= $df09					; DMA Destination Address MEDIUM byte
DMA_DST_H		= $df0a					; DMA Destination Address HIGH byte
DMA_CNT_L		= $df0c					; DMA Transfer Count LOW byte
DMA_CNT_M		= $df0d					; DMA Transfer Count MEDIUM byte
DMA_CNT_H		= $df0e					; DMA Transfer Count HIGH byte

;Random Number Generator
Random_Reg		= $d6a6
Random_L		= $d6a4

; Misc Variables for Indirect Indexing
ptr_src			= $80						; A pointer to read data
ptr_dst			= $82						; A pointer to write data



