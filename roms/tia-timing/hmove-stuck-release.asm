; hmove-stuck-release — a sweep of the whole $x0 column, one candidate per band,
; showing which HM values free a stuck HMOVE latch.
;
; hmove-stuck-latch jams the "more movement" latch: a mid-sequence HMxx rewrite
; dodges its clear step, and the TIA then nudges the object left every line
; with no further HMOVE. What frees the latch is a later HMxx write whose
; clear step equals the ripple counter's resting state, %1111. The values that
; satisfy this are the $8x family and only those — top nibble 8, low three
; bits inverted, giving %1111. hmove-stuck-latch exercises the $80 release
; directly; this frame documents the whole $x0 column at once — sixteen
; horizontal bands stacked top to bottom, band 0 probing $00 up to band 15
; probing $F0 — so band 8 ($80) stands out as the only one that frees the latch.
;
; The picture: a 1-clock white missile drifts under the jam in each band, and the
; band's probe value either freezes it into a constant column or leaves it
; staircasing left ~17 px/line. Only band 8's observe window freezes, at x=38.
; The cleanup release holds each drifting band's dot at x=96 across the next
; band's setup lines; band 8's dot stays at x=38 there instead.
;
; Verdict: the captured frame vs hmove-stuck-release_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15 (probe value = BAND<<4)
VAL     = $82                   ; the band's probe value, preloaded

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background: black field
        lda #$0E
        sta COLUP0              ; missile 0: white
        lda #$02
        sta ENAM0               ; enable M0 (1 colour clock wide)

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0                  ; band = 0
.bandloop:
        stx BAND
        txa
        asl
        asl
        asl
        asl
        sta VAL                 ; probe value = band << 4  ($00, $10, ... $F0)

        ; line 1: park M0 at x=101 and arm HMM0 = $70
        sta WSYNC
        lda #$70
        sta HMM0
        SLEEP 47
        sta RESM0               ; strobe at write cycle 55 -> M0 lands at x=101

        ; line 2: jam (HMOVE at write cycle 3, $00 rewrite at write cycle 19)
        sta WSYNC
        sta HMOVE
        lda #$00
        SLEEP 11
        sta HMM0                ; clear step already passed: latch stuck

        ; lines 3-5: drift under the stuck latch, ~17 px/line left
        ldy #3
.drift:
        sta WSYNC
        dey
        bne .drift

        ; line 6: the probe — write this band's $x0, no HMOVE. Frees the latch
        ; only if $x0's clear step is the resting state, i.e. only $80
        sta WSYNC
        lda VAL
        sta HMM0                ; zp load + zp store: write cycle 6

        ; lines 7-11: observe — a frozen column if the probe freed the latch,
        ; otherwise the staircase continues
        ldy #5
.observe:
        sta WSYNC
        dey
        bne .observe

        ; line 12: cleanup — $80 is a known release, so the next band starts
        ; from rest whatever the probe did
        sta WSYNC
        lda #$80
        sta HMM0

        ldx BAND
        inx
        cpx #16                 ; 16 bands (band 0..15)
        bne .bandloop

        IFCONST FIELD_50HZ             ; 50 Hz fields have more visible lines: blank the extra
        lda #$00                ; ones so the picture keeps its NTSC shape
        sta ENAM0               ; disable M0 during the padding lines
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$02
        sta ENAM0               ; re-enable M0 for the next field
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
