; missiles-ball — the two missiles and the ball switch on and off, and each
; takes one of four widths.
;
; The TIA (Television Interface Adaptor, the console's video/sound chip) draws
; five movable objects on every scanline: two players, their two companion
; missiles, and one ball. A missile is turned on by writing bit 1 of its
; ENAM0 / ENAM1 register (ENAble Missile 0/1); the ball by bit 1 of ENABL
; (ENAble BaLl). A disabled object is simply absent from the line — it lights
; no pixels and cannot take part in any collision.
;
; Each of the three is a solid horizontal bar 1, 2, 4 or 8 colour clocks wide
; (one colour clock = one visible pixel). A missile takes its width from bits
; 4-5 of its player's NUSIZ0 / NUSIZ1 register (Number-SIZe); the ball takes
; its width from bits 4-5 of CTRLPF (ConTRoL PlayField). Those two bits are the
; power-of-two exponent: 00 -> 1px, 01 -> 2px, 10 -> 4px, 11 -> 8px.
;
; The TIA also keeps a set of collision latches, one per pair of objects that
; can overlap. The moment two objects light the same pixel their latch sets,
; and it stays set until CXCLR (Clear Collisions) is strobed (a strobe: any
; write clears it, the value ignored). A self-test has no screen to inspect,
; so it uses those latches as a presence detector: put an object over the
; playfield, then read whether they touched.
;
; Enable is checked over a solid-lit playfield: each object is parked in the
; visible area and enabled; an enabled missile or ball must record a playfield
; collision, a disabled one must record nothing. Width is checked over a
; playfield cleared to a single lit cell — a 4px bar — with each object parked
; 4px to its left. At width 1 the object cannot reach the bar; at width 8 it
; spans the gap and touches it. The playfield's cell grid is 4px wide, so this
; +4px gap separates narrow from wide but cannot tell widths 1, 2 and 4 apart —
; the test checks only the two extremes.
;
;   CODE $01 = missile 0 enabled over solid playfield did not collide
;        $02 = missile 1 enabled over solid playfield did not collide
;        $03 = ball enabled over solid playfield did not collide
;        $04 = missile 0 disabled but still collided
;        $05 = missile 1 disabled but still collided
;        $06 = ball disabled but still collided
;        $07 = width-1 missile 0 wrongly reached the +4px bar
;        $08 = width-8 missile 0 failed to reach the +4px bar
;        $09 = width-1 missile 1 wrongly reached the bar
;        $0A = width-8 missile 1 failed to reach the bar
;        $0B = width-1 ball wrongly reached the bar
;        $0C = width-8 ball failed to reach the bar
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

; COLL_IS coll_reg, expected_top_bit, failcode
;   read collision register {1}, keep only D7 (the "these two touched" bit),
;   and assert it equals {2} ($80 = collided, $00 = clear).
        MAC COLL_IS
        lda {1}                         ; read the collision latch
        and #$80                        ; isolate D7 (object vs playfield)
        sta SCRATCH
        ASSERT_EQ SCRATCH, {2}, {3}     ; assert collided ($80) / clear ($00)
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF

        ; one field of sync, then leave the beam on; each check needs only a
        ; couple of drawn lines to latch, so the whole test fits inside a field.
        jsr vertical_sync
        jsr vblank_lines

        ; park the three objects in the visible area (over solid PF, so exact
        ; position doesn't matter for the enable checks)
        sta WSYNC
        SLEEP 25
        sta RESM0
        sta RESM1
        sta RESBL

        ; --- enabled over a SOLID playfield: all three must collide ---
        lda #$FF
        sta PF0                         ; whole playfield lit: every visible
        sta PF1                         ; pixel is playfield, so any enabled
        sta PF2                         ; object overlaps it
        lda #$02
        sta ENAM0                       ; enable M0/M1/BL (bit 1)
        sta ENAM1
        sta ENABL
        sta CXCLR                       ; clear latches, then draw
        jsr latch
        COLL_IS CXM0FB, $80, $01        ; M0 enabled -> touched playfield
        COLL_IS CXM1FB, $80, $02        ; M1 enabled -> touched playfield
        COLL_IS CXBLPF, $80, $03        ; BL enabled -> touched playfield

        ; --- disabled: none collide ---
        lda #$00
        sta ENAM0                       ; disable all three (bit 1 clear)
        sta ENAM1
        sta ENABL
        sta CXCLR
        jsr latch
        COLL_IS CXM0FB, $00, $04        ; M0 off -> nothing to touch
        COLL_IS CXM1FB, $00, $05        ; M1 off -> nothing to touch
        COLL_IS CXBLPF, $00, $06        ; BL off -> nothing to touch

        ; a single lit cell at cell 5 (px 20-23): a 4px bar. Each object below
        ; is parked at px~16, exactly +4px short of the bar's left edge.
        lda #$00
        sta PF0
        sta PF2
        lda #$40                        ; PF1 bit -> playfield cell 5 only
        sta PF1

        ; --- M0 width (NUSIZ0 D4-5) ---
        lda #$00
        sta ENAM1                       ; isolate M0: only it is enabled
        sta ENABL
        lda #$02
        sta ENAM0
        sta WSYNC
        SLEEP 23
        sta RESM0                       ; park M0 at px~16, +4px left of the bar
        lda #$00
        sta NUSIZ0                      ; width 1: 1px, cannot reach the bar
        sta CXCLR
        jsr latch
        COLL_IS CXM0FB, $00, $07        ; narrow M0 misses -> clear
        lda #$30
        sta NUSIZ0                      ; width 8: spans the +4px gap to the bar
        sta CXCLR
        jsr latch
        COLL_IS CXM0FB, $80, $08        ; wide M0 reaches -> collided

        ; --- M1 width (NUSIZ1 D4-5) ---
        lda #$00
        sta ENAM0                       ; isolate M1
        lda #$02
        sta ENAM1
        sta WSYNC
        SLEEP 23
        sta RESM1                       ; park M1 at px~16
        lda #$00
        sta NUSIZ1                      ; width 1
        sta CXCLR
        jsr latch
        COLL_IS CXM1FB, $00, $09        ; narrow M1 misses
        lda #$30
        sta NUSIZ1                      ; width 8
        sta CXCLR
        jsr latch
        COLL_IS CXM1FB, $80, $0A        ; wide M1 reaches

        ; --- BL width (CTRLPF D4-5) ---
        lda #$00
        sta ENAM1                       ; isolate BL
        lda #$02
        sta ENABL
        sta WSYNC
        SLEEP 23
        sta RESBL                       ; park BL at px~16
        lda #$00
        sta CTRLPF                      ; width 1
        sta CXCLR
        jsr latch
        COLL_IS CXBLPF, $00, $0B        ; narrow BL misses
        lda #$30
        sta CTRLPF                      ; width 8
        sta CXCLR
        jsr latch
        COLL_IS CXBLPF, $80, $0C        ; wide BL reaches

        PASS_TEST

; two beam-on lines: enough for the static overlap to latch.
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
