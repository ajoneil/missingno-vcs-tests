; vertical-delay — each player's graphics are double-buffered: writing GRP0
; fills a "new" latch, writing GRP1 copies "new" into an "old" latch, and the
; VDELP0 flag picks which latch is drawn. This is the mechanism two-line sprite
; kernels are built on.
;
; Player 0 has two 8-bit graphics latches, "new" and "old". Writing the
; player's own graphics register (GRP0) loads its new latch. The copy from new
; into old is triggered by writing the OTHER player's graphics register: a
; write to GRP1 loads player 1's new latch and, as a side effect, snapshots
; player 0's new latch into player 0's old latch (and symmetrically, a GRP0
; write snapshots player 1's). Which latch actually reaches the screen is
; chosen by the vertical-delay flag VDELP0: clear draws the new latch, set
; draws the old one. A two-line kernel uses this to keep last line's shape on
; screen while it stages the next line into the new latch.
;
; The test loads two tell-apart shapes into the two latches, then reads the
; drawn shape back out of the TIA one column at a time: old = $F0 (a quad
; player's left half), new = $0F (its right half). A 1px missile M1 is swept
; across the player in coarse steps, and the M1/P0 collision latch (CXM1P bit 7)
; records, per step, which player columns are opaque — a fingerprint of the
; shape on screen. The sweep runs twice: once with VDELP0 set (must fingerprint
; the old shape $F0) and once clear (must fingerprint the new shape $0F); both
; 16-bit profiles are asserted whole.
;
; The quad player spans x = [19..51), four pixels per graphics bit, most
; significant bit leftmost — so bits 7..4 ($F0) paint x = [19..35) and bits 3..0
; ($0F) paint x = [35..51).
;
;   CODE $01 = VDELP0 set: old-shape ($F0) profile wrong in steps 0-7
;        $02 = VDELP0 set: old-shape ($F0) profile wrong in steps 8-15
;        $03 = VDELP0 clear: new-shape ($0F) profile wrong in steps 0-7
;        $04 = VDELP0 clear: new-shape ($0F) profile wrong in steps 8-15
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 4 bytes: 2 per VDELP0 state ($90..$93)
PHASE   = $94                   ; 0 = VDEL on (old), 1 = VDEL off (new)
IDX     = $95                   ; probe-sweep index
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUP0              ; player white (colour is irrelevant; only the
                               ; player/missile overlap is measured)
        lda #$07
        sta NUSIZ0             ; quad P0: each GRP0 bit = 4px, one 32px copy
        lda #$00
        sta NUSIZ1             ; M1 probe: 1px
        lda #$02
        sta ENAM1              ; enable missile 1 (the sweeping probe)

        ; double-buffer: old = $F0, new = $0F
        lda #$F0
        sta GRP0               ; new latch = $F0
        lda #$00
        sta GRP1               ; copies GRP0 new -> old (old = $F0); P1 blank
        lda #$0F
        sta GRP0               ; new latch = $0F (old still $F0)

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        sta WSYNC
        SLEEP 24
        sta RESP0              ; player base near the left

        ldx #3                 ; clear the 4 profile bytes
        lda #0
.clr:
        sta PROFILE,x
        dex
        bpl .clr

        ldx #0
.phaseloop:
        stx PHASE
        txa
        eor #$01
        sta VDELP0             ; phase 0 -> VDELP0=1 (draw old); phase 1 -> 0 (new)
        ldx #0
.sweep:
        stx IDX
        sta WSYNC               ; fresh scanline: strobe timing measured from here
        txa                     ; jump target = Sled + IDX; a higher index skips
        clc                     ; more nops (strobes earlier) -> missile moves left
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
        sta RESM1              ; probe missile lands at x = 104 - 6*IDX

        sta CXCLR              ; clear latches, then draw so this step's overlap
        jsr latch              ; latches fresh (two beam-on lines)
        lda CXM1P
        and #$80               ; M1-P0 collision bit: is this column opaque?
        beq .next

        lda IDX                ; set bit IDX of PROFILE[PHASE*2 + IDX/8]
        and #$07
        tay
        lda Bit,y
        pha
        lda PHASE
        asl
        ldx IDX
        cpx #8
        bcc .lo
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
        bne .sweep

        ldx PHASE
        inx
        cpx #2
        bne .phaseloop

        ASSERT_EQ PROFILE+0, $00, $01   ; VDEL on: old $F0 fingerprint, no hits 0-7
        ASSERT_EQ PROFILE+1, $70, $02   ; ...bits 4,5,6 = steps 12,13,14 (x 19..35)
        ASSERT_EQ PROFILE+2, $00, $03   ; VDEL off: new $0F fingerprint, no hits 0-7
        ASSERT_EQ PROFILE+3, $0E, $04   ; ...bits 1,2,3 = steps 9,10,11 (x 35..51)
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X (indices
; in PHASE/IDX).
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
