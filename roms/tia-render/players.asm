; players — a player sprite's 8 graphics bits are painted most-significant bit
; first, at the left.
;
; The TIA (the console's video chip) draws two "player" sprites, each held in an
; 8-bit graphics register: GRP0 for player 0, GRP1 for player 1. When the
; electron beam reaches a player's horizontal position, the TIA shifts those 8
; bits out one per pixel, painting the player's colour (from COLUP0) wherever a
; bit is 1 and leaving the pixel transparent wherever it is 0. The bit order is
; fixed: bit 7 is drawn at the left edge, bit 0 at the right. A companion
; register, NUSIZ0, can stretch each graphics bit to 2 or 4 pixels wide; here the
; player runs at quad width, so each of the 8 bits becomes a 4-pixel column and
; the whole sprite is 32 pixels across.
;
; A self-test has no screen to inspect, so it reads the player's shape through the
; missile-versus-player collision latch (CXM1P bit 7), probed by a 1-pixel
; missile 1.
;
; The probe is swept across the line in sixteen coarse steps, building a 16-bit
; profile of which columns it found lit. The player carries the deliberately
; asymmetric pattern GRP0 = $B4 (1011 0100), painted MSB-first at 4px per bit and
; spanning x = [37..69). Its lit columns sit at fixed positions, so the swept
; probe returns a hardware-constant fingerprint. Only two steps land inside a lit
; column: step 9 at x=50 (bit 4) and step 11 at x=38 (bit 7); every other step
; misses. The expected profile is low byte $00, high byte $0A. A decoder
; that paints the bits LSB-first, or that misplaces the sprite, produces a
; different fingerprint.
;
;   CODE $01 = low 8 probe positions wrong  (steps 0-7,  x 104..62)
;        $02 = high 8 probe positions wrong (steps 8-15, x 56..14)
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
        sta COLUP0              ; player colour (any lit pixel shows this)
        lda #$B4               ; asymmetric pattern 1011 0100 (MSB-left check)
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

        lda #$00
        sta PROFILE            ; profile = 0000: no lit columns found yet
        sta PROFILE+1

        ldx #0                 ; step index 0..15
.sweep:
        stx IDX
        sta WSYNC              ; fresh scanline for this probe position
        txa                    ; VEC = Sled + step: entry point skips `step` NOPs
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
        beq .miss              ; no overlap -> leave the profile bit clear

        lda IDX                ; hit: OR bit (step & 7) into the profile...
        and #$07
        tay
        lda Bit,y
        ldx IDX
        cpx #8
        bcc .lo                ; steps 0-7 -> low byte, steps 8-15 -> high byte
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
        bne .sweep             ; next probe position

        ASSERT_EQ PROFILE,   $00, $01   ; steps 0-7: no lit column found
        ASSERT_EQ PROFILE+1, $0A, $02   ; steps 8-15: bits 1,3 = steps 9,11 lit
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
