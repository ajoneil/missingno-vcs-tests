; hmove-late — strobing HMOVE late in the line applies less than the full move.
;
; HMOVE is the TIA's object-motion strobe (the chip that generates the video).
; Firing it injects a burst of extra "motion clocks" into the object position
; counters during an 8-clock extension of the horizontal blank; each object
; stops taking them once an internal countdown matches its motion register
; (HMM0 for the missile here), so the object shifts by the programmed amount.
; That full shift only lands when HMOVE is strobed right at the start of the
; line, while the whole burst still fits inside the blank. Strobe it later and
; the burst is cut short — the object moves less, and delayed far enough the
; motion shrinks to nothing or even reverses. This reduced-motion regime is the
; mechanism behind the "9th sprite" and fine sub-pixel positioning tricks.
;
; The test draws a 1-pixel missile — white on a black field, the missile taking
; player 0's colour (COLUP0) — and sweeps the strobe across this regime. HMM0 is
; held at $70 (a +7 leftward move); the screen is 16 horizontal bands top to
; bottom, and each band strobes HMOVE two CPU cycles later than the band above.
; Band 0's strobe falls inside the horizontal blank; the later bands push it out
; into the visible region. The missile's column per band is the position curve;
; read top to bottom, the columns are:
;
;   band  0  1  2  3  4  5  6   7 .. 15
;   x    20 21 23 24 26 27 29  23 .. 23
;
; The missile steps rightward across the first seven bands as the strobe is
; delayed, then holds at a fixed column for the remaining bands. The exact
; staircase is the fingerprint of correct late-HMOVE timing; a mistimed partial
; move bends it — wrong step widths, a missing or extra step, or a kink.
;
; Verdict: the captured frame vs hmove-late_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 16

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK
        lda #$0E
        sta COLUP0              ; missile takes COLUP0: white
        lda #$00
        sta NUSIZ0
        lda #$02
        sta ENAM0

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: blank the missile (transitional lines), re-home to base, preload
        ; HMM0, and precompute the sled entry (VEC = Sled + STEPS-BAND)
        sta WSYNC
        lda #$00
        sta ENAM0               ; blank line 1 + the HMOVE line from any draw
        SLEEP 21
        sta RESM0               ; base px 23
        lda #$70
        sta HMM0
        lda #STEPS
        sec
        sbc BAND
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1

        ; line 2: HMOVE strobed at write cycle 8 + 2*BAND (missile still blanked, so
        ; the transitional HMOVE-strobe-line rendering is excluded). The
        ; computed jump lands one nop deeper into the sled per band, delaying
        ; the strobe by 2 CPU cycles a band.
        sta WSYNC
        jmp (VEC)
Sled:
        REPEAT STEPS
        nop
        REPEND
        sta HMOVE

        ; lines 3..12: re-enable the missile and draw it at its settled position
        sta WSYNC
        lda #$02
        sta ENAM0
        ldy #9
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
        sta ENAM0
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
