; hmove-values — HMOVE applies a signed horizontal-motion amount, drawn as a
; 16-value ruler.
;
; Each of the TIA's five movable objects (two players, two missiles, the ball)
; has a horizontal-motion register — HMP0/HMP1/HMM0/HMM1/HMBL. Only the high
; nibble is used; the low nibble is ignored. That nibble is a signed 4-bit
; two's-complement number, and strobing HMOVE shifts the object by that many
; pixels in one go: a positive amount moves the object left, a negative amount
; moves it right.
;
;   $00 = 0 (no move)   $10..$70 = +1..+7 left   $80..$F0 = -8..-1 right
;
; So $70 is the largest left move (+7), $80 the largest right move (-8), and
; $F0 the smallest right move (-1). This test drives HMM0 (missile 0) through
; all 16 values and reads the object's landing column off the screen.
;
; The picture: a 1px missile (white, on a black background) steps down the
; screen in 16 horizontal bands, one HM value per band from $00 through $F0. The
; missile's column in each band marks base + the value's signed offset. Base sits
; at pixel 17, right of the 8px HMOVE comb — the blanked left-edge tab that
; HMOVE leaves on each strobed line — so the whole ruler clears the comb.
;
;   band 0    $00   px 17   no move: the base column
;   bands 1-7 $10-$70   px 16..10   +1..+7, stepping one pixel left per band
;   band 8    $80   px 25   -8: the far-right landing (the sign wrap)
;   bands 9-15 $90-$F0   px 24..18   -7..-1, stepping back left toward base
;   elsewhere black
;
; Read top to bottom the columns walk left 17->10 across $00..$70, then the
; $70->$80 sign wrap jumps from far-left (px 10) to far-right (px 25), then walk
; left again 25->18 across $80..$F0. A wrong sign or magnitude moves a band's
; body column off its expected pixel.
;
; Each band opens with two setup lines: the re-home line, where RESM0 fires
; mid-line, then the HMOVE line. The HMOVE line already shows the band's own
; column — the shift lands in the blanked start of the line. The re-home line
; is decided by a race between the reset and the old draw countdown: the
; reset point sits 4 colour clocks left of the base column, and where the old
; dot falls relative to it picks the outcome (hardware-measured: real PAL
; console, 2026-07-16):
;
;   bands 5-8     old dot at or left of the reset point, already drawn: the
;                 previous band's column stays for one more line
;   bands 1-4     old draw countdown in flight at the reset: re-phased to
;                 land 4 CLK after it, at the base column (px 17)
;   bands 0,9-15  no draw started yet: blank — a missile counter reset
;                 issues no "start drawing" pulse of its own (unlike the ball)
;
; (The line above band 0 still shows the previous frame's final column, px 18.)
;
; Verdict: the captured frame vs hmove-values_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; scratch: current band 0..15

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background black
        lda #$0E
        sta COLUP0              ; missile draws in COLUP0: white
        lda #$00
        sta NUSIZ0              ; M0 width 1px
        lda #$02
        sta ENAM0               ; enable missile 0

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: re-home M0 to the base, load this band's HM value
        sta WSYNC
        SLEEP 24
        sta RESM0               ; strobe RESM0 -> base px 17 (right of the comb)
        txa                     ; HMM0 = BAND << 4 (value $00,$10,..,$F0)
        asl
        asl
        asl
        asl
        sta HMM0

        ; line 2: strobe HMOVE at write cycle 3 -> full motion applied to M0
        sta WSYNC
        sta HMOVE

        ; lines 3-12: draw the missile -> M0 sits at base + the value's offset
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
        sta ENAM0
        IFCONST FIELD_50HZ
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF
        lda #$02
        sta ENAM0               ; re-enable for the next frame

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
