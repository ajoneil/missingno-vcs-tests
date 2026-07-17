; draw-delay — after a RESxx strobe resets an object's position counter, the
; object waits a fixed number of colour clocks before its first pixel appears,
; and that delay depends on the object's TYPE: a player starts one clock later
; than a missile or the ball, while objects of the same type start together.
;
; The TIA's five movable objects (player 0, player 1, missile 0, missile 1,
; ball) each ride a horizontal position counter. A RESxx strobe grounds that
; counter to wherever the beam is, but it does not light a pixel at once: the
; reset feeds a short pipeline — a position decode, then a serialiser tail —
; before the object begins drawing. A player carries one extra latch stage in
; that pipeline that a missile and the ball do not, so from the very same reset
; position a player's first pixel lands exactly one colour clock to the right
; of a missile's or the ball's. Missiles match each other, the ball matches the
; missiles, and the two players match: the delay is fixed per object type.
;
; The test draws the objects in two horizontal bands.
;
; Band 1 (top) resets all five objects to the same beam position, so any
; horizontal offset between them is purely their differing start delays.
; Priority collapses the stack into a single red run at x 50-58: missile 0 pokes
; out at x=50 — one clock left of its player, the delay under test — and player
; 0 fills x 51-58. Player 1, missile 1 and the ball land beneath the red and
; never show; that they are fully hidden is the assertion.
;
; Band 2 (bottom) re-strobes the same objects in three groups, 18 colour clocks
; apart, so every landing is separately visible:
;
;   x  50      red     missile 0
;   x  51- 58  red     player 0 (8px), one clock right of missile 0
;   x  68      white   ball, 18 clocks right of missile 0
;   x  86      green   missile 1
;   x  87- 94  green   player 1 (8px), one clock right of missile 1
;   elsewhere  black   background
;
; Each missile sits exactly one pixel left of its player, and the ball lands
; where a missile would — the type-dependent delay shown three ways. The band
; pins absolute columns, so a shift of a whole group fails the test too, not
; just a change in the relative spacing. (On the PAL palette the hues differ —
; P0/M0 render brown-red and P1/M1 purple — but the three colours stay
; distinct.)
;
; Verdict: the captured frame vs draw-delay_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background black
        lda #$42
        sta COLUP0              ; player 0 red — missile 0 shares this colour
        lda #$C4
        sta COLUP1              ; player 1 green — missile 1 shares this colour
        lda #$0E
        sta COLUPF              ; ball takes the playfield colour: white

MainLoop:
        jsr vertical_sync

        ; band 1 setup: reset all five objects to the same beam position, one
        ; per line, on the first five VBLANK lines (screen still blanked)
        lda #$02
        sta VBLANK
        sta WSYNC               ; line 1
        SLEEP 35
        sta RESP0               ; reset player 0
        sta WSYNC               ; line 2
        SLEEP 35                ; identical offset -> identical landing
        sta RESP1               ; reset player 1
        sta WSYNC               ; line 3
        SLEEP 35
        sta RESM0               ; reset missile 0
        sta WSYNC               ; line 4
        SLEEP 35
        sta RESM1               ; reset missile 1
        sta WSYNC               ; line 5
        SLEEP 35
        sta RESBL               ; reset ball

        lda #$FF
        sta GRP0                ; player 0 graphic: 8 solid bits
        sta GRP1                ; player 1 graphic: 8 solid bits
        lda #$02
        sta ENAM0               ; enable missile 0 (1px wide)
        sta ENAM1               ; enable missile 1 (1px wide)
        sta ENABL               ; enable ball (1px wide)

        ldx #(VBLANK_LINES-5)   ; wait out the rest of VBLANK
.vbwait:
        sta WSYNC
        dex
        bne .vbwait
        lda #$00
        sta VBLANK              ; beam on

        ; band 1: everything stacked at one landing -> a single red run
        ; (M0 at x=50, P0 at x51-58; P1/M1/BL hidden beneath)
        ldx #92
.band1:
        sta WSYNC
        dex
        bne .band1

        ; transition: blank all five, then re-strobe them to split positions
        sta WSYNC
        lda #$00
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta WSYNC
        SLEEP 35
        sta RESP0               ; player 0  -> spans x51-58
        sta WSYNC
        SLEEP 35                ; same offset, but a missile draws 1 clock early
        sta RESM0               ; missile 0 -> x=50 (1px left of P0)
        sta WSYNC
        SLEEP 41                ; +6 cycles = +18 clocks from the P0/M0 landing
        sta RESBL               ; ball     -> x=68, alone
        sta WSYNC
        SLEEP 47                ; +36 clocks from the P0/M0 landing
        sta RESP1               ; player 1  -> spans x87-94
        sta WSYNC
        SLEEP 47                ; same offset as P1: missile draws 1 clock early
        sta RESM1               ; missile 1 -> x=86 (1px left of P1)
        sta WSYNC               ; re-enable during the next line's hblank
        lda #$FF
        sta GRP0                ; player 0 graphic back on
        sta GRP1                ; player 1 graphic back on
        lda #$02
        sta ENAM0               ; missile 0 back on
        sta ENAM1               ; missile 1 back on
        sta ENABL               ; ball back on

        ; band 2: remaining visible lines, all five landings separately visible
        ldx #(VISIBLE_LINES-99)
.band2:
        sta WSYNC
        dex
        bne .band2

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
