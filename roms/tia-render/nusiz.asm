; nusiz — the low 3 bits of NUSIZ0 pick one of eight size-and-copy layouts for a
; player sprite.
;
; The TIA (the console's video chip) draws a "player" sprite by shifting the 8
; bits of its graphics register GRP0 out one per pixel. NUSIZ0 bits 0-2 change how
; many times, how far apart, and how wide that sprite is repeated across the line:
;
;   0  one copy, 8px wide          4  two copies, 64px apart
;   1  two copies, 16px apart      5  one double-width copy (16px)
;   2  two copies, 32px apart      6  three copies, 32px then 64px apart
;   3  three copies, 16+32 apart   7  one quad-width copy (32px)
;
; The extra copies are the same 8-bit graphics drawn again further right; the
; double/quad modes instead stretch each graphics bit to 2 or 4 pixels. In the
; stretched modes the sprite's first pixel is drawn one colour clock later than in
; the 1x modes, so a stretched copy's left edge sits 1px right of a 1x copy's.
;
; A self-test has no screen to inspect, so it reads the sprite's shape through the
; missile-versus-player collision latch (CXM1P bit 7), probed by a 1-pixel
; missile 1.
;
; The player carries a solid pattern, so every mode's profile marks exactly the
; columns its copies occupy. With the player anchored near the left, the main copy
; starts at x=18 (1x) or x=19 (stretched, the +1 draw-start delay), and further
; copies repeat at +16 / +32 / +64. The probe is swept across the line in sixteen
; coarse steps, building a 16-bit profile of which columns it found lit. The sweep
; runs once per mode and all eight profiles are asserted against their
; hardware-constant values; the assert table below spells out the expected bytes
; and the layout each one confirms.
;
;   CODE $01..$10 = a mode's profile is wrong. Two codes per mode, in mode
;   order starting at mode 0: the first of each pair is that mode's steps 0-7,
;   the second its steps 8-15.
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 16 bytes ($90..$9F): 2 per NUSIZ mode
MODE    = $A0                   ; current NUSIZ0 value 0..7
IDX     = $A1                   ; probe-sweep index 0..STEPS-1
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta GRP0                ; solid player (the object under test)
        lda #$0E
        sta COLUP0              ; player colour (any lit pixel shows this)
        lda #$02
        sta ENAM1              ; enable missile 1, 1px probe (NUSIZ1 = 0)

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        sta WSYNC
        SLEEP 24
        sta RESP0              ; anchor the player near the left

        ldx #15                ; clear the 16 profile bytes (2 per mode)
        lda #0
.clr:
        sta PROFILE,x
        dex
        bpl .clr

        ldx #0                 ; mode 0..7
.modeloop:
        stx MODE
        stx NUSIZ0             ; select the layout under test
        ldx #0                 ; step index 0..15
.sweep:
        stx IDX
        sta WSYNC              ; fresh scanline for this probe position
        txa                    ; VEC = Sled + step: entry skips `step` NOPs
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)              ; jump `step` NOPs into the sled
Sled:
        REPEAT STEPS
        nop                    ; each skipped NOP = 2 cycles = 6 colour clocks
        REPEND
        sta RESM1              ; strobe missile to x = 104 - 6*step

        sta CXCLR              ; clear the collision latches
        jsr latch              ; hold 2 beam-on lines so the overlap latches
        lda CXM1P
        and #$80               ; missile-1-vs-player-0: was this column lit?
        beq .next              ; no overlap -> leave the profile bit clear

        lda IDX                ; hit: OR bit (step&7) into PROFILE[mode*2 + step/8]
        and #$07
        tay
        lda Bit,y
        pha
        lda MODE
        asl                    ; mode*2 selects this mode's byte pair
        ldx IDX
        cpx #8
        bcc .lo                ; steps 0-7 -> low byte, steps 8-15 -> +1 high byte
        clc
        adc #1
.lo:
        tax
        pla
        ora PROFILE,x
        sta PROFILE,x
.next:
        ldx IDX
        inx
        cpx #STEPS
        bne .sweep             ; next probe position

        ldx MODE
        inx
        cpx #8
        bne .modeloop          ; next NUSIZ0 layout

        ASSERT_EQ PROFILE+0,  $00, $01   ; mode 0  (one copy, 8px)
        ASSERT_EQ PROFILE+1,  $40, $02
        ASSERT_EQ PROFILE+2,  $00, $03   ; mode 1  (two copies, +16)
        ASSERT_EQ PROFILE+3,  $48, $04
        ASSERT_EQ PROFILE+4,  $00, $05   ; mode 2  (two copies, +32)
        ASSERT_EQ PROFILE+5,  $43, $06
        ASSERT_EQ PROFILE+6,  $00, $07   ; mode 3  (three copies, +16 +32)
        ASSERT_EQ PROFILE+7,  $4B, $08
        ASSERT_EQ PROFILE+8,  $08, $09   ; mode 4  (two copies, +64)
        ASSERT_EQ PROFILE+9,  $40, $0A
        ASSERT_EQ PROFILE+10, $00, $0B   ; mode 5  (double width, 16px)
        ASSERT_EQ PROFILE+11, $70, $0C
        ASSERT_EQ PROFILE+12, $08, $0D   ; mode 6  (three copies, +32 +64)
        ASSERT_EQ PROFILE+13, $43, $0E
        ASSERT_EQ PROFILE+14, $00, $0F   ; mode 7  (quad width, 32px)
        ASSERT_EQ PROFILE+15, $7E, $10
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X (indices
; live in MODE/IDX).
latch:
        ldx #2
.ll:
        sta WSYNC
        dex
        bne .ll
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
