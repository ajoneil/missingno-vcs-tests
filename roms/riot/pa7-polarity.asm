; pa7-polarity — selecting a PA7 edge polarity never sets the edge flag by
; itself: only a genuine pin transition of the armed polarity does.
;
; The RIOT (the 6532 "RAM-I/O-Timer" chip) watches bit 7 of port A (the pin
; named PA7) with an edge detector and latches bit 6 of the interrupt flag
; register (named TIMINT) on a transition of the armed polarity. The polarity is
; chosen by the WRITE address — $284 arms the negative (high->low) edge, $285
; the positive (low->high). The select write only arms the detector; it does NOT
; act as an edge, so the flag stays clear no matter what level PA7 already sits
; at when the polarity is chosen. (The defensive TIMINT read software performs
; after a polarity change clears a flag left over from EARLIER pin activity, not
; one induced by the write itself.)
;
; pa7-edge covers genuine pin transitions; this test pins down the select write
; as a (polarity x level) matrix. PA7 is driven from the CPU by making it an
; output (port-A direction register SWACNT bit 7 = 1, pin then follows the
; output register SWCHA):
;   A  PA7 high, select positive   -> flag clear
;   B  PA7 high, select negative   -> flag clear
;   C  PA7 low,  select positive   -> flag clear
;   D  PA7 low,  select negative   -> flag clear
; plus controls that pin down the ordinary detector, so a clear is meaningful:
;   E  a genuine active-direction PA7 edge      -> set
;   F  a genuine wrong-direction PA7 edge       -> clear
;   G  read TIMINT, read again with no new edge -> clear (a flag read clears it)
;   H  a same-polarity re-write, pin static     -> flag clear (recorded + asserted
;      with the matrix: no select write disturbs the flag)
;
; The full A-H matrix is hardware-measured: real PAL console, 2026-07-16,
; OBSERVED = $10 (only E set). A datasheet reading under which the select write
; acts as if the newly armed edge had just landed (setting the flag when PA7
; already sits at the post-edge level — cells A and D) is CONTRADICTED by that
; measurement. On a pass, OBSERVED ($82) packs the A..H results (bit0=A ..
; bit7=H) and the green pass screen displays that byte in white hex digits
; (pass_result_observed), so the matrix stays readable on a real console, where
; RAM is invisible.
;
;   CODE $01 = A: PA7 high, select positive set the flag
;        $02 = B: PA7 high, select negative set the flag
;        $03 = C: PA7 low,  select positive set the flag
;        $04 = D: PA7 low,  select negative set the flag
;        $05 = E: a genuine active-direction edge did not set (control)
;        $06 = F: a genuine wrong-direction edge set (control)
;        $07 = G: the second flag read did not leave it clear (control)
;        $08 = H: a same-polarity re-write set the flag
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PA7_NEG = $0284                 ; write: select negative (high->low) edge detect
PA7_POS = $0285                 ; write: select positive (low->high) edge detect

S       = $90                   ; S..S+7: masked TIMINT bit-6 samples, cells A..H

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$80
        sta SWACNT              ; PA7 = output (follows SWCHA bit 7), PA0-6 input

        ; Each cell drives PA7, reads TIMINT to clear the flag (so any edge from
        ; the level change is gone), performs the select under test, then samples
        ; bit 6. The armed polarity persists from one cell to the next.

        ; A: PA7 high, select positive -> clear (high is positive's post-edge level)
        lda #$80
        sta SWCHA               ; drive PA7 high
        lda TIMINT              ; read-to-clear
        sta PA7_POS             ; select positive: PA7 is high -> no set
        lda TIMINT
        and #$40
        sta S+0

        ; B: PA7 still high, select negative -> clear (high is negative's pre-edge)
        lda TIMINT              ; read-to-clear
        sta PA7_NEG             ; select negative: PA7 is high -> no set
        lda TIMINT
        and #$40
        sta S+1

        ; C: PA7 low, select positive -> clear (low is positive's pre-edge)
        lda #$00
        sta SWCHA               ; drive PA7 low
        lda TIMINT              ; read-to-clear (also clears the high->low edge)
        sta PA7_POS             ; select positive: PA7 is low -> no set
        lda TIMINT
        and #$40
        sta S+2

        ; D: PA7 still low, select negative -> clear (low is negative's post-edge level)
        lda TIMINT              ; read-to-clear
        sta PA7_NEG             ; select negative: PA7 is low -> no set
        lda TIMINT
        and #$40
        sta S+3

        ; E: arm positive, PA7 low, clear, then drive low->high (genuine edge) -> set
        sta PA7_POS             ; arm positive (PA7 low: no write-induced set)
        lda #$00
        sta SWCHA               ; hold PA7 low
        lda TIMINT              ; read-to-clear
        lda #$80
        sta SWCHA               ; PA7 low -> high: the armed positive edge
        lda TIMINT
        and #$40
        sta S+4

        ; F: PA7 high under positive, clear, drive high->low (wrong direction) -> clear
        lda TIMINT              ; read-to-clear
        lda #$00
        sta SWCHA               ; PA7 high -> low: wrong direction while POS armed
        lda TIMINT
        and #$40
        sta S+5

        ; G: drive an active edge to set, read (clears), read again (no edge) -> clear
        lda #$80
        sta SWCHA               ; PA7 low -> high: sets the positive-edge flag
        lda TIMINT              ; this read samples the set flag and clears it
        lda TIMINT
        and #$40
        sta S+6

        ; H: arm negative, drive PA7 low (genuine edge), clear, then re-write the
        ;    same select with PA7 static at low (post-edge level) -> stays clear
        sta PA7_NEG             ; arm negative (PA7 high here: no write set)
        lda #$00
        sta SWCHA               ; drive PA7 low: the genuine negative edge (sets)
        lda TIMINT              ; read-to-clear that genuine edge
        sta PA7_NEG             ; re-write the same polarity, PA7 unchanged
        lda TIMINT
        and #$40
        sta S+7

        ; --- controls: the ordinary edge detector, asserted unconditionally
        ASSERT_EQ S+4, $40, $05
        ASSERT_EQ S+5, $00, $06
        ASSERT_EQ S+6, $00, $07

        ; --- matrix A-D + H: no select write sets the flag (hardware-measured)
        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $00, $02
        ASSERT_EQ S+2, $00, $03
        ASSERT_EQ S+3, $00, $04
        ASSERT_EQ S+7, $00, $08

        ; pack A..H (bit0=A .. bit7=H) into OBSERVED for the characterisation read
        lda #$00
        ldx #7
.pack:
        asl
        ldy S,x
        beq .zero
        ora #$01
.zero:
        dex
        bpl .pack
        sta OBSERVED

RS_PASS_OBSERVED = 1            ; pass screen shows OBSERVED (the A..H matrix)

        lda #$00
        sta CODE
        lda #PASS_MAGIC
        sta RESULT
        jmp pass_result_observed

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
