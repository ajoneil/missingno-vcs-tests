; hmove-edge — an object's collision latch switches on and off at exact pixel
; boundaries: the overlap is counted pixel by pixel, with no soft edges.
;
; The TIA (the console's video chip) draws the picture live as the beam sweeps
; a scanline — there is no framebuffer. It carries five movable objects: two
; players (8-bit sprites), two missiles, and the ball. Whenever two of them
; are lit on the same pixel the TIA sets a sticky "collision" latch for that
; pair, and the latch holds until a write to CXCLR clears every latch at once.
; The pair "missile 0 overlaps player 1" is bit 7 of the read register CXM0P.
;
; Each object's horizontal position is set in two stages. A strobe register
; (RESP1 for player 1, RESM0 for missile 0) drops the object wherever the beam
; happens to be when the write lands — coarse, to within a few pixels. Fine
; adjustment comes from HMOVE: each object has a 4-bit horizontal-motion
; register (HMM0 here) holding a signed offset in its high nibble, -8..+7, and
; a write to the HMOVE strobe applies that offset once, as a short burst of
; extra motion clocks. HMM0 = $F0 is high nibble $F = -1, so every HMOVE strobe
; nudges missile 0 exactly one pixel (one colour clock) to the right.
;
; HMOVE also blanks the leftmost 8 pixels of the line it fires on — the "comb",
; a band where the motion machinery steals the beam. Both objects sit
; mid-screen, well clear of the comb, so it never touches the overlap measured.
;
; The test builds an 8px solid player 1 and a 1px missile 0 placed a few pixels
; to its left, then steps the missile one pixel right on each of 16 HMOVE
; strobes, recording per step whether M0-P1 latched — a 16-bit profile, one bit
; per step. The hits form one run exactly eight steps wide, bracketed by misses
; on both sides: the onset and the offset are each a single-step transition,
; pinning the player's 8px span to one pixel. A model with fuzzy collision edges
; smears the onset or offset across an extra step, or counts seven or nine hits
; instead of eight.
;
;   CODE $01 = low 8 steps of the profile wrong (steps 0..7)
;        $02 = high 8 steps of the profile wrong (steps 8..15)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; 2-byte collision bitfield ($90 lo, $91 hi)
IDX     = $92                   ; sweep index 0..STEPS-1
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta GRP1                ; player 1 = 8 solid pixels: the reference span
        lda #$00
        sta NUSIZ1              ; one copy, normal width
        lda #$0E
        sta COLUP1              ; player 1 colour (unused by the collision read)
        lda #$02
        sta ENAM0               ; enable missile 0: the 1px probe dot
        lda #$F0
        sta HMM0                ; HM offset -1: each HMOVE nudges M0 one px right

        jsr vertical_sync
        jsr vblank_lines        ; VBLANK now 0 — beam on

        ; park P1 mid-screen, then M0 a few pixels to its left (sweep start)
        sta WSYNC
        SLEEP 40
        sta RESP1               ; fix the 8px player span (mid-screen)
        sta WSYNC
        SLEEP 39
        sta RESM0               ; drop M0 a few px left of the span's left edge

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ldx #0
.sweep:
        stx IDX
        sta WSYNC
        sta HMOVE              ; step M0 one pixel right
        sta CXCLR              ; clear this line's transient overlap
        jsr latch              ; clean beam-on lines at the new position
        lda CXM0P
        and #$80               ; M0-P1
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

        ; Step -> column. M0 starts left of the span and each step nudges it one
        ; pixel right, so the sweep reads:
        ;   steps 0,1,2   miss   M0 is still left of the player
        ;   steps 3..10   hit    M0's 1px sits inside the 8px player span
        ;   steps 11..15  miss   M0 has passed the player's right edge
        ; Exactly 8 consecutive hits = P1's 8px span pinned to 1px by HMOVE;
        ; single-pixel onset (step 3) and offset (step 10), misses either side —
        ; the pixel-exact collision edges, a hardware constant.
        ASSERT_EQ PROFILE,   $F8, $01   ; low 8: bits 3..7 set = hits at steps 3..7
        ASSERT_EQ PROFILE+1, $07, $02   ; high 8: bits 0..2 set = hits at steps 8..10
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the static overlap to latch. Clobbers X (the
; sweep index lives in IDX). No HMOVE here, so M0 holds its stepped position.
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
