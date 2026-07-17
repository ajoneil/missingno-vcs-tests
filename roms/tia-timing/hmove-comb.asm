; hmove-comb — strobing HMOVE blanks the leftmost 8 pixels of the line (the
; "comb").
;
; Every scanline opens with a horizontal blank: the beam retraces off the left
; edge and the TIA (the chip that generates the video) outputs nothing for the
; first 68 of the line's 228 colour clocks, then the visible 160 clocks begin.
; HMOVE is the TIA's object-motion strobe (writing the register fires it). As a
; side effect of firing it, the TIA holds the horizontal blank on for 8 extra
; colour clocks — so the first 8 visible pixels of that line stay blanked to
; black instead of showing the object or background underneath. This is the
; classic HMOVE "comb": a black bar down the left edge of any screen that
; strobes HMOVE every line. It comes purely from the strobe, independent of the
; motion registers (HMP0/HMM0/... — all zero here, so no object actually moves).
;
; The test draws sparse green playfield stripes (4px on a 16px period, at
; x = 0, 16, ... , 144) and strobes HMOVE on alternating 4-line groups.
; The first stripe sits at x 0-3, inside the comb's 8 blanked pixels:
;
;   comb lines      the x 0-3 stripe is blanked; every other stripe intact
;   no-comb lines   all ten stripes present, x 0-3 included
;
; Down the frame the left column is a 4-on/4-off dash while every other
; stripe column is solid — the comb and its absence, both in one frame.
; Without the extended blank the left column is solid like the rest. A
; comb that misses x 0-3 also leaves the column solid; one reaching the
; next stripe at x 16 clips it on the comb lines.
;
; Verdict: the captured frame vs hmove-comb_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

        lda #COL_FIELD
        sta COLUPF              ; green stripes (luma 4 on every standard)
        lda #$10
        sta PF0                 ; the 4px / 16px stripe cadence: lit cells at
        lda #$88                ; x 0-3, 16-19, ... , 144-147 (reflect off,
        sta PF1                 ; right half repeats the left)
        lda #$11
        sta PF2

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #VISIBLE_LINES
.visible:
        sta WSYNC
        txa
        and #%00000100          ; 4-line groups: comb on when bit 2 of the
        beq .nocomb             ; line counter is set
        sta HMOVE               ; strobe in HBLANK: blanks this line's first 8px
.nocomb:
        dex
        bne .visible

        ; HMOVE strobed with the HM registers at 0 (never set) moves nothing;
        ; only the comb is exercised.
        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
