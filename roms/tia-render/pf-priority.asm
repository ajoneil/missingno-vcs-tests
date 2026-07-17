; pf-priority — CTRLPF bit 2 puts the playfield and ball in front of the
; players and missiles.
;
; When TIA objects overlap on a pixel, a fixed priority ladder picks the
; colour. Normal order, front to back: P0/M0, then P1/M1, then PF/BL, then
; the background. Setting CTRLPF bit 2 lifts the playfield and ball to the
; front, above all four player/missile objects — sprites pass behind the
; scenery.
;
; The playfield draws 4px white stripes on a 16px period over a black
; background; the player is quad-width (32px footprint) with GRP $88 — two
; 4px lit segments 16px apart — placed so each segment half-crosses a
; stripe. Priority bit set: the stripe stays white across the player.
; Every visible line shows:
;
;   x   0-  3  white   playfield stripe alone (also 16-19, 64-67, and the
;                      right-half repeats 80-83 ... 144-147)
;   x  32- 33  white   stripe, left of the player's first segment
;   x  34- 35  white   stripe OVER the player — the priority discriminator
;   x  36- 37  blue    the segment's remainder, past the stripe's end
;   x  48- 49  white   stripe, left of the second segment
;   x  50- 51  white   stripe over the player again
;   x  52- 53  blue    the second segment's remainder
;   elsewhere black
;
; If bit 2 is ignored the player wins instead: 34-35 and 50-51 turn blue.
;
; The blue runs double as a position check: a quad-stretched player starts
; drawing one colour clock late, so the second segment's right edge must
; sit exactly at x=53.
;
; Verdict: the captured frame vs pf-priority_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background black
        lda #$0E
        sta COLUPF              ; playfield white
        lda #$92
        sta COLUP0              ; player blue

        lda #$07
        sta NUSIZ0              ; player 0 quad width: 8 GRP0 bits x 4px = 32px
        lda #$04
        sta CTRLPF              ; bit 2: playfield/ball in front; reflect off
        ; playfield stripes, 4px on a 16px period (right half repeats the
        ; left with REF clear): x = 0, 16, 32, ... , 144
        lda #$10
        sta PF0                 ; bit 4 -> x 0-3
        lda #$88
        sta PF1                 ; bits 7,3 -> x 16-19, 32-35
        lda #$11
        sta PF2                 ; bits 0,4 -> x 48-51, 64-67

        ; strobe RESP0 mid-line: the player lands at x=33, and the quad
        ; stretch delays its draw start one clock -> segments 34-37, 50-53
        sta WSYNC
        SLEEP 29
        sta RESP0
        lda #$88                ; two lit segments, the stripe cadence
        sta GRP0

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
