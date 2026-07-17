; player-reflect — setting bit 3 of REFP0 mirrors a player sprite left-to-right,
; so its 8 graphics bits paint least-significant bit first.
;
; The TIA (the console's video chip) draws a "player" sprite by shifting the 8
; bits of its graphics register GRP0 out one per pixel: normally bit 7 lands at
; the left edge and bit 0 at the right. Writing REFP0 with bit 3 set flips this —
; the sprite is mirrored, so bit 0 is drawn at the left and bit 7 at the right.
; The pixels, colour and position are otherwise unchanged; only the left-to-right
; order of the pattern reverses. Here the sprite runs at quad width, so each of
; the 8 bits is a 4-pixel column and the sprite is 32 pixels across.
;
; A self-test has no screen to inspect, so it reads the sprite's shape through the
; missile-versus-player collision latch (CXM1P bit 7), probed by a 1-pixel
; missile 1.
;
; The probe is swept across the line in sixteen coarse steps, building a 16-bit
; profile of which columns it found lit. The whole sweep is run twice on the
; asymmetric pattern GRP0 = $B4 (1011 0100), spanning x = [37..69): once with
; REFP0 off and once on. Painted MSB-first, two probes hit — step 9 (x=50, bit 4)
; and step 11 (x=38, bit 7) — for a profile of low byte $00, high byte $0A.
; Reflected, the pattern reverses about the sprite's centre and different columns
; light: step 6 (x=68) and step 8 (x=56) hit, for low byte $40, high byte $01.
; Both profiles are hardware constants, asserted exactly. A decoder that ignores
; bit 3 produces the MSB-first profile in both passes.
;
;   CODE $01/$02 = REFP-off profile low/high byte wrong (expected $00 / $0A)
;        $03/$04 = REFP-on  profile low/high byte wrong (expected $40 / $01)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 4 bytes: 2 per REFP0 state ($90..$93)
PHASE   = $94                   ; 0 = REFP off, 1 = REFP on
IDX     = $95                   ; probe-sweep index
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUP0              ; player colour (any lit pixel shows this)
        lda #$B4               ; asymmetric pattern 1011 0100
        sta GRP0
        lda #$07
        sta NUSIZ0             ; quad P0: each bit 4px, 32px total
        lda #$00
        sta NUSIZ1             ; missile 1 at its narrowest: 1px probe
        lda #$02
        sta ENAM1              ; enable missile 1 (the swept probe)

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        sta WSYNC
        SLEEP 30
        sta RESP0              ; anchor the player, centred in the sweep

        ldx #3                 ; clear the 4 profile bytes (2 per phase)
        lda #0
.clr:
        sta PROFILE,x
        dex
        bpl .clr

        ldx #0                 ; phase 0 = REFP off, phase 1 = REFP on
.phaseloop:
        stx PHASE
        txa
        asl
        asl
        asl                    ; phase*8 -> $00 (off) or $08 (REFP0 bit 3 set)
        sta REFP0              ; select mirror off / on for this sweep
        ldx #0                 ; step index 0..15
.sweep:
        stx IDX
        sta WSYNC              ; fresh scanline for this probe position
        txa                    ; VEC = Sled + step: entry skips `step` NOPs
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)              ; jump `step` NOPs into the sled
Sled:
        REPEAT STEPS
        nop                    ; each skipped NOP = 2 cycles = 6 colour clocks
        REPEND
        sta RESM1              ; strobe missile to x = 104 - 6*step

        sta CXCLR              ; clear the collision latches
        jsr latch              ; hold 2 beam-on lines so the overlap latches
        lda CXM1P
        and #$80               ; missile-1-vs-player-0: was this column lit?
        beq .next              ; no overlap -> leave the profile bit clear

        lda IDX                ; hit: OR bit (step&7) into PROFILE[phase*2 + step/8]
        and #$07
        tay
        lda Bit,y
        pha
        lda PHASE
        asl                    ; phase*2 selects this phase's byte pair
        ldx IDX
        cpx #8
        bcc .lo                ; steps 0-7 -> low byte, steps 8-15 -> +1 high byte
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
        bne .sweep             ; next probe position

        ldx PHASE
        inx
        cpx #2
        bne .phaseloop         ; second sweep with the mirror on

        ASSERT_EQ PROFILE+0, $00, $01   ; REFP off: steps 0-7, no lit column
        ASSERT_EQ PROFILE+1, $0A, $02   ; REFP off: steps 9,11 lit (bits 4,7)
        ASSERT_EQ PROFILE+2, $40, $03   ; REFP on:  step 6 lit (mirrored bit 7)
        ASSERT_EQ PROFILE+3, $01, $04   ; REFP on:  step 8 lit (mirrored bit 4)
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
