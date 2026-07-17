; missile-copies — the NUSIZ copy modes replicate a player's missile alongside
; it, but the double/quad player-width modes leave the missile unstretched.
;
; The TIA (the console's video chip) pairs each 8-bit player sprite with a
; missile: a solid bar 1, 2, 4 or 8 pixels wide, the width picked by bits 4-5
; of the player's NUSIZ0 register. The low 3 bits of the same register select
; the player's layout — one, two or three copies at close/medium/wide spacing,
; or one double/quad-width copy (the eight modes are tabulated in nusiz.asm) —
; and those same 3 bits drive the missile's copy circuit too: a mode that
; draws two or three player copies draws the missile two or three times, at
; the same +16/+32/+64 pixel spacings. The stretch modes are where the two
; objects part ways: modes 5 and 7 double or quadruple the player's pixels,
; but a missile has no stretch circuit — in those modes it draws a single
; copy, at the same position and width as mode 0. A missile's width comes only
; from bits 4-5, in every mode.
;
; A self-test has no screen to inspect, so it reads missile 0's shape through
; the missile-versus-missile collision latch (CXPPMM bit 6), probed by a
; 1-pixel missile 1 (M1).
;
; Part 1 maps the copies. Missile 0, at the full 8-pixel width, is anchored
; with its main copy at x = 17-24, and the probe is swept across the line in
; coarse steps, building a 16-bit profile of lit columns. All eight copy modes
; are swept and asserted against their hardware-constant values. Extra copies
; repeat at +16/+32/+64 from the main copy, and modes 5 and 7 must produce
; byte-for-byte the profile of mode 0: one copy, nothing stretched.
;
; Part 2 pins the no-stretch rule at 1-pixel resolution, finer than the
; sweep's grid. M1 is re-parked one pixel right of missile 0 as a stationary
; ruler at x=18. A 1-pixel missile 0 at x=17 never touches it — in mode 0 and
; equally in modes 5 and 7, whereas a missile that inherits any width at all
; from the player size bits covers x=18 and trips the latch. An 8-pixel
; missile in the same stretch modes must reach it, showing bits 4-5 still set
; the width there. Finally the ruler is walked one more pixel left, onto the
; missile, and must collide — confirming it really sat one pixel away, so the
; clear results measured a 1-pixel missile and not an oversized gap.
;
;   CODE $01..$10 = a copy mode's sweep profile is wrong. Two codes per mode,
;   in mode order starting at mode 0: the first of each pair is that mode's
;   steps 0-7, the second its steps 8-15.
;        $11 = baseline 1px missile (mode 0) reached the +1px ruler
;        $12 = mode 5 (double player) stretched the 1px missile
;        $13 = mode 7 (quad player) stretched the 1px missile
;        $14 = 8px missile in mode 5 failed to reach the ruler
;        $15 = 8px missile in mode 7 failed to reach the ruler
;        $16 = ruler shifted onto the missile did not collide
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 16 bytes ($90..$9F): 2 per copy mode
MODE    = $A0                   ; current NUSIZ0 copy mode 0..7
IDX     = $A1                   ; probe-sweep index 0..STEPS-1
SCRATCH = $A2
STEPS   = 16

; M0M1_IS expected, failcode
;   read the missile-0-vs-missile-1 collision latch (CXPPMM bit 6) and assert
;   it equals {1} ($40 = touched, $00 = clear).
        MAC M0M1_IS
        lda CXPPMM
        and #$40
        sta SCRATCH
        ASSERT_EQ SCRATCH, {1}, {2}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$02
        sta ENAM0               ; missile 0: the object under test
        sta ENAM1               ; missile 1: the 1px probe (NUSIZ1 = 0)
        lda #$0E
        sta COLUP0              ; light both missiles (legible on hardware)
        sta COLUP1

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        sta WSYNC
        SLEEP 24
        sta RESM0               ; anchor M0's main copy at x=17

        ldx #15                 ; clear the 16 profile bytes (2 per mode)
        lda #0
.clr:
        sta PROFILE,x
        dex
        bpl .clr

        ; --- part 1: sweep the probe across all eight copy modes ---
        ldx #0                  ; mode 0..7
.modeloop:
        stx MODE
        txa
        ora #$30
        sta NUSIZ0              ; copy mode under test + 8px missile width
        ldx #0                  ; step index 0..15
.sweep:
        stx IDX
        sta WSYNC               ; fresh scanline for this probe position
        txa                     ; VEC = Sled + step: entry skips `step` NOPs
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)               ; jump `step` NOPs into the sled
Sled:
        REPEAT STEPS
        nop                     ; each skipped NOP = 2 cycles = 6 colour clocks
        REPEND
        sta RESM1               ; strobe the probe to x = 104 - 6*step

        sta CXCLR               ; clear the collision latches
        jsr latch               ; hold 2 beam-on lines so the overlap latches
        lda CXPPMM
        and #$40                ; missile-0-vs-missile-1: was this column lit?
        beq .next               ; no overlap -> leave the profile bit clear

        lda IDX                 ; hit: OR bit (step&7) into PROFILE[mode*2 + step/8]
        and #$07
        tay
        lda Bit,y
        pha
        lda MODE
        asl                     ; mode*2 selects this mode's byte pair
        ldx IDX
        cpx #8
        bcc .lo                 ; steps 0-7 -> low byte, steps 8-15 -> +1 high byte
        clc
        adc #1
.lo:
        tax
        pla
        ora PROFILE,x
        sta PROFILE,x
.next:
        ldx IDX
        inx
        cpx #STEPS
        bne .sweep              ; next probe position

        ldx MODE
        inx
        cpx #8
        bne .modeloop           ; next copy mode

        ASSERT_EQ PROFILE+0,  $00, $01   ; mode 0  (one copy)
        ASSERT_EQ PROFILE+1,  $40, $02
        ASSERT_EQ PROFILE+2,  $00, $03   ; mode 1  (two copies, +16)
        ASSERT_EQ PROFILE+3,  $48, $04
        ASSERT_EQ PROFILE+4,  $00, $05   ; mode 2  (two copies, +32)
        ASSERT_EQ PROFILE+5,  $43, $06
        ASSERT_EQ PROFILE+6,  $00, $07   ; mode 3  (three copies, +16 +32)
        ASSERT_EQ PROFILE+7,  $4B, $08
        ASSERT_EQ PROFILE+8,  $08, $09   ; mode 4  (two copies, +64)
        ASSERT_EQ PROFILE+9,  $40, $0A
        ASSERT_EQ PROFILE+10, $00, $0B   ; mode 5  (double player: ONE missile copy,
        ASSERT_EQ PROFILE+11, $40, $0C   ;          profile identical to mode 0)
        ASSERT_EQ PROFILE+12, $08, $0D   ; mode 6  (three copies, +32 +64)
        ASSERT_EQ PROFILE+13, $43, $0E
        ASSERT_EQ PROFILE+14, $00, $0F   ; mode 7  (quad player: ONE missile copy,
        ASSERT_EQ PROFILE+15, $40, $10   ;          profile identical to mode 0)

        ; --- part 2: the no-stretch rule at 1-pixel resolution ---
        ; park M1 one pixel right of M0: RESM1 two CPU cycles after the M0
        ; anchor timing lands it at x=23, and an HMOVE walks it 5px left.
        sta WSYNC
        SLEEP 24
        sta RESM0               ; M0 back at x=17 (same anchor as the sweep)
        sta WSYNC
        SLEEP 24
        nop
        sta RESM1               ; M1 at x=23
        lda #$50
        sta HMM1                ; 5px left on the next HMOVE
        sta WSYNC
        sta HMOVE               ; M1 -> x=18, the +1px ruler

        lda #$00
        sta NUSIZ0              ; mode 0, 1px missile: the baseline
        sta CXCLR
        jsr latch
        M0M1_IS $00, $11        ; 1px M0 at 17 does not reach 18

        lda #$05
        sta NUSIZ0              ; double-player mode, missile width still 1
        sta CXCLR
        jsr latch
        M0M1_IS $00, $12        ; no stretch leaks onto the missile

        lda #$07
        sta NUSIZ0              ; quad-player mode, missile width still 1
        sta CXCLR
        jsr latch
        M0M1_IS $00, $13

        lda #$35
        sta NUSIZ0              ; double-player mode + 8px missile width
        sta CXCLR
        jsr latch
        M0M1_IS $40, $14        ; width bits still apply: 17-24 covers 18

        lda #$37
        sta NUSIZ0              ; quad-player mode + 8px missile width
        sta CXCLR
        jsr latch
        M0M1_IS $40, $15

        lda #$10
        sta HMM1
        sta WSYNC
        sta HMOVE               ; ruler 1px further left, onto M0 at x=17
        lda #$00
        sta NUSIZ0              ; back to a 1px missile
        sta CXCLR
        jsr latch
        M0M1_IS $40, $16        ; overlap proves the ruler really sat at +1

        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X
; (indices live in MODE/IDX).
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
