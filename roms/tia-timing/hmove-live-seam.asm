; hmove-live-seam — a mid-line HMOVE that moves nothing still runs its pulse
; train, and that train distorts a parked missile dot.
;
; HMOVE is the TIA's horizontal-motion mechanism. Each of the five movable
; objects (players P0/P1, missiles M0/M1, ball BL) has a motion register (HMP0,
; HMM0, ...) holding a signed 4-bit amount in its high nibble. Writing anything
; to the HMOVE strobe register starts a motion sequence: an internal 4-bit
; counter loads to 15 and counts down, and once per four-colour-clock group each
; object still "armed" for motion is handed an extra motion clock — a stuffed
; pulse — that nudges it one pixel left. An object drops out of the sequence when
; the counter reaches that object's stored amount (with its low three bits
; inverted): $70 never matches until the run ends, so it stays armed for all
; fifteen pulses; $00 drops out after eight. (A line-start HMOVE also stretches
; horizontal blank eight clocks, withholding eight ordinary motion clocks —
; fifteen stuffs minus those eight is $70's usual seven-pixel move.)
;
; The strobe is an ordinary bus write, not tied to any beam position. Struck at
; the very start of a line (right after WSYNC) the whole pulse train falls inside
; horizontal blank, so the only visible trace is an 8-pixel widening of the left
; blanking bar — the HMOVE "comb". Struck later — here at write cycle 33, well
; inside the visible line — the identical train instead runs out across the
; picture. At these mid-line write phases (write cycles 21 through 54) the motion
; nets to zero: the object ends exactly where it began. But the pulses are still
; emitted, and every armed object still receives them.
;
; A stuffed pulse is an extra motion clock handed to an object whether or not it
; is meant to move. When one lands while a missile's 1-pixel dot is being
; serialised, it corrupts the draw. The pulses fall on a fixed grid four pixels
; apart, so whether a given dot is hit depends only on its column mod 4:
;   column mod 4 == 2   the pulse swallows the dot — nothing is drawn
;   column mod 4 == 3   the pulse widens it to 2px — the pixel to its left, plus it
;   column mod 4 == 0/1 the dot draws normally
; A dot distorted this way need never have moved: a zero-motion train corrupts it
; exactly as a permanently stuck one does (see hmove-stuck-latch), the difference
; being that this train finishes on its own — there is no jammed latch to release.
;
; The picture: a black field with one white missile dot stepping down and to the
; left in 16 bands of 12 lines each, parked from x=101 down to x=56 in 3-pixel
; steps so the bands walk through all four grid residues.
; Within a band the dot holds a steady column on every line but one — the line
; that strobes the mid-line HMOVE, which shows the distortion: a blank row where a
; column-mod-4 == 2 dot was swallowed, a 2-pixel row where a column-mod-4 == 3 dot
; was widened. The lines above and below that one show the undistorted dot for
; comparison. The rightmost distorted column is x=98 (band 1), a hair past the
; last moving pulse's slot; no band here parks further right, so the right-edge
; extent is hmove-live-reach's job. A build that emits no visible pulses for a
; zero-motion mid-line HMOVE leaves every band's dot clean — no row is ever
; blanked or widened.
;
; Verdict: the captured frame vs hmove-live-seam_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15 (park x = 101 - 3*BAND)
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

        ldx #0
.bandloop:
        stx BAND

        ; line 1: precompute the park sled entry (VEC = Sled + 1 + BAND/2
        ; + odd, so RESM0's write cycle is 55 - BAND -> park x = 101 - 3*BAND)
        sta WSYNC
        lda BAND
        and #$01
        sta ODD
        lda BAND
        lsr
        clc
        adc ODD
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
        REPEAT 21               ; nop sled: the entry point trims one cycle/band
        nop
        REPEND
        sta RESM0               ; park M0: write cycle 55 - BAND -> x = 101 - 3*BAND

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
