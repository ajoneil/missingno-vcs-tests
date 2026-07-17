; hmove-walk — each HMOVE strobe applies the motion value once, so repeated
; strobes walk an object cumulatively.
;
; A movable TIA object holds a horizontal-motion amount in its motion register,
; and strobing HMOVE shifts the object by that amount. The shift happens once
; per strobe: the register is not consumed, so striking HMOVE again on the next
; line applies the same amount again, and the object marches across the screen
; a fixed step at a time. This test uses HMM0=$80, whose signed nibble is -8, so
; each strobe moves missile 0 eight pixels to the right.
;
; Rather than trust one large overshoot to land inside a target, the test sweeps
; the STROBE COUNT. For k = 1..12 it resets M0 to a fixed start near the left,
; strobes HMOVE k times on k successive lines, and records whether M0 has by
; then walked into a fixed white playfield block spanning pixels 64-79. A hit is
; read from the collision register CXM0FB, which latches an M0-vs-playfield
; overlap on bit 7. The 12 yes/no answers are packed into a profile, one bit per
; k. The missile starts near pixel 14 and steps a clean 8 pixels per strobe, and
; the block is 16 pixels — two steps — wide, so exactly two strobe counts land
; M0 inside it: k = 7 and k = 8 hit, every other k falls short or overshoots.
; Pinning the hits to specific k values ties both the per-strobe amount and its
; accumulation to the step count.
;
;   CODE $01 = walk-onset profile low byte (k = 1..8) wrong: the hit run is not
;              at k = 7,8 — a wrong per-strobe amount, or motion that does not
;              accumulate across strobes, moves it
;        $02 = walk-onset profile high byte (k = 9..12) wrong: M0 registered a
;              hit past the block it should have overshot
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; 2-byte collision bitfield ($90 lo, $91 hi)
KCOUNT  = $92                   ; sweep index J (0..STEPS-1); strobe count = J+1
STEPS   = 12

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF             ; playfield white
        lda #$02
        sta ENAM0              ; enable M0, width 1px
        lda #$F0
        sta PF2                ; PF2 top nibble -> cells 16-19 solid -> px 64-79 block

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ldx #0
.kloop:
        stx KCOUNT

        ; reset M0 to a fixed start near px 14 (left of the block, and clear of
        ; the 8px HMOVE comb — the blanked left-edge tab each strobed line
        ; leaves). start + k*8: k=6 -> 62 falls short, k=7 -> 70 and k=8 -> 78
        ; land inside the 64-79 block, k=9 -> 86 overshoots it.
        sta WSYNC
        SLEEP 23
        sta RESM0

        ; strobe HMOVE (J+1) times, -8 each -> M0 walks 8px right per strobe
        lda #$80
        sta HMM0               ; motion value -8 (8px right per apply)
        ldy KCOUNT
        iny                    ; Y = J+1 = strobe count k
.hm:
        sta WSYNC
        sta HMOVE              ; one step: +8px right
        dey
        bne .hm

        sta CXCLR              ; clear latches, then let any overlap latch
        jsr latch
        lda CXM0FB
        and #$80               ; CXM0FB bit 7 = M0-playfield overlap
        beq .next              ; no hit -> leave this k's bit clear

        ; hit -> set this k's bit in the 12-bit profile
        lda KCOUNT
        and #$07
        tay
        lda Bit,y              ; bit for k index KCOUNT (mod 8)
        ldx KCOUNT
        cpx #8
        bcc .lo                ; k = 1..8 -> low byte, k = 9..12 -> high byte
        ora PROFILE+1
        sta PROFILE+1
        jmp .next
.lo:
        ora PROFILE
        sta PROFILE
        jmp .next
.next:
        ldx KCOUNT
        inx
        cpx #STEPS
        bne .kloop

        ASSERT_EQ PROFILE,   $C0, $01   ; hits only at k = 7,8 (bits 6,7)
        ASSERT_EQ PROFILE+1, $00, $02   ; no hit at k = 9..12 (walked past)
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X (index in
; KCOUNT). HMCLR not needed — M0 is repositioned with RESM0 each iteration.
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
