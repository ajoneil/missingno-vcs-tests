; playfield — the three playfield registers each own a fixed slice of the
; screen and are read out in their own bit order.
;
; The playfield is the TIA's low-resolution background pattern. The 160-pixel
; visible line is divided into 40 cells of 4 pixels each; a single bit decides
; whether its cell is drawn in the playfield colour or left to the background.
; Twenty of those bits — supplied by three registers — describe the left half
; of the screen (pixels 0-79); the right half (pixels 80-159) either repeats
; those twenty bits or mirrors them, chosen by CTRLPF bit 0 (this test leaves
; it clear, so the right half repeats).
;
; Each of the three registers is clocked out in a different bit order — a
; hardware quirk, not a mistake:
;   PF0  uses only its high nibble, drawn D4,D5,D6,D7 : cells 0-3   (px 0-15)
;   PF1  drawn most-significant bit first, D7..D0      : cells 4-11  (px 16-47)
;   PF2  drawn least-significant bit first, D0..D7      : cells 12-19 (px 48-79)
; So the playfield pattern is fixed to the screen, 4 pixels per bit starting
; at x = 0, and cell n covers pixels 4n..4n+3.
;
; A self-test has no screen to inspect, so it senses lit columns through the
; missile-playfield collision latch (CXM0FB bit 7, which reports whether missile
; 0 has shared a pixel with the playfield since the last write to CXCLR). A
; 1-pixel missile acts as a movable probe: park it on a column, clear the
; latches, let the frame render, and the latch answers "is this column lit?"
;
; The test loads a distinctive pattern (PF0 = $50, PF1 = $C3, PF2 = $A5) and
; sweeps the probe across 16 evenly spaced columns in coarse steps, recording
; each yes/no into a 16-bit profile — the exact set of lit columns, a hardware
; constant asserted exactly. Step k lands the probe at x = 104 - 6k, so to
; locate a failing bit: its column is 104 - 6k and its PF cell is (104 - 6k)/4
; (taken modulo 20 cells, since the right half repeats the left).
;
;   CODE $01 = low 8 probe columns (steps 0-7) don't match the fingerprint
;        $02 = high 8 probe columns (steps 8-15) don't match the fingerprint
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 2-byte collision bitfield ($90 lo, $91 hi)
IDX     = $92                   ; sweep index 0..STEPS-1
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF              ; playfield colour (irrelevant; only lit/unlit matters)
        lda #$02
        sta ENAM0              ; enable a 1px probe missile (NUSIZ0 = 0)
        lda #$00
        sta CTRLPF             ; no reflect: right half repeats the left

        lda #$50               ; distinctive pattern across the three registers
        sta PF0
        lda #$C3
        sta PF1
        lda #$A5
        sta PF2

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        lda #$00
        sta PROFILE             ; profile = 0000_0000_0000_0000
        sta PROFILE+1

        ldx #0                  ; x = step index k, 0..15
.sweep:
        stx IDX
        sta WSYNC               ; anchor the strobe to a fresh scanline
        txa                     ; VEC = Sled + k  (skip k of the 16 NOPs)
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)               ; land k NOPs into the sled
Sled:
        REPEAT STEPS
        nop                    ; each skipped NOP = 2 cycles = 6 colour clocks
        REPEND
        sta RESM0              ; strobe missile to x = 104 - 6k

        sta CXCLR              ; clear all collision latches
        jsr latch              ; render two beam-on lines so the overlap latches
        lda CXM0FB
        and #$80               ; isolate the M0-PF collision bit
        beq .miss              ; column dark -> record a 0

        lda IDX                ; column lit: set bit (k mod 8) of the profile
        and #$07
        tay
        lda Bit,y              ; A = 1 << (k mod 8)
        ldx IDX
        cpx #8
        bcc .lo                ; steps 0-7 -> low byte, 8-15 -> high byte
        ora PROFILE+1
        sta PROFILE+1
        jmp .next
.lo:
        ora PROFILE
        sta PROFILE
        jmp .next
.miss:
        nop
.next:
        ldx IDX                ; k += 1; loop until all 16 columns probed
        inx
        cpx #STEPS
        bne .sweep

        ASSERT_EQ PROFILE,   $52, $01   ; lit-column fingerprint of the PF pattern
        ASSERT_EQ PROFILE+1, $47, $02
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X (index in
; IDX).
latch:
        ldx #2
.ll:
        sta WSYNC
        dex
        bne .ll
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
