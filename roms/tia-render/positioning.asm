; positioning — a movable object's horizontal position is fixed by the CPU
; cycle on which its reset strobe is written; the TIA has no X register.
;
; The TIA gives each of its five movable objects (players 0 and 1, missiles 0
; and 1, the ball) a horizontal counter that free-runs in step with the beam,
; one count every four colour clocks. There is nowhere to write an X position.
; Instead, writing an object's reset strobe (RESP0 for player 0) clears that
; counter at the moment of the write, so the object begins its copy wherever
; the beam stands right then. The CPU clock is the colour clock divided by
; three, so each extra CPU cycle of delay before the strobe lands the object
; three colour clocks — three pixels — further right. This test uses only the
; strobe; the separate HMOVE fine-motion mechanism is not involved.
;
; The test sweeps the strobe and watches where the object lands. The probe is a
; solid 8px player P0; the reference is a fixed 32px quad-width player P1,
; strobed once near mid-line and left there. The probe's strobe is swept across
; the line in 16 coarse steps, and after each one the P0/P1 collision latch
; (CXPPMM bit 7) says whether the probe overlapped the reference on that step.
; The 16 answers are packed into a 16-bit profile. The hits form one contiguous
; run; its two edges pin the first and last strobe step at which the objects
; touch, so a one-step positioning error shifts an edge and changes the profile.
; A player is the reference rather than the playfield because the playfield's
; right half repeats its left, which would add a second false overlap.
;
;   CODE $01 = low half of the overlap profile wrong (strobe steps 0-7): the
;              probe's landing position is off at the run's low edge
;        $02 = high half wrong (steps 8-15): off at the run's high edge
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
        sta COLUP0              ; both players white (colour is irrelevant here;
        sta COLUP1              ; only their overlap is measured)
        lda #$FF
        sta GRP0                ; solid 8px player (the swept probe)
        sta GRP1                ; solid reference player
        lda #$00
        sta NUSIZ0             ; probe: one copy, 8px wide
        lda #$07
        sta NUSIZ1             ; reference: quad size, one 32px-wide copy

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; fixed reference span near mid-line (the run straddles it)
        sta WSYNC
        SLEEP 34
        sta RESP1

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ldx #0
.sweep:
        stx IDX
        sta WSYNC               ; fresh scanline: strobe timing measured from here
        txa                     ; jump target = Sled + IDX; a higher index skips
        clc                     ; more nops (strobes earlier) -> probe moves left
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)              ; run (STEPS - IDX) nops, then strobe
Sled:
        REPEAT STEPS
        nop                    ; each skipped nop = 2 cycles = 6 colour clocks
        REPEND
        sta RESP0              ; strobe: probe lands at x = 105 - 6*IDX

        sta CXCLR              ; clear latches, then draw so this step's overlap
        jsr latch              ; latches fresh (two beam-on lines)
        lda CXPPMM
        and #$80               ; P0-P1 collision bit: did probe touch reference?
        beq .miss

        lda IDX                ; hit: set bit IDX in the 16-bit PROFILE
        and #$07
        tay
        lda Bit,y
        ldx IDX
        cpx #8
        bcc .lo
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
        ldx IDX
        inx
        cpx #STEPS
        bne .sweep

        ; contiguous run at strobe steps 5..10 — the 8px probe overlapping the
        ; 32px reference as it sweeps leftward across it, onset/offset pinned:
        ; step k parks the probe's first pixel at x = 105 - 6k, and the fixed
        ; quad reference spans x = [49..81), so exactly those six steps touch.
        ASSERT_EQ PROFILE,   $E0, $01   ; low 8: bits 5,6,7
        ASSERT_EQ PROFILE+1, $07, $02   ; high 8: bits 0,1,2 (positions 8,9,10)
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the statically-positioned objects to latch.
; Clobbers X (the sweep index lives in IDX).
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
