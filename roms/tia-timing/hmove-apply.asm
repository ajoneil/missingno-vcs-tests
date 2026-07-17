; hmove-apply — strobing HMOVE moves an object for every nonzero motion value,
; and HMCLR cancels a move that has not yet been strobed.
;
; Each movable TIA object has a horizontal-motion register holding a signed
; amount in its high nibble; strobing HMOVE shifts the object by that amount.
; This test checks something coarser than the exact distance: that HMOVE moves
; the object at all, for each of the 16 possible values. When two 1-pixel
; missiles sit on the exact same column the TIA records an M0-M1 overlap in the
; collision register CXPPMM (the overlap is reported on bit 6); shift M0 by even
; a single pixel and the overlap is gone. The latch therefore reports whether an
; object moved at all, without measuring how far.
;
; The test parks M1 mid-line as a fixed reference. For each of the 16 HMM0
; values ($00,$10,..,$F0) it re-places M0 exactly on M1, strobes HMOVE, and
; records whether the M0-M1 overlap is still latched. The 16 yes/no answers are
; packed into a 16-bit profile (one bit per value). Only $00 — zero motion —
; leaves the missiles overlapping, so the profile must be exactly $0001: HMOVE
; moved the object for all fifteen nonzero values, no matter the amount.
;
; A final case checks HMCLR. HMCLR zeroes every motion register, so loading
; HMM0=$70 and then striking HMCLR before HMOVE leaves nothing to apply: M0
; stays put and the overlap survives, proving the pending move was cancelled.
;
;   CODE $01 = motion profile low byte (values $00-$70) wrong: some value in
;              this half either failed to move M0, or $00 moved it
;        $02 = motion profile high byte (values $80-$F0) wrong, same reading
;        $03 = HMM0=$70 then HMCLR, then HMOVE: M0 moved anyway (overlap lost),
;              so HMCLR did not cancel the pending move
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; 2-byte motion bitfield ($90 lo, $91 hi)
HMIDX   = $92                   ; HM-value sweep index 0..15
SCRATCH = $93

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$42
        sta COLUP0             ; M0 colour (irrelevant to the collision)
        lda #$C4
        sta COLUP1             ; M1 colour
        lda #$02
        sta ENAM0
        sta ENAM1              ; enable M0 and M1, both width 1px

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; M1 = fixed reference near px 40
        sta WSYNC
        SLEEP 31
        sta RESM1

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ldx #0
.hmloop:
        stx HMIDX
        jsr colocate_m0        ; re-place M0 exactly on M1 (same strobe delay)

        txa                    ; HMM0 = HMIDX << 4 (value $00,$10,..,$F0)
        asl
        asl
        asl
        asl
        sta HMM0
        sta WSYNC
        sta HMOVE              ; apply this value's motion to M0

        sta CXCLR              ; clear collision latches, then let the overlap latch
        jsr latch
        lda CXPPMM
        and #$40               ; CXPPMM bit 6 = M0-M1 overlap
        beq .next              ; no overlap -> M0 moved: leave this value's bit clear

        ; overlap survived -> set this value's bit in the 16-bit profile
        lda HMIDX
        and #$07
        tay
        lda Bit,y              ; bit for value index HMIDX (mod 8)
        ldx HMIDX
        cpx #8
        bcc .lo                ; values $00-$70 -> low byte, $80-$F0 -> high byte
        ora PROFILE+1
        sta PROFILE+1
        jmp .next
.lo:
        ora PROFILE
        sta PROFILE
        jmp .next
.next:
        ldx HMIDX
        inx
        cpx #16
        bne .hmloop

        ASSERT_EQ PROFILE,   $01, $01   ; only HMM0=$00 (bit 0) keeps them together
        ASSERT_EQ PROFILE+1, $00, $02   ; no value $80-$F0 leaves them overlapping

        ; --- HMM0 = +7, then HMCLR before HMOVE: the move is cancelled, M0
        ;     stays on M1, and the overlap survives ---
        jsr colocate_m0        ; M0 back onto M1
        lda #$70
        sta HMM0               ; arm a +7 (left) move...
        sta HMCLR              ; ...then wipe all motion registers to zero
        sta WSYNC
        sta HMOVE              ; nothing left to apply -> M0 does not move
        sta CXCLR
        jsr latch
        lda CXPPMM
        and #$40               ; M0-M1 overlap still latched?
        sta SCRATCH
        ASSERT_EQ SCRATCH, $40, $03     ; $40 = overlap held: HMCLR cancelled the move

        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; place M0 co-located with M1 (same strobe delay). Uses only A; preserves X.
colocate_m0:
        sta WSYNC
        SLEEP 31
        sta RESM0
        rts

; two beam-on lines: enough for the static overlap to latch. Clobbers X.
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
