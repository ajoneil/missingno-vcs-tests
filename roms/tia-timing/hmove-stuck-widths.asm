; hmove-stuck-widths — how the stuck-train dot distortion depends on missile and
; ball WIDTH, and whether the ball follows the same rules as the missile.
;
; Under a stuck HMOVE latch (see hmove-stuck-latch) the TIA stuffs one extra
; horizontal-motion pulse per 4 colour clocks into an object's position counter
; on every line, drifting it 17 px left per line. For a 1-colour-clock missile
; the pulse distorts the drifting dot as a function of where the dot falls within
; the 4-clock pulse cycle — its residue, an offset of 0-3: residue 3 widens the
; dot to 2 px (a leading clock added), residue 2 swallows the dot entirely,
; residues 0 and 1 draw it normally. A missile can be 1, 2, 4 or 8 colour clocks
; wide (NUSIZ0 bits 4-5) and the ball likewise (CTRLPF bits 4-5). This test
; drifts every width under an identical jammed train to see how the distortion
; scales with width, and whether the ball behaves like the missile.
;
; The picture: eight 24-line bands, the same jam driving both movers at once —
; each band parks its object at x=101, jams the train, drifts, and releases on
; the band's last line.
;   band 0-3: missile M0 at widths 1 / 2 / 4 / 8 (NUSIZ0 = $00/$10/$20/$30)
;   band 4-7: ball    BL at widths 1 / 2 / 4 / 8 (CTRLPF = $00/$10/$20/$30)
; What each width draws, per residue (hardware-measured: real PAL console,
; 2026-07-16):
;   width 1:   the residue classes above, missile and ball alike
;   width 2:   residue 3 draws 3 px (a leading clock added), nothing swallowed;
;              the ball alone also loses its second clock at residue 1 (1 px)
;   width 4/8: residue 3 draws the full width 1 px left (leading clock gained,
;              last clock lost); every other residue normal
; A stuffed pulse costs one serial clock, never the whole draw, so only the
; 1-clock dot can vanish. A broken implementation typically blanks every width
; once per 4 lines, or shifts the ball's classes one residue off the missile's.
;
; Verdict: the captured frame vs hmove-stuck-widths_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..7

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black field
        lda #$0E
        sta COLUP0              ; white missile
        sta COLUPF              ; white ball

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: configure the band's shape and arm both movers
        sta WSYNC
        lda NusizTab,x
        sta NUSIZ0
        lda CtrlTab,x
        sta CTRLPF
        lda EnamTab,x
        sta ENAM0
        lda EnablTab,x
        sta ENABL
        lda #$70
        sta HMM0
        sta HMBL

        ; line 2: park the missile at x=101
        sta WSYNC
        SLEEP 52
        sta RESM0               ; write cycle 55

        ; line 3: park the ball at x=101
        sta WSYNC
        SLEEP 52
        sta RESBL               ; write cycle 55

        ; line 4: jam both movers
        sta WSYNC
        sta HMOVE               ; HMOVE write on cycle 3
        lda #$00
        SLEEP 11
        sta HMM0                ; rewrite HMM0=$00 at cycle 19: stuck
        sta HMBL                ; rewrite HMBL=$00 at cycle 22 — still mid-window

        ; lines 5..23: 19 drift rows showing width vs distortion
        ldy #19
.drift:
        sta WSYNC
        dey
        bne .drift

        ; line 24: release both latches ($80 clear point = ripple rest), so the
        ; bands stay independent; the missile freezes 5 px left of its last drift
        ; position and the ball 7 px left
        sta WSYNC
        lda #$80
        sta HMM0
        sta HMBL

        ldx BAND
        inx
        cpx #8
        bne .bandloop

        IFCONST FIELD_50HZ
        lda #$00
        sta ENAM0
        sta ENABL
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF

        jsr overscan_lines
        jmp MainLoop

NusizTab:
        .byte $00,$10,$20,$30,$00,$00,$00,$00
CtrlTab:
        .byte $00,$00,$00,$00,$00,$10,$20,$30
EnamTab:
        .byte $02,$02,$02,$02,$00,$00,$00,$00
EnablTab:
        .byte $00,$00,$00,$00,$02,$02,$02,$02

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
