; hmove-live-reach — the rightmost column at which a live HMOVE's pulse train
; still distorts a parked dot.
;
; Companion to hmove-live-seam. There, a mid-line HMOVE strobe — one that nets
; zero motion but still emits its pulse train across the visible line — corrupts
; a 1-pixel missile dot wherever the dot sits on the pulses' fixed 4-pixel grid:
; a column that is 2 mod 4 is swallowed, one that is 3 mod 4 is widened to two
; pixels, columns 0 and 1 mod 4 draw clean. (HMOVE is the TIA's horizontal-motion
; strobe: it loads a 4-bit counter to 15 and hands each armed object a stuffed
; motion clock per four-clock group; a motion value of +7 in HMM0 keeps missile 0
; armed for all fifteen pulses. See hmove-live-seam for the full mechanism.)
;
; hmove-live-seam parks its dots only as far right as x=101; this test asks how
; far right the distortion actually STOPS. The train is identical — HMOVE at write
; cycle 33 with HMM0 = $70, zero net motion, fifteen pulses on the same fixed line
; grid — but the dots are parked much further right, and the answer is that the
; distortion reaches no further than x=98. Every park to the right of x=98, at
; every one of the four grid residues, renders as a clean dot. Whether the x=98
; slot is the fifteenth moving pulse itself or a trailing clearing step is not
; teased apart here; what is pinned down is that nothing beyond it is disturbed.
;
; The picture: a black field with one white missile dot stepping down and to the
; left in 16 bands of 12 lines each, parked from x=143 down to x=98 in 3-pixel
; steps so the bands walk through all four grid residues. On one line of each band
; the mid-line HMOVE is strobed; the lines above and below show the undistorted
; dot. Bands 0 through 14 (x=143 down to x=101) all sit right of the reach, so
; every one of their strobe lines is clean. Band 15 re-parks the known-distorted
; x=98 cell as an in-frame control: its strobe line is blank (the dot swallowed),
; proving the train really did run — a frame with no distortion anywhere would
; mean the pulse train was never reproduced at all.
;
; Verdict: the captured frame vs hmove-live-reach_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15 (park x = 143 - 3*BAND)
ODD     = $82                   ; BAND & 1 (adds the odd park cycle)
T       = $83                   ; scratch
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black field
        lda #$0E
        sta COLUP0              ; missile 0 takes COLUP0: white
        lda #$02
        sta ENAM0               ; enable the missile-0 dot
        lda #$70
        sta HMM0                ; HMM0 = +7: fifteen stuffed pulses, armed every line

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; the parks step LEFTWARD on purpose: stepping rightward would land every
        ; re-park on the reset-versus-wrap race alignment (see hmove-values) and
        ; drag that unrelated behaviour into every band boundary
        ldx #0
.bandloop:
        stx BAND

        ; line 1: precompute the park sled entry (VEC = Sled + 1 + (BAND+1)/2,
        ; ODD = BAND&1: RESM0's write cycle is 69 - BAND -> x = 143 - 3*BAND)
        sta WSYNC
        lda BAND
        and #$01
        sta ODD
        lda BAND
        clc
        adc #1
        lsr
        clc
        adc #<(Sled+1)
        sta VEC
        lda #>(Sled+1)
        adc #0
        sta VEC+1

        ; line 2: park M0 via the sled
        sta WSYNC
        lda ODD
        lsr                     ; C = BAND & 1
        bcs .go                 ; +1 cycle on odd bands
.go:
        jmp (VEC)                ; land in the sled, later entry = earlier RESM0
Sled:
        REPEAT 28               ; nop sled: the entry point trims one cycle/band
        nop
        REPEND
        sta RESM0               ; park M0: write cycle 69 - BAND -> x = 143 - 3*BAND

        ; lines 3-4: settle — the undistorted parked dot, two clean rows
        sta WSYNC
        sta WSYNC

        ; line 5: the live train — HMOVE at write cycle 33 (zero net motion),
        ; the pulses run across the visible line and hit the dot on THIS row
        sta WSYNC
        SLEEP 30
        sta HMOVE

        ; lines 6-12: the parked dot again — position unchanged (net motion zero)
        ldy #7
.post:
        sta WSYNC
        dey
        bne .post

        ldx BAND
        inx
        cpx #16
        bne .bandloop

        IFCONST FIELD_50HZ
        lda #$00
        sta ENAM0
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$02
        sta ENAM0
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
