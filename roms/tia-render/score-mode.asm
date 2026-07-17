; score-mode — CTRLPF bit 1 (score mode) recolours the playfield: instead of
; drawing in COLUPF, its left half takes the player-0 colour and its right half
; the player-1 colour.
;
; CTRLPF is the playfield control register. Normally the whole playfield draws
; in COLUPF. Setting bit 1 puts it into "score mode": across the left 80 pixels
; of the visible line, wherever the playfield is on it draws in COLUP0 (the
; player-0 colour register); across the right 80 pixels it draws in COLUP1. The
; split sits at the screen midline (pixel 80), the same point where the 20-bit
; playfield pattern would repeat or reflect into the second half. This exists so
; a game can show two players' scores side by side, each half in that player's
; own colour, using only playfield graphics. Score mode recolours the playfield
; only — the players, the ball, and the background are untouched, and it changes
; no positions or shapes.
;
; The test draws 4px playfield stripes on a 16px period over a black
; background and turns score mode on, with player 0 green (COL_FIELD —
; mid-luma green on every standard) and player 1 blue (luma 6). The two are
; hue-distinct on NTSC/PAL and two luma steps apart everywhere, so even
; SECAM's luma-only decode keeps the halves apart (green vs yellow there).
; COLUPF is set to a third colour ($46) that appears nowhere in the correct
; picture. Every visible line shows:
;
;   x  0- 3, 16-19, 32-35, 48-51, 64-67    green   left-half stripes in COLUP0
;   x 80-83, 96-99, 112-115, 128-131,
;     144-147                              blue    right-half stripes in COLUP1
;   black between the stripes
;
; The split sits between the x=64 and x=80 stripes: the same 20-bit pattern
; drawn twice, recoloured per half. A decoder that ignores bit 1 draws every
; stripe in COLUPF instead, a colour absent from the correct picture; one
; that muddles the halves swaps the two stripe colours across x=80.
;
; Verdict: the captured frame vs score-mode_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background black
        lda #$46
        sta COLUPF              ; drawn ONLY if score mode is broken
        lda #COL_FIELD
        sta COLUP0              ; left-half playfield colour: green (luma 4)
        lda #$9C
        sta COLUP1              ; right-half playfield colour: blue (luma 6)
        lda #$02
        sta CTRLPF              ; bit 1 score mode on; reflect off, priority off

        ; playfield stripes, 4px on a 16px period (the right half repeats
        ; the pattern, recoloured by score mode): x = 0, 16, ... , 144
        lda #$10
        sta PF0                 ; bit 4 -> x 0-3
        lda #$88
        sta PF1                 ; bits 7,3 -> x 16-19, 32-35
        lda #$11
        sta PF2                 ; bits 0,4 -> x 48-51, 64-67

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #VISIBLE_LINES
.visible:
        sta WSYNC
        dex
        bne .visible

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
