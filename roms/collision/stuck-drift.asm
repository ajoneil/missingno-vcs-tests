; stuck-drift — a missile dot the stuck HMOVE mechanism swallows collides with
; nothing, and a dot it merely distorts still collides.
;
; HMOVE is the TIA's horizontal-motion strobe (the value written is ignored, the
; write itself is the event). Each movable object holds a 4-bit motion value
; (HMM0 for missile 0, and so on); writing HMOVE arms a "more motion" latch for
; every object and starts a countdown, and the object is fed extra motion clocks
; until a comparator matches its motion value, at which point the latch clears.
; Normally that is a handful of clocks and done. But if the motion value is
; rewritten mid-countdown so the comparator never meets its match, the latch
; never clears: it keeps demanding an extra motion clock, line after line, with
; no further HMOVE (this is the mechanism behind Cosmic Ark's drifting
; starfield; see tia-timing/hmove-stuck-latch).
;
; Only some of those stuck clocks move the object. During the visible part of a
; line the extra clock lands on top of the object's own motion clock and merges
; into it — no net move, but the serialiser (the shift register that clocks the
; dot's pixels out) is disturbed. During horizontal blank the motion clock is
; gated off, so there the extra clock is a genuine advance. There are 17 of those
; per line, so the missile drifts 17 colour clocks left each line (mod the
; 160-clock visible width).
;
; The merged visible clock falls at some offset — a residue — within the object's
; 4-colour-clock serialiser cell, and the residue decides what the dot does that
; line: residues 0 and 1 draw a normal 1-clock dot; residue 3 widens it to a
; 2-clock dot; residue 2 swallows it, drawing nothing at all. Collisions are read
; off the serialiser's output, not off the position counter — so the swallowed
; dot that renders nothing also collides with nothing, while the widened dot is
; still lit and still collides.
;
; The test parks the missile, jams the latch, and lets the drifting dot walk
; across a playfield bar. Each distortion class gets its own one-line collision
; window: CXCLR clears the collision latches in the horizontal blank before the
; line, and the missile-vs-playfield latch CXM0FB is read (D7) in the horizontal
; blank after. Four lines of the walk are windowed — a residue-0 dot and a
; residue-1 dot, then a residue-3 dot and a residue-2 dot — preceded by a
; control line taken before the jam, with the missile parked clear of the bar.
;
;   CODE $01 = parked control latched with the missile outside the bar
;        $02 = normal drifting dot in the bar did not latch
;        $03 = normal drifting dot outside the bar latched
;        $04 = 2-clk (residue 3) dot in the bar did not latch
;        $05 = swallowed (residue 2) dot in the bar latched — it must not, the
;              collision follows the serialiser output, and that dot drew nothing
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S       = $90                   ; S..S+4: masked latch samples

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta PF2                 ; bar at x=[48..80) (+ repeat at 128)
        lda #$0E
        sta COLUPF
        sta COLUP0
        lda #$02
        sta ENAM0

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; park M0 at x=101 and arm the mover
        sta WSYNC
        lda #$70
        sta HMM0
        SLEEP 47
        sta RESM0

        ; parked control: one clean full line, M0 at 101 (outside both bars)
        sta WSYNC
        sta CXCLR
        sta WSYNC
        lda CXM0FB
        and #$80                ; keep D7 = missile-vs-playfield collision
        sta S+0                 ; expect $00

        ; Jam the latch (drift line n=0 is this line's tail): HMOVE lands at store
        ; cycle 3 and HMM0=$00 at cycle 19, before the countdown can match. The
        ; bar lights x=[48..80) and M0 parked at x=101, so the jammed walk runs
        ; 94, 77, 60, 43, ... (-17 per line, mod 160). The windowed lines:
        ;   n=2  x=60, residue 0: normal dot in the bar         -> must latch
        ;   n=5  x=9,  residue 1: normal dot outside the bar    -> must stay clear
        ;   n=11 x=67, residue 3: 2-clk dot [66..68) in the bar -> must latch
        ;   n=12 x=50, residue 2: swallowed dot in the bar      -> must stay clear
        sta WSYNC
        sta HMOVE
        lda #$00
        SLEEP 11
        sta HMM0

        sta WSYNC               ; -> n=1 (77)
        sta WSYNC               ; -> n=2 (60, residue 0, in the bar)
        sta CXCLR               ; hblank of n=2: window covers n=2
        sta WSYNC               ; -> n=3
        lda CXM0FB              ; hblank of n=3: close the n=2 window
        and #$80                ; keep D7 = missile-vs-playfield collision
        sta S+1                 ; expect $80
        sta WSYNC               ; -> n=4 (26)
        sta WSYNC               ; -> n=5 (9, residue 1, outside the bar)
        sta CXCLR               ; window covers n=5
        sta WSYNC               ; -> n=6
        lda CXM0FB
        and #$80                ; keep D7 = missile-vs-playfield collision
        sta S+2                 ; expect $00
        sta WSYNC               ; -> n=7 (135)
        sta WSYNC               ; -> n=8 (118)
        sta WSYNC               ; -> n=9 (101)
        sta WSYNC               ; -> n=10 (84)
        sta WSYNC               ; -> n=11 (67, residue 3, 2-CLK dot in bar)
        sta CXCLR               ; window covers n=11
        sta WSYNC               ; -> n=12 (50, residue 2, swallowed in bar)
        lda CXM0FB              ; close the n=11 window...
        and #$80                ; keep D7 = missile-vs-playfield collision
        sta S+3                 ; expect $80
        sta CXCLR               ; ...and open n=12's in the same hblank
        sta WSYNC               ; -> n=13
        lda CXM0FB
        and #$80                ; keep D7 = missile-vs-playfield collision
        sta S+4                 ; the question

        sta WSYNC
        lda #$80
        sta HMM0                ; release the latch

        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $80, $02
        ASSERT_EQ S+2, $00, $03
        ASSERT_EQ S+3, $80, $04
        ASSERT_EQ S+4, $00, $05 ; swallowed dot does not latch (see header)
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
