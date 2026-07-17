; hmove-strobe-line — how the scanline that carries the HMOVE strobe itself
; renders, swept across sixteen strobe timings.
;
; The TIA is the console's video chip; its movable objects (two players, two
; missiles, one ball) each have a horizontal position. Writing the HMOVE strobe
; register nudges every object by the signed 4-bit amount in the high nibble of
; its motion register (missile 0's: HMM0; $70 = +7, seven colour clocks left).
;
; The strobe does two things on the line it is written. It applies the nudge,
; and it extends horizontal blank — the black margin before the visible picture
; — by eight colour clocks, forcing the leftmost eight visible pixels (x 0-7)
; to the background colour: the 8-pixel HMOVE "comb." Every object also resumes
; its motion clock eight clocks late, so on that line a moving object draws
; mid-transition around the comb — exactly where Cosmic Ark's starfield lives.
;
; The test deliberately CAPTURES that line. A 1px white missile ($0E on a black
; field — the largest luminance gap on all three palettes) stays enabled, and
; band by band down the screen it is re-homed to a base column (x 8) and nudged
; by a single HMOVE strobed two CPU cycles later each band. Sixteen bands of 12
; lines, top to bottom — re-home row, strobe row, ten settled rows each:
;
;   band        0   1   2   3   4      5   6   7   8..15
;   re-home x   8   8   8   8   -      -   -   -   8
;   strobe x    -   -   8   9   10-11  12  -   8   8
;   settled x   5   6   8   9   11     12  14  8   8
;
; The settled column walks rightward across bands 0-6: a later strobe lands
; less of the nudge, past zero into reverse. From band 7 on, the strobe is too
; late to move anything (hmove-late charts the curve). On the strobe rows,
; bands 0-1's moved dots sit inside the comb, hidden. The rest land clear of
; it and take the live pulse train's column-mod-4 grid: band 4's dot
; (mod 4 = 3) widens to two pixels, and band 6's (mod 4 = 2) is swallowed
; (see hmove-live-seam).
;
; The re-home rows carry the same race hmove-values charts, between the reset
; and the missile's own draw countdown. A band whose old dot was due after the
; reset's landing slot draws nothing on that row (the reset silences bands
; 4-7); the rest show the re-phased base dot. Hardware-measured: real PAL
; console, 2026-07-16.
;
; Verdict: the captured frame vs hmove-strobe-line_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $82                   ; current band 0..15 ($80/$81 are RESULT/CODE)
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 16

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background black
        lda #$0E
        sta COLUP0              ; missile takes COLUP0: white
        lda #$00
        sta NUSIZ0              ; missile width 1px
        lda #$02
        sta ENAM0               ; missile stays on — the strobe line is drawn

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: re-home the missile, preload HMM0, and precompute the sled
        ; entry so the strobe walks one nop (two CPU cycles) later per band
        sta WSYNC
        SLEEP 21
        sta RESM0               ; re-home to the base column (x 8)
        lda #$70
        sta HMM0                ; arm +7 = move 7 clocks left
        lda #STEPS              ; VEC = Sled + (16 - band): higher band enters
        sec                     ;   the nop sled earlier, runs more nops, so the
        sbc BAND                ;   strobe fires two CPU cycles later each band
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1

        ; line 2: the HMOVE strobe line — comb + moving object rendered here
        sta WSYNC
        jmp (VEC)
Sled:
        REPEAT STEPS
        nop
        REPEND
        sta HMOVE               ; strobe at the swept timing (write cycle 8 + 2*BAND)

        ; lines 3..12: the object at its settled position
        ldy #10
.band:
        sta WSYNC
        dey
        bne .band

        ldx BAND
        inx
        cpx #16
        bne .bandloop

        ; 16 bands x 12 lines = 192 visible; 50 Hz fields are taller — pad blank
        lda #$00
        sta ENAM0               ; off in hblank of band 15's last line — dark
                                ;   row on 50 Hz; 60 Hz re-enables it in time
        IFCONST FIELD_50HZ
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF
        lda #$02
        sta ENAM0

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
